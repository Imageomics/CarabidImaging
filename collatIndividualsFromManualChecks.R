library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)

setwd("/fs/ess/PAS2136/CarabidImaging/")

#Read in the NEON data
combined_data <- read.csv("./NEON_ExpertParaCombined.csv")
combined_data$scientificName_Species<-gsub(r"{\s*\([^\)]+\)}","",as.character(combined_data$scientificName))
combined_data$scientificName_Species<-gsub(" {2,}", " ", combined_data$scientificName_Species)
combined_data$scientificName_Species<-sub("^(\\S*\\s+\\S+).*", "\\1", combined_data$scientificName_Species)

#### 1. Query Over ####
# 1.1 Read in the data ####
#Individuals that had to be manually filtered from query with too many entries
QueryOverCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver/Checked/"
QueryOverCheckedFiles<-list.files(QueryOverCheckedDir, pattern = "*.xlsx")

#Read in first file to create the seed for the dataset
QueryOverChecked_df <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[1]),
                                                sheet = 1))
QueryOverCheckedFiles[1]
QueryOverChecked_df$imageID<-paste0(substr(QueryOverCheckedFiles[1], 
                                           7, (nchar(QueryOverCheckedFiles[1])-4)),
                                    "png")
QueryOverChecked_df<-QueryOverChecked_df %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
if (!"Order" %in% names(QueryOverChecked_df)) {
  QueryOverChecked_df<-add_column(QueryOverChecked_df, Order = "", .before = "sampleCondition")
  QueryOverChecked_df$Order <- 1:nrow(QueryOverChecked_df)
}

#Define the desired output column names
cols<-c("uid","namedLocation","domainID","siteID","plotID","setDate","collectDate","identifiedDate","individualID","Present",
        "Order","sampleCondition","taxonID","scientificName","taxonRank","identificationQualifier","scientificNameAuthorship",
        "morphospeciesID","identificationReferences","nativeStatusCode","identifiedBy","remarks","identificationHistoryID",
        "publicationDate","release","ID_status","numbericID","yearCollected","scientificName_Species","NumberOfBeetlesInTray",
        "notes","processingNotes","imagePath","imageID")

#### 1.2 Standardize Column Names and Fill Missing Columns ####

# Fix inconsistent "Present" column name
present_col <- names(QueryOverChecked_df)[tolower(names(QueryOverChecked_df)) == "present" | 
                                            tolower(names(QueryOverChecked_df)) == "p"]

if (length(present_col) == 1 && present_col != "Present") {
  names(QueryOverChecked_df)[names(QueryOverChecked_df) == present_col] <- "Present"
}

# Add any missing columns from `cols`
missing_cols <- setdiff(cols, names(QueryOverChecked_df))
if (length(missing_cols) > 0) {
  for (col in missing_cols) {
    QueryOverChecked_df[[col]] <- NA
  }
}

# Reorder columns to match `cols` order
QueryOverChecked_df <- QueryOverChecked_df[, cols]

#### 1.3 Loop over the rest of the files and rbind them together####
for (i in 2:length(QueryOverCheckedFiles)) {
  # Read in the file
  tmp <- as.data.frame(read_excel(paste0(QueryOverCheckedDir, QueryOverCheckedFiles[i]),
                                  sheet = 1))
  
  # Add imageID column based on filename
  tmp$imageID <- paste0(substr(QueryOverCheckedFiles[i], 
                               7, (nchar(QueryOverCheckedFiles[i]) - 4)),
                        "png")
  
  # Sort by individualID
  tmp <- tmp %>% arrange(individualID)
  
  # Add "Order" column if missing
  if (!"Order" %in% names(tmp)) {
    tmp <- add_column(tmp, Order = "", .before = "sampleCondition")
    tmp$Order <- 1:nrow(tmp)
  }
  
  # Fix inconsistent "Present" column name
  present_col <- names(tmp)[tolower(names(tmp)) == "present" | 
                              tolower(names(tmp)) == "p"]
  if (length(present_col) == 1 && present_col != "Present") {
    names(tmp)[names(tmp) == present_col] <- "Present"
  }
  
  # Add any missing columns from `cols`
  missing_cols <- setdiff(cols, names(tmp))
  if (length(missing_cols) > 0) {
    for (col in missing_cols) {
      tmp[[col]] <- NA
    }
  }
  
  # Reorder columns
  tmp <- tmp[, cols]
  
  # Bind to master dataframe
  QueryOverChecked_df <- bind_rows(QueryOverChecked_df, tmp)
}

