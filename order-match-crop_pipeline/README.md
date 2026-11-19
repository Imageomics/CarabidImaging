# Order-Match-Crop Pipeline

This folder contains scripts that take finalized beetle detections and produce per-beetle image crops linked to individual specimen IDs.

## Overview

The pipeline runs in two steps:

1. **Merge annotations** — patches GDino detections with manual CVAT corrections for ~146 images, producing a clean `detections_merged.csv`.
2. **Crop and link** — spatially orders bounding boxes within each tray, crops each beetle, and links each crop to an `individualID` from the metadata CSVs via a sidecar `_ids.csv` file.

## Scripts

### `merge_annotations.py`
Merges CVAT XML annotations into `detections_all.csv`, replacing bad GDino detections for manually corrected images.

- For dual-tray (`-and-`) images, splits boxes at the image Y-midpoint: top half → TRAY1, bottom half → TRAY2.
- Supports `--dry-run` to preview changes before writing.

```bash
python merge_annotations.py \
    --detections /path/to/detections_all.csv \
    --xml        /path/to/manualAnnotations.xml \
    --output     /path/to/detections_merged.csv

# Preview without writing:
python merge_annotations.py --dry-run ...
```

### `crop_and_link.py`
For each tray in `detections_merged.csv` where `true_NumberOfBeetles == pred_NumberOfBeetles`:

1. Groups bounding boxes into rows using an iterative-merge algorithm with a dynamic height-based tolerance.
2. Orders boxes top-to-bottom, left-to-right within each row.
3. Crops each beetle from the original tray image.
4. Looks up the ordered `individualID` list from metadata, saves each crop as `{tray}_{N}.png`, and writes a sidecar `{tray}_ids.csv` mapping position/filename → `individualID` (when the counts line up).
5. Saves a numbered overview image for QC.

Trays where counts don't match are saved to `review/` for manual inspection.

Supports SLURM array job sharding via `--task` and `--total-tasks`.

```bash
python crop_and_link.py \
    --detections          /path/to/detections_merged.csv \
    --images-abtray       /path/to/FinalImages/ABTrays \
    --images-ctray        /path/to/FinalImages/CTrays \
    --images-smallbeetles /path/to/FinalImages/SmallBeetles \
    --individuals         /path/to/allIndividuals.csv \
    --allimages           /path/to/allImages.csv \
    --output              /path/to/Cropped
```

### `crop_scalebars.py`
Crops the scalebar out of each tray image, mirroring the manual-bbox workflow used for beetles.

Two sources are merged (manual boxes override the automatic ones, just like `merge_annotations.py`):

- **Base** — `Scalebars.csv` (Moondream auto-detections), one row per tray.
- **Override** — `ScalebarAnnotations*.xml` (manual CVAT export, label `Scalebar`).

Each scalebar box is cropped and saved as `scalebars/{tray}_scalebar.png`. Dual-tray (`-and-`) images are split at the Y-midpoint into `_Tray1` / `_Tray2`, matching the beetle convention. Supports SLURM array sharding via `--task` / `--total-tasks`.

```bash
python crop_scalebars.py \
    --scalebar-csv        /path/to/Scalebar/Scalebars.csv \
    --scalebar-xml        /path/to/ScalebarAnnotations1.xml /path/to/ScalebarAnnotations2.xml \
    --images-abtray       /path/to/FinalImages/ABTrays \
    --images-ctray        /path/to/FinalImages/CTrays \
    --images-smallbeetles /path/to/FinalImages/SmallBeetles \
    --output              /path/to/Cropped
```

### `run_pipeline.sh`
Runs all steps end-to-end: step 1 interactively, steps 2 and 3 as 8-task SLURM array jobs.

```bash
bash run_pipeline.sh               # run all steps
bash run_pipeline.sh --merge-only     # only merge annotations
bash run_pipeline.sh --crop-only      # only submit the beetle crop job
bash run_pipeline.sh --scalebar-only  # only submit the scalebar crop job
bash run_pipeline.sh --no-scalebar    # merge + beetle crop, skip scalebars
```

## Output structure

```
Cropped/
├── cropped/          # per-tray folders: cropped/{tray}/{tray}_{N}.png (spatial order) + cropped/{tray}/{tray}_ids.csv linking each crop to its individualID
├── numbered_trays/   # full tray images with numbered bounding boxes (QC)
├── review/           # trays where pred count != true count
├── no_metadata/      # trays with no matching individualID metadata
└── scalebars/        # one scalebar crop per tray: {tray}_scalebar.png
```

## Metadata sources

| Tray type | Source file | Lookup key |
|---|---|---|
| ABTrays / FirstPass / Belitz | `allIndividuals.csv` | `imageID`, sorted by `Order` |
| CTrays | `allImages.csv` | `trayID` (or `imageID` as fallback) |
