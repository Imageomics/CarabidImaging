#!/bin/bash

# Exit if any command fails
set -e

# Set remote name and path
REMOTE="NEONIndividualLinkageChecks"

# Set local destination
LOCAL_DIR="/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/" 

# Use rclone to copy only new or updated files
rclone copy "$LOCAL_DIR" "$REMOTE:" \
  --max-depth 2 \
  --include "*.csv" \
  --exclude "*/Checked/" \
  --verbose \
  --log-file="rclone_send.log"
