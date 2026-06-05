# Bespoke Workflow

## Extended Workflow (FirstPass, Belitz)

Historical imaging campaigns with variable image quality require an additional initial quality filtering stage before metadata validation.

### Stage 1: Quality Filtering and Initial Renaming

#### Step 1A: Quality Assessment and Filtering
**Script:** `[DataSource]/generateFirstImageRenaming.R`

**Input:** 
- `catalog_[DataSource].xlsx` - Initial metadata spreadsheet with quality annotations
  - Contains all images from imaging campaign
  - Includes `Good` field marking image quality (1 = acceptable, 0 = reject due to focus/resolution issues)
  - Contains preliminary metadata: domain, numeric IDs, species, year, tray type

**Process:**
1. Filters to images marked as acceptable quality (`Good == 1`)
2. Formats individual IDs to NEON standard format (NEON.BET.D##.######)
3. Generates standardized new image names encoding metadata
4. Creates file list for copying/renaming operations
5. Generates metadata template for next stage of student data entry

**Outputs:**
- `catalog_[DataSource]_filesToRename.csv` - List mapping original filenames to new standardized names
- `catalog_[DataSource]_renamedMetadataTemplate.csv` - Template for comprehensive metadata entry with columns for order verification and marking

#### Step 1B: Copy and Rename Quality-Filtered Images
**Script:** `[DataSource]/copyImagesWithFirstRename.sh`

Copies quality-filtered images from original directory and renames according to generated file list.

**Process:**
- Reads `catalog_[DataSource]_filesToRename.csv`
- Copies images from source directory (e.g., `/Images/Belitz/`) to cleaned directory (e.g., `/Images/BelitzClean/`)
- Applies standardized naming convention
- Reports any missing files

#### Combined Execution
**Script:** `[DataSource]/renameImagesWorkflow.sh`

Slurm job script that executes both quality filtering steps in sequence:
1. `generateFirstImageRenaming.R`
2. `copyImagesWithFirstRename.sh`

**Note:** This initial quality filtering workflow is a prerequisite that must be completed before running the main processing pipeline (`runAllTrayProcesses.sh`).

### Stage 2: Manual Metadata Transcription

After quality filtering, student researchers perform comprehensive metadata entry using the generated template:

**Input:** `catalog_[DataSource]_renamedMetadataTemplate.csv`

**Process:**
1. Students physically verify specimen arrangement in sequential order by NEON individual ID
2. Complete metadata entry including:
   - Four redundant individual IDs (first, second, penultimate, last)
   - Verification that specimens are in correct sequential order (`checkedOrder`)
   - Marking any irregularities (`Marked` field)
   - All metadata required for NEON database linkage

**Output:** `catalog_[DataSource]_renamedMetadata.xlsx` - Complete metadata ready for validation

### Stage 3: Metadata Validation and Individual Linkage
**Script:** `[DataSource]/CheckBeetleCounts.R`

**Input:** `catalog_[DataSource]_renamedMetadata.xlsx`

Identical validation process to standard workflow (see ABTrays description above), using the comprehensive metadata from manual transcription.

**Outputs:**
- `catalog_[DataSource]_renamedIndividualsMetadata.csv` - Successfully linked specimens
- `catalog_[DataSource]_renamedMetadataClean.csv` - Validated image metadata
- Flagged records in `NEONIndividualLinkageChecks/` directories

### Stage 4: Final Image Renaming
**Script:** `[DataSource]/copyImagesWithSecondRename.sh`

**Input:** `catalog_[DataSource]_renamedMetadataClean.csv`

Final renaming pass accounts for any metadata corrections made during validation. Copies images from intermediate directory (e.g., `/Images/BelitzClean/`) to final location (`/Images/FinalImages/ABTrays/`).

> [!NOTE]
> FirstPass and Belitz images are placed in the `ABTrays` final directory as they represent the same tray format.
