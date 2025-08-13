# import warnings
# warnings.filterwarnings("ignore")

# import os
# import torch
# import argparse
# import pandas as pd
# import numpy as np
# from tqdm import tqdm
# from PIL import Image, ImageDraw
# from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection
# from transformers import LlavaNextProcessor, LlavaNextForConditionalGeneration



# class Detection:

#     def __init__(self, image_paths, output_dir, model_id="IDEA-Research/grounding-dino-base", dino_prompt="a beetle.", metadata_file=None):
#         self.image_paths = image_paths
#         self.output_dir = output_dir
#         self.model_id = model_id
#         self.dino_prompt = dino_prompt
#         self.metadata_file = metadata_file
#         self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
#         self.processor = AutoProcessor.from_pretrained(model_id)
#         self.model = AutoModelForZeroShotObjectDetection.from_pretrained(model_id).to(self.device)
#         self.llava_processor, self.llava_model = self.setup_llava_model()
#         self.df = self._load_metadata() if metadata_file else None
#         self.imagenet_mean = [123.675, 116.28, 103.53]
        
#     def setup_llava_model(self):
#         print("Loading LLaVA model... (this may take a while on first run)")
#         model_name = "llava-hf/llava-v1.6-mistral-7b-hf"
#         processor = LlavaNextProcessor.from_pretrained(model_name, use_fast=True)
#         model = LlavaNextForConditionalGeneration.from_pretrained(
#             model_name, torch_dtype=torch.float16, low_cpu_mem_usage=True
#         ).to(self.device)
#         return processor, model

#     def _load_metadata(self):
#         if self.metadata_file.endswith('.csv'):
#             df = pd.read_csv(self.metadata_file)
#             df = df.loc[:, ~df.columns.str.contains('^Unnamed')]
#         elif self.metadata_file.endswith('.json'):
#             df = pd.read_json(self.metadata_file)
#         else:
#             raise ValueError("Metadata file must be CSV or JSON")
#         return df

#     def compute_iou(self, box1, box2):
#         x1, y1, x2, y2 = box1
#         x1g, y1g, x2g, y2g = box2
#         xi1 = max(x1, x1g)
#         yi1 = max(y1, y1g)
#         xi2 = min(x2, x2g)
#         yi2 = min(y2, y2g)
#         inter_width = max(0, xi2 - xi1)
#         inter_height = max(0, yi2 - yi1)
#         intersection = inter_width * inter_height
#         box1_area = (x2 - x1) * (y2 - y1)
#         box2_area = (x2g - x1g) * (y2g - y1g)
#         union = box1_area + box2_area - intersection
#         return intersection / union if union > 0 else 0

#     def compute_containment_ratio(self, small_box, large_box):
#         sx1, sy1, sx2, sy2 = small_box
#         lx1, ly1, lx2, ly2 = large_box
#         xi1 = max(sx1, lx1)
#         yi1 = max(sy1, ly1)
#         xi2 = min(sx2, lx2)
#         yi2 = min(sy2, ly2)
#         inter_width = max(0, xi2 - xi1)
#         inter_height = max(0, yi2 - yi1)
#         intersection = inter_width * inter_height
#         small_area = (sx2 - sx1) * (sy2 - sy1)
#         return intersection / small_area if small_area > 0 else 0

#     def filter_contained_boxes(self, detections, containment_threshold=0.6, size_ratio_threshold=0.75):
#         if len(detections) <= 1:
#             return detections
#         sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
#         keep = []
#         for i, detection in enumerate(sorted_detections):
#             current_box = detection['box']
#             current_area = (current_box[2] - current_box[0]) * (current_box[3] - current_box[1])
#             should_keep = True
#             for kept_detection in keep:
#                 kept_box = kept_detection['box']
#                 kept_area = (kept_box[2] - kept_box[0]) * (kept_box[3] - kept_box[1])
#                 if current_area < kept_area * size_ratio_threshold:
#                     containment_ratio = self.compute_containment_ratio(current_box, kept_box)
#                     if containment_ratio > containment_threshold:
#                         should_keep = False
#                         break
#             if should_keep:
#                 keep.append(detection)
#         return keep

