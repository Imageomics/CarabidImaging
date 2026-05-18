"""
Template matching and position inference for beetle images.

This script:
1. Template matches individual beetles on group images
2. Infers correct beetle positions based on spatial layout and scale bar
3. Identifies files with incorrect position labels
4. Renames files to correct position numbers (with dry-run option)
5. Creates visualizations and rename logs

CONTEXT FOR CARABIDIMAGING:
----------------------------
This script addresses the same ordering problem as box_order_crop.py — individual
beetle crops in Output/cropped_images/ were numbered in detection-score order rather
than the spatial order (top-to-bottom, left-to-right) that allIndividuals.csv uses
for its Order column.

The key difference from box_order_crop.py is *how* it determines spatial position:
- box_order_crop.py re-sorts bounding boxes from Detection_results.csv before cropping
- This script works *after* cropping is done: it takes the existing crop images,
  template-matches each one back onto the full tray image to find where it actually
  sits, then re-numbers files based on that inferred spatial position.

This script is NOT integrated into the CarabidImaging pipeline. It was written for a
separate dataset (see "beetlepalooza" paths in Config) and is included here as a
standalone utility. To use it on CarabidImaging data the Config paths and input file
naming conventions would need to be adapted.

INPUT FILES THIS SCRIPT NEEDS:
- Individual beetle crop images (pre-existing, in {specimen_id}_specimen_{N}.png format)
- Resized group tray images (separate from the originals in Images/FinalImages/)
- BeetleMeasurements.csv — contains pixel coordinates of the scale bar per image;
  this comes from TORAS annotations in the beetle-traits project, not from anything
  produced by CarabidImaging's pipeline
- metadata.csv — links each group image filename to its individual crop filenames,
  with columns groupImageFilePath and individualImageFilePath

WHAT IT MODIFIES (when --no-dry-run is set):
- Renames individual crop files in-place (e.g. _specimen_3.png -> _specimen_1.png)
- Uses a two-phase temp-rename to avoid conflicts when two files need to swap numbers
- Updates individualImageFilePath entries in metadata.csv to match the new names

SCALE BAR BEHAVIOR:
The script uses the scale bar position from BeetleMeasurements.csv to identify which
row of beetles sits alongside the scale bar. That row is numbered first (position 1
starts at the leftmost beetle on the scale bar row), then remaining rows continue
top-to-bottom. If no scale bar row is detected, plain top-to-bottom left-to-right
ordering is used.

ROW DETECTION vs. box_order_crop.py:
box_order_crop.py groups boxes into rows by comparing each new box's y_min against
the last box added to the current row (a drifting threshold). This script uses an
iterative merge approach: it checks whether centers, tops, OR bottoms of any two
beetles are within a dynamic tolerance (scaled to average beetle height). This is
more robust for trays where beetles vary in size or pin height.

USAGE:
------
1. First run with --dry-run (the default) to see what would be renamed
2. Review the visualizations in output_dir/
3. Check the rename log CSV
4. If satisfied, rerun with --no-dry-run to actually rename files

CONFIGURATION (key Config fields):
------------------------------------
- process_all_images: True = all group images in metadata, False = use test_group_images list
- dry_run: True = show what would happen, False = actually rename files
- create_rename_log: True = save CSV log of all renames
- row_center_tolerance_ratio: tolerance / avg beetle height (default 50px / 221.4px avg)

Visualization color key:
- Cyan: Scale bar location and horizontal reference line
- Red boxes: Beetle bounding boxes
- Magenta lines: Beetle center Y
- Light blue lines: Beetle top Y
- Orange lines: Beetle bottom Y
- Green lines: ElytraLength measurements
- Yellow lines: ElytraWidth measurements
- White labels: Inferred beetle positions (#1, #2, etc.)

Row detection: Beetles are grouped into rows if their centers, tops, OR bottoms are within a dynamic tolerance that scales with beetle size. The tolerance is (average_beetle_height * row_center_tolerance_ratio).
"""

import ast
import csv
import dataclasses
import pathlib
from datetime import datetime
from typing import NamedTuple

import beartype
import numpy as np
import polars as pl
import skimage.feature
import tyro
from PIL import Image, ImageDraw, ImageFont


