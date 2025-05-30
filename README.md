# Carabid Imaging
__Description of work__

# Backing up data
`rclone.sh`
> This script automates the rclone copying from Google Drive to OSC. Students at the biorepository have contributor access to upload images to the Google Drive at the end of every day, from there, they can be copied to OSC

Each folder in this directory (FirstPass, ABTrays, CTrays, Belitz, and SmallBeetles) refers to a distinct data source and contains code to do all necessary preprocessing of the images provided by that data source. 

# Scripts for each data source:
## First Pass Images
These images were collected by NEON and have some issues with resolution and no associated metadata. The scripts below process the data and work iteratively to take student inputs, collecting subsequent metadata and annotations on image quality. 

The workflow for this repository is broken into iterative chunks:
### Renaming and filtering initial data
`renameImagesWorkflow.sh`
> This shell script runs the entire first renaming workflow. It kicks off the slurm submission for the First Pass Images Preprocessing, including `generateFirstImageRenaming.R` and `copyImagesWithFirstRename.sh`

`generateFirstImageRenaming.R`
> Takes inputs from the first pass student metadata entry and annotations to generate a list of files deemed "good quality". It generates output lists of original files, renamed file names, and a metadata template for the next pass of student annotations.

`copyImagesWithFirstRename.sh`
> Copies "good" images from the first pass collection, renames them, and places them in a new directory based on the outputs of the R script above.

### Manual metadata transcription
Students take the file `catalog_firstPass_renamedMetadataTemplate.csv` output by `generateFirstImageRenaming.R`. In this step, they check the physical ordering of the tray to ensure that individuals are arranged sequentially and enter all necessary metadata for image processing and linking to individual beetle records into a Google sheet. The entered metadata is stored as `catalog_firstPass_renamedMetadata.xlsx`

### Generating lists of individuals to link to the image

`CheckBeetleCounts.R`
> `catalog_firstPass_renamedMetadata.xlsx` is used to query the NEON ground beetle record and the NEON Availability data to try and generate lists of individuals contained in each image.
> This outputs lists of the correct length to `catalog_firstPass_renamedIndividualsMetadata.csv` and lists that have either too many or too few records to `/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver` or `/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder` respectively for students to go through manually and correct the lists.

## ABTrays

## CTrays

## Belitz

## SmallBeetles




# Pulling all the Data Sources together
IndividualsFromAllSources.R
