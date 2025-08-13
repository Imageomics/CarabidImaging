#!/bin/bash
#SBATCH --account=PAS2136
#SBATCH --job-name=detection_beetle_tray
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --gres=gpu:4
#SBATCH --time=8:00:00  # Adjust based on expected runtime
#SBATCH --output=/users/PAS2136/rayees/ML-Challenge/detection_beetle_tray/detection_beetle_tray_%j.out
#SBATCH --error=/users/PAS2136/rayees/ML-Challenge/detection_beetle_tray/detection_beetle_tray_%j.err


# Run the script
python /users/PAS2136/rayees/ML-Challenge/detection_beetle_tray/detection_beeltes.py \
    --image-dir=/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays \
    --output-dir=/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted \
    --metadata-file /fs/ess/PAS2136/CarabidImaging/allIndividuals.csv