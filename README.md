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

The repository is organized by data source, with each folder containing scripts for preprocessing images from that specific imaging campaign. This data collection effort combined five data streams, two (FirstPass and Belitz) were from earlier partial digitization efforts that did not utilize our [SOP](https://docs.google.com/document/d/1LAFRHcIYBlsGHMpv6suvsMbSYi10SKChOLsU5JlXlqw/edit?usp=sharing), so they required some bespoke scripts and iterative processes to match.

The primary re-usable workflow is run through `runAllTrayProcesses.sh`, which implements the `ABTrays`, `CTrays`, and `SmallBeetles` processing.

Root-level scripts handle data synchronization and cross-source integration.

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

This work was supported by the [Imageomics Institute](https://imageomics.org), which is funded by the US National Science Foundation's Harnessing the Data Revolution (HDR) program under [Award #2118240](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2118240) (Imageomics: A New Frontier of Biological Information Powered by Knowledge-Guided Machine Learning). This material is based in part upon work supported by the National Ecological Observatory Network ([NEON](https://www.neonscience.org/)), a program sponsored by the U.S. National Science Foundation (NSF) and operated under cooperative agreement by Battelle.

S. Record and A. East were additionally supported by the US National Science Foundation's [Award No. 242918](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2429418&HistoricalAwards=false) (EPSCOR Research Fellows: NSF: Advancing National Ecological Observatory Network-Enabled Science and Workforce Development at the University of Maine with Artificial Intelligence) and by Hatch project Award #MEO-022425 from the US Department of Agriculture’s National Institute of Food and Agriculture. M. Belitz was additionally supported by the US National Science Foundation's [Award #2410152](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2410152&HistoricalAwards=false).

Any opinions, findings and conclusions or recommendations expressed in this material are those of the author(s) and do not necessarily reflect the views of the National Science Foundation or US Department of Agriculture.

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


