"""
merge_annotations.py
--------------------
Merges CVAT manual annotations (manualAnnotations.xml) into detections_all.csv,
replacing the bad GDino outputs for the 146 manually corrected images.

For "and" images (two physical trays in one photo), CVAT annotated all boxes in
a single <image> entry. This script splits those boxes at the image Y-midpoint:
  - boxes with ytl < height/2  → TRAY1 row in detections_all.csv
  - boxes with ytl >= height/2 → TRAY2 row in detections_all.csv

The CVAT task appends _1 to filenames when the same image appears in a second
task (e.g. Detections_More after Detections_Less). That suffix is stripped before
matching so the name aligns with the imageID in detections_all.csv.

Inputs (defaults match the OSC paths):
  --detections   path to detections_all.csv
  --xml          path to manualAnnotations.xml
  --individuals  path to allIndividuals.csv (used to recompute true_NumberOfBeetles)
  --allimages    path to allImages.csv (used for CTray true_NumberOfBeetles)
  --output       path to write detections_merged.csv

Output: detections_merged.csv — same schema as detections_all.csv but with:
  - CVAT boxes (and updated pred_NumberOfBeetles) replacing the bad GDino entries
  - true_NumberOfBeetles recomputed from allIndividuals.csv / allImages.csv
"""

import argparse
import ast
import csv
import re
import xml.etree.ElementTree as ET
from pathlib import Path


# ---------------------------------------------------------------------------
# Parse CVAT XML → {name: [(xtl, ytl, xbr, ybr), ...], ...}
# ---------------------------------------------------------------------------

