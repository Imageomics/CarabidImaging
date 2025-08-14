import pandas as pd
import ast
from PIL import Image, ImageDraw, ImageFont
import os

def sort_boxes(boxes):
    if not boxes:
        return []

    boxes.sort(key=lambda box: box[1])
    all_rows = []
    current_row = [boxes[0]]

    for i in range(1, len(boxes)):
        current_box = boxes[i]
        prev_box = current_row[-1]

        if current_box[1] < (prev_box[1] + (prev_box[3] - prev_box[1]) * 0.5):
            current_row.append(current_box)
        else:
            all_rows.append(current_row)
            current_row = [current_box]
    all_rows.append(current_row)

    sorted_boxes = []
    for row in all_rows:
        row.sort(key=lambda box: box[0])
        sorted_boxes.extend(row)

    return sorted_boxes

def main(input_dir, output_dir, csv_file_path):
    os.makedirs(output_dir, exist_ok=True)
    font = ImageFont.truetype("ARIAL.TTF", 100)
    df = pd.read_csv(csv_file_path)

    print(f"Finish reading CSV, processing {len(df)} images...")
    num_images = 0

    for index, row in df.iterrows():
        if row['actual'] != row['detected']:
            continue

        filename = row['filename']
        detections_str = row['detections']

        image_path = os.path.join(input_dir, filename)
        if not os.path.exists(image_path):
            for file in os.listdir(input_dir):
                if os.path.splitext(filename)[0] == os.path.splitext(file)[0]:
                    image_path = os.path.join(input_dir, file)
                    break
            else:
                print(f"\nCan't find image '{os.path.splitext(filename)[0]}', skip.")
                continue

        base_filename = os.path.splitext(filename)[0]
        original_ext = os.path.splitext(filename)[1]
        image_output_dir = os.path.join(output_dir, base_filename)
        single_images_dir = os.path.join(image_output_dir, 'single_beetles')

        if os.path.isdir(image_output_dir):
            print(f"\nDirectory '{base_filename}' already exists, skip.")
            continue
        os.makedirs(image_output_dir)
        os.makedirs(single_images_dir, exist_ok=True)

        print(f"\nProcessing {index}: {image_output_dir}")

        boxes = ast.literal_eval(detections_str)
        sorted_boxes = sort_boxes(boxes)

        with Image.open(image_path) as img:
            img_to_draw = img.copy()
            draw = ImageDraw.Draw(img_to_draw)

            for i, box in enumerate(sorted_boxes):
                number = str(i + 1)

                draw.rectangle(box, outline="red", width=5)
                text_bbox = draw.textbbox((box[0], box[1]), number, font=font)
                draw.rectangle(text_bbox, fill="red")
                draw.text((box[0], box[1]), number, fill="white", font=font)

                cropped_image = img.crop(box)
                cropped_image_path = os.path.join(single_images_dir, f"{number}{original_ext}")
                cropped_image.save(cropped_image_path)

            full_image_path = os.path.join(image_output_dir, f"full_tray{original_ext}")
            img_to_draw.save(full_image_path)

            print(f"-> Full image saved.")
            print(f"-> {len(sorted_boxes)} cropped images saved.")

        num_images += 1

    print(f"\nAll done, {num_images} images processed.")

if __name__ == "__main__":
    input_dir = '/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays'
    output_dir = '/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted_Cropped'
    csv_file_path = '/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted/GDino-Detection-Stats.csv'
    main(input_dir, output_dir, csv_file_path)