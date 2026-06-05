## Manual Verification Workflow

When automated validation cannot confidently link specimens to images, records are flagged for manual review:

## Flagging Categories

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

## Verification Process

1. **Automated Export:** `CheckBeetleCounts.R` generates CSV files with full database query results
2. **Student Review:** Files distributed via `rclone_sendFilesToStudents.sh` to Google Drive
3. **Manual Correction:** Students verify against physical specimens, mark present individuals, correct ordering
4. **Return:** Corrected files saved as XLSX in `Checked/` subdirectories
5. **Re-import:** `rclone.sh` copies verified records back to computing environment
6. **Integration:** `collatIndividualsFromManualChecks.R` integrates all manually verified records
