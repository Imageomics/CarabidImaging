# Requirements

## R Packages
```r
neonUtilities  # NEON API data retrieval and database access
readxl         # Excel file reading for metadata spreadsheets
dplyr          # Data manipulation and transformation
tibble         # Enhanced data frames with quality checks
stringr        # String processing for validation
bit            # Set operations for column comparison
```

## External Data Files

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

## Computing Environment

**Current Configuration:**
- Ohio Supercomputer Center (OSC)
- Slurm job scheduling
- R version: 4.4.0
- GCC version: 12.3.0

**Path Configuration:**
- Google Drive sync via rclone
- Paths in scripts may require adjustment for other computing environments
