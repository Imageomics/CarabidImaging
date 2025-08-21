# Define directories
dir <- "/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays"

# List .csv and .xlsx files
png_files <- list.files(dir, pattern = "\\.png$", full.names = FALSE)
jpg_files <- list.files(dir, pattern = "\\.jpg$", full.names = TRUE)

# Get base names (without extensions) of the xlsx files
png_basenames <- tools::file_path_sans_ext(png_files)

# Filter csv files to identify which to delete
jpg_to_remove <- jpg_files[
  tools::file_path_sans_ext(basename(jpg_files)) %in% png_basenames
]

# Confirm what will be deleted
cat("The following jpgs files will be removed:\n")
print(jpg_to_remove)

# OPTIONAL: Delete the files
# Be careful with this step; uncomment to activate deletion
file.remove(jpg_to_remove)
length(list.files(jpg_files, pattern = "\\.jpg$", full.names = TRUE))
