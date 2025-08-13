import os
import csv
import argparse
from PIL import Image, ImageDraw
from transformers import AutoModelForCausalLM

def load_moondream():
    """Load the MoonDream2 model."""
    model = AutoModelForCausalLM.from_pretrained(
        "vikhyatk/moondream2",
        revision="2025-06-21",
        trust_remote_code=True,
        device_map={"": "cpu"}
    )
    return model

def detect_colorpicker(image, model):
    """Run detection on the image and return the detected colorpicker objects."""
    width, height = image.size
    result = model.detect(image, "a colorpicker")
    objects = result.get("objects", [])

    coords_list = []
    for obj in objects:
        x1 = int(obj["x_min"] * width)
        y1 = int(obj["y_min"] * height)
        x2 = int(obj["x_max"] * width)
        y2 = int(obj["y_max"] * height)
        coords_list.append({"x_min": x1, "y_min": y1, "x_max": x2, "y_max": y2})
    return coords_list

def main(image_dir, output_dir, output_csv):
    os.makedirs(output_dir, exist_ok=True)
    model = load_moondream()

    image_paths = []
    for root, dirs, files in os.walk(image_dir):
        for file in files:
            if file.lower().endswith((".png", ".jpg", ".jpeg")):
                image_paths.append(os.path.join(root, file))

    rows = []
    for image_path in image_paths:
        try:
            image = Image.open(image_path).convert("RGB")
            coords_list = detect_colorpicker(image, model)

            # Draw red bounding boxes
            draw = ImageDraw.Draw(image)
            for box in coords_list:
                draw.rectangle(
                    [box["x_min"], box["y_min"], box["x_max"], box["y_max"]],
                    outline="red",
                    width=3
                )

            base_name = os.path.basename(image_path)
            plotted_image_path = os.path.join(output_dir, base_name)
            image.save(plotted_image_path)

            row = {
                "image_name": image_path,
                "plotted_image": plotted_image_path,
                "number of colorpickers": len(coords_list),
                "colorpicker coordinates": str(coords_list),
                "checkflag": len(coords_list) != 1
            }
            rows.append(row)

        except Exception as e:
            print(f"[ERROR] {image_path}: {e}")

    # Write CSV
    with open(output_csv, "w", newline="") as csvfile:
        fieldnames = ["image_name", "plotted_image", "number of colorpickers", "colorpicker coordinates", "checkflag"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n✅ Processed {len(image_paths)} images.")
    print(f"📄 CSV saved to: {output_csv}")





if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Colorpicker Detection in Tray Images")
    parser.add_argument(
        "--image_dir",
        type=str,
        default="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays/OLD",
        help="Directory containing tray images."
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysColorpicker",
        help="Directory to save plotted output images."
    )
    parser.add_argument(
        "--output_csv",
        type=str,
        default="/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysColorpicker/colorpickers.csv",
        help="Path to the output CSV file."
    )
    args = parser.parse_args()

    main(args.image_dir, args.output_dir, args.output_csv)
