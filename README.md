
# First Pass Images
These images were collected by NEON and have some issues with resolution and no associated metadata. The scripts below process the data and work iterativly to take student inputs were we have collected subsiquent metadata and annotations on image quality. 

`renameFirstPassImagesWorkflow.sh`
> This script kicks off the slurm submission for the First Pass Images Preprocessing including `1_renameFirstPassImages.R` and `2_renameFirstPassImages.sh`

`1_renameFirstPassImages.R`
> Takes inputs from first pass studne metadata entry and annotations to generate lists of original files, renamed file names, and a metadata template for the next pass of student annoations.

`2_renameFirstPassImages.sh`
> Copies "good" images from the first pass colection, renames them, and places them in a new directory.




# Backing up data
`rclone.sh`
> This script automates the rclone copying from google drive to OSC. Studnets at the biorepository have contributor access to upload images to the google drive at the end of every day from where they can be copied to OSC
