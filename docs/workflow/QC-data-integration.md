# Data Integration and Quality Control

After all data sources are processed, root-level scripts aggregate and harmonize results:

## Step 1: Image Metadata Aggregation
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

## Step 2: Manual Verification Integration
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
