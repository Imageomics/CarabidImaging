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
### catalog_Belitz_renamedMetadata (DONE, does not need to be downloaded again)

## Download and reopload to Google Drive as xlsx
### /NEONIndividualLinkageChecks/QueryUnder/Checked/[all google sheets]
### /NEONIndividualLinkageChecks/QueryOver/Checked/[all google sheets]

#Run the rclone copy to pull over everything of OSC
echo ______________________________________________ RClone ______________________________________________
./rclone.sh

sleep 5

#Run all ABTray Processes in Sequence
echo ______________________________________________ ABTrays ______________________________________________
Rscript ./ABTrays/CheckBeetleCounts.R
sleep 5
./ABTrays/copyImagesRename.sh
sleep 5

#Run Secondary FirstPass Processes in Sequence
echo ______________________________________________ First Pass ______________________________________________
Rscript ./FirstPass/CheckBeetleCounts.R
sleep 5
./FirstPass/copyImagesWithSecondRename.sh
sleep 5

#Run Secondary Belitz Processes in Sequence
echo ______________________________________________ Belitz ______________________________________________
Rscript ./Belitz/CheckBeetleCounts.R
sleep 5
./Belitz/copyImagesWithSecondRename.sh
sleep 5

# Put all of the datasets togethers
echo ______________________________________________ collate ______________________________________________
Rscript collatIndividualsFromManualChecks.R
sleep 5
Rscript collatImageMetadata.R
sleep 5
Rscript collatIndividualsFromAllSources.R
