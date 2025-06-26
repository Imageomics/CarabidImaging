#!/bin/bash

# Exit if any command fails
set -e

# Set remote name and path
REMOTE="StudentRAW"

# Set local destination
LOCAL_DIR="/fs/ess/PAS2136/CarabidImaging/StudentRAW/" 

# Use rclone to copy only new or updated files
rclone copy "$REMOTE:" "$LOCAL_DIR" \
  --drive-export-formats xlsx \
  --update \
  --verbose \
  --log-file="/fs/ess/PAS2136/CarabidImaging/rclone_pullStudentRAWs.log"

REMOTE="GoogleDrive_NEONBeetleRAW"

# Use rclone to copy only new or updated files
rclone copy "$LOCAL_DIR" "$REMOTE:" \
  --max-depth 1 \
  --update \
  --verbose \
  --log-file="/fs/ess/PAS2136/CarabidImaging/rclone_changeOwnership.log"
