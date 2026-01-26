# NEON Ground Beetle Digitization and Metadata Integration Workflow

## Overview

This repository contains the complete automated workflow for digitizing ground beetle (Carabidae) specimens from the NEON (National Ecological Observatory Network) Biorepository and linking specimen images to NEON's ecological database. The workflow integrates standardized imaging protocols, redundant metadata capture, automated quality control, and database validation to create a comprehensive dataset linking individual beetle specimens to their images and ecological metadata.

**Key Features:**
- Automated metadata validation against NEON database records
- Redundant quality control using multiple specimen identifiers
- Conservative auto-correction protocols for metadata integrity
- Integration of multiple imaging data sources with varying quality requirements
- Comprehensive specimen-to-image linkage for continental-scale ecological analysis

**Final Outputs:**
- `allIndividuals.csv`: Complete dataset linking every digitized specimen to its image and NEON database record
- `allImages.csv`: Comprehensive image metadata for all digitized specimens

---


## Repository Structure

The repository is organized by data source, with each folder containing scripts for preprocessing images from that specific imaging campaign. Root-level scripts handle data synchronization and cross-source integration.

```
CarabidImaging/
├── ABTrays/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── CTrays/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── FirstPass/
│   ├── generateFirstImageRenaming.R
│   ├── copyImagesWithFirstRename.sh
│   ├── CheckBeetleCounts.R
│   ├── copyImagesWithSecondRename.sh
│   └── renameImagesWorkflow.sh
├── Belitz/
│   ├── generateFirstImageRenaming.R
│   ├── copyImagesWithFirstRename.sh
│   ├── CheckBeetleCounts.R
│   ├── copyImagesWithSecondRename.sh
│   └── renameImagesWorkflow.sh
├── SmallBeetles/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── rclone.sh
├── rclone_sendFilesToStudents.sh
├── runAllTrayProcesses.sh
├── collatImageMetadata.R
├── collatIndividualsFromManualChecks.R
├── collatIndividualsFromAllSources.R
└── rmDuplicateImages.R
```

---

## Complete Workflow Overview

### Stage 0: Data Synchronization
__Moving data between local and Google Drive__
**Script:** `rclone.sh`

Automated synchronization of data between Google Drive and the computing environment. Student researchers upload images and metadata to Google Drive, and rclone copies these files to the processing environment. This script is called automatically at the beginning of `runAllTrayProcesses.sh`.
- `rclone.sh`
  - This script automates the rclone copying from Google Drive to OSC. Students at the biorepository have contributor access to upload images to the Google Drive at the end of every day, from there, they can be copied to OSC

- `rclone_sendFilesToStudents.sh`
  - This script automates the rclone copying of files that need to be individually checked by students from OSC to the appropriate Google Drive subfolders. This script should only be run after manually checking that all Google Sheets in the `Checked` subfolders of `NEONIndividualLinkageChecks` have been downloaded as xlsx files and reuploaded to the drive. These files can then be moved over to OSC with the `rclone.sh` script detailed above, and only then should a list of desired files be derived from the `CheckBeetleCounts.R` scripts below.

---

## Data Source Processing Workflows

Each data source follows a specific processing workflow based on image quality and metadata availability. ABTrays, CTrays, and SmallBeetles have direct workflows, while FirstPass and Belitz require additional quality filtering steps.

### Standard Workflow (ABTrays, CTrays, SmallBeetles)

Data sources with consistently high-quality images and complete metadata follow a streamlined two-step workflow:

#### Step 1: Metadata Validation and Individual Linkage
**Script:** `[DataSource]/CheckBeetleCounts.R`

**Input:** 
- `BeetleMetadata.xlsx` - Google Sheet with manually entered metadata including:
  - Four redundant individual IDs (first, second, penultimate, last specimens)
  - Species scientific name
  - Collection year
  - NEON domain identifier
  - Tray type designation
  - Taxonomic identification status (Expert vs. Parataxonomist)
  - Total specimen count