@beartype.beartype
@dataclasses.dataclass(frozen=True)
class Config:
    hf_root: pathlib.Path = pathlib.Path("./data/beetlepalooza/individual_specimens")
    """Where individual specimen images are stored (individual_specimens directory)."""

    resized_root: pathlib.Path = pathlib.Path(
        "./data/beetlepalooza/group_images_resized"
    )
    """Where resized group images are stored."""

    output_dir: pathlib.Path = pathlib.Path(
        "./data/beetlepalooza/template_match_output"
    )
    """Where to save visualizations and rename logs."""

    process_all_images: bool = True
    """Set to True to process all images in metadata, False to use test_group_images list."""

    test_group_images: list[str] = dataclasses.field(
        default_factory=lambda: [
            "A00000046183.jpg",
            "A00000051535.jpg",
            "A00000041403.jpg",
            "A00000009160.jpg",
            "A00000041381.jpg",
            "A00000051535.jpg",
        ]
    )
    """Only used if process_all_images = False."""

    dry_run: bool = True
    """Set to False to actually rename files (True = just show what would happen)."""

    create_rename_log: bool = True
    """Create a log file of all renames."""

    row_center_tolerance_ratio: float = 50 / 221.4
    """Ratio of tolerance to average beetle height."""

    scalebar_row_tolerance_ratio: float = 50 / 221.4
    """Ratio for scale bar row detection. NOTE: currently unused — is_row_near_scalebar ignores its tolerance arg."""

    # Visualization settings
    bbox_color: tuple[int, int, int] = (255, 0, 0)
    """Red for bounding boxes."""

    bbox_width: int = 4
    """Width of bounding box lines."""

    elytra_length_color: tuple[int, int, int] = (0, 255, 0)
    """Green for elytra length measurements."""

    elytra_width_color: tuple[int, int, int] = (255, 255, 0)
    """Yellow for elytra width measurements."""

    measurement_width: int = 3
    """Width of measurement lines."""

    text_color: tuple[int, int, int] = (255, 255, 255)
    """White for text labels."""


class BeetleMatch(NamedTuple):
    """Result of template matching for one beetle."""

    x: float
    y: float
    width: int
    height: int
    ncc: float  # Normalized cross-correlation score
    individual_path: str  # Relative path, e.g. "part_000/A00000001831_specimen_5.png"
    filename_position: int  # Position claimed in filename (may differ from inferred)


class RenameOperation(NamedTuple):
    """Information about a file rename operation."""

    old_path: pathlib.Path
    new_path: pathlib.Path
    old_relative: str  # Relative path from cfg.hf_root
    new_relative: str  # Relative path from cfg.hf_root
    group_image: str
    old_position: int
    new_position: int


class ScaleBar(NamedTuple):
    """Scale bar position."""

    x1: float
    y1: float
    x2: float
    y2: float

    @property
    def center_y(self) -> float:
        """Y coordinate of scale bar center."""
        return (self.y1 + self.y2) / 2


def parse_coords(coords_str):
    """Parse coordinate string from CSV."""
    if coords_str:
        try:
            coords_str = coords_str.replace('""', '"')
            return ast.literal_eval(coords_str)
        except (ValueError, SyntaxError):
            return {}
    return {}


def create_new_filename(old_path: str, new_position: int) -> str:
    """Return path with corrected position suffix, e.g. "part_000/A_specimen_5.png" -> "..._3.png"."""
    path_obj = pathlib.Path(old_path)
    old_stem = path_obj.stem  # e.g., "A00000001831_specimen_5"
    extension = path_obj.suffix  # e.g., ".png"

    # Split by underscore and replace last part
    parts = old_stem.split("_")
    parts[-1] = str(new_position)
    new_stem = "_".join(parts)

    # Reconstruct path
    new_filename = new_stem + extension
    if path_obj.parent != pathlib.Path("."):
        return str(path_obj.parent / new_filename)
    return new_filename


