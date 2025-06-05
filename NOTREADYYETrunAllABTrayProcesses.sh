#!/bin/bash
#SBATCH --job-name=allABTrays
#SBATCH --time=0:20:00 #10 minutes
#SBATCH --mail-type=ALL
#SBATCH --output=out_allABTrays.%j
#SBATCH --account=PUOM0017

module load R/4.4.0-gnu11.2

#Manuall Processes:
## Download from Google Drive and Upload to OSC
### BeetleMetadata
### catalog_firstPass_renamedMetadata
### catalog_Belitz_renamedMetadata

## Download and reopload to Google Drive as xlsx
### /NEONIndividualLinkageChecks/QueryUnder/Checked/[all google sheets]
### /NEONIndividualLinkageChecks/QueryOver/Checked/[all google sheets]

#Run the rclone copy to pull over everything of OSC
./rclone.sh

sleep 5

#Run all ABTray Processes in Sequence
Rscript ./ABTrays/CheckBeetleCounts.R
sleep 5
./ABTrays/copyImagesRename.sh
sleep 5

#Run Secondary FirstPass Processes in Sequence
Rscript ./FirstPass/CheckBeetleCounts.R
sleep 5
./FirstPass/copyImagesWithSecondRename.sh
sleep 5

#Run Secondary Belitz Processes in Sequence
#Rscript ./Belitz/CheckBeetleCounts.R
sleep 5
#./Belitz/copyImagesWithSecondRename.sh
sleep 5

# NOT READY YET, but eventually:
Rscript collatIndividualsFromManualChecks.R
sleep 5
Rscript collatIndividualsFromAllSources.R
