import os
import csv
import argparse
import time
import random
import moondream as md
from PIL import Image, ImageDraw


def load_moondream():
    api_key = os.environ.get("MOONDREAM_API_KEY")
    if not api_key:
        raise ValueError("❌ MOONDREAM_API_KEY environment variable is not set!")
    return md.vl(api_key=api_key)


def calculate_iou(box1, box2):
    x_left = max(box1["x_min"], box2["x_min"])
    y_top = max(box1["y_min"], box2["y_min"])
    x_right = min(box1["x_max"], box2["x_max"])
    y_bottom = min(box1["y_max"], box2["y_max"])

    if x_right < x_left or y_bottom < y_top:
        return 0.0

    intersection_area = (x_right - x_left) * (y_bottom - y_top)
    area_box1 = (box1["x_max"] - box1["x_min"]) * (box1["y_max"] - box1["y_min"])
    area_box2 = (box2["x_max"] - box2["x_min"]) * (box2["y_max"] - box2["y_min"])
    union_area = float(area_box1 + area_box2 - intersection_area)

    return intersection_area / union_area if union_area > 0 else 0.0


def get_box_area(box):
    return (box["x_max"] - box["x_min"]) * (box["y_max"] - box["y_min"])


# NEW: mirrors the beetle script — flat Good/Recheck dirs would otherwise collide
# whenever two source subdirectories contain the same filename, and the
# resume-skip below would then wrongly skip the second one.
def flat_name(image_dir, image_path):
    rel = os.path.relpath(image_path, image_dir)
    return rel.replace(os.sep, "__")


def detect_colorpicker(image, model):

    width, height = image.size
    prompts = ["a color palette", "a colorpicker"]
    all_detected_boxes = []

    for prompt in prompts:
        max_retries = 5
        result = None
        for attempt in range(max_retries):
            try:
                time.sleep(random.uniform(0.1, 0.3))
                result = model.detect(image, prompt)
                break
            except Exception as e:
                if "429" in str(e) and attempt < max_retries - 1:
                    wait_time = (2 ** attempt) + random.random()
                    print(f"⚠️ Rate limited on prompt '{prompt}'. Waiting {wait_time:.1f}s...")
                    time.sleep(wait_time)
                else:
                    raise e

        if result:
            objects = result.get("objects", [])
            # Prioritize taking only one bounding box per prompt per image
            if objects:
                obj = objects[0]
                x1 = int(obj["x_min"] * width)
                y1 = int(obj["y_min"] * height)
                x2 = int(obj["x_max"] * width)
                y2 = int(obj["y_max"] * height)
                all_detected_boxes.append({"x_min": x1, "y_min": y1, "x_max": x2, "y_max": y2})

    if not all_detected_boxes:
        return [], True

    # Check for overlap if we got detections from both prompts
    overlapping_pair = None
    if len(all_detected_boxes) >= 2:
        iou = calculate_iou(all_detected_boxes[0], all_detected_boxes[1])
        if iou >= 0.75:
            overlapping_pair = (all_detected_boxes[0], all_detected_boxes[1])

    if overlapping_pair:
        b1, b2 = overlapping_pair
        merged_box = {
            "x_min": int((b1["x_min"] + b2["x_min"]) / 2),
            "y_min": int((b1["y_min"] + b2["y_min"]) / 2),
            "x_max": int((b1["x_max"] + b2["x_max"]) / 2),
            "y_max": int((b1["y_max"] + b2["y_max"]) / 2),
        }
        return [merged_box], False

    # Fallback: Select the smaller bounding box, flag for human verification
    smallest_box = min(all_detected_boxes, key=get_box_area)
    return [smallest_box], True


def main():
    parser = argparse.ArgumentParser(description="Colorpicker Detection Chunk Runner")
    parser.add_argument("--image_dir", type=str, required=True)
    parser.add_argument("--output_dir", type=str, required=True)
    parser.add_argument("--task_id", type=int, default=0)
    parser.add_argument("--num_tasks", type=int, default=1)
    args = parser.parse_args()

    good_dir = os.path.join(args.output_dir, "Plotted_Good")
    recheck_dir = os.path.join(args.output_dir, "Plotted_Recheck")
    os.makedirs(good_dir, exist_ok=True)
    os.makedirs(recheck_dir, exist_ok=True)

    csv_path = os.path.join(args.output_dir, f"Colorpickers_task_{args.task_id}.csv")
    model = load_moondream()

    all_images = []
    for root, dirs, files in os.walk(args.image_dir):
        for file in files:
            if file.lower().endswith((".png", ".jpg", ".jpeg")):
                if "SmallBeetles" not in root and "SmallBeetles" not in file:
                    all_images.append(os.path.join(root, file))

    all_images.sort()

    total_images = len(all_images)
    chunk_size = (total_images // args.num_tasks) + 1
    start_idx = args.task_id * chunk_size
    end_idx = min(start_idx + chunk_size, total_images)
    my_chunk = all_images[start_idx:end_idx]

    print(f"🚀 Task {args.task_id}/{args.num_tasks}: Processing indices {start_idx} to {end_idx} ({len(my_chunk)} items)...")

    fieldnames = ["image_name", "plotted_image", "num_colorpickers", "colorpicker_coords", "verify"]

    # CHANGED: hoisted out of the loop — one stat per task, not one per image.
    csv_exists = os.path.isfile(csv_path)

    for image_path in my_chunk:
        base_name = flat_name(args.image_dir, image_path)

        # NEW: resume-skip so a requeued SLURM task doesn't re-burn API calls.
        if (os.path.exists(os.path.join(good_dir, base_name)) or
                os.path.exists(os.path.join(recheck_dir, base_name))):
            print(f"⏭️ Skipping {base_name} (Already processed)")
            continue

        try:
            with Image.open(image_path) as src:
                image = src.convert("RGB")

            coords_list, recheck_flag = detect_colorpicker(image, model)

            if len(coords_list) != 1:
                recheck_flag = True

            draw = ImageDraw.Draw(image)
            for box in coords_list:
                draw.rectangle([box["x_min"], box["y_min"], box["x_max"], box["y_max"]], outline="red", width=2)

            target_dir = recheck_dir if recheck_flag else good_dir
            plotted_image_path = os.path.join(target_dir, base_name)
            image.save(plotted_image_path)

            row_data = {
                "image_name": image_path,
                "plotted_image": plotted_image_path,
                "num_colorpickers": len(coords_list),
                "colorpicker_coords": str(coords_list),
                "verify": recheck_flag,
            }

            # CHANGED: append one row per image instead of rewriting the whole
            # file (was O(n^2) and lost the entire log if interrupted mid-write).
            with open(csv_path, "a", newline="") as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                if not csv_exists:
                    writer.writeheader()
                    csv_exists = True
                writer.writerow(row_data)
                csvfile.flush()
                os.fsync(csvfile.fileno())

        except Exception as e:
            print(f"[ERROR] {image_path}: {e}")

    print(f"✅ Task {args.task_id} complete. Log saved to {csv_path}")


if __name__ == "__main__":
    main()