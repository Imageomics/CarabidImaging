"""
crop_and_link.py
----------------
For each image in detections_merged.csv where true_NumberOfBeetles == pred_NumberOfBeetles:
  1. Sort bounding boxes into spatial order (rows top→bottom, beetles left→right
     within each row) using an iterative-merge row-grouping algorithm that checks
     whether any two boxes share a row based on center, top, OR bottom alignment.
     The dynamic tolerance scales with the average beetle height in that image.
  2. Crop each beetle from the original tray image.
  3. Look up the ordered list of individualIDs for the tray:
       - ABTrays / FirstPass / Belitz (trayID empty):
           allIndividuals.csv, matched by imageID, sorted by Order
       - CTrays (trayID non-empty, from allImages.csv):
           IndividualID_1, IndividualID_2, IndividualID_n1, IndividualID_n columns,
           expanded into a list in order.
  4. Save each crop as {stem}_{N}.png (matching Output/ naming convention),
     with a sidecar {stem}_ids.csv mapping position → individualID

Images where counts still don't match after merging are saved (with numbered crops,
no individual IDs) to output_dir/review/ for manual inspection.

Usage:
  python crop_and_link.py [options]

Key options:
  --detections    path to detections_merged.csv  (default: Output-Finalized/detections_merged.csv)
  --images        directory with original tray images  (default: FinalImages/ABTrays)
  --individuals   path to allIndividuals.csv
  --allimages     path to allImages.csv  (for CTrays)
  --output        root output directory  (default: Output-Finalized/Cropped)
  --row-tolerance fraction of avg beetle height used as row-grouping tolerance (default: 0.25)
  --task          SLURM array task index (0-based); used with --total-tasks to shard work
  --total-tasks   total number of SLURM array tasks
"""

import argparse
import ast
import csv
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


# ---------------------------------------------------------------------------
# Row-grouping helpers (adapted from row_template_match_rename.py)
# ---------------------------------------------------------------------------

def boxes_on_same_row(b1, b2, tolerance: float) -> bool:
    """
    True if any vertical alignment metric between two boxes is within tolerance.
    b1, b2 are [x1, y1, x2, y2] lists.
    Checks: center Y, top Y, bottom Y — OR logic handles size variation.
    """
    top1, top2 = b1[1], b2[1]
    bot1, bot2 = b1[3], b2[3]
    cen1 = (top1 + bot1) / 2
    cen2 = (top2 + bot2) / 2
    return (
        abs(cen1 - cen2) <= tolerance
        or abs(top1 - top2) <= tolerance
        or abs(bot1 - bot2) <= tolerance
    )


def group_into_rows(
    boxes: list[list], tolerance_ratio: float = 0.25
) -> list[list[list]]:
    """
    Cluster boxes into rows via iterative merge.
    tolerance = tolerance_ratio * average_box_height (dynamic, adapts to beetle size).
    Returns list of rows, each row is a list of boxes sorted left→right.
    Rows are sorted top→bottom by their average center Y.
    """
    if not boxes:
        return []

    heights = [b[3] - b[1] for b in boxes]
    avg_h = sum(heights) / len(heights) if heights else 1.0
    tolerance = avg_h * tolerance_ratio

    # Start: each box is its own row
    rows = [[b] for b in boxes]

    merged = True
    while merged:
        merged = False
        new_rows: list[list] = []
        used = set()

        for i, row_i in enumerate(rows):
            if i in used:
                continue
            for j, row_j in enumerate(rows):
                if j <= i or j in used:
                    continue
                # Merge if ANY pair of beetles (one from each row) are on the same row
                if any(
                    boxes_on_same_row(bi, bj, tolerance)
                    for bi in row_i
                    for bj in row_j
                ):
                    new_rows.append(row_i + row_j)
                    used.add(i)
                    used.add(j)
                    merged = True
                    break
            if i not in used:
                new_rows.append(row_i)
                used.add(i)

        rows = new_rows

    # Sort each row left→right by x1
    for row in rows:
        row.sort(key=lambda b: b[0])

    # Sort rows top→bottom by average center Y
    rows.sort(key=lambda row: sum((b[1] + b[3]) / 2 for b in row) / len(row))

    return rows


