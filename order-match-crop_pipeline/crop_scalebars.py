"""
crop_scalebars.py
-----------------
Crops the scalebar out of each tray image and saves it alongside the beetle
crops, mirroring the manual-bbox workflow used for beetles.

Two scalebar sources are merged (same idea as merge_annotations.py for beetles,
where manual CVAT boxes override the automatic GDino detections):

  1. BASE  — Scalebars.csv (Moondream auto-detections), one row per tray image
             with a `scalebar_coords` list of {x_min,y_min,x_max,y_max} dicts.
  2. OVERRIDE — ScalebarAnnotations*.xml (manual CVAT export, label "Scalebar").
             Where a tray has a manual box it replaces the Moondream box.

For each tray the scalebar box is cropped from the original image and saved as
  output_dir/scalebars/{stem}_scalebar.png

Dual-tray ("-and-") images are split at the image Y-midpoint just like beetles:
boxes above the midpoint are tagged _Tray1, below _Tray2, producing
  {stem}_Tray1_scalebar.png / {stem}_Tray2_scalebar.png
A tray half with no scalebar box simply produces no crop.

Usage:
  python crop_scalebars.py [options]

Key options:
  --scalebar-csv   Moondream detections CSV (base source)
  --scalebar-xml   one or more manual CVAT XML exports (override source)
  --images-abtray / --images-ctray / --images-smallbeetles
                   directories searched (by stem) for the original tray images
  --output         root output dir; crops go to <output>/scalebars/
  --pad            fraction of box size to pad each crop on every side (default 0)
  --task / --total-tasks   SLURM array sharding (same convention as crop_and_link.py)
"""

import argparse
import ast
import csv
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


# ---------------------------------------------------------------------------
# Source loading
# ---------------------------------------------------------------------------

