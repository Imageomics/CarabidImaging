#!/bin/bash

# Set working directory
WORKDIR="/fs/ess/PAS2136/CarabidImaging"

# Define paths
CSV="$WORKDIR/catalog_firstPass_filesToRename.csv"
SRC_DIR="$WORKDIR/Images/FirstPass"
DEST_DIR="$WORKDIR/Images/FirstPassClean"


# Make sure the destination directory exists

mkdir -p "$DEST_DIR"

# Skip the header and process CSV lines
tail -n +2 "$CSV" | awk -F',' '{print $3","$15}' | while IFS=',' read -r imageID newImageID; do
    # Trim whitespace (optional but good practice)
    imageID=$(echo "$imageID" | xargs)
    newImageID=$(echo "$newImageID" | xargs)

    src="$SRC_DIR/$imageID"
    dest="$DEST_DIR/$newImageID"

    if [ -f "$src" ]; then
        cp "$src" "$dest"
        echo "Copied: $src -> $dest"
    else
        # Append missing file path to the array
        missing_files+=("$src")
    fi
done

# After the loop, print all missing files (if any)
if [ ${#missing_files[@]} -gt 0 ]; then
    echo
    echo "The following files were missing and could not be copied:"
    for filepath in "${missing_files[@]}"; do
        echo "  $filepath"
    done
fi
