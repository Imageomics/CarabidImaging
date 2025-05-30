#!/bin/bash
#SBATCH --job-name=FirstpassRename
#SBATCH --time=0:10:00 #10 minutes
#SBATCH --mail-type=ALL
#SBATCH --output=out_FirstpassRename.%j
#SBATCH --account=PUOM0017

module load R/4.4.0-gnu11.2

./generateFirstImageRenaming.R

sleep 5

./copyImagesWithFirstRename.sh