#     def filter_overlapping_boxes(self, detections, iou_threshold=0.4):
#         if len(detections) <= 1:
#             return detections
#         sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
#         keep = []
#         for detection in sorted_detections:
#             box = detection['box']
#             should_keep = True
#             for kept_detection in keep:
#                 kept_box = kept_detection['box']
#                 if self.compute_iou(box, kept_box) > iou_threshold:
#                     should_keep = False
#                     break
#             if should_keep:
#                 keep.append(detection)
#         return keep

#     def extract_ground_truth(self, image_path):
#         if self.df is None:
#             return None
#         base_name = os.path.basename(image_path)
#         image_rows = self.df[self.df['imageID'] == base_name]
#         if not image_rows.empty:
#             return int(image_rows['NumberOfBeetlesInTray'].iloc[0])
#         return None

#     def whiteout_boxes(self, image, boxes):
#         image_np = np.array(image)
#         for box in boxes:
#             x1, y1, x2, y2 = [int(coord) for coord in box]
#             x1, y1, x2, y2 = max(0, x1), max(0, y1), min(image_np.shape[1], x2), min(image_np.shape[0], y2)
#             image_np[y1:y2, x1:x2, :] = self.imagenet_mean
#         return Image.fromarray(image_np.astype(np.uint8))

#     def get_bounding_region(self, boxes, image_width, image_height, padding=50):
#         if not boxes:
#             return 0, 0, image_width, image_height
#         x1s = [box[0] for box in boxes]
#         y1s = [box[1] for box in boxes]
#         x2s = [box[2] for box in boxes]
#         y2s = [box[3] for box in boxes]
#         x1 = max(0, min(x1s) - padding)
#         y1 = max(0, min(y1s) - padding)
#         x2 = min(image_width, max(x2s) + padding)
#         y2 = min(image_height, max(y2s) + padding)
#         return x1, y1, x2, y2

#     def count_x_in_image(self, image):
#         try:
#             target_size = (336, 336)
#             resized_image = image.resize(target_size, Image.Resampling.LANCZOS)
#             image_np = np.array(resized_image).astype(np.float32) / 255.0
#             image_tensor = torch.from_numpy(image_np).permute(2, 0, 1).unsqueeze(0).to(self.device)

#             conversation = [
#                 {
#                     "role": "user",
#                     "content": [
#                         {"type": "image"},
#                         {"type": "text", "text": "Can you see any Beetles in this image? Please look at the image carefully and provide only the 'YES' or 'NO' answer."}
#                     ],
#                 },
#             ]
#             prompt = self.llava_processor.apply_chat_template(conversation, add_generation_prompt=True)
#             inputs = self.llava_processor(text=prompt, images=image_tensor, return_tensors="pt").to(self.device)
#             with torch.no_grad():
#                 output = self.llava_model.generate(**inputs, max_new_tokens=100, do_sample=False)
#             response = self.llava_processor.decode(output[0], skip_special_tokens=True)
#             assistant_response = response.split("ASSISTANT:")[-1].strip()
#             answer = assistant_response.split()[-1]
#             return answer
#         except Exception as e:
#             print(f"Error in LLaVA processing: {e}")

#     def detect_objects(self, text="a beetle.", box_threshold=0.3, text_threshold=0.2, max_size_ratio=0.05):
        
#         os.makedirs(self.output_dir, exist_ok=True)
#         results = {}
#         count_records = []

#         for image_path in tqdm(self.image_paths, desc="Processing ..."):
#             image = Image.open(image_path).convert("RGB")
#             img_width, img_height = image.size
#             img_area = img_width * img_height
#             base_name = os.path.splitext(os.path.basename(image_path))[0]
#             actual_count = self.extract_ground_truth(image_path)
#             all_filtered_boxes = []
#             current_image = image.copy()
#             region = None

#             # Create subfolder for this image
#             subfolder_path = os.path.join(self.output_dir, base_name)
#             os.makedirs(subfolder_path, exist_ok=True)