def spatial_order(boxes: list[list], tolerance_ratio: float = 0.25) -> list[list]:
    """
    Return boxes in spatial order: top-most row first, left-to-right within each row.
    The top-most row is defined as the one with the smallest average center Y.
    The leftmost beetle in the top row is position 1.
    """
    rows = group_into_rows(boxes, tolerance_ratio)
    ordered = []
    for row in rows:
        ordered.extend(row)
    return ordered


# ---------------------------------------------------------------------------
# Metadata loading
# ---------------------------------------------------------------------------

def load_individuals(csv_path: Path) -> dict[str, list[str]]:
    """
    Load allIndividuals.csv.
    Returns {imageID: [individualID in Order order]} for ABTrays.
    """
    by_image: dict[str, list[tuple]] = {}  # imageID → [(Order, individualID)]
    with open(csv_path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            img = row.get("imageID", "").strip()
            ind = row.get("individualID", "").strip()
            try:
                order = int(row.get("Order", 0))
            except (ValueError, TypeError):
                order = 0
            if img and ind:
                by_image.setdefault(img, []).append((order, ind))

    # Sort each list by Order and return just the individualID sequence.
    # Key by stem (no extension) so .jpg/.png mismatches between CSVs don't break lookup.
    return {
        Path(img).stem: [ind for _, ind in sorted(pairs)]
        for img, pairs in by_image.items()
    }


def _extract_ctray_ids(row: dict) -> list[str]:
    """
    Extract ordered individualIDs from allImages.csv CTray row.
    The format stores: IndividualID_1, IndividualID_2, IndividualID_n1, IndividualID_n
    where n1 = second-to-last and n = last.
    For N ≤ 4 this covers everything; for N > 4 interior positions are unknown
    and a placeholder is inserted.
    """
    n = int(row.get("NumberOfBeetles") or 0)
    if n == 0:
        return []

    def clean(val):
        v = (val or "").strip()
        return v if v and v.upper() != "NA" else None

    id1 = clean(row.get("IndividualID_1"))
    id2 = clean(row.get("IndividualID_2"))
    idn1 = clean(row.get("IndividualID_n1"))
    idn = clean(row.get("IndividualID_n"))

    if n == 1:
        return [id1] if id1 else []
    if n == 2:
        ids = []
        if id1:
            ids.append(id1)
        if idn:
            ids.append(idn)
        return ids
    if n == 3:
        ids = []
        if id1:
            ids.append(id1)
        if idn1:
            ids.append(idn1)
        if idn:
            ids.append(idn)
        return ids
    # n >= 4: positions 1, 2, …, n-1, n
    ids = []
    if id1:
        ids.append(id1)
    if id2:
        ids.append(id2)
    # interior positions 3..(n-2) are unknown
    unknown_count = n - 4
    for k in range(unknown_count):
        ids.append(f"UNKNOWN_pos{k + 3}")
    if idn1:
        ids.append(idn1)
    if idn:
        ids.append(idn)
    return ids


def load_allimages(csv_path: Path) -> dict[str, list[str]]:
    """
    Load allImages.csv.
    Returns {trayID: [individualID in physical order]} for CTrays.
    Also accepts imageID as key for non-"and" single CTrays.
    """
    result: dict[str, list[str]] = {}
    with open(csv_path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            tray_id = (row.get("trayID") or "").strip()
            image_id = (row.get("imageID") or "").strip()
            ids = _extract_ctray_ids(row)
            if not ids:
                continue
            key = tray_id if tray_id else image_id
            if key:
                result[key] = ids
    return result


# ---------------------------------------------------------------------------
# Core crop logic
# ---------------------------------------------------------------------------

def crop_tray(
    image_path: Path,
    boxes: list[list],
    individual_ids: list[str],
    output_dir: Path,
    tolerance_ratio: float,
    review: bool = False,
) -> int:
    """
    Crop beetles from image_path in spatial order.
    Naming follows the Output convention: {stem}_{N}.png (1-based position).
    If individual_ids is non-empty, its length matches the number of ordered
    boxes, AND every box was successfully saved (none skipped as out-of-bounds),
    also writes a sidecar {stem}_ids.csv mapping each crop's position and
    filename to its individualID. Any skip makes the mapping unreliable, so
    the sidecar is omitted rather than written partial.
    Returns the number of crops actually saved.
    """
    ordered_boxes = spatial_order(boxes, tolerance_ratio)
    output_dir.mkdir(parents=True, exist_ok=True)
    # Use the folder name as the file prefix so that -and- tray subfolders
    # (e.g. Species-and-Species_Tray1/) produce correctly named crops
    # (e.g. Species-and-Species_Tray1_1.png) instead of the raw image stem.
    file_stem = output_dir.name

    # Caller already warns on count mismatch ([COUNT MISMATCH]); here we just
    # skip writing the sidecar mapping if positions can't be aligned 1:1.
    ids_match = bool(individual_ids) and len(individual_ids) == len(ordered_boxes)

    n_saved = 0
    id_rows = []
    with Image.open(image_path) as img:
        img_w, img_h = img.size

        for i, box in enumerate(ordered_boxes):
            x1, y1, x2, y2 = [int(v) for v in box]
            x1 = max(0, min(x1, img_w))
            y1 = max(0, min(y1, img_h))
            x2 = max(0, min(x2, img_w))
            y2 = max(0, min(y2, img_h))
            if x2 <= x1 or y2 <= y1:
                continue  # box is entirely outside the image

            crop = img.crop((x1, y1, x2, y2))
            fname = f"{file_stem}_{i + 1}.png"
            crop.save(output_dir / fname)
            n_saved += 1
            if ids_match:
                id_rows.append((i + 1, fname, individual_ids[i]))

    if ids_match and n_saved == len(individual_ids):
        ids_csv = output_dir / f"{file_stem}_ids.csv"
        with open(ids_csv, "w", newline="") as fh:
            writer = csv.writer(fh)
            writer.writerow(["position", "filename", "individualID"])
            writer.writerows(id_rows)

    return n_saved


def draw_numbered_tray(
    image_path: Path,
    boxes: list[list],
    tolerance_ratio: float,
    output_path: Path,
) -> None:
    """
    Save a copy of the tray image with spatially-ordered numbered bounding boxes.
    Useful for QC — the number on each box matches the crop filename position.
    """
    ordered_boxes = spatial_order(boxes, tolerance_ratio)

    with Image.open(image_path) as img:
        draw_img = img.copy()

    draw = ImageDraw.Draw(draw_img)

    # Try to load a font; fall back gracefully
    font = None
    for font_path in ["arial.ttf", "Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]:
        try:
            font = ImageFont.truetype(font_path, size=max(30, draw_img.size[0] // 80))
            break
        except (OSError, IOError):
            continue
    if font is None:
        font = ImageFont.load_default()

    for i, box in enumerate(ordered_boxes):
        x1, y1, x2, y2 = box
        label = str(i + 1)
        draw.rectangle([x1, y1, x2, y2], outline="red", width=4)
        text_bbox = draw.textbbox((x1, y1), label, font=font)
        draw.rectangle(text_bbox, fill="red")
        draw.text((x1, y1), label, fill="white", font=font)

    # Downscale to max 2000px on the long edge for QC — keeps labels readable,
    # reduces file size significantly vs full-resolution tray images
    max_side = 2000
    w, h = draw_img.size
    if max(w, h) > max_side:
        scale = max_side / max(w, h)
        draw_img = draw_img.resize(
            (int(w * scale), int(h * scale)), Image.LANCZOS
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    # Save as JPEG at 85% quality for further size reduction
    jpeg_path = output_path.with_suffix(".jpg")
    draw_img.save(jpeg_path, format="JPEG", quality=85)


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def parse_boxes(detections_str: str) -> list[list]:
    """Parse the detections string from CSV into a list of [x1,y1,x2,y2] boxes."""
    if not detections_str or detections_str.strip() == "[]":
        return []
    try:
        return ast.literal_eval(detections_str)
    except (ValueError, SyntaxError):
        return []


def find_image_file(image_dirs: list, stem: str):
    """Find the image file with the given stem in any of the provided directories."""
    exts = (".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG")
    for image_dir in image_dirs:
        for ext in exts:
            candidate = image_dir / (stem + ext)
            if candidate.exists():
                return candidate
    return None


def run(args):
    detections_csv = Path(args.detections)
    image_dirs = [Path(args.images_abtray), Path(args.images_ctray), Path(args.images_smallbeetles)]
    output_dir = Path(args.output)
    tolerance_ratio = args.row_tolerance

    print(f"Loading detections from: {detections_csv}")
    print(f"ABTray image directory:      {image_dirs[0]}")
    print(f"CTray image directory:       {image_dirs[1]}")
    print(f"SmallBeetles image directory:{image_dirs[2]}")
    print(f"Output directory:        {output_dir}")
    print(f"Row tolerance ratio:     {tolerance_ratio}")

    # Load metadata
    print("\nLoading allIndividuals.csv ...")
    individuals = load_individuals(Path(args.individuals))
    print(f"  {len(individuals)} trays with per-beetle order data (ABTrays)")

    print("Loading allImages.csv ...")
    allimages = load_allimages(Path(args.allimages))
    print(f"  {len(allimages)} tray entries (CTrays and others)")

    # Load detection rows
    with open(detections_csv, newline="") as fh:
        rows = list(csv.DictReader(fh))
    print(f"\n{len(rows)} rows in detections CSV")

    # Optionally shard for SLURM array jobs
    if args.total_tasks and args.total_tasks > 1:
        task_idx = args.task
        total = args.total_tasks
        rows = [r for i, r in enumerate(rows) if i % total == task_idx]
        print(f"SLURM task {task_idx}/{total}: processing {len(rows)} rows")

    # Stats
    n_cropped = 0
    n_review = 0
    n_no_image = 0
    n_no_metadata = 0
    n_skipped_no_gt = 0

    for row in rows:
        image_id = row["imageID"]
        tray_id = row.get("trayID", "").strip()
        true_n_str = row.get("true_NumberOfBeetles", "").strip()
        pred_n_str = row.get("pred_NumberOfBeetles", "").strip()
        detections_str = row.get("detections", "")

        # Skip rows without ground truth
        if not true_n_str:
            n_skipped_no_gt += 1
            continue

        try:
            true_n = int(float(true_n_str))
            pred_n = int(float(pred_n_str))
        except (ValueError, TypeError):
            n_skipped_no_gt += 1
            continue

        boxes = parse_boxes(detections_str)
        if not boxes:
            n_skipped_no_gt += 1
            continue

        # Locate the source image
        stem = Path(image_id).stem
        image_path = find_image_file(image_dirs, stem)
        if image_path is None:
            print(f"  [MISSING IMAGE] {stem}")
            n_no_image += 1
            continue

        # C-trays have angled pins causing large vertical drift within a row;
        # use a higher tolerance for row grouping
        is_ctray = "Ctray" in image_id
        effective_tolerance = args.ctray_row_tolerance if is_ctray else tolerance_ratio

        # For -and- images the CSV has one row per physical tray with a trayID
        # of the form "TRAY1_Image..." or "TRAY2_Image...".  Give each tray its
        # own output folder so crop numbering matches the per-tray individual
        # ID list and mirrors the _Tray1 / _Tray2 naming in Plotted Detections.
        tray_suffix = ""
        if "-and-" in stem:
            if tray_id.startswith("TRAY1_"):
                tray_suffix = "_Tray1"
            elif tray_id.startswith("TRAY2_"):
                tray_suffix = "_Tray2"
        out_stem = stem + tray_suffix

        is_match = (true_n == pred_n)

        if is_match:
            # --- Look up individual IDs ---
            if tray_id:
                # CTray: look up by trayID in allImages.csv
                ind_ids = allimages.get(tray_id, [])
                if not ind_ids:
                    # Fallback to imageID
                    ind_ids = allimages.get(image_id, [])
            else:
                # ABTray: look up by stem (no extension) in allIndividuals.csv
                ind_ids = individuals.get(Path(image_id).stem, [])

            if not ind_ids:
                print(f"  [NO METADATA] {image_id}")
                n_no_metadata += 1
                # Still crop but save with positional names to review
                tray_out = output_dir / "no_metadata" / out_stem
                crop_tray(image_path, boxes, [], tray_out, effective_tolerance, review=True)
                draw_numbered_tray(
                    image_path, boxes, effective_tolerance,
                    output_dir / "no_metadata" / f"{out_stem}_numbered.png"
                )
                continue

            # Crop and write a sidecar {stem}_ids.csv linking each crop to its individualID
            tray_out = output_dir / "cropped" / out_stem
            n_saved = crop_tray(image_path, boxes, ind_ids, tray_out, effective_tolerance)

            # Save numbered overview image for QC
            draw_numbered_tray(
                image_path, boxes, effective_tolerance,
                output_dir / "numbered_trays" / f"{out_stem}_numbered.png"
            )

            # Warn if crops saved don't line up 1:1 with known individualIDs
            if n_saved != len(ind_ids):
                print(
                    f"  [COUNT MISMATCH] {out_stem}: {n_saved} crops saved but "
                    f"{len(ind_ids)} individualIDs — check metadata"
                )

            n_cropped += 1

        else:
            # Mismatch: save to review folder with numbered crops
            tray_out = output_dir / "review" / out_stem
            crop_tray(image_path, boxes, [], tray_out, effective_tolerance, review=True)
            draw_numbered_tray(
                image_path, boxes, effective_tolerance,
                output_dir / "review" / f"{out_stem}_numbered.png"
            )
            n_review += 1

    print("\n" + "=" * 60)
    print("DONE")
    print(f"  Trays cropped & linked: {n_cropped}")
    print(f"  Sent to review/:        {n_review}")
    print(f"  Missing image file:     {n_no_image}")
    print(f"  No metadata found:      {n_no_metadata}")
    print(f"  Skipped (no GT):        {n_skipped_no_gt}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--detections",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/detections_merged.csv",
        help="Path to detections_merged.csv (output of merge_annotations.py)",
    )
    parser.add_argument(
        "--images-abtray",
        default="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays",
        help="Directory containing ABTray images",
    )
    parser.add_argument(
        "--images-ctray",
        default="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/CTrays",
        help="Directory containing CTray images",
    )
    parser.add_argument(
        "--images-smallbeetles",
        default="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/SmallBeetles",
        help="Directory containing SmallBeetles images",
    )
    parser.add_argument(
        "--individuals",
        default="/fs/ess/PAS2136/CarabidImaging/allIndividuals.csv",
        help="Path to allIndividuals.csv (per-beetle order for ABTrays)",
    )
    parser.add_argument(
        "--allimages",
        default="/fs/ess/PAS2136/CarabidImaging/allImages.csv",
        help="Path to allImages.csv (individual IDs for CTrays)",
    )
    parser.add_argument(
        "--output",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Cropped",
        help="Root output directory. Subfolders: cropped/, review/, numbered_trays/, no_metadata/",
    )
    parser.add_argument(
        "--row-tolerance",
        type=float,
        default=0.25,
        help=(
            "Fraction of average beetle height used as row-grouping tolerance for ABTrays. "
            "Higher = more boxes merged into the same row. Default: 0.25"
        ),
    )
    parser.add_argument(
        "--ctray-row-tolerance",
        type=float,
        default=1.0,
        help=(
            "Row-grouping tolerance for CTrays. CTrays have angled pins causing "
            "large vertical drift within a single row. Default: 1.0"
        ),
    )
    parser.add_argument(
        "--task",
        type=int,
        default=0,
        help="SLURM array task index (0-based). Use with --total-tasks.",
    )
    parser.add_argument(
        "--total-tasks",
        type=int,
        default=1,
        help="Total number of SLURM array tasks. Rows are sharded by index.",
    )
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