**Process:**
1. Loads NEON beetle database records via neonUtilities API
2. Retrieves both parataxonomist (`bet_parataxonomistID`) and expert taxonomist (`bet_expertTaxonomistIDProcessed`) identifications
3. Combines datasets with expert IDs superseding parataxonomist records where both exist
4. Filters to physically available specimens using NEON availability data (`occurrences.csv`, `determinations.csv`, `shipments.csv`)
5. Validates manually entered metadata using redundant identifier queries:
   - **Domain ID Validation:** Queries NEON database with species name, year, and numeric ID for all four specimens. If all four queries return the same domain ID that differs from manual entry, automatically corrects domain and cascades update to individual ID formatting
   - **Year Validation:** Cross-references collection year across four specimen queries. Auto-corrects when unanimous agreement differs from manual entry
   - **Species Validation:** Compares species identity across queries. Conservative auto-correction preserves specific manual IDs over generic database placeholders (e.g., "Carabidae sp.")
   - **ID Status Validation:** Verifies expert vs. parataxonomist identification status
6. Generates specimen lists for images where database queries match expected counts
7. Flags mismatches for manual review:
   - `QueryOver/`: Database returns more individuals than expected specimen count
   - `QueryUnder/`: Database returns fewer individuals than expected
   - `QueryZero/`: No matching database records found
8. Creates final lists of images already verified (checks for existing files in `Checked/` subdirectories and removes from output to avoid redundant work)

