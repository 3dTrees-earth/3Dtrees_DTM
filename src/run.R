#!/usr/bin/env Rscript

script_dir <- function() {
  sourced_files <- Filter(
    function(path) !is.null(path) && nzchar(path),
    lapply(sys.frames(), function(frame) frame$ofile)
  )

  if (length(sourced_files) > 0) {
    return(dirname(normalizePath(sourced_files[[length(sourced_files)]])))
  }

  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))))
  }

  return(getwd())
}

source(file.path(script_dir(), "parameters.R"))

suppressPackageStartupMessages(library(lidR))
suppressPackageStartupMessages(library(terra))

has_ground_points <- function(las) {
  "Classification" %in% colnames(las@data) &&
    any(las@data$Classification == 2, na.rm = TRUE)
}

count_ground_points <- function(las) {
  if (!"Classification" %in% colnames(las@data)) {
    return(0)
  }
  sum(las@data$Classification == 2, na.rm = TRUE)
}

classify_ground_if_needed <- function(las, mode, cloth_resolution) {
  if (lidR::is.empty(las)) {
    return(las)
  }

  should_classify <- mode == "always" ||
    (mode == "auto" && !has_ground_points(las))

  if (!should_classify) {
    return(las)
  }

  lidR::classify_ground(
    las,
    lidR::csf(cloth_resolution = cloth_resolution)
  )
}

cluster_to_dtm <- function(
  cluster,
  resolution,
  ground_classification_mode,
  cloth_resolution,
  chunk_dir
) {
  las <- lidR::readLAS(cluster)

  if (is.null(las)) {
    return(NULL)
  }

  if (lidR::is.empty(las)) {
    return(NULL)
  }

  las <- classify_ground_if_needed(
    las = las,
    mode = ground_classification_mode,
    cloth_resolution = cloth_resolution
  )

  if (!has_ground_points(las)) {
    warning("Skipping chunk without ground points")
    return(NULL)
  }

  if (count_ground_points(las) < 3) {
    warning("Skipping chunk with fewer than 3 ground points")
    return(NULL)
  }

  dtm <- lidR::rasterize_terrain(las, res = resolution, algorithm = lidR::tin())
  core_bbox <- sf::st_bbox(cluster)
  dtm <- terra::crop(
    dtm,
    terra::ext(
      unname(core_bbox["xmin"]),
      unname(core_bbox["xmax"]),
      unname(core_bbox["ymin"]),
      unname(core_bbox["ymax"])
    ),
    snap = "out"
  )

  chunk_file <- tempfile(pattern = "dtm_chunk_", tmpdir = chunk_dir, fileext = ".tif")
  terra::writeRaster(dtm, chunk_file, overwrite = TRUE)
  chunk_file
}

args <- parse_parameters()

dtm_file <- args$dtm_file
if (!nzchar(dtm_file)) {
  dtm_file <- file.path(args$output_dir, args$output_name)
}

message("Reading LAScatalog from: ", args$dataset_path)
catalog <- lidR::readLAScatalog(args$dataset_path)

lidR::opt_chunk_size(catalog) <- args$chunk_size
lidR::opt_chunk_buffer(catalog) <- args$chunk_buffer
lidR::opt_output_files(catalog) <- ""
lidR::opt_progress(catalog) <- FALSE

galaxy_slots <- suppressWarnings(as.integer(Sys.getenv("GALAXY_SLOTS", "1")))
if (!is.na(galaxy_slots) && galaxy_slots > 1 && requireNamespace("future", quietly = TRUE)) {
  future_strategy <- if (future::supportsMulticore()) {
    future::multicore
  } else {
    future::multisession
  }
  future::plan(future_strategy, workers = galaxy_slots)
}

message("Creating DTM at resolution: ", args$resolution)
chunk_dir <- file.path(args$output_dir, paste0(".dtm_chunks_", Sys.getpid()))
dir.create(chunk_dir, recursive = TRUE, showWarnings = FALSE)

dtm_tile_files <- lidR::catalog_apply(
  catalog,
  cluster_to_dtm,
  resolution = args$resolution,
  ground_classification_mode = args$ground_classification_mode,
  cloth_resolution = args$cloth_resolution,
  chunk_dir = chunk_dir
)

dtm_tile_files <- unlist(Filter(Negate(is.null), dtm_tile_files), use.names = FALSE)
if (length(dtm_tile_files) == 0) {
  stop("No DTM tiles were created. Check that the input contains ground points or enable ground classification.")
}

message("Writing DTM GeoTIFF to: ", dtm_file)
if (length(dtm_tile_files) == 1) {
  invisible(terra::writeRaster(terra::rast(dtm_tile_files[[1]]), dtm_file, overwrite = TRUE))
} else {
  dtm_collection <- terra::sprc(lapply(dtm_tile_files, terra::rast))
  invisible(terra::merge(dtm_collection, filename = dtm_file, overwrite = TRUE))
}

unlink(chunk_dir, recursive = TRUE)
message("Done")