#             # Initial Grounding DINO run
#             inputs = self.processor(images=current_image, text=text, return_tensors="pt").to(self.device)
#             with torch.no_grad():
#                 outputs = self.model(**inputs)
#             detection_results = self.processor.post_process_grounded_object_detection(
#                 outputs,
#                 inputs.input_ids,
#                 box_threshold=box_threshold,
#                 text_threshold=text_threshold,
#                 target_sizes=[current_image.size[::-1]]
#             )
#             filtered_boxes = []
#             for result in detection_results:
#                 boxes = result["boxes"]
#                 scores = result["scores"]
#                 for box, score in zip(boxes, scores):
#                     x1, y1, x2, y2 = box.tolist()
#                     box_area = (x2 - x1) * (y2 - y1)
#                     size_ratio = box_area / img_area
#                     if size_ratio <= max_size_ratio:
#                         filtered_boxes.append({
#                             'box': [x1, y1, x2, y2],
#                             'score': score.item(),
#                             'size_ratio': size_ratio
#                         })
#             filtered_boxes = self.filter_overlapping_boxes(filtered_boxes)
#             filtered_boxes = self.filter_contained_boxes(filtered_boxes)
#             all_filtered_boxes.extend(filtered_boxes)
#             detected_count = len(all_filtered_boxes)

#             # Save cropped beetle images
#             for i, detection in enumerate(all_filtered_boxes, 1):
#                 x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
#                 x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
#                 cropped_image = image.crop((x1, y1, x2, y2))
#                 crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
#                 cropped_image.save(crop_output_path, format='PNG')

#             # Whiteout detected boxes
#             if filtered_boxes:
#                 current_image = self.whiteout_boxes(current_image, [det['box'] for det in filtered_boxes])
#                 region = self.get_bounding_region([det['box'] for det in filtered_boxes], img_width, img_height)