**Quality Control Features:**
- **Conservative Corrections:** Automatic updates only when all four specimen queries return unanimous agreement
- **Cascading Updates:** Domain ID corrections trigger reformatting of all individual IDs within the tray (format: NEON.BET.D##.######)
- **Comprehensive Documentation:** All automated corrections logged in processing notes with query details

**Outputs:**
- `BeetleMetadata[DataSource]Individuals.csv` - Successfully linked specimens with complete NEON metadata
- `BeetleMetadata[DataSource].csv` - Image-level metadata with processing notes and validation results
- Flagged CSV files in `NEONIndividualLinkageChecks/QueryOver/`, `QueryUnder/`, or `QueryZero/` directories


## Running all ABTray Processes
- `runAllABTrayProcesses.sh` is intended to execute scripts from the subfolders below the result in final images of the A and B Trays (ABTrays, FirstPass, and Belitz, and the "Pulling all data source together" scripts). The shell script submits a Slurm job that kicks off each script in the appropriate order. Unfortunately, some steps need to be performed manually before running, as rclone does not move Google Sheets; only exported versions, such as CSV and XLSX, are supported. 
  - Before running, the following should be downloaded as xlsx from google drive and uploaded to OSC
    - `BeetleMetadata`
    - `catalog_firstPass_renamedMetadata`
    - `catalog_Belitz_renamedMetadata`
  - Download and reupload to Google Drive as xlsx
    - `/NEONIndividualLinkageChecks/QueryUnder/Checked/[all google sheets]`
    - `/NEONIndividualLinkageChecks/QueryOver/Checked/[all google sheets]`

#### Step 2: Image Renaming and Organization
**Script:** `[DataSource]/copyImagesRename.sh`

Renames and copies images to final location using standardized nomenclature encoding specimen metadata. Images moved to `/Images/FinalImages/[DataSource]/` directory.

**Naming Convention:**
```
{Species}_{TrayType}tray_Y{Year}_{FirstIndividualID}-{LastIndividualID}.png
```

Example: `Amara_tenax_Btray_Y2018_NEON.BET.D09.002825-NEON.BET.D09.003611.png`

---

### Extended Workflow (FirstPass, Belitz)

Historical imaging campaigns with variable image quality require an additional initial quality filtering stage before metadata validation.

#### Stage 1: Quality Filtering and Initial Renaming

##### Step 1A: Quality Assessment and Filtering
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

##### Step 1B: Copy and Rename Quality-Filtered Images
**Script:** `[DataSource]/copyImagesWithFirstRename.sh`

Copies quality-filtered images from original directory and renames according to generated file list.

**Process:**
- Reads `catalog_[DataSource]_filesToRename.csv`
- Copies images from source directory (e.g., `/Images/Belitz/`) to cleaned directory (e.g., `/Images/BelitzClean/`)
- Applies standardized naming convention
- Reports any missing files

##### Combined Execution
**Script:** `[DataSource]/renameImagesWorkflow.sh`

Slurm job script that executes both quality filtering steps in sequence:
1. `generateFirstImageRenaming.R`
2. `copyImagesWithFirstRename.sh`

**Note:** This initial quality filtering workflow is a prerequisite that must be completed before running the main processing pipeline (`runAllTrayProcesses.sh`).

#### Stage 2: Manual Metadata Transcription

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

#### Stage 3: Metadata Validation and Individual Linkage
**Script:** `[DataSource]/CheckBeetleCounts.R`

**Input:** `catalog_[DataSource]_renamedMetadata.xlsx`

Identical validation process to standard workflow (see ABTrays description above), using the comprehensive metadata from manual transcription.

**Outputs:**
- `catalog_[DataSource]_renamedIndividualsMetadata.csv` - Successfully linked specimens
- `catalog_[DataSource]_renamedMetadataClean.csv` - Validated image metadata
- Flagged records in `NEONIndividualLinkageChecks/` directories

#### Stage 4: Final Image Renaming
**Script:** `[DataSource]/copyImagesWithSecondRename.sh`

**Input:** `catalog_[DataSource]_renamedMetadataClean.csv`

Final renaming pass accounts for any metadata corrections made during validation. Copies images from intermediate directory (e.g., `/Images/BelitzClean/`) to final location (`/Images/FinalImages/ABTrays/`).

**Note:** FirstPass and Belitz images are placed in the `ABTrays` final directory as they represent the same tray format.

---
## Manual Verification Workflow

When automated validation cannot confidently link specimens to images, records are flagged for manual review:

### Flagging Categories

**QueryOver/** - Database query returns more individuals than expected
- Indicates potential missing specimens, out-of-order arrangement, or database duplicates
- Students mark which specimens are actually present in the image

**QueryUnder/** - Database query returns fewer individuals than expected  
- Indicates potential transcription errors or database gaps
- Students verify actual specimen IDs and add missing individuals

**QueryZero/** - No matching database records found
- Indicates potential transcription errors in domain, year, species, or IDs
- Students reverify all metadata fields against physical specimens

**QueryZeroFilled/** - Manually resolved zero-match cases
- Contains corrected records for cases where no initial database matches were found
- Integrated during final collation with documentation of manual resolution

### Verification Process

1. **Automated Export:** `CheckBeetleCounts.R` generates CSV files with full database query results
2. **Student Review:** Files distributed via `rclone_sendFilesToStudents.sh` to Google Drive
3. **Manual Correction:** Students verify against physical specimens, mark present individuals, correct ordering
4. **Return:** Corrected files saved as XLSX in `Checked/` subdirectories
5. **Re-import:** `rclone.sh` copies verified records back to computing environment
6. **Integration:** `collatIndividualsFromManualChecks.R` integrates all manually verified records

---

## Data Integration and Quality Control

After all data sources are processed, root-level scripts aggregate and harmonize results:

### Step 1: Image Metadata Aggregation
**Script:** `collatImageMetadata.R`

**Inputs:**
- `BeetleMetadataABTrays.csv`
- `BeetleMetadataCTrays.csv`
- `catalog_firstPass_renamedMetadataClean.csv`
- `catalog_Belitz_renamedMetadataClean.csv`
- `BeetleMetadataSmallBeetles.csv`

**Process:**
1. Loads image-level metadata from all five data sources
2. Adds source identifier for each dataset
3. Identifies common columns across datasets
4. Handles source-specific fields (e.g., tray IDs for CTrays)
5. Standardizes image ID fields (renames `newImageID` to `imageID`, preserves original as `originalImageID`)
6. Identifies and documents any duplicate image IDs

**Output:** `allImages.csv` - Master image catalog

### Step 2: Manual Verification Integration
**Script:** `collatIndividualsFromManualChecks.R`

**Inputs:**
- All XLSX files from `NEONIndividualLinkageChecks/QueryOver/Checked/`
- All XLSX files from `NEONIndividualLinkageChecks/QueryUnder/Checked/`
- All XLSX files from `NEONIndividualLinkageChecks/QueryZero/Checked/`
- All XLSX files from `NEONIndividualLinkageChecks/QueryZeroFilled/Checked/`
- `NEON_ExpertParaCombined.csv` - Full NEON database for metadata enrichment

**Process:**
1. **Consolidation:** Collects all manually verified records across query types
2. **Deduplication:** Identifies files present in multiple directories using hierarchical prioritization (QueryOver > QueryUnder > QueryZeroFilled > QueryZero)
3. **Column Standardization:** 
   - Handles inconsistent column naming (`Present` vs. `P`)
   - Adds missing columns from standardized schema
   - Reorders columns to match expected structure
4. **Metadata Backfilling:**
   - Propagates metadata from partially filled rows (notes, processing notes, image paths, tray IDs)
   - Uses longest non-NA value when multiple entries exist
5. **Filtering:** Removes records where `Present != 1` (specimens marked as absent)
6. **Metadata Enrichment:**
   - Identifies manually added individual IDs (those with NA in NEON database fields like `uid`)
   - Queries full NEON database to retrieve complete metadata for manually transcribed IDs
   - Merges database fields with manual verification annotations
7. **CTray Correction:** Uses `allImages.csv` to correct image IDs for CTray records based on tray IDs
8. **Documentation:** Appends query type and manual verification status to processing notes

**Output:** `BeetleMetadataManualIndividuals.csv` - All manually verified specimens with complete metadata
### Step 3: Complete Dataset Assembly
**Script:** `collatIndividualsFromAllSources.R`

**Inputs:**
- `BeetleMetadataABTraysIndividuals.csv`
- `BeetleMetadataCTraysIndividuals.csv`
- `catalog_firstPass_renamedIndividualsMetadata.csv`
- `catalog_Belitz_renamedIndividualsMetadata.csv`
- `BeetleMetadataSmallBeetlesIndividuals.csv`
- `BeetleMetadataManualIndividuals.csv`
- `allImages.csv` - For validation

**Process:**
1. **Source Identification:** Adds source tag to each dataset
2. **Image Path Assignment:** Sets appropriate final image directory for each source
3. **Column Harmonization:** Identifies common columns across all datasets
4. **Initial Merge:** Combines all sources using common column structure
5. **Image Validation:** Removes records for images not present in `allImages.csv`
6. **Duplicate Detection:** Identifies records with duplicate individual IDs
7. **Hierarchical Duplicate Resolution:**

   **Case 1 - Same Image, Same Order:**
   - Multiple records for same individual ID, same image, same spatial order
   - Resolution: Keep single record using source priority
   - Priority: ABTrays > SmallBeetles > CTrays > Manual > Belitz > FirstPass
   - Rationale: Most recent, quality-controlled data sources prioritized

   **Case 2 - Same Image, Different Order:**
   - Same individual ID, same image, but different spatial positions
   - Resolution: Keep single record using alternate priority
   - Priority: Manual > ABTrays > SmallBeetles > CTrays > Belitz > FirstPass
   - Rationale: Manual verification trumps automated spatial assignment conflicts

   **Case 3 - Different Images:**
   - Same individual ID appearing in multiple different images
   - Resolution: Retain ALL records, flag potential errors
   - Quality Control: Species name validation against image identifiers
   - Flag as "Potential IndividualID Error" when:
     - Species name doesn't match image filename
     - Multiple images match the species name (ambiguous case)
   - Rationale: May represent legitimate re-imaging or indicate data quality issues requiring expert review

8. **Final Cleaning:** Removes intermediate columns used for resolution logic

**Output:** `allIndividuals.csv` - Complete specimen dataset

---

## Master Execution Script

### Complete Pipeline Execution
**Script:** `runAllTrayProcesses.sh`

Orchestrates the entire processing workflow as a single Slurm job, executing all steps in correct sequence with appropriate delays for file system synchronization.

**Prerequisites:** 
- FirstPass and Belitz initial quality filtering workflows must be completed beforehand (see Extended Workflow section)
- All manual verification XLSX files in `Checked/` subdirectories will be automatically integrated

**Execution Order:**
```bash
1.  rclone.sh                                    # Data synchronization
2.  FirstPass/CheckBeetleCounts.R                # Validate FirstPass metadata
3.  FirstPass/copyImagesWithSecondRename.sh      # Final FirstPass image renaming
4.  Belitz/CheckBeetleCounts.R                   # Validate Belitz metadata
5.  Belitz/copyImagesWithSecondRename.sh         # Final Belitz image renaming
6.  SmallBeetles/CheckBeetleCounts.R             # Process SmallBeetles
7.  SmallBeetles/copyImagesRename.sh             # Rename SmallBeetles images
8.  ABTrays/CheckBeetleCounts.R                  # Process ABTrays
9.  ABTrays/copyImagesRename.sh                  # Rename ABTrays images
10. CTrays/CheckBeetleCounts.R                   # Process CTrays
11. CTrays/copyImagesRename.sh                   # Rename CTrays images
12. collatImageMetadata.R                        # Aggregate image metadata
13. collatIndividualsFromManualChecks.R          # Integrate manual verifications
14. collatIndividualsFromAllSources.R            # Assemble complete dataset
15. rmDuplicateImages.R                          # Final quality control
```

**Usage:**
```bash
sbatch runAllTrayProcesses.sh
```
---

## Data Source Descriptions

### ABTrays
Standard A and B format specimen trays imaged by trained student researchers at the NEON Biorepository. Images follow standardized protocols with species labels, collection metadata, color reference cards, and 0-1 cm scale bars. Specimens arranged in sequential order by NEON individual ID.

**Characteristics:**
- High image quality
- Complete metadata from imaging session
- Direct processing workflow
- Represents majority of specimens

### CTrays
C format trays containing multiple sub-trays per image. Each image may contain specimens from multiple trays requiring tray-level tracking.

**Characteristics:**
- Multiple trays per image
- Tray ID field for specimen-to-tray mapping
- Specialized handling in data integration
- Distinct final image naming convention

### FirstPass
Initial imaging campaign conducted by NEON with variable image quality and incomplete metadata. Requires quality filtering before processing.

**Characteristics:**
- Variable image resolution and focus
- Missing metadata requiring transcription
- Two-stage processing with quality filtering
- Historical dataset from early digitization efforts

### Belitz
Images from Michael Belitz's ground beetle imaging campaign. Some images have focus issues requiring quality assessment.

**Characteristics:**
- Variable image quality
- Quality annotation and filtering required
- Extended workflow matching FirstPass
- Independent imaging methodology

### SmallBeetles
Processing the images of the small beetles imaged by Aly East at the NEON Biorepository. These data are distinct from other data streams to account for the beetle size. Specialized imaging protocol for small-bodied beetle specimens requiring magnification. Modified imaging setup lacks standardized header information.

**Characteristics:**
- High magnification for small specimens
- Modified imaging protocol
- No standardized header labels
- Specialized handling for image IDs

---
## Key Metadata Fields

### Image Metadata (`allImages.csv`)

**Identification:**
- `imageID` - Standardized image identifier encoding species, tray type, year, and specimen range
- `originalImageID` - Original filename from imaging system
- `trayID` - Tray identifier (CTrays only)

**Collection Context:**
- `domainID` - NEON domain identifier (D01-D20)
- `scientificName` - Species identification
- `yearCollected` - Collection year
- `trayType` - Tray format designation (A, B, C, etc.)

**Imaging Details:**
- `imageSource` - Data source identifier (ABTray Imaging, CTray Imaging, FirstPass Imaging, Belitz Imaging, SmallBeetles Imaging)
- `Photographer` - Imaging personnel identifier
- `dateImaged` - Image capture date

**Quality Control:**
- `NumberOfBeetles` - Count of specimens in image
- `ExpertOrPara` - Taxonomic identification status
- `processingNotes` - Automated processing annotations and corrections
- `Notes` - Manual annotations from students

### Individual Metadata (`allIndividuals.csv`)

**Specimen Identification:**
- `individualID` - NEON unique specimen identifier (format: NEON.BET.D##.######)
- `numbericID` - Numeric portion of individual ID for sorting
- `uid` - NEON database unique identifier

**Image Linkage:**
- `imageID` - Linked image identifier
- `imagePath` - Directory location of linked image
- `Order` - Spatial position of specimen within image (1 = first specimen)
- `Present` - Specimen presence flag (1 = present, 0 = absent)

**Taxonomy:**
- `scientificName` - Full taxonomic identification from NEON database
- `scientificName_Species` - Genus and species only
- `taxonID` - NEON taxonomic identifier
- `taxonRank` - Taxonomic rank of identification
- `identificationQualifier` - Qualifier for uncertain identifications
- `scientificNameAuthorship` - Taxonomic authority
- `morphospeciesID` - Morphospecies designation if applicable
- `ID_status` - Expert vs. parataxonomist identification (Expert/Para)
- `identifiedBy` - Taxonomist name
- `identifiedDate` - Date of identification

**Spatial Context:**
- `domainID` - NEON domain identifier (D01-D20)
- `siteID` - NEON site code
- `plotID` - NEON plot identifier
- `namedLocation` - Full location string

**Temporal Context:**
- `setDate` - Trap deployment date
- `collectDate` - Trap collection date
- `yearCollected` - Collection year

**Specimen Condition:**
- `sampleCondition` - Physical condition notes
- `remarks` - Additional notes from NEON database

**Data Provenance:**
- `source` - Data source and processing method (AB_matched, C_matched, FirstPass_matched, Belitz_matched, Small_matched, Manual)
- `processingNotes` - Documentation of automated corrections, manual verification, and data transformations
- `notes` - Student annotations during metadata entry
- `flag` - Quality control flags ("Potential IndividualID Error" or NA)

**Database Metadata:**
- `publicationDate` - NEON data publication date
- `release` - NEON data release version
- `identificationHistoryID` - NEON identification history tracker
- `identificationReferences` - References used for identification
- `nativeStatusCode` - Native/introduced status

---

## Validation Logic and Quality Control

### Conservative Auto-Correction Protocol

The workflow implements strict requirements for automated metadata correction to prevent erroneous updates:

**Unanimous Agreement Requirement:**
All four redundant specimen queries (first, second, penultimate, last) must return identical values that differ from manual entry before auto-correction is applied.

**Implemented for:**
- Domain ID corrections (with cascading individual ID reformatting)
- Collection year validation
- Species identity updates (with preservation of specific IDs over generic placeholders)
- Taxonomic identification status

**Documentation:**
All corrections logged in `processingNotes` field with details of:
- Original manually entered value
- Corrected value from database
- Query results from all four specimens
- Timestamp and processing stage

### Spatial Order Validation

Sequential ordering of specimens within trays is critical for automated linkage:

**Assumptions:**
- Physical specimens arranged in ascending order by numeric portion of individual ID
- Spatial position in image corresponds to database sequence
- Out-of-order specimens trigger manual review

**Validation:**
- Expected specimen count compared to database query results
- Order position assigned based on spatial arrangement and sequential IDs
- Mismatches flagged for student verification

### Species Validation Logic

Conservative approach preserves information while correcting clear errors:

**Auto-Correction Criteria:**
- All four specimen queries return identical species name
- Returned name differs from manual entry
- Manual entry is generic placeholder ("Carabidae sp.") and database has specific identification
- Unanimous agreement across all queries

**Preservation:**
- Specific manual identifications retained over generic database entries
- Ambiguous cases (conflicting query results) flagged for manual review
- Recent identifications in manual entry preserved over outdated database records

### Duplicate Resolution Rationale

**Source Priority Logic:**
Hierarchy reflects data quality confidence:
1. Manual verification - Highest confidence, directly verified against physical specimens
2. ABTrays - Most recent, standardized protocol with trained students
3. SmallBeetles - Recent, specialized protocol for difficult specimens
4. CTrays - Recent, but complex multi-tray images
5. Belitz - Historical campaign, quality-filtered but older methods
6. FirstPass - Earliest campaign, variable quality

**Spatial Consistency:**
When same individual appears in same image at same position from multiple sources, most reliable source retained. When positions differ, manual verification prioritized as it involves physical specimen checking.

**Cross-Image Duplicates:**
Individual IDs appearing in multiple different images retained with quality flags rather than automatic resolution, as these may represent:
- Legitimate re-imaging for quality improvement
- Specimen curation errors (mislabeled specimens)
- Transcription errors in one or both records
- Database linkage errors requiring expert review

---

## File Naming Conventions

### Standardized Image Names

Images renamed to encode metadata for AI-ready dataset organization:

**Format:**
```
{Species_name}_{TrayType}tray_Y{Year}_{FirstIndividualID}-{LastIndividualID}.{ext}
```

**Components:**
- `Species_name` - Genus_species with underscores replacing spaces
- `TrayType` - Single letter (A, B, C, etc.)
- `Year` - Four-digit collection year
- `FirstIndividualID` - Full NEON ID of first specimen
- `LastIndividualID` - Full NEON ID of last specimen (omitted if single specimen)
- `ext` - File extension (JPG, PNG, etc.)

**Examples:**
```
Amara_tenax_Btray_Y2018_NEON.BET.D09.002825-NEON.BET.D09.003611.png
Carabus_goryi_Atray_Y2020_NEON.BET.D15.001234.PNG
Pterostichus_melanarius_Ctray_Y2019_NEON.BET.D03.005678-NEON.BET.D03.005702.png
```

### Individual ID Format

NEON individual identifiers follow standardized structure enabling automated parsing:

**Format:** `NEON.BET.D{DomainID}.{NumericID}`

**Components:**
- `NEON` - Network identifier
- `BET` - Beetle (ground beetle) product code
- `D{DomainID}` - Two-digit domain identifier (D01-D20)
- `{NumericID}` - Six-digit numeric identifier unique within domain

**Examples:**
```
NEON.BET.D09.002825
NEON.BET.D15.001234
NEON.BET.D03.005678
```

---

## Requirements

### R Packages
```r
neonUtilities  # NEON API data retrieval and database access
readxl         # Excel file reading for metadata spreadsheets
dplyr          # Data manipulation and transformation
tibble         # Enhanced data frames with quality checks
stringr        # String processing for validation
bit            # Set operations for column comparison
```

### External Data Files

**NEON Database (automatically downloaded):**
- Data Product ID: DP1.10022.001 (Ground beetles sampled from pitfall traps)
- Retrieved via neonUtilities API with personal token
- Includes both released and provisional data

**NEON Availability Data (provided by NEON staff):**
- `occurrences.csv` - Specimen occurrence records with availability flags
- `determinations.csv` - Identification history
- `shipments.csv` - Specimen loan and shipment tracking

**Metadata Spreadsheets:**
- `BeetleMetadata.xlsx` - Manual metadata entry for ABTrays, CTrays, SmallBeetles
- `catalog_firstPass.xlsx` - Initial FirstPass data with quality annotations
- `catalog_firstPass_renamedMetadata.xlsx` - FirstPass comprehensive metadata
- `catalog_Belitz.xlsx` - Initial Belitz data with quality annotations
- `catalog_Belitz_renamedMetadata.xlsx` - Belitz comprehensive metadata

**NEON API Token:**
- Stored in `~/NEON_Token_AE`
- Required for database queries
- Obtain from NEON data portal user account

### Computing Environment

**Current Configuration:**
- Ohio Supercomputer Center (OSC)
- Slurm job scheduling
- R version: 4.4.0
- GCC version: 12.3.0

**Path Configuration:**
- Google Drive sync via rclone
- Paths in scripts may require adjustment for other computing environments

---
## Citation

If you use this workflow or dataset, please cite:
**Workflow Paper:**
East, A., et al. (in prep). From collection trays to AI-ready data: An operational framework for automated entomological specimen processing.

**Dataset:**
[Citation details to be added upon data publication]

---

## Acknowledgments

This work was conducted in collaboration with the NEON Biorepository at Arizona State University. We thank the student researchers who performed imaging and metadata transcription. We are grateful to NEON staff for providing specimen availability data, database access, and expertise in collections and groud beetle systematics.

Special thanks to Michael Belitz for contributing the Belitz imaging dataset and contunued input on this work.

**Funding:**
This work was supported by both the Imageomics Institute and the AI and Biodiversity Change (ABC) Global Center. The Imageomics Institute is funded by the US National Science Foundation's Office of Advanced Cyberinfrastructure: Harnessing the Data Revolution (HDR) programme under Award #2118240 (Imageomics: A New Frontier of Biological Information Powered by Knowledge-Guided Machine Learning). The ABC Global Climate Center is funded by the US National Science Foundation Office of International Science and Engineering under Award #2330423 and the Natural Sciences and Engineering Research Council of Canada under Award #585136. S.R. and A.E. were additionally supported by NSF award #2429418 (EPSCOR Research Fellows: NSF: Advancing National Ecological Observatory Network-Enabled Science and Workforce Development at the University of Maine with Artificial Intelligence) and by Hatch Project Award #MEO-022425 from the US Department of Agriculture's National Institute of Food and Agriculture. This material is based in part upon work supported by the National Ecological Observatory Network (NEON), a programme sponsored by the U.S. National Science Foundation (NSF) and operated under cooperative agreement by Battelle.

---
## Appendix: Directory Structure

### Complete Working Directory Layout

```
CarabidImaging/
├── Images/
│   ├── Belitz/                      # Original Belitz images
│   ├── BelitzClean/                 # Quality-filtered Belitz images
│   ├── FirstPass/                   # Original FirstPass images
│   ├── FirstPassClean/              # Quality-filtered FirstPass images
│   └── FinalImages/
│       ├── ABTrays/                 # Final ABTrays, FirstPass, Belitz images
│       ├── CTrays/                  # Final CTrays images
│       └── SmallBeetles/            # Final SmallBeetles images
├── NEONIndividualLinkageChecks/
│   ├── QueryOver/                   # Too many database matches
│   │   └── Checked/                 # Manually verified
│   ├── QueryUnder/                  # Too few database matches
│   │   └── Checked/                 # Manually verified
│   ├── QueryZero/                   # No database matches
│   │   └── Checked/                 # Manually verified
│   └── QueryZeroFilled/             # Resolved zero-match cases
│       └── Checked/                 # Manually verified
├── ABTrays/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── CTrays/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── FirstPass/
│   ├── generateFirstImageRenaming.R
│   ├── copyImagesWithFirstRename.sh
│   ├── CheckBeetleCounts.R
│   ├── copyImagesWithSecondRename.sh
│   └── renameImagesWorkflow.sh
├── Belitz/
│   ├── generateFirstImageRenaming.R
│   ├── copyImagesWithFirstRename.sh
│   ├── CheckBeetleCounts.R
│   ├── copyImagesWithSecondRename.sh
│   └── renameImagesWorkflow.sh
├── SmallBeetles/
│   ├── CheckBeetleCounts.R
│   └── copyImagesRename.sh
├── out/                             # Slurm job output logs
├── rclone.sh
├── rclone_sendFilesToStudents.sh
├── runAllTrayProcesses.sh
├── collatImageMetadata.R
├── collatIndividualsFromManualChecks.R
├── collatIndividualsFromAllSources.R
├── rmDuplicateImages.R
├── NEON_ExpertParaCombined.csv      # Downloaded NEON database
├── NEON_ExpertParaCombined_Prelim.csv
├── occurrences.csv                  # NEON availability data
├── determinations.csv
├── shipments.csv
├── BeetleMetadata.xlsx              # Manual metadata entry
├── catalog_firstPass.xlsx           # Initial FirstPass annotations
├── catalog_firstPass_filesToRename.csv
├── catalog_firstPass_renamedMetadata.xlsx
├── catalog_firstPass_renamedMetadataClean.csv
├── catalog_firstPass_renamedIndividualsMetadata.csv
├── catalog_Belitz.xlsx              # Initial Belitz annotations
├── catalog_Belitz_filesToRename.csv
├── catalog_Belitz_renamedMetadata.xlsx
├── catalog_Belitz_renamedMetadataClean.csv
├── catalog_Belitz_renamedIndividualsMetadata.csv
├── BeetleMetadataABTrays.csv
├── BeetleMetadataABTraysIndividuals.csv
├── BeetleMetadataCTrays.csv
├── BeetleMetadataCTraysIndividuals.csv
├── BeetleMetadataSmallBeetles.csv
├── BeetleMetadataSmallBeetlesIndividuals.csv
├── BeetleMetadataManualIndividuals.csv
├── allImages.csv                    # FINAL OUTPUT
└── allIndividuals.csv               # FINAL OUTPUT
```


