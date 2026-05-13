# 3Dtrees: DTM

Generate a Digital Terrain Model (DTM) GeoTIFF from LAS/LAZ point clouds.

The tool reads a single LAS/LAZ file or a directory of LAS/LAZ files as a `lidR`
LAScatalog, classifies ground points with CSF by default, rasterizes terrain, and
writes `dtm.tif`.

## Docker

Build the image:

```bash
docker build -t tool_dtm .
```

Run on a local file or folder:

```bash
docker run --rm \
  -v "$PWD/in:/in" \
  -v "$PWD/out:/out" \
  tool_dtm \
  Rscript /src/run.R \
    --dataset-path /in \
    --output-dir /out \
    --resolution 0.2 \
    --chunk-size 200 \
    --chunk-buffer 10
```

## Parameters

- `--dataset-path`: LAS/LAZ file or directory.
- `--output-dir`: output directory used with `--output-name`.
- `--output-name`: output GeoTIFF name, default `dtm.tif`.
- `--dtm-file`: explicit output GeoTIFF path, kept for the original Galaxy wrapper shape.
- `--resolution`: DTM raster resolution in input coordinate units.
- `--chunk-size`: LAScatalog chunk size.
- `--chunk-buffer`: LAScatalog chunk buffer.
- `--cloth-resolution`: CSF cloth resolution.
- `--ground-classification-mode`: `always` by default, or `auto`/`never` when existing class-2 ground points should be reused.

Set `GALAXY_SLOTS` to control the `lidR`/`future` worker count. In Docker, also
use Docker runtime limits such as `--cpus` and `--memory` for hard resource
limits.
