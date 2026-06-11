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


def detect_scalebar(image, model):
    width, height = image.size
    total_image_area = width * height
    max_allowed_area = 0.10 * total_image_area  # 10% of total size rule

    prompts = ["a scalebar", "a centimeter scale"]
    all_detected_boxes = []

    # 1. Collect boxes from both prompts (Max 1 per prompt)
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
            if objects:
                obj = objects[0]
                x1 = int(obj["x_min"] * width)
                y1 = int(obj["y_min"] * height)
                x2 = int(obj["x_max"] * width)
                y2 = int(obj["y_max"] * height)
                all_detected_boxes.append({"x_min": x1, "y_min": y1, "x_max": x2, "y_max": y2})

    if not all_detected_boxes:
        return [], True

    # 2. If we have exactly two boxes, check for a clean overlap first
    if len(all_detected_boxes) == 2:
        iou = calculate_iou(all_detected_boxes[0], all_detected_boxes[1])
        if iou >= 0.6:
            merged_box = {
                "x_min": int((all_detected_boxes[0]["x_min"] + all_detected_boxes[1]["x_min"]) / 2),
                "y_min": int((all_detected_boxes[0]["y_min"] + all_detected_boxes[1]["y_min"]) / 2),
                "x_max": int((all_detected_boxes[0]["x_max"] + all_detected_boxes[1]["x_max"]) / 2),
                "y_max": int((all_detected_boxes[0]["y_max"] + all_detected_boxes[1]["y_max"]) / 2),
            }
            return [merged_box], False

    # 3. If overlap is low or we only have one box, filter out boxes > 10% area
    valid_boxes = [box for box in all_detected_boxes if get_box_area(box) <= max_allowed_area]

    if not valid_boxes:
        return [], True  # Both boxes were giant hallucinations, drop them all

    # 4. If we filtered out a giant box and are left with exactly one good box, return it
    if len(valid_boxes) == 1:
        return [valid_boxes[0]], True

    # 5. Fallback: Both boxes are under 10% but don't overlap, take the smaller one
    smallest_box = min(valid_boxes, key=get_box_area)
    return [smallest_box], True


def main():
    parser = argparse.ArgumentParser(description="Scalebar Detection Chunk Runner")
    parser.add_argument("--image_dir", type=str, required=True)
    parser.add_argument("--output_dir", type=str, required=True)
    parser.add_argument("--task_id", type=int, default=0)
    parser.add_argument("--num_tasks", type=int, default=1)
    args = parser.parse_args()

    good_dir = os.path.join(args.output_dir, "Plotted_Good")
    recheck_dir = os.path.join(args.output_dir, "Plotted_Recheck")
    os.makedirs(good_dir, exist_ok=True)
    os.makedirs(recheck_dir, exist_ok=True)

    csv_path = os.path.join(args.output_dir, f"Scalebars_task_{args.task_id}.csv")
    model = load_moondream()

    all_images = []
    for root, dirs, files in os.walk(args.image_dir):
        for file in files:
            if file.lower().endswith((".png", ".jpg", ".jpeg")):
                all_images.append(os.path.join(root, file))
    
    all_images.sort()

    total_images = len(all_images)
    chunk_size = (total_images // args.num_tasks) + 1
    start_idx = args.task_id * chunk_size
    end_idx = min(start_idx + chunk_size, total_images)
    my_chunk = all_images[start_idx:end_idx]

    print(f"🚀 Task {args.task_id}/{args.num_tasks}: Processing indices {start_idx} to {end_idx} ({len(my_chunk)} items)...")

    # Check if CSV exists so we know whether to write the header
    csv_exists = os.path.isfile(csv_path)

    for image_path in my_chunk:
        base_name = os.path.basename(image_path)
        
        
        expected_good_path = os.path.join(good_dir, base_name)
        expected_recheck_path = os.path.join(recheck_dir, base_name)
        
        if os.path.exists(expected_good_path) or os.path.exists(expected_recheck_path):
            print(f"⏭️ Skipping {base_name} (Already processed)")
            continue
        

        try:
            image = Image.open(image_path).convert("RGB")
            coords_list, recheck_flag = detect_scalebar(image, model)

            if len(coords_list) != 1:
                recheck_flag = True

            draw = ImageDraw.Draw(image)
            for box in coords_list:
                draw.rectangle([box["x_min"], box["y_min"], box["x_max"], box["y_max"]], outline="red", width=3)

            target_dir = recheck_dir if recheck_flag else good_dir
            plotted_image_path = os.path.join(target_dir, base_name)
            image.save(plotted_image_path)

            row_data = {
                "image_name": image_path,
                "plotted_image": plotted_image_path,
                "num_scalebars": len(coords_list),
                "scalebar_coords": str(coords_list),
                "verify": recheck_flag
            }

            with open(csv_path, "a", newline="") as csvfile:
                fieldnames = ["image_name", "plotted_image", "num_scalebars", "scalebar_coords", "verify"]
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                
                # Only write the header once
                if not csv_exists:
                    writer.writeheader()
                    csv_exists = True 
                    
                writer.writerow(row_data)

        except Exception as e:
            print(f"[ERROR] {image_path}: {e}")

    print(f"✅ Task {args.task_id} complete. Log saved to {csv_path}")

    


if __name__ == "__main__":
    main()