#             # Compare with ground truth
#             check_flag = 0
#             if actual_count is not None:
#                 if detected_count == actual_count:
#                     llava_response = self.count_x_in_image(current_image)
#                     if llava_response.upper() == "NO":
#                         check_flag = 0
#                     else:
#                         while True:
#                             if region:
#                                 x1, y1, x2, y2 = region
#                                 region_image = current_image.crop((x1, y1, x2, y2))
#                             else:
#                                 region_image = current_image
#                             inputs = self.processor(images=region_image, text=text, return_tensors="pt").to(self.device)
#                             with torch.no_grad():
#                                 outputs = self.model(**inputs)
#                             detection_results = self.processor.post_process_grounded_object_detection(
#                                 outputs,
#                                 inputs.input_ids,
#                                 box_threshold=box_threshold,
#                                 text_threshold=text_threshold,
#                                 target_sizes=[region_image.size[::-1]]
#                             )
#                             new_boxes = []
#                             for result in detection_results:
#                                 boxes = result["boxes"]
#                                 scores = result["scores"]
#                                 for box, score in zip(boxes, scores):
#                                     x1_b, y1_b, x2_b, y2_b = box.tolist()
#                                     box_area = (x2_b - x1_b) * (y2_b - y1_b)
#                                     size_ratio = box_area / img_area
#                                     if size_ratio <= max_size_ratio:
#                                         if region:
#                                             x1_b += x1
#                                             x2_b += x1
#                                             y1_b += y1
#                                             y2_b += y1
#                                         new_boxes.append({
#                                             'box': [x1_b, y1_b, x2_b, y2_b],
#                                             'score': score.item(),
#                                             'size_ratio': size_ratio
#                                         })
#                             new_boxes = self.filter_overlapping_boxes(new_boxes)
#                             new_boxes = self.filter_contained_boxes(new_boxes)
#                             if not new_boxes:
#                                 break
#                             all_filtered_boxes.extend(new_boxes)
#                             detected_count = len(all_filtered_boxes)
#                             # Save new cropped beetle images
#                             for i, detection in enumerate(new_boxes, len(all_filtered_boxes) - len(new_boxes) + 1):
#                                 x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
#                                 x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
#                                 cropped_image = image.crop((x1, y1, x2, y2))
#                                 crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
#                                 cropped_image.save(crop_output_path, format='PNG')
#                             current_image = self.whiteout_boxes(current_image, [det['box'] for det in new_boxes])
#                             region = self.get_bounding_region([det['box'] for det in all_filtered_boxes], img_width, img_height)
#                             if detected_count == actual_count:
#                                 llava_response = self.count_x_in_image(current_image)
#                                 if llava_response.upper() == "NO":
#                                     check_flag = 0
#                                     break
#                                 else:
#                                     check_flag = 1
#                 elif detected_count < actual_count:
#                     while True:
#                         if region:
#                             x1, y1, x2, y2 = region
#                             region_image = current_image.crop((x1, y1, x2, y2))
#                         else:
#                             region_image = current_image
#                         inputs = self.processor(images=region_image, text=text, return_tensors="pt").to(self.device)
#                         with torch.no_grad():
#                             outputs = self.model(**inputs)
#                         detection_results = self.processor.post_process_grounded_object_detection(
#                             outputs,
#                             inputs.input_ids,
#                             box_threshold=box_threshold,
#                             text_threshold=text_threshold,
#                             target_sizes=[region_image.size[::-1]]
#                         )
#                         new_boxes = []
#                         for result in detection_results:
#                             boxes = result["boxes"]
#                             scores = result["scores"]
#                             for box, score in zip(boxes, scores):
#                                 x1_b, y1_b, x2_b, y2_b = box.tolist()
#                                 box_area = (x2_b - x1_b) * (y2_b - y1_b)
#                                 size_ratio = box_area / img_area
#                                 if size_ratio <= max_size_ratio:
#                                     if region:
#                                         x1_b += x1
#                                         x2_b += x1
#                                         y1_b += y1
#                                         y2_b += y1
#                                     new_boxes.append({
#                                         'box': [x1_b, y1_b, x2_b, y2_b],
#                                         'score': score.item(),
#                                         'size_ratio': size_ratio
#                                     })
#                         new_boxes = self.filter_overlapping_boxes(new_boxes)
#                         new_boxes = self.filter_contained_boxes(new_boxes)
#                         if not new_boxes:
#                             break
#                         all_filtered_boxes.extend(new_boxes)
#                         detected_count = len(all_filtered_boxes)
#                         # Save new cropped beetle images
#                         for i, detection in enumerate(new_boxes, len(all_filtered_boxes) - len(new_boxes) + 1):
#                             x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
#                             x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
#                             cropped_image = image.crop((x1, y1, x2, y2))
#                             crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
#                             cropped_image.save(crop_output_path, format='PNG')
#                         current_image = self.whiteout_boxes(current_image, [det['box'] for det in new_boxes])
#                         region = self.get_bounding_region([det['box'] for det in all_filtered_boxes], img_width, img_height)
#                         if detected_count == actual_count:
#                             llava_response = self.count_x_in_image(current_image)
#                             check_flag = 1 if llava_response.upper() == "YES" else 0
#                             break
#                     if detected_count != actual_count:
#                         check_flag = 1
#                 else:  # detected_count > actual_count
#                     llava_response = self.count_x_in_image(current_image)
#                     check_flag = 1
#                     if llava_response.upper() == "YES":
#                         while llava_response.upper() == "YES":
#                             if region:
#                                 x1, y1, x2, y2 = region
#                                 region_image = current_image.crop((x1, y1, x2, y2))
#                             else:
#                                 region_image = current_image
#                             inputs = self.processor(images=region_image, text=text, return_tensors="pt").to(self.device)
#                             with torch.no_grad():
#                                 outputs = self.model(**inputs)
#                             detection_results = self.processor.post_process_grounded_object_detection(
#                                 outputs,
#                                 inputs.input_ids,
#                                 box_threshold=box_threshold,
#                                 text_threshold=text_threshold,
#                                 target_sizes=[region_image.size[::-1]]
#                             )
#                             new_boxes = []
#                             for result in detection_results:
#                                 boxes = result["boxes"]
#                                 scores = result  ["scores"]
#                                 for box, score in zip(boxes, scores):
#                                     x1_b, y1_b, x2_b, y2_b = box.tolist()
#                                     box_area = (x2_b - x1_b) * (y2_b - y1_b)
#                                     size_ratio = box_area / img_area
#                                     if size_ratio <= max_size_ratio:
#                                         if region:
#                                             x1_b += x1
#                                             x2_b += x1
#                                             y1_b += y1
#                                             y2_b += y1
#                                         new_boxes.append({
#                                             'box': [x1_b, y1_b, x2_b, y2_b],
#                                             'score': score.item(),
#                                             'size_ratio': size_ratio
#                                         })
#                             new_boxes = self.filter_overlapping_boxes(new_boxes)
#                             new_boxes = self.filter_contained_boxes(new_boxes)
#                             if not new_boxes:
#                                 break
#                             all_filtered_boxes.extend(new_boxes)
#                             detected_count = len(all_filtered_boxes)
#                             # Save new cropped beetle images
#                             for i, detection in enumerate(new_boxes, len(all_filtered_boxes) - len(new_boxes) + 1):
#                                 x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
#                                 x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
#                                 cropped_image = image.crop((x1, y1, x2, y2))
#                                 crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
#                                 cropped_image.save(crop_output_path, format='PNG')
#                             current_image = self.whiteout_boxes(current_image, [det['box'] for det in new_boxes])
#                             region = self.get_bounding_region([det['box'] for det in all_filtered_boxes], img_width, img_height)
#                             llava_response = self.count_x_in_image(current_image)