def update_metadata_csv(
    rename_ops: list[RenameOperation], cfg: Config
) -> tuple[int, int]:
    """Update individualImageFilePath entries in metadata.csv after renames. Returns (successful, failed)."""
    print("\n" + "=" * 60)
    print("UPDATING METADATA CSV")
    print("=" * 60)

    # Try different possible locations for metadata.csv
    possible_paths = [
        cfg.hf_root / "metadata.csv",
        cfg.hf_root / "Separate_segmented_train_test_splits_80_20" / "metadata.csv",
        cfg.hf_root.parent / "individual_specimens.csv",
    ]

    metadata_csv = None
    for path in possible_paths:
        if path.exists():
            metadata_csv = path
            break

    if metadata_csv is None:
        print(f"ERROR: Metadata CSV not found. Tried: {possible_paths}")
        return 0, len(rename_ops)

    # Load metadata
    print(f"Loading metadata from {metadata_csv}")
    metadata_df = pl.read_csv(metadata_csv)
    print(f"  Loaded {len(metadata_df)} rows")

    # Create a mapping of old paths to new paths
    # Both with and without "individual_specimens/" prefix
    path_updates = {}
    for op in rename_ops:
        # Store both versions (with and without prefix)
        path_updates[op.old_relative] = op.new_relative

        # Also store versions with "individual_specimens/" prefix
        old_with_prefix = f"individual_specimens/{op.old_relative}"
        new_with_prefix = f"individual_specimens/{op.new_relative}"
        path_updates[old_with_prefix] = new_with_prefix

    print(f"\nNeed to update {len(rename_ops)} file paths in metadata")

    successful = 0
    failed = 0

    if cfg.dry_run:
        print("\n[DRY RUN] Would update the following metadata rows:")
        for old_path, new_path in path_updates.items():
            # Check if this path exists in metadata
            matching_rows = metadata_df.filter(
                pl.col("individualImageFilePath") == old_path
            )
            if not matching_rows.is_empty():
                print(f"  {old_path} -> {new_path}")
                successful += 1

        print(f"\n[DRY RUN] Would update {successful} rows in metadata.csv")
    else:
        # Create a new column with updated paths
        def update_path(path: str) -> str:
            return path_updates.get(path, path)

        # Update the paths
        original_paths = metadata_df.get_column("individualImageFilePath").to_list()
        updated_paths = [update_path(p) for p in original_paths]

        # Count how many were actually changed
        changes = sum(
            1 for old, new in zip(original_paths, updated_paths) if old != new
        )

        # Create updated dataframe
        updated_df = metadata_df.with_columns(
            pl.Series("individualImageFilePath", updated_paths)
        )

        # Save updated metadata
        print(f"\nUpdating {changes} paths in metadata.csv...")
        updated_df.write_csv(metadata_csv)
        print(f"✓ Saved updated metadata to {metadata_csv}")

        successful = changes
        failed = len(rename_ops) - changes

        if failed > 0:
            print(f"⚠ WARNING: {failed} renames were not found in metadata")

    return successful, failed


def execute_renames(
    rename_ops: list[RenameOperation], dry_run: bool = True
) -> tuple[int, int, list[RenameOperation]]:
    """Rename files via temp names first to avoid conflicts when positions swap. Returns (successful, failed, completed_ops)."""
    successful = 0
    failed = 0
    completed_ops = []  # Track successfully completed operations

    if dry_run:
        # In dry run mode, just show what would happen
        for idx, op in enumerate(rename_ops, 1):
            print(
                f"\n[{idx}/{len(rename_ops)}] {op.group_image}: position {op.old_position} -> {op.new_position}"
            )
            print("  [DRY RUN] Would rename:")
            print(f"    FROM: {op.old_relative}")
            print(f"    TO:   {op.new_relative}")

            if not op.old_path.exists():
                print("    ⚠ WARNING: Source file not found!")
                failed += 1
            else:
                successful += 1
                completed_ops.append(op)
    else:
        # Two-phase rename to avoid conflicts
        temp_mappings = []  # List of (temp_path, final_path, operation) tuples

        print("\n" + "=" * 60)
        print("PHASE 1: Renaming to temporary names")
        print("=" * 60)

        # Phase 1: Rename to temporary names
        for idx, op in enumerate(rename_ops, 1):
            # Create temporary name (add .tmp_rename suffix)
            temp_path = op.old_path.with_suffix(
                op.old_path.suffix + f".tmp_rename_{idx}"
            )

            print(f"\n[{idx}/{len(rename_ops)}] {op.group_image}: Temp rename phase")

            try:
                if not op.old_path.exists():
                    print("  ✗ FAILED: Source file not found!")
                    print(f"    {op.old_relative}")
                    failed += 1
                    continue

                # Rename to temporary name
                op.old_path.rename(temp_path)
                temp_mappings.append((temp_path, op.new_path, op))
                print(f"  ✓ Phase 1 OK: {op.old_path.name} -> {temp_path.name}")

            except Exception as e:
                print(f"  ✗ FAILED: {e}")
                print(f"    FROM: {op.old_relative}")
                failed += 1

        print("\n" + "=" * 60)
        print("PHASE 2: Renaming to final names")
        print("=" * 60)

        # Phase 2: Rename from temporary to final names
        for idx, (temp_path, new_path, op) in enumerate(temp_mappings, 1):
            print(
                f"\n[{idx}/{len(temp_mappings)}] {op.group_image}: position {op.old_position} -> {op.new_position}"
            )

            try:
                # Make sure parent directory exists
                new_path.parent.mkdir(parents=True, exist_ok=True)

                # Rename from temp to final
                temp_path.rename(new_path)
                print("  ✓ Renamed successfully")
                print(f"    FROM: {op.old_relative}")
                print(f"    TO:   {op.new_relative}")
                successful += 1
                completed_ops.append(op)

            except Exception as e:
                print(f"  ✗ FAILED: {e}")
                print(f"    Temp was: {temp_path}")
                print(f"    Target: {op.new_relative}")
                failed += 1

                # Try to restore from temp name on failure
                try:
                    temp_path.rename(op.old_path)
                    print(f"    → Restored to original: {op.old_relative}")
                except Exception as restore_error:
                    print(
                        f"    ⚠ WARNING: Could not restore temp file: {restore_error}"
                    )

    return successful, failed, completed_ops