# 1.4 Remove all of the instances where there is an individual ID recorded that is not present ####
table(QueryOverChecked_df$imageID)
table(QueryOverChecked_df$Present)
QueryOverChecked_df<-subset(QueryOverChecked_df, Present==1)
QueryOverChecked_df$processingNotes<-paste0("QueryOver, Manually Checked;",QueryOverChecked_df$processingNotes)
table(QueryOverChecked_df$P)
table(QueryOverChecked_df$processingNotes)

table(QueryOverChecked_df$domainID, useNA = "ifany")

#### 1.5 Pull out records where individualID exists but other NEON columns are NA ####
# Filter manually added entries (i.e., those with NA in key NEON fields like uid)
QueryOverChecked_df_manualAdditions <- QueryOverChecked_df %>% 
  filter(is.na(uid))

# List unique images where manual additions occurred
Images_w_Additions <- unique(QueryOverChecked_df_manualAdditions$imageID)

# Initialize empty dataframe to hold corrected records
manual_filled_df <- data.frame()

#### 1.6 Fill in metadata for manually transcribed individualIDs with missing metadata ####
# Loop over each imageID to refill data from combined_data
for (img in Images_w_Additions) {
  # Subset manually added records for this image
  tmp_manual <- QueryOverChecked_df %>% 
    filter(imageID == img) %>%
    arrange(individualID)
  
  # Get matching NEON records for the same individuals
  tmp_neon <- combined_data %>% 
    filter(individualID %in% tmp_manual$individualID) %>%
    arrange(individualID)
  
  # Ensure same number of records for merging
  if (nrow(tmp_neon) != nrow(tmp_manual)) {
    warning(paste("Row count mismatch for image:", img))
    next
  }
  
  # Enrich NEON records with data fields from manual records
  tmp_filled <- tmp_neon %>%
    mutate(
      Present = 1,
      Order = tmp_manual$Order,
      yearCollected = substr(setDate, 1, 4),
      NumberOfBeetlesInTray = max(tmp_manual$NumberOfBeetlesInTray, na.rm = TRUE),
      imageID = img,
      imagePath = unique(tmp_manual$imagePath)[1],
      processingNotes = tmp_manual$notes,
      notes = tmp_manual$processingNotes
    ) 
  
  # Add any missing columns to match full `cols` set
  missing_cols <- setdiff(cols, names(tmp_filled))
  if (length(missing_cols) > 0) {
    tmp_filled[missing_cols] <- NA
  }
  # Reorder columns
  tmp_filled <- tmp_filled[, cols]
  
  # Append to result
  manual_filled_df <- bind_rows(manual_filled_df, tmp_filled)
}

dim(QueryOverChecked_df)
dim(manual_filled_df)

QueryOverChecked_df<-QueryOverChecked_df%>%
  filter(!(imageID %in% Images_w_Additions))

dim(QueryOverChecked_df)
QueryOverChecked_df<-rbind(QueryOverChecked_df,manual_filled_df)
dim(QueryOverChecked_df)

#### Query Under####
# 2.1 Read in the data ####
#Individuals that had to be manually filtered from query with too many entries
QueryUnderCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/"
QueryUnderCheckedFiles<-list.files(QueryUnderCheckedDir, pattern = "*.xlsx")

#Read in first file to create the seed for the dataset
QueryUnderChecked_df <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[1]),
                                                 sheet = 1))
QueryUnderChecked_df$imageID<-paste0(substr(QueryUnderCheckedFiles[1], 
                                            7, (nchar(QueryUnderCheckedFiles[1])-4)),
                                     "png")

#### 2.2 Standardize Column Names and Fill Missing Columns ####

# Fix inconsistent "Present" column name
present_col <- names(QueryUnderChecked_df)[tolower(names(QueryUnderChecked_df)) == "present" | 
                                            tolower(names(QueryUnderChecked_df)) == "p"]

if (length(present_col) == 1 && present_col != "Present") {
  names(QueryUnderChecked_df)[names(QueryUnderChecked_df) == present_col] <- "Present"
}

# Add any missing columns from `cols`
missing_cols <- setdiff(cols, names(QueryUnderChecked_df))
if (length(missing_cols) > 0) {
  for (col in missing_cols) {
    QueryUnderChecked_df[[col]] <- NA
  }
}

# Reorder columns to match `cols` order
QueryUnderChecked_df <- QueryUnderChecked_df[, cols]

