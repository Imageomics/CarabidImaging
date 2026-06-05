# Primary Workflow

## Standard Workflow (ABTrays, CTrays, SmallBeetles)

Data sources with consistently high-quality images and complete metadata follow a streamlined two-step workflow:

### Step 1: Metadata Validation and Individual Linkage
**Script:** `[DataSource]/CheckBeetleCounts.R`

#### Input
- `BeetleMetadata.xlsx` - Google Sheet with manually entered metadata including:
  - Four redundant individual IDs (first, second, penultimate, last specimens)
  - Species scientific name
  - Collection year
  - NEON domain identifier
  - Tray type designation
  - Taxonomic identification status (Expert vs. Parataxonomist)
  - Total specimen count

#### Process
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

#### Quality Control Features
- **Conservative Corrections:** Automatic updates only when all four specimen queries return unanimous agreement
- **Cascading Updates:** Domain ID corrections trigger reformatting of all individual IDs within the tray (format: NEON.BET.D##.######)
- **Comprehensive Documentation:** All automated corrections logged in processing notes with query details

#### Outputs
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

### Step 2: Image Renaming and Organization
**Script:** `[DataSource]/copyImagesRename.sh`

Renames and copies images to final location using standardized nomenclature encoding specimen metadata. Images moved to `/Images/FinalImages/[DataSource]/` directory.

**Naming Convention:**
```
{Species}_{TrayType}tray_Y{Year}_{FirstIndividualID}-{LastIndividualID}.png
```

Example: `Amara_tenax_Btray_Y2018_NEON.BET.D09.002825-NEON.BET.D09.003611.png`

---