def load_scale_bar(measurements_df: pl.DataFrame, picture_id: str) -> ScaleBar:
    """Extract scale bar coordinates for a given picture."""
    row = measurements_df.filter(pl.col("pictureID") == picture_id).row(0, named=True)
    coords = parse_coords(row["scalebar"])
    return ScaleBar(x1=coords["x1"], y1=coords["y1"], x2=coords["x2"], y2=coords["y2"])


def template_match_beetles(
    group_image_path: pathlib.Path,
    individual_paths: list[tuple[str, int]],  # (path, filename_position)
    cfg: Config,
) -> list[BeetleMatch]:
    """NCC template-match each individual crop against the group image, returning pixel locations and scores."""
    print(f"\nLoading group image: {group_image_path}")
    group_img = np.asarray(Image.open(group_image_path).convert("L"))
    print(f"  Group image size: {group_img.shape}")

    matches = []

    for indiv_path_str, filename_pos in individual_paths:
        indiv_path = cfg.hf_root / indiv_path_str
        # Strip prefix if present
        if indiv_path_str.startswith("individual_specimens/"):
            indiv_path_str = indiv_path_str[len("individual_specimens/") :]
            indiv_path = cfg.hf_root / indiv_path_str

        print(
            f"\n  Template matching: {indiv_path.name} (filename says position {filename_pos})"
        )

        try:
            template = np.asarray(Image.open(indiv_path).convert("L"))
            print(f"    Template size: {template.shape}")

            # Perform template matching
            corr = skimage.feature.match_template(group_img, template, pad_input=False)

            if corr.size == 0:
                print("    WARNING: Empty correlation map!")
                continue

            # Find best match
            max_idx = np.argmax(corr)
            y, x = np.unravel_index(max_idx, corr.shape)
            ncc_score = float(corr.flat[max_idx])

            match = BeetleMatch(
                x=float(x),
                y=float(y),
                width=template.shape[1],
                height=template.shape[0],
                ncc=ncc_score,
                individual_path=indiv_path_str,  # Store relative path, not full path
                filename_position=filename_pos,
            )

            print(f"    Found at: ({match.x:.1f}, {match.y:.1f}), NCC: {match.ncc:.3f}")
            matches.append(match)

        except Exception as e:
            print(f"    ERROR: {e}")

    return matches


def beetles_on_same_row(
    beetle1: BeetleMatch, beetle2: BeetleMatch, tolerance: float = 30
) -> bool:
    """True if centers, tops, OR bottoms are within tolerance; OR logic handles beetles at different heights on the same row."""
    # Calculate vertical positions
    top1, top2 = beetle1.y, beetle2.y
    bottom1 = beetle1.y + beetle1.height
    bottom2 = beetle2.y + beetle2.height
    center1_y = beetle1.y + beetle1.height / 2
    center2_y = beetle2.y + beetle2.height / 2

    # Check if any alignment metric is within tolerance
    centers_aligned = abs(center1_y - center2_y) <= tolerance
    tops_aligned = abs(top1 - top2) <= tolerance
    bottoms_aligned = abs(bottom1 - bottom2) <= tolerance

    return centers_aligned or tops_aligned or bottoms_aligned


def group_beetles_into_rows(
    matches: list[BeetleMatch], center_tolerance: float = 30
) -> list[list[BeetleMatch]]:
    """Cluster beetles into rows by vertical alignment (iterative merge), sorted top-to-bottom; each row left-to-right."""
    if not matches:
        return []

    # Start with each beetle in its own row
    rows = [[match] for match in matches]

    # Iteratively merge rows that have beetles with similar vertical centers
    merged = True
    while merged:
        merged = False
        new_rows = []
        used = set()

        for i, row1 in enumerate(rows):
            if i in used:
                continue

            # Try to find another row that should be merged with this one
            for j, row2 in enumerate(rows[i + 1 :], start=i + 1):
                if j in used:
                    continue

                # Check if any beetle in row1 is on same row as any beetle in row2
                same_row_found = False
                for beetle1 in row1:
                    for beetle2 in row2:
                        if beetles_on_same_row(beetle1, beetle2, center_tolerance):
                            same_row_found = True
                            break
                    if same_row_found:
                        break

                if same_row_found:
                    # Merge the rows
                    new_rows.append(row1 + row2)
                    used.add(i)
                    used.add(j)
                    merged = True
                    break

            if i not in used:
                new_rows.append(row1)
                used.add(i)

        rows = new_rows

    # Sort each row left-to-right by x coordinate
    for row in rows:
        row.sort(key=lambda m: m.x)

    # Sort rows top-to-bottom by average center y coordinate
    rows.sort(key=lambda row: sum(m.y + m.height / 2 for m in row) / len(row))

    return rows