#             detection_coords = [det['box'] for det in all_filtered_boxes]
#             results[image_path] = all_filtered_boxes
#             count_records.append({
#                 "filename": base_name + ".png",
#                 "actual": actual_count,
#                 "detected": detected_count,
#                 "Check?": check_flag,
#                 "detections": detection_coords
#             })

#             if all_filtered_boxes:
#                 draw_image = image.copy()
#                 draw = ImageDraw.Draw(draw_image)
#                 for detection in all_filtered_boxes:
#                     x1, y1, x2, y2 = detection['box']
#                     draw.rectangle([x1, y1, x2, y2], outline="red", width=4)
#                 actual_display = actual_count if actual_count is not None else "N/A"
#                 print(f"{base_name:<110} => True: {actual_display:<3}, DINO: {detected_count:<3}, Check?: {check_flag}")
#                 output_path = os.path.join(self.output_dir, f"{base_name}.png")
#                 draw_image.save(output_path, format='PNG')
#             else:
#                 print(f"No valid detections found: {base_name}")

#         count_df = pd.DataFrame(count_records)
#         count_df.to_csv(os.path.join(self.output_dir, "GDino-Detection-Stats.csv"), index=False)
#         return results, count_df



# if __name__ == "__main__":

#     parser = argparse.ArgumentParser(description="Grounding DINO Object Detection with LLaVA")
#     parser.add_argument("--image-dir", required=True, help="Directory containing input images")
#     parser.add_argument("--output-dir", required=True, help="Directory to save detection results")
#     parser.add_argument("--model-id", default="IDEA-Research/grounding-dino-base", help="Model identifier for Grounding DINO")
#     parser.add_argument("--dino-prompt", default="a beetle.", help="Prompt for object detection with Grounding DINO")
#     parser.add_argument("--metadata-file", default="/fs/ess/PAS2136/CarabidImaging/allIndividuals.csv", help="Path to CSV/JSON file with ground truth data")
#     args = parser.parse_args()

#     # image_paths = [
#     #     os.path.join(args.image_dir, f) for f in os.listdir(args.image_dir)
#     #     if os.path.isfile(os.path.join(args.image_dir, f))
#     # ]

#     image_paths = [
#         os.path.join(root, file)
#         for root, _, files in os.walk(args.image_dir)
#         for file in files
#         if file.lower().endswith((".jpg", ".jpeg", ".png"))
#     ]

#     detector = Detection(
#         image_paths=image_paths,
#         output_dir=args.output_dir,
#         model_id=args.model_id,
#         dino_prompt=args.dino_prompt,
#         metadata_file=args.metadata_file
#     )
    
#     results, count_df = detector.detect_objects()
#     print("\nDetection statistics saved to:", os.path.join(args.output_dir, "GDino-Detection-Stats.csv"))
#     print("Detection complete!")




import warnings
warnings.filterwarnings("ignore")

import os
import torch
import argparse
import pandas as pd
import numpy as np
from tqdm import tqdm
from PIL import Image, ImageDraw
from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection
from transformers import LlavaNextProcessor, LlavaNextForConditionalGeneration

