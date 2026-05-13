#!/usr/bin/env Rscript

script_dir <- function() {
  sourced <- Filter(Negate(is.null), lapply(sys.frames(), function(frame) frame$ofile))
  if (length(sourced) > 0) {
    return(dirname(normalizePath(tail(sourced, 1)[[1]])))
  }

  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))))
  }

  getwd()
}

source(file.path(script_dir(), "parameters.R"))

suppressPackageStartupMessages(library(lidR))
suppressPackageStartupMessages(library(terra))

ground_count <- function(las) {
  if (!"Classification" %in% names(las@data)) {
    return(0)
  }
  sum(las@data$Classification == 2, na.rm = TRUE)
}

ensure_ground <- function(las, mode, cloth_resolution) {
  needs_classification <- mode == "always" ||
    (mode == "auto" && ground_count(las) == 0)

  if (!needs_classification) {
    return(las)
  }

  lidR::classify_ground(las, lidR::csf(cloth_resolution = cloth_resolution))
}

crop_to_core <- function(raster, cluster) {
  bbox <- sf::st_bbox(cluster)
  terra::crop(
    raster,
    terra::ext(bbox[["xmin"]], bbox[["xmax"]], bbox[["ymin"]], bbox[["ymax"]]),
    snap = "out"
  )
}

chunk_to_dtm <- function(cluster, resolution, ground_mode, cloth_resolution, chunk_dir) {
  las <- lidR::readLAS(cluster)
  if (is.null(las) || lidR::is.empty(las)) {
    return(NULL)
  }

  las <- ensure_ground(las, ground_mode, cloth_resolution)
  n_ground <- ground_count(las)
  if (n_ground < 3) {
    warning(
      if (n_ground == 0) "Skipping chunk without ground points"
      else "Skipping chunk with fewer than 3 ground points"
    )
    return(NULL)
  }

  dtm <- lidR::rasterize_terrain(las, res = resolution, algorithm = lidR::tin())
  dtm <- crop_to_core(dtm, cluster)

  chunk_file <- tempfile("dtm_chunk_", tmpdir = chunk_dir, fileext = ".tif")
  terra::writeRaster(dtm, chunk_file, overwrite = TRUE)
  chunk_file
}

enable_parallel <- function() {
  slots <- suppressWarnings(as.integer(Sys.getenv("GALAXY_SLOTS", "1")))
  if (is.na(slots) || slots <= 1 || !requireNamespace("future", quietly = TRUE)) {
    return(invisible(FALSE))
  }

  strategy <- if (future::supportsMulticore()) future::multicore else future::multisession
  future::plan(strategy, workers = slots)
  invisible(TRUE)
}

merge_tiles <- function(tile_files, output_file) {
  message("Writing DTM GeoTIFF to: ", output_file)

  if (length(tile_files) == 1) {
    return(invisible(terra::writeRaster(terra::rast(tile_files[[1]]), output_file, overwrite = TRUE)))
  }

  tiles <- terra::sprc(lapply(tile_files, terra::rast))
  invisible(terra::merge(tiles, filename = output_file, overwrite = TRUE))
}

args <- parse_parameters()
dtm_file <- if (nzchar(args$dtm_file)) args$dtm_file else file.path(args$output_dir, args$output_name)

message("Reading LAScatalog from: ", args$dataset_path)
catalog <- lidR::readLAScatalog(args$dataset_path)
lidR::opt_chunk_size(catalog) <- args$chunk_size
lidR::opt_chunk_buffer(catalog) <- args$chunk_buffer
lidR::opt_output_files(catalog) <- ""
lidR::opt_progress(catalog) <- FALSE
enable_parallel()

message("Creating DTM at resolution: ", args$resolution)
chunk_dir <- file.path(args$output_dir, paste0(".dtm_chunks_", Sys.getpid()))
dir.create(chunk_dir, recursive = TRUE, showWarnings = FALSE)

dtm_tiles <- lidR::catalog_apply(
  catalog,
  chunk_to_dtm,
  resolution = args$resolution,
  ground_mode = args$ground_classification_mode,
  cloth_resolution = args$cloth_resolution,
  chunk_dir = chunk_dir
)

dtm_tiles <- unlist(Filter(Negate(is.null), dtm_tiles), use.names = FALSE)
if (length(dtm_tiles) == 0) {
  stop("No DTM tiles were created. Check that the input contains ground points or enable ground classification.")
}

merge_tiles(dtm_tiles, dtm_file)
unlink(chunk_dir, recursive = TRUE)
message("Done")