def is_row_near_scalebar(
    row: list[BeetleMatch], scalebar_y: float, tolerance: float = 50
) -> bool:
    """True if any beetle's vertical midpoint is above scalebar_y. NOTE: tolerance param is currently unused."""
    for beetle in row:
        if beetle.y + (beetle.height / 2) < scalebar_y:
            return True
    return False


def infer_positions(
    matches: list[BeetleMatch],
    scale_bar: ScaleBar,
    row_tolerance: float,
    scalebar_tolerance: float,
) -> dict[int, BeetleMatch]:
    """Map position numbers (1-N) to beetles: scale-bar row numbered first left-to-right, then remaining rows top-to-bottom."""
    print("\n" + "=" * 60)
    print("INFERRING BEETLE POSITIONS")
    print("=" * 60)
    print(f"Scale bar center Y: {scale_bar.center_y:.1f}")

    # Group beetles into rows based on vertical alignment (tops, centers, and bottoms)
    print(
        f"\nGrouping beetles into rows based on vertical alignment (tolerance={row_tolerance:.1f}px)..."
    )
    print("  (Checking if centers, tops, OR bottoms are within tolerance)")
    rows = group_beetles_into_rows(matches, center_tolerance=row_tolerance)
    print(f"Found {len(rows)} distinct rows")

    for row_idx, row in enumerate(rows):
        avg_center_y = sum(m.y + m.height / 2 for m in row) / len(row)
        avg_top_y = sum(m.y for m in row) / len(row)
        avg_bottom_y = sum(m.y + m.height for m in row) / len(row)
        print(f"  Row {row_idx + 1}: {len(row)} beetles")
        print(
            f"    Avg top Y: {avg_top_y:.1f}, Avg center Y: {avg_center_y:.1f}, Avg bottom Y: {avg_bottom_y:.1f}"
        )
        for beetle in row:
            center_y = beetle.y + beetle.height / 2
            bottom_y = beetle.y + beetle.height
            print(
                f"    - x={beetle.x:.1f}, top={beetle.y:.1f}, center={center_y:.1f}, bottom={bottom_y:.1f}, size=({beetle.width}x{beetle.height})"
            )

    # Find which row contains the scale bar
    scalebar_row_idx = None
    for idx, row in enumerate(rows):
        if is_row_near_scalebar(row, scale_bar.center_y, tolerance=scalebar_tolerance):
            scalebar_row_idx = idx
            print(f"\nRow {idx + 1} is aligned with scale bar!")
            break

    # Build position map
    position_map = {}
    current_pos = 1

    if scalebar_row_idx is not None:
        # PRIORITY: Start with scale bar row - leftmost beetle = position 1
        print(f"\n{'=' * 60}")
        print("SCALE BAR ROW DETECTED - This row will be numbered FIRST")
        print(f"{'=' * 60}")
        print(
            f"\nAssigning positions starting with scale bar row (row {scalebar_row_idx + 1}):"
        )
        print("  (Beetles in this row ordered left-to-right)")

        scalebar_row = rows[scalebar_row_idx]
        for beetle in scalebar_row:
            position_map[current_pos] = beetle
            print(
                f"  Position {current_pos}: ({beetle.x:.1f}, {beetle.y:.1f}) <- {'LEFTMOST on scale bar row' if current_pos == 1 else ''}"
            )
            current_pos += 1

        # Continue with other rows in top-to-bottom order
        print("\nContinuing with remaining rows (top-to-bottom):")
        for idx, row in enumerate(rows):
            if idx == scalebar_row_idx:
                continue
            print(f"\nAssigning positions for row {idx + 1}:")
            for beetle in row:
                position_map[current_pos] = beetle
                print(f"  Position {current_pos}: ({beetle.x:.1f}, {beetle.y:.1f})")
                current_pos += 1
    else:
        # No scale bar row found, use all rows in order
        print(f"\n{'=' * 60}")
        print("NO SCALE BAR ROW DETECTED")
        print("Using top-to-bottom, left-to-right ordering")
        print(f"{'=' * 60}")
        for idx, row in enumerate(rows):
            print(f"\nAssigning positions for row {idx + 1}:")
            for beetle in row:
                position_map[current_pos] = beetle
                if current_pos == 1:
                    print(
                        f"  Position {current_pos}: ({beetle.x:.1f}, {beetle.y:.1f}) <- TOP-LEFT beetle"
                    )
                else:
                    print(f"  Position {current_pos}: ({beetle.x:.1f}, {beetle.y:.1f})")
                current_pos += 1

    return position_map


