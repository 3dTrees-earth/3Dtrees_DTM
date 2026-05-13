library(argparse)

parse_parameters <- function() {
  parser <- ArgumentParser(
    description = "3Dtrees DTM generation tool"
  )

  parser$add_argument(
    "--dataset-path", "--dataset_path", "--las-list", "--las_list",
    dest = "dataset_path",
    type = "character",
    required = TRUE,
    help = "Input LAS/LAZ file or directory/catalog of LAS/LAZ files"
  )

  parser$add_argument(
    "--output-dir", "--output_dir",
    dest = "output_dir",
    type = "character",
    default = "/out",
    help = "Output directory used when --dtm-file is not set"
  )

  parser$add_argument(
    "--output-name", "--output_name",
    dest = "output_name",
    type = "character",
    default = "dtm.tif",
    help = "Output GeoTIFF file name used inside --output-dir"
  )

  parser$add_argument(
    "--dtm-file", "--dtm_file",
    dest = "dtm_file",
    type = "character",
    default = "",
    help = "Explicit output GeoTIFF path. Kept for compatibility with the original Galaxy wrapper"
  )

  parser$add_argument(
    "--resolution", "--res",
    dest = "resolution",
    type = "double",
    default = 0.2,
    help = "DTM raster resolution in input coordinate units"
  )

  parser$add_argument(
    "--chunk-size", "--chunk_size",
    dest = "chunk_size",
    type = "double",
    default = 200,
    help = "LAScatalog chunk size in input coordinate units"
  )

  parser$add_argument(
    "--chunk-buffer", "--chunk_buffer",
    dest = "chunk_buffer",
    type = "double",
    default = 10,
    help = "LAScatalog chunk buffer in input coordinate units"
  )

  parser$add_argument(
    "--cloth-resolution", "--cloth_resolution",
    dest = "cloth_resolution",
    type = "double",
    default = 0.25,
    help = "CSF cloth resolution used when ground classification is run"
  )

  parser$add_argument(
    "--ground-classification-mode", "--ground_classification_mode",
    dest = "ground_classification_mode",
    type = "character",
    choices = c("auto", "always", "never"),
    default = "always",
    help = "Ground handling: always reclassifies ground points by default, auto classifies chunks without class 2, never requires existing class 2"
  )

  args <- parser$parse_args()

  if (!file.exists(args$dataset_path)) {
    stop("Input dataset path does not exist: ", args$dataset_path)
  }

  if (args$resolution <= 0) {
    stop("--resolution must be greater than 0")
  }

  if (args$chunk_size < 0) {
    stop("--chunk-size must be greater than or equal to 0")
  }

  if (args$chunk_buffer < 0) {
    stop("--chunk-buffer must be greater than or equal to 0")
  }

  if (args$cloth_resolution <= 0) {
    stop("--cloth-resolution must be greater than 0")
  }

  if (!nzchar(args$dtm_file)) {
    if (!dir.exists(args$output_dir)) {
      dir.create(args$output_dir, recursive = TRUE, showWarnings = FALSE)
    }
    if (!dir.exists(args$output_dir)) {
      stop("Output directory does not exist and could not be created: ", args$output_dir)
    }
  } else {
    output_parent <- dirname(args$dtm_file)
    if (!dir.exists(output_parent)) {
      dir.create(output_parent, recursive = TRUE, showWarnings = FALSE)
    }
    if (!dir.exists(output_parent)) {
      stop("Output file parent directory does not exist and could not be created: ", output_parent)
    }
  }

  return(args)
}
