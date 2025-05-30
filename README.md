# Carabid Imaging
__Description of work__

# Backing up data
`rclone.sh`
> This script automates the rclone copying from google drive to OSC. Studnets at the biorepository have contributor access to upload images to the google drive at the end of every day from where they can be copied to OSC

Each folder in this directory (FirstPass, ABTrays, CTrays, Belitz, and SmallBeetles) referes to a distinct data source, and contains code to do all nessisary preprocessing of the images provided by that data source. 


## First Pass Images
These images were collected by NEON and have some issues with resolution and no associated metadata. The scripts below process the data and work iterativly to take student inputs were we have collected subsiquent metadata and annotations on image quality. 

The workflow for this repositiry is boken into iterative chuncks:
### Renaming and filtering inital data
`renameImagesWorkflow.sh`
> This shell script runs the entire first renaming workflow, it kicks off the slurm submission for the First Pass Images Preprocessing including `generateFirstImageRenaming.R` and `copyImagesWithFirstRename.sh`

`generateFirstImageRenaming.R`
> Takes inputs from first pass student metadata entry and annotations to generate a list of files deamed "good quality". It the outputs lists of original files, renamed file names, and a metadata template for the next pass of student annoations.

`copyImagesWithFirstRename.sh`
> Copies "good" images from the first pass colection, renames them, and places them in a new directory.

### Mannual metadata transcription
Students take the file `catalog_firstPass_renamedMetadataTemplate.csv` output by `generateFirstImageRenaming.R`. In this step they check the physicall ordering of the tray to ensure that Inividuals are arranged sequentally, and enter all nessesary metadata for image processing and linking to individual beetle records into a google sheet. The entered metadata in stored as `catalog_firstPass_renamedMetadata.xlsx`

### Generating lists of individuals to link to the image

`CheckBeetleCounts.R`
> `catalog_firstPass_renamedMetadata.xlsx` is used to query the NEON groundbeetle record and the NEON Avaiability data to try and generate lists of indivuiduals contained in each image.
> This outputs lists of the correct lenght to `catalog_firstPass_renamedIndividualsMetadata.csv` and lists that have either too many or too few records to `/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver` or `/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder` respectivly for students to go through manually and correct the lists. 


# Pulling all the Data Sources together
IndividualsFromAllSources.R