def get_measurements(
    measurements_df: pl.DataFrame, picture_id: str, inferred_position: int
) -> dict[str, dict]:
    """Return ElytraLength and ElytraWidth coordinate dicts for one beetle position."""
    rows = measurements_df.filter(
        (pl.col("pictureID") == picture_id)
        & (pl.col("individual") == inferred_position)
    )

    measurements = {}
    for row in rows.iter_rows(named=True):
        structure = row["structure"]
        coords = parse_coords(row["coords_pix"])
        if coords and "x1" in coords:
            measurements[structure] = coords

    return measurements


def visualize_results(
    group_image_path: pathlib.Path,
    position_map: dict[int, BeetleMatch],
    measurements_df: pl.DataFrame,
    picture_id: str,
    scale_bar: ScaleBar,
    output_path: pathlib.Path,
    cfg: Config,
):
    """Draw bounding boxes, alignment lines, scale bar, and elytra measurements on the group image."""
    print("\n" + "=" * 60)
    print("CREATING VISUALIZATION")
    print("=" * 60)

    # Load image
    img = Image.open(group_image_path).convert("RGB")
    draw = ImageDraw.Draw(img)

    # Try to load a font, fallback to default
    try:
        font = ImageFont.truetype("arial.ttf", 40)
    except OSError:
        font = ImageFont.load_default()

    # Draw the scale bar first (so it's in the background)
    print("\nDrawing scale bar:")
    print(
        f"  From ({scale_bar.x1:.1f}, {scale_bar.y1:.1f}) to ({scale_bar.x2:.1f}, {scale_bar.y2:.1f})"
    )
    print(f"  Center Y: {scale_bar.center_y:.1f}")

    # Draw the scale bar line in cyan/blue
    draw.line(
        [(scale_bar.x1, scale_bar.center_y), (scale_bar.x2, scale_bar.center_y)],
        fill=(0, 255, 255),  # Cyan
        width=6,
    )

    # Draw endpoint circles
    for x, y in [(scale_bar.x1, scale_bar.y1), (scale_bar.x2, scale_bar.y2)]:
        radius = 10
        draw.ellipse(
            [x - radius, y - radius, x + radius, y + radius],
            fill=(0, 255, 255),
            outline=(255, 255, 255),
            width=2,
        )

    # Draw a horizontal reference line at the scale bar's center Y
    img_width = img.size[0]
    draw.line(
        [(0, scale_bar.center_y), (img_width, scale_bar.center_y)],
        fill=(0, 200, 200),  # Darker cyan
        width=2,
    )

    # Draw each beetle
    for inferred_pos, match in position_map.items():
        print(f"\nDrawing beetle at inferred position {inferred_pos}:")
        print(f"  Location: ({match.x:.1f}, {match.y:.1f})")
        print(f"  Filename claimed position: {match.filename_position}")

        # Draw bounding box
        bbox = [match.x, match.y, match.x + match.width, match.y + match.height]
        draw.rectangle(bbox, outline=cfg.bbox_color, width=cfg.bbox_width)

        # Draw horizontal alignment reference lines
        center_y = match.y + match.height / 2
        top_y = match.y
        bottom_y = match.y + match.height

        # Center line (magenta)
        draw.line(
            [(match.x, center_y), (match.x + match.width, center_y)],
            fill=(255, 0, 255),  # Magenta
            width=2,
        )
        # Top line (light blue)
        draw.line(
            [(match.x, top_y), (match.x + match.width, top_y)],
            fill=(173, 216, 230),  # Light blue
            width=1,
        )
        # Bottom line (orange)
        draw.line(
            [(match.x, bottom_y), (match.x + match.width, bottom_y)],
            fill=(255, 165, 0),  # Orange
            width=1,
        )

        # Draw position label
        label = f"#{inferred_pos}"
        text_pos = (match.x + 10, match.y + 10)

        # Draw text with background for visibility
        bbox_text = draw.textbbox(text_pos, label, font=font)
        draw.rectangle(bbox_text, fill=(0, 0, 0))
        draw.text(text_pos, label, fill=cfg.text_color, font=font)

        # Get and draw measurements
        measurements = get_measurements(measurements_df, picture_id, inferred_pos)

        if "ElytraLength" in measurements:
            coords = measurements["ElytraLength"]
            draw.line(
                [(coords["x1"], coords["y1"]), (coords["x2"], coords["y2"])],
                fill=cfg.elytra_length_color,
                width=cfg.measurement_width,
            )
            print(
                f"  Drew ElytraLength: ({coords['x1']}, {coords['y1']}) -> ({coords['x2']}, {coords['y2']})"
            )

        if "ElytraWidth" in measurements:
            coords = measurements["ElytraWidth"]
            draw.line(
                [(coords["x1"], coords["y1"]), (coords["x2"], coords["y2"])],
                fill=cfg.elytra_width_color,
                width=cfg.measurement_width,
            )
            print(
                f"  Drew ElytraWidth: ({coords['x1']}, {coords['y1']}) -> ({coords['x2']}, {coords['y2']})"
            )

    # Save output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_path)
    print(f"\nSaved visualization to: {output_path}")