def parse_cvat_xml(
    xml_path: Path,
) -> tuple[dict[str, list[tuple[float, float, float, float]]], dict[str, tuple[int, int]]]:
    """
    Return a 2-tuple of:
      - annotations: {name: [(xtl, ytl, xbr, ybr), ...]}
      - dimensions:  {name: (width, height)}
    The name has any trailing CVAT _N suffix (e.g. _1.png → .png) stripped.
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()

    annotations: dict[str, list[tuple[float, float, float, float]]] = {}
    dimensions: dict[str, tuple[int, int]] = {}

    for img_elem in root.iter("image"):
        raw_name = img_elem.attrib["name"]
        width = int(img_elem.attrib.get("width", 0))
        height = int(img_elem.attrib.get("height", 0))

        # Strip CVAT duplicate-task suffix: e.g. "foo_1.png" → "foo.png"
        name = re.sub(r"_\d+(\.[^.]+)$", r"\1", raw_name)

        boxes = []
        for box in img_elem.iter("box"):
            xtl = float(box.attrib["xtl"])
            ytl = float(box.attrib["ytl"])
            xbr = float(box.attrib["xbr"])
            ybr = float(box.attrib["ybr"])
            boxes.append((xtl, ytl, xbr, ybr))

        # If the same name appears twice (same image in two CVAT tasks, _N suffix stripped),
        # overwrite with the later entry — both contain all boxes for the full image,
        # so merging would double-count. Keep the last (most recently annotated) version.
        annotations[name] = boxes
        dimensions[name] = (width, height)

    return annotations, dimensions


# ---------------------------------------------------------------------------
# Split "and" image boxes by Y midpoint
# ---------------------------------------------------------------------------

def split_and_boxes(
    boxes: list[tuple],
    img_height: int,
) -> tuple[list[tuple], list[tuple]]:
    """
    For dual-tray images, split boxes into top (TRAY1) and bottom (TRAY2)
    using the image midpoint as the boundary.
    A box is assigned based on where its top-left corner (ytl) sits.
    """
    midpoint = img_height / 2
    tray1 = [b for b in boxes if b[1] < midpoint]
    tray2 = [b for b in boxes if b[1] >= midpoint]
    return tray1, tray2


# ---------------------------------------------------------------------------
# Main merge logic
# ---------------------------------------------------------------------------

def merge(detections_csv: Path, xml_path: Path, output_csv: Path, dry_run: bool = False) -> None:
    if dry_run:
        print("=" * 60)
        print("DRY RUN — no files will be written")
        print("=" * 60)

    # Load CVAT annotations
    cvat_boxes, cvat_dims = parse_cvat_xml(xml_path)
    print(f"Loaded CVAT annotations for {len(cvat_boxes)} images")
    and_names = [n for n in cvat_boxes if "-and-" in n]
    print(f"  of which {len(and_names)} are dual-tray ('and') images")

    # Load detections_all.csv into memory
    with open(detections_csv, newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames
        rows = list(reader)

    print(f"Loaded {len(rows)} rows from {detections_csv.name}")

    replaced = 0
    not_found = []

    # Track changes for dry-run reporting
    changes: list[dict] = []

    for row in rows:
        image_id = row["imageID"]
        tray_id = row.get("trayID", "")

        cvat_name = image_id

        if cvat_name not in cvat_boxes:
            # Not a corrected image — leave row unchanged
            continue

        boxes_all = cvat_boxes[cvat_name]
        img_height = cvat_dims[cvat_name][1]

        if "-and-" in image_id:
            # Dual-tray: split by Y midpoint
            tray1_boxes, tray2_boxes = split_and_boxes(boxes_all, img_height)

            if tray_id.startswith("TRAY1"):
                selected_boxes = tray1_boxes
                which_tray = "TRAY1 (top half, y < height/2)"
            elif tray_id.startswith("TRAY2"):
                selected_boxes = tray2_boxes
                which_tray = "TRAY2 (bottom half, y >= height/2)"
            else:
                print(f"  WARNING: 'and' image has unexpected trayID '{tray_id}', skipping")
                continue
        else:
            selected_boxes = boxes_all
            which_tray = None

        box_list = [[b[0], b[1], b[2], b[3]] for b in selected_boxes]
        old_pred = row.get("pred_NumberOfBeetles", "?")
        true_n = row.get("true_NumberOfBeetles", "?")
        new_pred = len(box_list)

        changes.append({
            "imageID": image_id,
            "trayID": tray_id,
            "which_tray": which_tray,
            "true_n": true_n,
            "old_pred": old_pred,
            "new_pred": new_pred,
            "old_match": old_pred == true_n,
            "new_match": str(new_pred) == true_n,
        })

        if not dry_run:
            row["detections"] = str(box_list)
            row["pred_NumberOfBeetles"] = str(new_pred)

        replaced += 1

    # --- Dry-run report ---
    if dry_run:
        print(f"\n{'─' * 60}")
        print(f"CHANGES THAT WOULD BE MADE ({replaced} rows):")
        print(f"{'─' * 60}")

        fixed = [c for c in changes if not c["old_match"] and c["new_match"]]
        still_wrong = [c for c in changes if not c["new_match"]]
        regression = [c for c in changes if c["old_match"] and not c["new_match"]]

        print(f"\n✅ Would fix (bad → exact match): {len(fixed)}")
        for c in fixed:
            tray_note = f"  [{c['which_tray']}]" if c["which_tray"] else ""
            print(f"   {c['imageID'][:70]}{tray_note}")
            print(f"     true={c['true_n']}, gdino={c['old_pred']} → cvat={c['new_pred']}")

        if still_wrong:
            print(f"\n⚠️  Would still be mismatched after replacement: {len(still_wrong)}")
            for c in still_wrong:
                tray_note = f"  [{c['which_tray']}]" if c["which_tray"] else ""
                print(f"   {c['imageID'][:70]}{tray_note}")
                print(f"     true={c['true_n']}, gdino={c['old_pred']} → cvat={c['new_pred']}")

        if regression:
            print(f"\n🔴 REGRESSIONS (was exact match, would become wrong): {len(regression)}")
            for c in regression:
                print(f"   {c['imageID'][:70]}")
                print(f"     true={c['true_n']}, gdino={c['old_pred']} → cvat={c['new_pred']}")

        # Preview post-merge counts without modifying rows
        pre_exact = sum(
            1 for r in rows
            if r["true_NumberOfBeetles"] and
            r["true_NumberOfBeetles"] == r["pred_NumberOfBeetles"]
        )
        # Simulate the merge to compute post counts
        sim_rows = []
        for row in rows:
            image_id = row["imageID"]
            tray_id = row.get("trayID", "")
            cvat_name = image_id
            if cvat_name in cvat_boxes:
                boxes_all = cvat_boxes[cvat_name]
                img_height = cvat_dims[cvat_name][1]
                if "-and-" in image_id:
                    tray1_boxes, tray2_boxes = split_and_boxes(boxes_all, img_height)
                    if tray_id.startswith("TRAY1"):
                        selected_boxes = tray1_boxes
                    elif tray_id.startswith("TRAY2"):
                        selected_boxes = tray2_boxes
                    else:
                        # Mirrors the real merge path: unexpected trayID on an
                        # "and" image is skipped, row is left unchanged.
                        selected_boxes = None
                else:
                    selected_boxes = boxes_all
                sim_pred = str(len(selected_boxes)) if selected_boxes is not None else row["pred_NumberOfBeetles"]
            else:
                sim_pred = row["pred_NumberOfBeetles"]
            sim_rows.append((row["true_NumberOfBeetles"], sim_pred))

        post_exact = sum(1 for t, p in sim_rows if t and t == p)
        post_mismatch = sum(1 for t, p in sim_rows if t and t != p)
        post_no_gt = sum(1 for t, _ in sim_rows if not t)

        print(f"\n{'─' * 60}")
        print(f"PROJECTED SUMMARY AFTER MERGE:")
        print(f"  Before: {pre_exact} exact matches")
        print(f"  After:  {post_exact} exact matches (+{post_exact - pre_exact})")
        print(f"  Still mismatched (→ review/): {post_mismatch}")
        print(f"  No ground truth:              {post_no_gt}")
        print(f"\nTo apply these changes, re-run without --dry-run")
        return

    # --- Actual write ---
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(output_csv, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nReplaced detections for {replaced} rows")
    if not_found:
        print(f"WARNING: {len(not_found)} CVAT images had no matching row in detections_all.csv:")
        for n in not_found:
            print(f"  {n}")
    print(f"Output written to: {output_csv}")

    # Summary of counts after merge
    exact = sum(
        1 for r in rows
        if r["true_NumberOfBeetles"] and
        r["true_NumberOfBeetles"] == r["pred_NumberOfBeetles"]
    )
    mismatch = sum(
        1 for r in rows
        if r["true_NumberOfBeetles"] and
        r["true_NumberOfBeetles"] != r["pred_NumberOfBeetles"]
    )
    no_gt = sum(1 for r in rows if not r["true_NumberOfBeetles"])
    print(f"\nPost-merge summary:")
    print(f"  Exact match (ready to crop): {exact}")
    print(f"  Still mismatched (review):   {mismatch}")
    print(f"  No ground truth:             {no_gt}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--detections",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/detections_all.csv",
        help="Path to detections_all.csv from GDino run",
    )
    parser.add_argument(
        "--xml",
        default="/fs/ess/PAS2136/CarabidImaging/manualAnnotations.xml",
        help="Path to CVAT export XML",
    )
    parser.add_argument(
        "--output",
        default="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/detections_merged.csv",
        help="Path to write the merged detections CSV",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Preview what would change without writing any files. "
            "Shows each image that would be updated, old vs new box count, "
            "whether it fixes or still mismatches, and projected final totals."
        ),
    )
    args = parser.parse_args()

    merge(
        detections_csv=Path(args.detections),
        xml_path=Path(args.xml),
        output_csv=Path(args.output),
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
