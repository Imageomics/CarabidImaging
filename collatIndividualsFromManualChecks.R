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

combined_data$scientificName_Species <-
  gsub("/.*$", "", combined_data$scientificName_Species)

#### Look at all Mannual Checks together incase of duplication ####
QueryOverCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver/Checked/"
QueryOverCheckedFiles<-list.files(QueryOverCheckedDir, pattern = "*.xlsx")

QueryUnderCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/"
QueryUnderCheckedFiles<-list.files(QueryUnderCheckedDir, pattern = "*.xlsx")

QueryZeroCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryZero/Checked/"
QueryZeroCheckedFiles<-list.files(QueryZeroCheckedDir, pattern = "*.xlsx")

QueryZeroFilledCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryZeroFilled/Checked/"
QueryZeroFilledCheckedFiles<-list.files(QueryZeroFilledCheckedDir, pattern = "*.xlsx")

QueryMannualAll<-as.data.frame(cbind(c(QueryOverCheckedFiles, QueryUnderCheckedFiles, 
                                       QueryZeroCheckedFiles, QueryZeroFilledCheckedFiles),
                                     c(rep(QueryOverCheckedDir, length(QueryOverCheckedFiles)),
                                       rep(QueryUnderCheckedDir, length(QueryUnderCheckedFiles)),
                                       rep(QueryZeroCheckedDir, length(QueryZeroCheckedFiles)),
                                       rep(QueryZeroFilledCheckedDir, length(QueryZeroFilledCheckedFiles)))))
colnames(QueryMannualAll)<-c("file","dir")
table(duplicated(QueryMannualAll$file))
QueryMannualAll$double<-duplicated(QueryMannualAll$file)
table(QueryMannualAll$double)
list<-subset(QueryMannualAll, double==TRUE)$file

duplicatedFiles<-QueryMannualAll[QueryMannualAll$file %in% list, ]
#View(duplicatedFiles)

QueryMannual_Unique<- QueryMannualAll %>% 
  mutate(dir = factor(dir, levels = c("/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver/Checked/",
                                          "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/",
                                          "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryZeroFilled/Checked/",
                                          "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryZero/Checked/"))) %>%
  group_by(dir) %>%
  group_by(file) %>%
  slice_head(n=1) %>%
  ungroup()
table(duplicated(QueryMannual_Unique$file))

QueryMannual_Unique <- QueryMannual_Unique[
  !grepl("\\(1\\)", QueryMannual_Unique$file),
]

table(QueryMannualAll$dir)
table(QueryMannual_Unique$dir)

# 2.1 Read in the data ####
#Read in first file to create the seed for the dataset
Checked_df <- as.data.frame(read_excel(paste0(QueryMannual_Unique$dir[1],QueryMannual_Unique$file[1]),
                                                 sheet = 1))
Checked_df$imageID<-paste0(substr(QueryMannual_Unique$file[1], 
                                            7, (nchar(QueryMannual_Unique$file[1])-4)),
                                     "png")

#Define the desired output column names
cols<-c("uid","namedLocation","domainID","siteID","plotID","setDate","collectDate","identifiedDate","individualID","Present",
        "Order","sampleCondition","taxonID","scientificName","taxonRank","identificationQualifier","scientificNameAuthorship",
        "morphospeciesID","identificationReferences","nativeStatusCode","identifiedBy","remarks","identificationHistoryID",
        "publicationDate","release","ID_status","numbericID","yearCollected","scientificName_Species","NumberOfBeetlesInTray",
        "notes","processingNotes","imagePath","imageID","trayID")

#### 2.2 Standardize Column Names and Fill Missing Columns ####
Checked_df$identifiedDate<-as.character(Checked_df$identifiedDate)
Checked_df$setDate<-as.character(Checked_df$setDate)
Checked_df$collectDate<-as.character(Checked_df$collectDate)


# Fix inconsistent "Present" column name
present_col <- names(Checked_df)[tolower(names(Checked_df)) == "present" | 
                                             tolower(names(Checked_df)) == "p"]

if (length(present_col) == 1 && present_col != "Present") {
  names(Checked_df)[names(Checked_df) == present_col] <- "Present"
}

# Add any missing columns from `cols`
missing_cols <- setdiff(cols, names(Checked_df))
if (length(missing_cols) > 0) {
  for (col in missing_cols) {
    Checked_df[[col]] <- NA
  }
}

Checked_df$processingNotes<-paste0(sub(".*/([^/]+)/Checked/?$", "\\1", QueryMannual_Unique$dir[1]), 
                                   "- Manually Checked; ",
                                   Checked_df$processingNotes)