def process_single_image(
    test_group_image: str,
    measurements_df: pl.DataFrame,
    metadata_df: pl.DataFrame,
    cfg: Config,
) -> list[RenameOperation]:
    """Template match, infer positions, and visualize one group image; return renames needed to fix position labels."""
    print("\n" + "=" * 80)
    print(f"PROCESSING: {test_group_image}")
    print("=" * 80)

    rename_operations = []

    # Get scale bar
    scale_bar = load_scale_bar(measurements_df, test_group_image)
    print(
        f"\nScale bar: ({scale_bar.x1:.1f}, {scale_bar.y1:.1f}) -> ({scale_bar.x2:.1f}, {scale_bar.y2:.1f})"
    )
    print(f"  Center Y: {scale_bar.center_y:.1f}")

    # Get individual images for this group
    group_rows = metadata_df.filter(
        pl.col("groupImageFilePath") == f"group_images/{test_group_image}"
    )

    print(f"\nFound {len(group_rows)} individual beetles for this group image")

    if len(group_rows) == 0:
        print(
            f"WARNING: No individual beetles found for {test_group_image}, skipping..."
        )
        return rename_operations

    # Extract individual paths and their claimed positions
    individual_paths = []
    for row in group_rows.iter_rows(named=True):
        path = row["individualImageFilePath"]
        # Extract position from filename (e.g., "A00000032929_specimen_1.png" -> 1)
        filename = pathlib.Path(path).stem  # Get filename without extension
        try:
            # Split by underscore and get last part
            claimed_pos = int(filename.split("_")[-1])
        except (ValueError, IndexError):
            claimed_pos = 0
        individual_paths.append((path, claimed_pos))

    # Template match all beetles
    group_image_path = cfg.resized_root / test_group_image
    if not group_image_path.exists():
        print(f"ERROR: Group image not found at {group_image_path}, skipping...")
        return rename_operations

    matches = template_match_beetles(group_image_path, individual_paths, cfg)

    if not matches:
        print("\nERROR: No successful template matches!")
        return rename_operations

    print(f"\nSuccessfully matched {len(matches)} beetles")

    # Calculate and print statistics about beetle sizes
    avg_height = sum(m.height for m in matches) / len(matches)
    avg_width = sum(m.width for m in matches) / len(matches)
    min_height = min(m.height for m in matches)
    max_height = max(m.height for m in matches)

    print("\nBeetle size statistics:")
    print(f"  Average height: {avg_height:.1f} pixels")
    print(f"  Average width: {avg_width:.1f} pixels")
    print(f"  Height range: {min_height} - {max_height} pixels")

    # Calculate dynamic thresholds based on average beetle height
    row_center_tolerance = avg_height * cfg.row_center_tolerance_ratio
    scalebar_row_tolerance = avg_height * cfg.scalebar_row_tolerance_ratio

    print("\nDynamic thresholds (based on avg height):")
    print(f"  Row center tolerance: {row_center_tolerance:.1f} pixels")
    print(f"  Scale bar row tolerance: {scalebar_row_tolerance:.1f} pixels")

    # Infer correct positions
    position_map = infer_positions(
        matches, scale_bar, row_center_tolerance, scalebar_row_tolerance
    )

    # Visualize results
    output_path = (
        cfg.output_dir / f"{test_group_image.replace('.jpg', '_annotated.png')}"
    )
    visualize_results(
        group_image_path,
        position_map,
        measurements_df,
        test_group_image,
        scale_bar,
        output_path,
        cfg,
    )

    # Create rename operations for files that need position correction
    print("\n" + "=" * 60)
    print("FILE RENAMING ANALYSIS")
    print("=" * 60)

    for inferred_pos, match in sorted(position_map.items()):
        if inferred_pos != match.filename_position:
            # Position needs to be corrected
            # match.individual_path is already the relative path (e.g., "part_000/filename.png")
            old_relative = match.individual_path
            new_relative = create_new_filename(old_relative, inferred_pos)

            old_full_path = cfg.hf_root / old_relative
            new_full_path = cfg.hf_root / new_relative

            rename_op = RenameOperation(
                old_path=old_full_path,
                new_path=new_full_path,
                old_relative=old_relative,
                new_relative=new_relative,
                group_image=test_group_image,
                old_position=match.filename_position,
                new_position=inferred_pos,
            )
            rename_operations.append(rename_op)
            print(
                f"  Position {inferred_pos}: needs rename (currently labeled as {match.filename_position})"
            )
        else:
            print(f"  Position {inferred_pos}: correct (no rename needed)")

    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Image: {test_group_image}")
    print(f"Total beetles: {len(matches)}")
    print(f"Files needing rename: {len(rename_operations)}")
    print(f"Output saved to: {output_path}")

    return rename_operations