#### 2.3 Loop over the rest of the files and rbind them together####
for (i in 2:length(QueryUnderCheckedFiles)) {
  # Read in the file
  tmp <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir, QueryUnderCheckedFiles[i]),
                                  sheet = 1))
  
  # Add imageID column based on filename
  tmp$imageID <- paste0(substr(QueryUnderCheckedFiles[i], 
                               7, (nchar(QueryUnderCheckedFiles[i]) - 4)),
                        "png")
  
  # Sort by individualID
  tmp <- tmp %>% arrange(individualID)
  
  # Add "Order" column if missing
  if (!"Order" %in% names(tmp)) {
    tmp <- add_column(tmp, Order = "", .before = "sampleCondition")
    tmp$Order <- 1:nrow(tmp)
  }
  
  # Fix inconsistent "Present" column name
  present_col <- names(tmp)[tolower(names(tmp)) == "present" | 
                              tolower(names(tmp)) == "p"]
  if (length(present_col) == 1 && present_col != "Present") {
    names(tmp)[names(tmp) == present_col] <- "Present"
  }
  
  # Add any missing columns from `cols`
  missing_cols <- setdiff(cols, names(tmp))
  if (length(missing_cols) > 0) {
    for (col in missing_cols) {
      tmp[[col]] <- NA
    }
  }
  
  # Reorder columns
  tmp <- tmp[, cols]
  
  # Bind to master dataframe
  QueryUnderChecked_df <- bind_rows(QueryUnderChecked_df, tmp)
}

# 2.4 Remove all of the instances where there is an individual ID recorded that is not present ####
table(QueryUnderChecked_df$imageID)
table(QueryUnderChecked_df$Present)
QueryUnderChecked_df<-subset(QueryUnderChecked_df, Present==1)
QueryUnderChecked_df$processingNotes<-paste0("QueryUnder, Manually Checked;",QueryUnderChecked_df$processingNotes)
table(QueryUnderChecked_df$P)
table(QueryUnderChecked_df$processingNotes)

table(QueryUnderChecked_df$domainID, useNA = "ifany")

#### 1.5 Pull out records where individualID exists but other NEON columns are NA ####
# Filter manually added entries (i.e., those with NA in key NEON fields like uid)
QueryUnderChecked_df_manualAdditions <- QueryUnderChecked_df %>% 
  filter(is.na(uid))

# List unique images where manual additions occurred
Images_w_Additions <- unique(QueryUnderChecked_df_manualAdditions$imageID)

# Initialize empty dataframe to hold corrected records
manual_filled_df <- data.frame()

#### 1.6 Fill in metadata for manually transcribed individualIDs with missing metadata ####
# Loop over each imageID to refill data from combined_data
for (img in Images_w_Additions) {
  # Subset manually added records for this image
  tmp_manual <- QueryUnderChecked_df %>% 
    filter(imageID == img) %>%
    arrange(individualID)
  
  # Get matching NEON records for the same individuals
  tmp_neon <- combined_data %>% 
    filter(individualID %in% tmp_manual$individualID) %>%
    arrange(individualID)
  
  # Ensure same number of records for merging
  if (nrow(tmp_neon) != nrow(tmp_manual)) {
    warning(paste("Row count mismatch for image:", img))
    next
  }
  
  # Enrich NEON records with data fields from manual records
  tmp_filled <- tmp_neon %>%
    mutate(
      Present = 1,
      Order = tmp_manual$Order,
      yearCollected = substr(setDate, 1, 4),
      NumberOfBeetlesInTray = max(tmp_manual$NumberOfBeetlesInTray, na.rm = TRUE),
      imageID = img,
      imagePath = unique(tmp_manual$imagePath)[1],
      processingNotes = tmp_manual$notes,
      notes = tmp_manual$processingNotes
    ) 
  
  # Add any missing columns to match full `cols` set
  missing_cols <- setdiff(cols, names(tmp_filled))
  if (length(missing_cols) > 0) {
    tmp_filled[missing_cols] <- NA
  }
  # Reorder columns
  tmp_filled <- tmp_filled[, cols]
  
  # Append to result
  manual_filled_df <- bind_rows(manual_filled_df, tmp_filled)
}

dim(QueryUnderChecked_df)
dim(manual_filled_df)

QueryUnderChecked_df<-QueryUnderChecked_df%>%
  filter(!(imageID %in% Images_w_Additions))

dim(QueryUnderChecked_df)
QueryUnderChecked_df<-rbind(QueryUnderChecked_df,manual_filled_df)
dim(QueryUnderChecked_df)




#### 3. Merged the Harmonized dataset and export ####
queryAll<-rbind(QueryUnderChecked_df, QueryOverChecked_df)
dim(queryAll)
write.csv(queryAll, "./BeetleMetadataManualIndividuals.csv")
