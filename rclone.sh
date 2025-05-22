#!/bin/bash

# Exit if any command fails
set -e

# Set remote name and path
REMOTE="GoogleDrive_NEONBeetle"

# Set local destination
LOCAL_DIR="/fs/ess/PAS2136/CarabidImaging/" 

# Use rclone to copy only new or updated files
rclone copy "$REMOTE:" "$LOCAL_DIR" \
  --drive-export-formats xlsx \
  --update \
  --verbose \
  --log-file="$LOCAL_DIR/rclone_sync.log"

