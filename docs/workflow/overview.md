# Data Source Processing Workflows

Each data source follows a specific processing workflow based on image quality and metadata availability. ABTrays, CTrays, and SmallBeetles have direct workflows, while FirstPass and Belitz require additional quality filtering steps.

## Master Execution Script

For the standard workflow, the entire pipeline can be run through the `runAllTrayProcesses.sh` script. Once this process is completed, `rclone_sendFilesToStudents.sh` is run manually to generate and share the completed spreadsheet for manual review.

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
