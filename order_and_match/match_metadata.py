import pandas as pd
import os

def distribute_metadata(main_csv_path, main_folder_path):
    df = pd.read_csv(main_csv_path)
    no_metadata_images = []

    for item_name in os.listdir(main_folder_path):
        item_path = os.path.join(main_folder_path, item_name)

        if os.path.isdir(item_path):
            subfolder_name = os.path.basename(item_path)
            filtered_df = df[df['imageID'].str.rsplit('.', n=1).str[0] == subfolder_name]

            if not filtered_df.empty:
                result_df = filtered_df.sort_values(by='Order')
                output_path = os.path.join(item_path, 'metadata.csv')
                result_df.to_csv(output_path, index=False)
                print(f"Finish processing {subfolder_name}")
            else:
                no_metadata_images.append(subfolder_name)
                print(f"No metadata for {subfolder_name}")

    if no_metadata_images:
        log_file_path = os.path.join(main_folder_path, 'no_metadata_trays.txt')
        with open(log_file_path, 'w', encoding='utf-8') as f:
            for image_name in no_metadata_images:
                f.write(image_name + '\n')
        print(f"Finish saving: {log_file_path}")

if __name__ == '__main__':
    main_csv_path = '/fs/ess/PAS2136/CarabidImaging/allIndividuals_SPEI.csv'
    main_folder_path = '/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted_Cropped'
    distribute_metadata(main_csv_path, main_folder_path)