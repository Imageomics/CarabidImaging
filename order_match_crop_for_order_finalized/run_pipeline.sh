#!/bin/bash
# =============================================================================
# run_pipeline.sh
# Full order-match-crop pipeline for Output-Finalized detections.
#
# STEP 1 (interactive, ~1 min):
#   Merges CVAT manual annotations into detections_all.csv
#   → produces detections_merged.csv
#
# STEP 2 (SLURM array, ~2-4 hrs total depending on image sizes):
#   Crops beetles in spatial order and links each crop to its individualID
#   via a sidecar {tray}_ids.csv
#   → output in Output-Finalized/Cropped/
#
# STEP 3 (SLURM array, fast — one scalebar box per tray):
#   Crops the scalebar out of each tray (Moondream CSV + manual CVAT override)
#   → output in Output-Finalized/Cropped/scalebars/
#
# Usage:
#   bash run_pipeline.sh              # runs all steps
#   bash run_pipeline.sh --merge-only     # only run step 1
#   bash run_pipeline.sh --crop-only      # only run step 2 (needs merged CSV)
#   bash run_pipeline.sh --scalebar-only  # only run step 3
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Temp SLURM job scripts get cleaned up on exit (success or failure) ----
TMP_FILES=()
cleanup() { rm -f "${TMP_FILES[@]}"; }
trap cleanup EXIT

# ---- Paths (edit if needed) ----
DETECTIONS="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/detections_all.csv"
MERGED="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/detections_merged.csv"
XML="/fs/ess/PAS2136/CarabidImaging/manualAnnotations.xml"
IMAGES_ABTRAY="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/ABTrays"
IMAGES_CTRAY="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/CTrays"
IMAGES_SMALLBEETLES="/fs/ess/PAS2136/CarabidImaging/Images/FinalImages/SmallBeetles"
INDIVIDUALS="/fs/ess/PAS2136/CarabidImaging/allIndividuals.csv"
ALLIMAGES="/fs/ess/PAS2136/CarabidImaging/allImages.csv"
OUTPUT="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Cropped"

# ---- Scalebar sources (step 3) ----
SCALEBAR_CSV="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/Scalebars.csv"
SCALEBAR_XML1="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/ScalebarAnnotations1.xml"
SCALEBAR_XML2="/fs/ess/PAS2136/CarabidImaging/Output-Finalized/Scalebar/ScalebarAnnotations2.xml"

# ---- SLURM settings for crop step ----
NTASKS=8          # number of array tasks (splits ~3500 trays across 8 jobs)
ACCOUNT="PAS2136"
CPUS=4
MEM="16G"
TIME="4:00:00"
PARTITION="nextgen"   # use "gpu" if PIL/image I/O benefits from GPU node memory

# ---- Parse args ----
MERGE=true
CROP=true
SCALEBAR=true
for arg in "$@"; do
    case $arg in
        --merge-only)    CROP=false;  SCALEBAR=false ;;
        --crop-only)     MERGE=false; SCALEBAR=false ;;
        --scalebar-only) MERGE=false; CROP=false ;;
        --no-scalebar)   SCALEBAR=false ;;
    esac
done

# =============================================================================
# STEP 1: Merge CVAT annotations
# =============================================================================
if $MERGE; then
    echo "============================================================"
    echo "STEP 1: Merging CVAT annotations into detections_merged.csv"
    echo "============================================================"
    python3 "${SCRIPT_DIR}/merge_annotations.py" \
        --detections "${DETECTIONS}" \
        --xml        "${XML}" \
        --output     "${MERGED}"
    echo "Done. Merged CSV at: ${MERGED}"
fi

# =============================================================================
# STEP 2: Submit SLURM array job for cropping
# =============================================================================
if $CROP; then
    echo ""
    echo "============================================================"
    echo "STEP 2: Submitting SLURM array job for cropping (${NTASKS} tasks)"
    echo "============================================================"

    JOB_SCRIPT=$(mktemp /tmp/crop_job_XXXX.sh)
    TMP_FILES+=("${JOB_SCRIPT}")
    cat > "${JOB_SCRIPT}" << SLURM_SCRIPT
