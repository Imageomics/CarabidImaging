# Order-Match-Crop Pipeline

This folder contains scripts that take finalized beetle detections and produce per-beetle image crops linked to individual specimen IDs.

## Overview

The pipeline runs in two steps:

1. **Merge annotations** — patches GDino detections with manual CVAT corrections for ~146 images, producing a clean `detections_merged.csv`.
2. **Crop and link** — spatially orders bounding boxes within each tray, crops each beetle, and renames the crops with `individualID`s from the metadata CSVs.

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
4. Looks up the ordered `individualID` list from metadata and saves each crop as `{tray}_{N}.png`.
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

### `run_pipeline.sh`
Runs both steps end-to-end: step 1 interactively, step 2 as an 8-task SLURM array job.

```bash
bash run_pipeline.sh             # run both steps
bash run_pipeline.sh --merge-only  # only merge annotations
bash run_pipeline.sh --crop-only   # only submit the crop job
```

## Output structure

```
Cropped/
├── cropped/          # beetle crops named {tray}_{N}.png, in spatial order
├── numbered_trays/   # full tray images with numbered bounding boxes (QC)
├── review/           # trays where pred count != true count
└── no_metadata/      # trays with no matching individualID metadata
```

## Metadata sources

| Tray type | Source file | Lookup key |
|---|---|---|
| ABTrays / FirstPass / Belitz | `allIndividuals.csv` | `imageID`, sorted by `Order` |
| CTrays | `allImages.csv` | `trayID` (or `imageID` as fallback) |