# Reorder columns to match `cols` order
Checked_df <- Checked_df[, cols]
Checked_df<-subset(Checked_df, Present == 1)


#### 2.3 Loop over the rest of the files and rbind them together####
for (i in 2:nrow(QueryMannual_Unique)) {
  # Read in the file
  tmp <- as.data.frame(read_excel(paste0(QueryMannual_Unique$dir[i],QueryMannual_Unique$file[i]),
                                  sheet = 1))
  
  # Add imageID column based on filename
  tmp$imageID <- paste0(substr(QueryMannual_Unique$file[i], 
                               7, (nchar(QueryMannual_Unique$file[i])-4)),
                        "png")
  
  # Sort by individualID
  tmp <- tmp %>% arrange(individualID)
  
  # Fix inconsistent "Present" column name
  present_col <- names(tmp)[tolower(names(tmp)) == "present" | 
                              tolower(names(tmp)) == "p"]
  if (length(present_col) == 1 && present_col != "Present") {
    names(tmp)[names(tmp) == present_col] <- "Present"
  }
  tmp<-subset(tmp, Present==1)
  if (nrow(tmp)==0) {
    next
  }
  
  # Add "Order" column if missing
  if (!"Order" %in% names(tmp)) {
    tmp <- add_column(tmp, Order = "", .before = "sampleCondition")
    tmp<-subset(tmp, Present==1)
    tmp$Order <- 1:nrow(tmp)
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
  
  tmp$processingNotes<-paste0(sub(".*/([^/]+)/Checked/?$", "\\1", QueryMannual_Unique$dir[i]), 
                                     "- Manually Checked; ",
                              tmp$processingNotes)
  tmp[] <- lapply(tmp, function(x) {
    type.convert(x, as.is = TRUE)
  })
  tmp$identifiedDate<-as.character(tmp$identifiedDate)
  tmp$setDate<-as.character(tmp$setDate)
  tmp$collectDate<-as.character(tmp$collectDate)
  tmp$notes<-as.character(tmp$notes)
  # Bind to master dataframe
  
  Checked_df <- bind_rows(Checked_df, tmp)
}

# 2.4 Remove all of the instances where there is an individual ID recorded that is not present ####
#table(Checked_df$imageID)
table(Checked_df$Present)
Checked_df<-subset(Checked_df, Present==1)
table(Checked_df$P)
#table(Checked_df$processingNotes)

table(Checked_df$domainID, useNA = "ifany")
table(Checked_df$NumberOfBeetlesInTray, useNA = "ifany")

str(Checked_df)

#### 1.5 Pull out records where individualID exists but other NEON columns are NA ####
# Filter manually added entries (i.e., those with NA in key NEON fields like uid)
Checked_df_manualAdditions <- Checked_df %>% 
  filter(is.na(uid))

# List unique images where manual additions occurred
Images_w_Additions <- unique(Checked_df_manualAdditions$imageID)

# Initialize empty dataframe to hold corrected records
manual_filled_df <- data.frame()

#### 1.6 Fill in metadata for manually transcribed individualIDs with missing metadata ####
# Loop over each imageID to refill data from combined_data
for (img in Images_w_Additions) {
  # Subset manually added records for this image
  tmp_manual <- Checked_df %>% 
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
      processingNotes = tmp_manual$processingNotes,
      notes = tmp_manual$notes
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

dim(Checked_df)
dim(manual_filled_df)

Checked_df<-Checked_df%>%
  filter(!(imageID %in% manual_filled_df$imageID))

dim(Checked_df)
(dim(Checked_df)+dim(manual_filled_df))

Checked_df<-rbind(Checked_df,manual_filled_df)
dim(Checked_df)

#### Correct CTray Image Names
#C Trays do not populate correctly with the naming convention
#We utilize the allImages metadata to correct for this based on the Tray ID

Checked_df_CTrays<-subset(Checked_df, !is.na(trayID))
allImages<-read.csv("./allImages.csv")

Checked_df_CTrays$imageID
Checked_df_CTrays$imageID <-
  allImages$imageID[match(Checked_df_CTrays$trayID, allImages$trayID)]
Checked_df_CTrays$imageID

Checked_df_notC<-subset(Checked_df, is.na(trayID))
dim(Checked_df)
dim(Checked_df_CTrays)
dim(Checked_df_notC)
(dim(Checked_df_CTrays)+
  dim(Checked_df_notC))

Checked_df<-rbind(Checked_df_CTrays,Checked_df_notC)
dim(Checked_df)

#### 3. Merged the Harmonized dataset and export ####
Checked_df$identifiedDate<-as.character(Checked_df$identifiedDate)
write.csv(Checked_df, "./BeetleMetadataManualIndividuals.csv")
