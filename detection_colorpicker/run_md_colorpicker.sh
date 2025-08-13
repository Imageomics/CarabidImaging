#!/bin/bash
#SBATCH --account=PAS2136
#SBATCH --job-name=colorpicker_detection_moondream
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --gres=gpu:4
#SBATCH --time=06:00:00  # Adjust based on expected runtime
#SBATCH --output=/users/PAS2136/rayees/ML-Challenge/detection_colorpicker/colorpicker_detection_moondream_%j.out
#SBATCH --error=/users/PAS2136/rayees/ML-Challenge/detection_colorpicker/colorpicker_detection_moondream_%j.err


# Run the script
module load python/3.12
python /users/PAS2136/rayees/ML-Challenge/detection_colorpicker/colorpicker_detection_moondream.py \
    --image_dir /fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays/ \
    --output_dir /fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysColorpicker \
    --output_csv /fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysColorpicker/colorpicker.csv

