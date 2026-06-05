# 

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