class Detection:
    def __init__(self, image_paths, output_dir, model_id="IDEA-Research/grounding-dino-base", dino_prompt="a beetle.", metadata_file=None):
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
        
    def setup_llava_model(self):
        model_name = "llava-hf/llava-v1.6-mistral-7b-hf"
        processor = LlavaNextProcessor.from_pretrained(model_name, use_fast=True)
        model = LlavaNextForConditionalGeneration.from_pretrained(
            model_name, torch_dtype=torch.float16, low_cpu_mem_usage=True
        ).to(self.device)
        return processor, model

    def _load_metadata(self):
        if self.metadata_file.endswith('.csv'):
            df = pd.read_csv(self.metadata_file)
            df = df.loc[:, ~df.columns.str.contains('^Unnamed')]
        elif self.metadata_file.endswith('.json'):
            df = pd.read_json(self.metadata_file)
        else:
            raise ValueError("Metadata file must be CSV or JSON")
        return df

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

    def filter_contained_boxes(self, detections, containment_threshold=0.6, size_ratio_threshold=0.75):
        if len(detections) <= 1:
            return detections
        sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
        keep = []
        for i, detection in enumerate(sorted_detections):
            current_box = detection['box']
            current_area = (current_box[2] - current_box[0]) * (current_box[3] - current_box[1])
            should_keep = True
            for kept_detection in keep:
                kept_box = kept_detection['box']
                kept_area = (kept_box[2] - kept_box[0]) * (kept_box[3] - kept_box[1])
                if current_area < kept_area * size_ratio_threshold:
                    containment_ratio = self.compute_containment_ratio(current_box, kept_box)
                    if containment_ratio > containment_threshold:
                        should_keep = False
                        break
            if should_keep:
                keep.append(detection)
        return keep

    def filter_overlapping_boxes(self, detections, iou_threshold=0.4):
        if len(detections) <= 1:
            return detections
        sorted_detections = sorted(detections, key=lambda x: x['score'], reverse=True)
        keep = []
        for detection in sorted_detections:
            box = detection['box']
            should_keep = True
            for kept_detection in keep:
                kept_box = kept_detection['box']
                if self.compute_iou(box, kept_box) > iou_threshold:
                    should_keep = False
                    break
            if should_keep:
                keep.append(detection)
        return keep

    # def extract_ground_truth(self, image_path):
    #     if self.df is None:
    #         return None
    #     base_name = os.path.basename(image_path)
    #     image_rows = self.df[self.df['imageID'] == base_name]
    #     if not image_rows.empty:
    #         return int(image_rows['NumberOfBeetlesInTray'].iloc[0])
    #     return None
    
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
            else:
                return None
        return None

    def whiteout_boxes(self, image, boxes):
        image_np = np.array(image)
        for box in boxes:
            x1, y1, x2, y2 = [int(coord) for coord in box]
            x1, y1, x2, y2 = max(0, x1), max(0, y1), min(image_np.shape[1], x2), min(image_np.shape[0], y2)
            image_np[y1:y2, x1:x2, :] = self.imagenet_mean
        return Image.fromarray(image_np.astype(np.uint8))

    def get_bounding_region(self, boxes, image_width, image_height, padding=50):
        if not boxes:
            return 0, 0, image_width, image_height
        x1s = [box[0] for box in boxes]
        y1s = [box[1] for box in boxes]
        x2s = [box[2] for box in boxes]
        y2s = [box[3] for box in boxes]
        x1 = max(0, min(x1s) - padding)
        y1 = max(0, min(y1s) - padding)
        x2 = min(image_width, max(x2s) + padding)
        y2 = min(image_height, max(y2s) + padding)
        return x1, y1, x2, y2

    def count_x_in_image(self, image):
        try:
            target_size = (336, 336)
            resized_image = image.resize(target_size, Image.Resampling.LANCZOS)
            image_np = np.array(resized_image).astype(np.float32) / 255.0
            image_tensor = torch.from_numpy(image_np).permute(2, 0, 1).unsqueeze(0).to(self.device)

            conversation = [
                {
                    "role": "user",
                    "content": [
                        {"type": "image"},
                        {"type": "text", "text": "Can you see any Beetles in this image? Please look at the image carefully and provide only the 'YES' or 'NO' answer."}
                    ],
                },
            ]
            prompt = self.llava_processor.apply_chat_template(conversation, add_generation_prompt=True)
            inputs = self.llava_processor(text=prompt, images=image_tensor, return_tensors="pt").to(self.device)
            with torch.no_grad():
                output = self.llava_model.generate(**inputs, max_new_tokens=100, do_sample=False)
            response = self.llava_processor.decode(output[0], skip_special_tokens=True)
            assistant_response = response.split("ASSISTANT:")[-1].strip()
            answer = assistant_response.split()[-1]
            return answer
        except Exception as e:
            print(f"Error in LLaVA processing: {e}")
            return "NO"  # Default to NO on error to avoid blocking automation

    def detect_objects(self, text="a beetle.", box_threshold=0.3, text_threshold=0.2, max_size_ratio=0.05):
        os.makedirs(self.output_dir, exist_ok=True)
        results = {}
        count_records = []

        for image_path in tqdm(self.image_paths, desc="Processing ..."):
            image = Image.open(image_path).convert("RGB")
            img_width, img_height = image.size
            img_area = img_width * img_height
            base_name = os.path.splitext(os.path.basename(image_path))[0]
            actual_count = self.extract_ground_truth(image_path)
            all_filtered_boxes = []
            current_image = image.copy()
            region = None
            check_flag = 0
            merge_flag = 0

            # Create subfolder for this image
            subfolder_path = os.path.join(self.output_dir, base_name)
            os.makedirs(subfolder_path, exist_ok=True)

            # Initial Grounding DINO run
            inputs = self.processor(images=current_image, text=text, return_tensors="pt").to(self.device)
            with torch.no_grad():
                outputs = self.model(**inputs)
            detection_results = self.processor.post_process_grounded_object_detection(
                outputs,
                inputs.input_ids,
                box_threshold=box_threshold,
                text_threshold=text_threshold,
                target_sizes=[current_image.size[::-1]]
            )
            filtered_boxes = []
            for result in detection_results:
                boxes = result["boxes"]
                scores = result["scores"]
                for box, score in zip(boxes, scores):
                    x1, y1, x2, y2 = box.tolist()
                    box_area = (x2 - x1) * (y2 - y1)
                    size_ratio = box_area / img_area
                    if size_ratio <= max_size_ratio:
                        filtered_boxes.append({
                            'box': [x1, y1, x2, y2],
                            'score': score.item(),
                            'size_ratio': size_ratio
                        })
            filtered_boxes = self.filter_overlapping_boxes(filtered_boxes)
            filtered_boxes = self.filter_contained_boxes(filtered_boxes)
            all_filtered_boxes.extend(filtered_boxes)
            detected_count = len(all_filtered_boxes)

            # Save cropped beetle images from initial run
            for i, detection in enumerate(all_filtered_boxes, 1):
                x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
                x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
                cropped_image = image.crop((x1, y1, x2, y2))
                crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
                cropped_image.save(crop_output_path, format='PNG')

            # Whiteout detected boxes
            if filtered_boxes:
                current_image = self.whiteout_boxes(current_image, [det['box'] for det in filtered_boxes])
                region = self.get_bounding_region([det['box'] for det in filtered_boxes], img_width, img_height)

            # Handle cases if ground truth is available

            if actual_count is not None:
                # Case 1: Detected count matches ground truth
                if detected_count == actual_count:
                    llava_response = self.count_x_in_image(current_image)
                    check_flag = 1 if llava_response.upper() == "YES" else 0

                # Case 2: Detected count is less than ground truth
                elif detected_count < actual_count:
                    while True:
                        if region:
                            x1, y1, x2, y2 = region
                            region_image = current_image.crop((x1, y1, x2, y2))
                        else:
                            region_image = current_image
                        inputs = self.processor(images=region_image, text=text, return_tensors="pt").to(self.device)
                        with torch.no_grad():
                            outputs = self.model(**inputs)
                        detection_results = self.processor.post_process_grounded_object_detection(
                            outputs,
                            inputs.input_ids,
                            box_threshold=box_threshold,
                            text_threshold=text_threshold,
                            target_sizes=[region_image.size[::-1]]
                        )
                        new_boxes = []
                        for result in detection_results:
                            boxes = result["boxes"]
                            scores = result["scores"]
                            for box, score in zip(boxes, scores):
                                x1_b, y1_b, x2_b, y2_b = box.tolist()
                                box_area = (x2_b - x1_b) * (y2_b - y1_b)
                                size_ratio = box_area / img_area
                                if size_ratio <= max_size_ratio:
                                    if region:
                                        x1_b += x1
                                        x2_b += x1
                                        y1_b += y1
                                        y2_b += y1
                                    new_boxes.append({
                                        'box': [x1_b, y1_b, x2_b, y2_b],
                                        'score': score.item(),
                                        'size_ratio': size_ratio
                                    })
                        new_boxes = self.filter_overlapping_boxes(new_boxes)
                        new_boxes = self.filter_contained_boxes(new_boxes)
                        if not new_boxes:
                            break
                        all_filtered_boxes.extend(new_boxes)
                        detected_count = len(all_filtered_boxes)
                        # Save new cropped beetle images
                        for i, detection in enumerate(new_boxes, len(all_filtered_boxes) - len(new_boxes) + 1):
                            x1, y1, x2, y2 = [int(coord) for coord in detection['box']]
                            x1, y1, x2, y2 = max(0, x1), max(0, y1), min(img_width, x2), min(img_height, y2)
                            cropped_image = image.crop((x1, y1, x2, y2))
                            crop_output_path = os.path.join(subfolder_path, f"{base_name}_{i}.png")
                            cropped_image.save(crop_output_path, format='PNG')
                        current_image = self.whiteout_boxes(current_image, [det['box'] for det in new_boxes])
                        region = self.get_bounding_region([det['box'] for det in all_filtered_boxes], img_width, img_height)
                        if detected_count == actual_count:
                            break
                    llava_response = self.count_x_in_image(current_image)
                    check_flag = 1 if llava_response.upper() == "YES" else 0

                # Case 3: Detected count is greater than ground truth
                else:
                    llava_response = self.count_x_in_image(current_image)
                    merge_flag = 1 if llava_response.upper() == "NO" else 0
                    check_flag = 1 if llava_response.upper() == "YES" else 0

            detection_coords = [det['box'] for det in all_filtered_boxes]
            results[image_path] = all_filtered_boxes
            count_records.append({
                "filename": base_name + ".png",
                "actual": actual_count,
                "detected": detected_count,
                "Check?": check_flag,
                "Merge?": merge_flag,
                "detections": detection_coords
            })

            if all_filtered_boxes:
                draw_image = image.copy()
                draw = ImageDraw.Draw(draw_image)
                for detection in all_filtered_boxes:
                    x1, y1, x2, y2 = detection['box']
                    draw.rectangle([x1, y1, x2, y2], outline="red", width=4)
                actual_display = actual_count if actual_count is not None else "N/A"
                print(f"{base_name:<110} => True: {actual_display:<3}, DINO: {detected_count:<3}, Check?: {check_flag}, Merge?: {merge_flag}")
                output_path = os.path.join(self.output_dir, f"{base_name}.png")
                draw_image.save(output_path, format='PNG')
            else:
                print(f"No valid detections found: {base_name}")

        count_df = pd.DataFrame(count_records)
        count_df.to_csv(os.path.join(self.output_dir, "GDino-Detection-Stats.csv"), index=False)
        return results, count_df

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Grounding DINO Object Detection with LLaVA")
    parser.add_argument("--image-dir", required=True, help="Directory containing input images")
    parser.add_argument("--output-dir", required=True, help="Directory to save detection results")
    parser.add_argument("--model-id", default="IDEA-Research/grounding-dino-base", help="Model identifier for Grounding DINO")
    parser.add_argument("--dino-prompt", default="a beetle.", help="Prompt for object detection with Grounding DINO")
    parser.add_argument("--metadata-file", default="/fs/ess/PAS2136/CarabidImaging/allIndividuals.csv", help="Path to CSV/JSON file with ground truth data")
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
        model_id=args.model_id,
        dino_prompt=args.dino_prompt,
        metadata_file=args.metadata_file
    )
    
    results, count_df = detector.detect_objects()
    print("\nDetection statistics saved to:", os.path.join(args.output_dir, "grouding-dino-detection-stats.csv"))
    print("Detection complete!")