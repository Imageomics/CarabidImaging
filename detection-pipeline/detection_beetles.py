import warnings
warnings.filterwarnings("ignore")

import os
import torch
import argparse
import pandas as pd
import numpy as np
from tqdm import tqdm
from PIL import Image, ImageDraw, ImageFile
from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection
from transformers import LlavaNextProcessor, LlavaNextForConditionalGeneration
ImageFile.LOAD_TRUNCATED_IMAGES = True


class Detection:
    def __init__(self, image_paths, output_dir,
                 model_id="IDEA-Research/grounding-dino-base",
                 dino_prompt="a beetle.",
                 metadata_file=None):

        self.image_paths = image_paths
        self.output_dir = output_dir
        self.model_id = model_id
        self.dino_prompt = dino_prompt
        self.metadata_file = metadata_file
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        self.processor = AutoProcessor.from_pretrained(model_id)
        self.model = AutoModelForZeroShotObjectDetection.from_pretrained(model_id).to(self.device)

        self.llava_processor, self.llava_model = self.setup_llava_model()
        self.df = self._load_metadata() if metadata_file else None
        self.imagenet_mean = [123.675, 116.28, 103.53]

    # ---------------- LLaVA ----------------
    def setup_llava_model(self):
        model_name = "llava-hf/llava-v1.6-mistral-7b-hf"
        processor = LlavaNextProcessor.from_pretrained(model_name, use_fast=True)
        model = LlavaNextForConditionalGeneration.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        ).to(self.device)
        return processor, model

    # ---------------- Metadata ----------------
    def _load_metadata(self):
        if self.metadata_file.endswith('.csv'):
            df = pd.read_csv(self.metadata_file)
            df = df.loc[:, ~df.columns.str.contains('^Unnamed')]
        elif self.metadata_file.endswith('.json'):
            df = pd.read_json(self.metadata_file)
        else:
            raise ValueError("Metadata file must be CSV or JSON")
        return df

    def extract_ground_truth(self, image_path):
        if self.df is None:
            return None
        base_name = os.path.basename(image_path)
        image_rows = self.df[self.df['imageID'] == base_name]
        if not image_rows.empty:
            val = image_rows['NumberOfBeetlesInTray'].iloc[0]
            if np.isinf(val):
                val = np.nan
            if pd.notna(val):
                return int(val)
        return None

    # ---------------- Utilities ----------------
    def adaptive_thresholds(self, start=0.30, end=0.10, step=0.05):
        t = start
        thresholds = []
        while t >= end:
            thresholds.append(round(t, 2))
            t -= step
        return thresholds

    def sort_boxes_reading_order(self, boxes):
        return sorted(boxes, key=lambda b: (b['box'][1], b['box'][0]))

    def split_two_trays(self, image, filename):
        if "-and-" not in filename:
            return [("single", image)]

        w, h = image.size

        tray1 = image.copy()
        tray2 = image.copy()

        tray1_np = np.array(tray1)
        tray1_np[h//2:, :, :] = self.imagenet_mean
        tray1 = Image.fromarray(tray1_np.astype(np.uint8))

        tray2_np = np.array(tray2)
        tray2_np[:h//2, :, :] = self.imagenet_mean
        tray2 = Image.fromarray(tray2_np.astype(np.uint8))

        return [("tray1", tray1), ("tray2", tray2)]

    def compute_iou(self, box1, box2):
        x1, y1, x2, y2 = box1
        x1g, y1g, x2g, y2g = box2

        xi1 = max(x1, x1g)
        yi1 = max(y1, y1g)
        xi2 = min(x2, x2g)
        yi2 = min(y2, y2g)

        inter_width = max(0, xi2 - xi1)
        inter_height = max(0, yi2 - yi1)
        intersection = inter_width * inter_height

        box1_area = (x2 - x1) * (y2 - y1)
        box2_area = (x2g - x1g) * (y2g - y1g)
        union = box1_area + box2_area - intersection

        return intersection / union if union > 0 else 0

    def compute_containment_ratio(self, small_box, large_box):
        sx1, sy1, sx2, sy2 = small_box
        lx1, ly1, lx2, ly2 = large_box

        xi1 = max(sx1, lx1)
        yi1 = max(sy1, ly1)
        xi2 = min(sx2, lx2)
        yi2 = min(sy2, ly2)

        inter_width = max(0, xi2 - xi1)
        inter_height = max(0, yi2 - yi1)
        intersection = inter_width * inter_height

        small_area = (sx2 - sx1) * (sy2 - sy1)
        return intersection / small_area if small_area > 0 else 0

    def filter_overlapping_boxes(self, detections, iou_threshold=0.4):
        if len(detections) <= 1:
            return detections

        sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
        keep = []

        for detection in sorted_detections:
            box = detection['box']
            should_keep = True
            for kept in keep:
                if self.compute_iou(box, kept['box']) > iou_threshold:
                    should_keep = False
                    break
            if should_keep:
                keep.append(detection)
        return keep

    def filter_contained_boxes(self, detections, containment_threshold=0.6, size_ratio_threshold=0.75):
        if len(detections) <= 1:
            return detections

        sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
        keep = []

        for detection in sorted_detections:
            current_box = detection['box']
            current_area = (current_box[2] - current_box[0]) * (current_box[3] - current_box[1])
            should_keep = True

            for kept in keep:
                kept_box = kept['box']
                kept_area = (kept_box[2] - kept_box[0]) * (kept_box[3] - kept_box[1])

                if current_area < kept_area * size_ratio_threshold:
                    containment_ratio = self.compute_containment_ratio(current_box, kept_box)
                    if containment_ratio > containment_threshold:
                        should_keep = False
                        break

            if should_keep:
                keep.append(detection)

        return keep

    def whiteout_boxes(self, image, boxes):
        image_np = np.array(image)
        for box in boxes:
            x1, y1, x2, y2 = [int(coord) for coord in box]
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(image_np.shape[1], x2), min(image_np.shape[0], y2)
            image_np[y1:y2, x1:x2, :] = self.imagenet_mean
        return Image.fromarray(image_np.astype(np.uint8))

    # ---------------- Detection ----------------
    def detect_objects(self):

        os.makedirs(self.output_dir, exist_ok=True)
        csv_path = os.path.join(self.output_dir, "Detection_results.csv")
        crop_root = os.path.join(self.output_dir, "cropped_images")
        tray_root = os.path.join(self.output_dir, "plotted_trays")

        os.makedirs(crop_root, exist_ok=True)
        os.makedirs(tray_root, exist_ok=True)

        count_records = []

        for image_path in tqdm(self.image_paths, desc="Processing"):
            
            try:
                image = Image.open(image_path)
                image.verify()
                image = Image.open(image_path).convert("RGB")
            except Exception as e:
                print(f"[WARNING] Skipping corrupted image: {image_path}")
                print(f"Reason: {e}")
                
                with open(os.path.join(self.output_dir, "BadImages.txt"), "a") as f:
                    f.write(image_path + "\n")
                continue

            tray_images = self.split_two_trays(image, os.path.basename(image_path))

            for tray_tag, tray_img in tray_images:

                current_image = tray_img.copy()
                img_width, img_height = current_image.size
                img_area = img_width * img_height

                base_name = os.path.splitext(os.path.basename(image_path))[0]
                if tray_tag != "single":
                    base_name = f"{base_name}_{tray_tag}"

                actual_count = self.extract_ground_truth(image_path)

                all_filtered_boxes = []

                # ---- Adaptive Threshold Loop ----
                for thr in self.adaptive_thresholds():

                    inputs = self.processor(images=current_image,
                                            text=self.dino_prompt,
                                            return_tensors="pt").to(self.device)

                    with torch.no_grad():
                        outputs = self.model(**inputs)

                    detection_results = self.processor.post_process_grounded_object_detection(
                        outputs,
                        inputs.input_ids,
                        threshold=thr,
                        text_threshold=0.2,
                        target_sizes=[current_image.size[::-1]]
                    )

                    temp_boxes = []
                    for result in detection_results:
                        boxes = result["boxes"]
                        scores = result["scores"]

                        for box, score in zip(boxes, scores):
                            x1, y1, x2, y2 = box.tolist()
                            box_area = (x2 - x1) * (y2 - y1)
                            size_ratio = box_area / img_area

                            if size_ratio <= 0.05:
                                temp_boxes.append({
                                    'box': [x1, y1, x2, y2],
                                    'score': score.item(),
                                    'size_ratio': size_ratio
                                })

                    temp_boxes = self.filter_overlapping_boxes(temp_boxes)
                    temp_boxes = self.filter_contained_boxes(temp_boxes)

                    if temp_boxes:
                        all_filtered_boxes = temp_boxes
                        break

                # ---- Sort in reading order ----
                all_filtered_boxes = self.sort_boxes_reading_order(all_filtered_boxes)

                # ---- Save Crops ----
                subfolder_path = os.path.join(crop_root, base_name)
                os.makedirs(subfolder_path, exist_ok=True)

                for idx, detection in enumerate(all_filtered_boxes, 1):
                    x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
                    cropped_image = image.crop((x1, y1, x2, y2))
                    cropped_image.save(
                        os.path.join(subfolder_path, f"{base_name}_{idx}.png"),
                        format='PNG'
                    )

                # ---- Save tray with boxes ----
                draw_image = image.copy()
                draw = ImageDraw.Draw(draw_image)

                for detection in all_filtered_boxes:
                    draw.rectangle(detection['box'], outline="red", width=4)

                draw_image.save(os.path.join(tray_root, f"{base_name}.png"))

                count_records.append({
                    "filename": base_name + ".png",
                    "actual": actual_count,
                    "detected": len(all_filtered_boxes),
                    "detections": [det['box'] for det in all_filtered_boxes]
                })

        count_df = pd.DataFrame(count_records)
        count_df.to_csv(csv_path, index=False)

        print("\nDetection statistics saved to:", csv_path)
        print("Detection complete!")


# ---------------- MAIN ----------------
if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Beetle Detection")

    parser.add_argument("--image-dir", required=True, help="Directory containing input images")
    parser.add_argument("--output-dir", required=True, help="Directory to save detection results")
    parser.add_argument("--metadata-file", required=True, help="Path to CSV/JSON file with ground truth data")

    args = parser.parse_args()

    image_paths = [
        os.path.join(root, file)
        for root, _, files in os.walk(args.image_dir)
        for file in files
        if file.lower().endswith((".jpg", ".jpeg", ".png"))
    ]

    detector = Detection(
        image_paths=image_paths,
        output_dir=args.output_dir,
        metadata_file=args.metadata_file
    )

    detector.detect_objects()