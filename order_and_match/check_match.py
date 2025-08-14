import pandas as pd
import os

def check_image_count(main_folder_path):
    mismatched_folders = []

    for subfolder_name in os.listdir(main_folder_path):
        subfolder_path = os.path.join(main_folder_path, subfolder_name)

        if os.path.isdir(subfolder_path):
            print(f"Processing: {subfolder_name}")

            images_folder_path = os.path.join(subfolder_path, 'single_beetles')
            metadata_file_path = os.path.join(subfolder_path, 'metadata.csv')

            if not os.path.isdir(images_folder_path):
                raise ValueError("Folder 'single_beetles' is missing.")
            if not os.path.isfile(metadata_file_path):
                print("  -> File 'metadata.csv' is missing.")
                continue

            image_count = 0
            for filename in os.listdir(images_folder_path):
                if filename.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
                    image_count += 1
                else:
                    raise ValueError("Unknown image format.")

            df = pd.read_csv(metadata_file_path)
            try:
                total_number = int(df['NumberOfBeetlesInTray'].iloc[0])
            except:
                print("  -> Metadata number is not an integer.")
                mismatched_folders.append(subfolder_name)
                continue

            if image_count != total_number:
                print(f"  -> Numbers don't match. Image number: {image_count}, metadata number: {total_number}.")
                mismatched_folders.append(subfolder_name)

    if mismatched_folders:
        log_file_path = os.path.join(main_folder_path, 'mismatched_trays.txt')
        with open(log_file_path, 'w', encoding='utf-8') as f:
            for folder in mismatched_folders:
                f.write(folder + '\n')
        print(f"Finish saving: {log_file_path}")

if __name__ == '__main__':
    main_folder_path = '/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted_Cropped'
    check_image_count(main_folder_path)