def main(cfg: Config) -> int:
    """Load measurements and metadata, process all group images, execute renames, and update metadata.csv."""
    print("=" * 80)
    print("BEETLE POSITION INFERENCE AND TEMPLATE MATCHING")
    print("=" * 80)

    # Load data once
    print("\nLoading data...")

    # Find measurements CSV
    measurements_csv = cfg.hf_root.parent / "BeetleMeasurements.csv"
    if not measurements_csv.exists():
        measurements_csv = cfg.hf_root / "BeetleMeasurements.csv"

    if not measurements_csv.exists():
        print(f"ERROR: BeetleMeasurements.csv not found at {measurements_csv}")
        return 1

    # Find metadata CSV
    possible_metadata_paths = [
        cfg.hf_root / "metadata.csv",
        cfg.hf_root / "Separate_segmented_train_test_splits_80_20" / "metadata.csv",
        cfg.hf_root.parent / "individual_specimens.csv",
    ]

    metadata_csv = None
    for path in possible_metadata_paths:
        if path.exists():
            metadata_csv = path
            break

    if metadata_csv is None:
        print(f"ERROR: Metadata CSV not found. Tried: {possible_metadata_paths}")
        return 1

    measurements_df = pl.read_csv(measurements_csv)
    metadata_df = pl.read_csv(metadata_csv)
    print(f"  Measurements: {len(measurements_df)} rows")
    print(f"  Metadata: {len(metadata_df)} rows")

    # Determine which images to process
    if cfg.process_all_images:
        # Get all unique group images from metadata
        all_group_images = (
            metadata_df.get_column("groupImageFilePath").unique().to_list()
        )
        # Extract just the filename (remove "group_images/" prefix)
        images_to_process = [path.split("/")[-1] for path in all_group_images]
        print(f"\nProcessing ALL {len(images_to_process)} group images from metadata")
    else:
        images_to_process = cfg.test_group_images
        print(f"\nProcessing {len(images_to_process)} specified test images")

    # Process each image and collect rename operations
    all_rename_operations = []
    successful_images = 0
    failed_images = 0

    for idx, test_image in enumerate(images_to_process, 1):
        print(f"\n\n{'#' * 80}")
        print(f"# IMAGE {idx}/{len(images_to_process)}: {test_image}")
        print(f"{'#' * 80}")
        try:
            rename_ops = process_single_image(
                test_image, measurements_df, metadata_df, cfg
            )
            all_rename_operations.extend(rename_ops)
            successful_images += 1
        except Exception as e:
            print(f"\nERROR processing {test_image}: {e}")
            import traceback

            traceback.print_exc()
            failed_images += 1
            continue

    # Summary of all rename operations
    print("\n\n" + "=" * 80)
    print("FINAL SUMMARY")
    print("=" * 80)
    print(f"Images processed successfully: {successful_images}")
    print(f"Images failed: {failed_images}")
    print(f"Total files needing rename: {len(all_rename_operations)}")
    print(f"Output directory: {cfg.output_dir}")

    if len(all_rename_operations) == 0:
        print("\nNo files need to be renamed - all positions are correct!")
        return 0

    # Create rename log if requested
    if cfg.create_rename_log:
        log_file = (
            cfg.output_dir
            / f"rename_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        )
        cfg.output_dir.mkdir(parents=True, exist_ok=True)

        with open(log_file, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([
                "group_image",
                "old_position",
                "new_position",
                "old_path",
                "new_path",
            ])
            for op in all_rename_operations:
                writer.writerow([
                    op.group_image,
                    op.old_position,
                    op.new_position,
                    op.old_relative,
                    op.new_relative,
                ])
        print(f"\nRename log saved to: {log_file}")

    # Execute renames
    print("\n" + "=" * 80)
    if cfg.dry_run:
        print("DRY RUN MODE - No files will be renamed")
    else:
        print("EXECUTING FILE RENAMES")
    print("=" * 80)

    successful, failed, completed_ops = execute_renames(
        all_rename_operations, dry_run=cfg.dry_run
    )

    print("\nRename results:")
    print(f"  Successful: {successful}")
    print(f"  Failed: {failed}")

    # Update metadata.csv to reflect the renamed files
    if len(completed_ops) > 0:
        metadata_success, metadata_failed = update_metadata_csv(completed_ops, cfg)
        print("\nMetadata update results:")
        print(f"  Updated: {metadata_success}")
        print(f"  Not found in metadata: {metadata_failed}")

    if cfg.dry_run:
        print(
            "\nTo actually rename files and update metadata, set --no-dry-run when running the script"
        )
    else:
        print("\nFiles have been renamed and metadata.csv has been updated!")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(tyro.cli(Config)))
    except KeyboardInterrupt:
        print("Interrupted.")
        raise SystemExit(130)