def load_moondream_csv(csv_path: Path) -> dict[str, list[list]]:
    """
    Load Scalebars.csv (Moondream).
    Returns {stem: [[x1,y1,x2,y2], ...]} keyed by image filename stem.
    Rows with num_scalebars == 0 / empty coords are skipped.
    """
    by_stem: dict[str, list[list]] = {}
    with open(csv_path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            name = (row.get("image_name") or "").strip()
            coords_str = (row.get("scalebar_coords") or "").strip()
            if not name or not coords_str:
                continue
            stem = Path(name).stem
            try:
                coords = ast.literal_eval(coords_str)
            except (ValueError, SyntaxError):
                continue
            boxes = []
            for c in coords:
                try:
                    boxes.append(
                        [c["x_min"], c["y_min"], c["x_max"], c["y_max"]]
                    )
                except (KeyError, TypeError):
                    continue
            if boxes:
                by_stem[stem] = boxes
    return by_stem


def load_cvat_xml(xml_paths: list[Path]) -> dict[str, list[list]]:
    """
    Load one or more manual CVAT XML exports (label "Scalebar").
    Returns {stem: [[x1,y1,x2,y2], ...]} keyed by image filename stem.
    The trailing CVAT duplicate-task suffix (e.g. foo_1.png -> foo.png) is
    stripped before keying. If the same stem appears in multiple files the
    later file wins (matches the "keep most recent annotation" rule used for
    beetles in merge_annotations.py).
    """
    by_stem: dict[str, list[list]] = {}
    for xml_path in xml_paths:
        root = ET.parse(xml_path).getroot()
        for img_elem in root.iter("image"):
            raw_name = img_elem.attrib["name"]
            name = re.sub(r"_\d+(\.[^.]+)$", r"\1", raw_name)
            stem = Path(name).stem
            boxes = []
            for box in img_elem.iter("box"):
                boxes.append([
                    float(box.attrib["xtl"]),
                    float(box.attrib["ytl"]),
                    float(box.attrib["xbr"]),
                    float(box.attrib["ybr"]),
                ])
            if boxes:
                by_stem[stem] = boxes
    return by_stem


def merge_sources(
    moondream: dict[str, list[list]],
    manual: dict[str, list[list]],
) -> dict[str, tuple[list[list], str]]:
    """
    Merge the two sources. Manual boxes override Moondream where present.
    Returns {stem: (boxes, source)} where source is "manual" or "moondream".
    """
    merged: dict[str, tuple[list[list], str]] = {}
    for stem, boxes in moondream.items():
        merged[stem] = (boxes, "moondream")
    for stem, boxes in manual.items():
        merged[stem] = (boxes, "manual")
    return merged


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def find_image_file(image_dirs: list, stem: str):
    """Find the image file with the given stem in any of the provided directories."""
    exts = (".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG")
    for image_dir in image_dirs:
        for ext in exts:
            candidate = image_dir / (stem + ext)
            if candidate.exists():
                return candidate
    return None


def crop_box(img, box, img_w, img_h, pad: float):
    """
    Crop a single box [x1,y1,x2,y2] from an open PIL image, optionally padded
    by `pad` fraction of the box width/height on each side, clamped to bounds.
    Returns the crop, or None if the box is degenerate / outside the image.
    """
    x1, y1, x2, y2 = (float(v) for v in box)
    if pad > 0:
        dw = (x2 - x1) * pad
        dh = (y2 - y1) * pad
        x1, y1, x2, y2 = x1 - dw, y1 - dh, x2 + dw, y2 + dh
    x1 = max(0, min(int(x1), img_w))
    y1 = max(0, min(int(y1), img_h))
    x2 = max(0, min(int(x2), img_w))
    y2 = max(0, min(int(y2), img_h))
    if x2 <= x1 or y2 <= y1:
        return None
    return img.crop((x1, y1, x2, y2))


def crop_scalebars_for_tray(
    image_path: Path,
    boxes: list[list],
    out_dir: Path,
    stem: str,
    pad: float,
) -> int:
    """
    Crop the scalebar box(es) for one tray and save into out_dir.

    Naming:
      - single tray:  {stem}_scalebar.png   (or _scalebar_1, _2 if >1 box)
      - "-and-" tray: boxes split at the Y-midpoint into _Tray1 / _Tray2,
                      each saved as {stem}_Tray{n}_scalebar.png (with _1/_2
                      suffix only if a half has more than one box)
    Returns the number of crops written.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    written = 0

    with Image.open(image_path) as img:
        img_w, img_h = img.size

        if "-and-" in stem:
            midpoint = img_h / 2
            groups = {
                "Tray1": [b for b in boxes if (b[1] + b[3]) / 2 < midpoint],
                "Tray2": [b for b in boxes if (b[1] + b[3]) / 2 >= midpoint],
            }
        else:
            groups = {"": boxes}

        for tray_tag, tray_boxes in groups.items():
            suffix = f"_{tray_tag}" if tray_tag else ""
            multi = len(tray_boxes) > 1
            for i, box in enumerate(tray_boxes):
                crop = crop_box(img, box, img_w, img_h, pad)
                if crop is None:
                    continue
                idx = f"_{i + 1}" if multi else ""
                fname = f"{stem}{suffix}_scalebar{idx}.png"
                crop.save(out_dir / fname)
                written += 1

    return written


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run(args):
    csv_path = Path(args.scalebar_csv)
    xml_paths = [Path(p) for p in args.scalebar_xml]
    image_dirs = [
        Path(args.images_abtray),
        Path(args.images_ctray),
        Path(args.images_smallbeetles),
    ]
    out_dir = Path(args.output) / "scalebars"

    print(f"Moondream CSV:   {csv_path}")
    print(f"Manual XML(s):   {', '.join(str(p) for p in xml_paths)}")
    print(f"ABTray images:   {image_dirs[0]}")
    print(f"CTray images:    {image_dirs[1]}")
    print(f"SmallBeetles:    {image_dirs[2]}")
    print(f"Output:          {out_dir}")
    print(f"Crop padding:    {args.pad}")

    moondream = load_moondream_csv(csv_path)
    print(f"\nMoondream detections (>=1 box): {len(moondream)} trays")

    manual = load_cvat_xml(xml_paths)
    print(f"Manual CVAT annotations:        {len(manual)} trays")

    merged = merge_sources(moondream, manual)
    print(f"Merged scalebar source:         {len(merged)} trays")

    # Stable ordering so SLURM sharding is deterministic.
    stems = sorted(merged.keys())

    if args.total_tasks and args.total_tasks > 1:
        stems = [s for i, s in enumerate(stems) if i % args.total_tasks == args.task]
        print(f"SLURM task {args.task}/{args.total_tasks}: processing {len(stems)} trays")

    n_cropped = 0
    n_crops = 0
    n_no_image = 0
    n_no_crop = 0
    n_manual = 0

    for stem in stems:
        boxes, source = merged[stem]
        image_path = find_image_file(image_dirs, stem)
        if image_path is None:
            print(f"  [MISSING IMAGE] {stem}")
            n_no_image += 1
            continue

        written = crop_scalebars_for_tray(image_path, boxes, out_dir, stem, args.pad)
        if written == 0:
            print(f"  [NO CROP] {stem} (degenerate/out-of-bounds box)")
            n_no_crop += 1
            continue

        n_cropped += 1
        n_crops += written
        if source == "manual":
            n_manual += 1

    print("\n" + "=" * 60)
    print("DONE")
    print(f"  Trays cropped:         {n_cropped}")
    print(f"    of which manual box: {n_manual}")
    print(f"  Total scalebar crops:  {n_crops}")
    print(f"  Missing image file:    {n_no_image}")
    print(f"  No usable crop:        {n_no_crop}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scalebar-csv",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/Scalebars.csv",
        help="Moondream Scalebars.csv (base source)",
    )
    parser.add_argument(
        "--scalebar-xml",
        nargs="+",
        default=[
            "/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/ScalebarAnnotations1.xml",
            "/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/ScalebarAnnotations2.xml",
        ],
        help="Manual CVAT XML export(s) (override source). Later files win on conflict.",
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
        "--output",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Cropped",
        help="Root output directory. Crops go to <output>/scalebars/",
    )
    parser.add_argument(
        "--pad",
        type=float,
        default=0.1,
        help="Fraction of box size to pad each crop on every side (default: 0.1 = 10%% buffer)",
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
        help="Total number of SLURM array tasks. Trays are sharded by index.",
    )
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