#!/bin/bash
#SBATCH --account=${ACCOUNT}
#SBATCH --job-name=beetle_crop
#SBATCH --array=0-$((NTASKS - 1))
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --mem=${MEM}
#SBATCH --time=${TIME}
#SBATCH --partition=${PARTITION}
#SBATCH --output=${SCRIPT_DIR}/logs/crop_%A_%a.out
#SBATCH --error=${SCRIPT_DIR}/logs/crop_%A_%a.err

mkdir -p "${SCRIPT_DIR}/logs"

echo "Task \${SLURM_ARRAY_TASK_ID} of ${NTASKS} starting on \$(hostname)"

python3 "${SCRIPT_DIR}/crop_and_link.py" \\
    --detections         "${MERGED}" \\
    --images-abtray      "${IMAGES_ABTRAY}" \\
    --images-ctray       "${IMAGES_CTRAY}" \\
    --images-smallbeetles "${IMAGES_SMALLBEETLES}" \\
    --individuals        "${INDIVIDUALS}" \\
    --allimages          "${ALLIMAGES}" \\
    --output             "${OUTPUT}" \\
    --row-tolerance 0.25 \\
    --ctray-row-tolerance 1.0 \\
    --task        \${SLURM_ARRAY_TASK_ID} \\
    --total-tasks ${NTASKS}

echo "Task \${SLURM_ARRAY_TASK_ID} done."
SLURM_SCRIPT

    mkdir -p "${SCRIPT_DIR}/logs"
    sbatch "${JOB_SCRIPT}"
    echo "Job submitted. Logs will appear in: ${SCRIPT_DIR}/logs/"
    echo "Output will be written to: ${OUTPUT}"
    echo ""
    echo "Output subfolders:"
    echo "  ${OUTPUT}/cropped/          — beetle crops named {tray}_{N}.png, plus a {tray}_ids.csv linking each crop to its individualID"
    echo "  ${OUTPUT}/numbered_trays/   — full tray images with numbered boxes (QC)"
    echo "  ${OUTPUT}/review/           — trays where count still doesn't match"
    echo "  ${OUTPUT}/no_metadata/      — trays with no matching metadata"
fi

# =============================================================================
# STEP 3: Submit SLURM array job for scalebar cropping
# =============================================================================
if $SCALEBAR; then
    echo ""
    echo "============================================================"
    echo "STEP 3: Submitting SLURM array job for scalebar cropping (${NTASKS} tasks)"
    echo "============================================================"

    SB_JOB_SCRIPT=$(mktemp /tmp/scalebar_job_XXXX.sh)
    TMP_FILES+=("${SB_JOB_SCRIPT}")
    cat > "${SB_JOB_SCRIPT}" << SLURM_SCRIPT
#!/bin/bash
#SBATCH --account=${ACCOUNT}
#SBATCH --job-name=scalebar_crop
#SBATCH --array=0-$((NTASKS - 1))
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --mem=${MEM}
#SBATCH --time=${TIME}
#SBATCH --partition=${PARTITION}
#SBATCH --output=${SCRIPT_DIR}/logs/scalebar_%A_%a.out
#SBATCH --error=${SCRIPT_DIR}/logs/scalebar_%A_%a.err

mkdir -p "${SCRIPT_DIR}/logs"

echo "Task \${SLURM_ARRAY_TASK_ID} of ${NTASKS} starting on \$(hostname)"

python3 "${SCRIPT_DIR}/crop_scalebars.py" \\
    --scalebar-csv        "${SCALEBAR_CSV}" \\
    --scalebar-xml        "${SCALEBAR_XML1}" "${SCALEBAR_XML2}" \\
    --images-abtray       "${IMAGES_ABTRAY}" \\
    --images-ctray        "${IMAGES_CTRAY}" \\
    --images-smallbeetles "${IMAGES_SMALLBEETLES}" \\
    --output              "${OUTPUT}" \\
    --pad         0.1 \\
    --task        \${SLURM_ARRAY_TASK_ID} \\
    --total-tasks ${NTASKS}

echo "Task \${SLURM_ARRAY_TASK_ID} done."
SLURM_SCRIPT

    mkdir -p "${SCRIPT_DIR}/logs"
    sbatch "${SB_JOB_SCRIPT}"
    echo "Job submitted. Logs will appear in: ${SCRIPT_DIR}/logs/"
    echo "Scalebar crops will be written to: ${OUTPUT}/scalebars/"
fi
