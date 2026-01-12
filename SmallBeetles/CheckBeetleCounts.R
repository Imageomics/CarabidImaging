#### Setup and Package Loading ####
library(neonUtilities)
library(readxl)
library(dplyr) 
library(tibble)

dataset<-"SmallBeetles"
finalDataset <- "SmallBeetles" 

# Set working directory to CarabidImaging project
setwd("/fs/ess/PAS2136/CarabidImaging/")

#### Load NEON Token and Data Product ####

# Read NEON token from file
neon_token <- read.delim("~/NEON_Token_AE", header = FALSE)[1, 1]
Beetle_dpID <- "DP1.10022.001"

# If already combined data exists, load it, else fetch and combine
if (file.exists("./NEON_ExpertParaCombined.csv")) {
  combined_data <- read.csv("./NEON_ExpertParaCombined.csv")
} else {
  neon_df <- neonUtilities::loadByProduct(
    dpID = Beetle_dpID,
    token = neon_token,
    include.provisional = FALSE,
    check.size = FALSE
  )
  
  neon_para <- neon_df$bet_parataxonomistID
  neon_expert <- neon_df$bet_expertTaxonomistIDProcessed
  
  neon_para_clean <- neon_para %>%
    filter(!(individualID %in% neon_expert$individualID))
  
  common_cols <- intersect(names(neon_para_clean), names(neon_expert))
  neon_para_common <- neon_para_clean[, common_cols]
  neon_expert_common <- neon_expert[, common_cols]
  
  neon_para_common$ID_status <- "Para"
  neon_expert_common$ID_status <- "Expert"
  
  combined_data <- bind_rows(neon_para_common, neon_expert_common)
  combined_data$numbericID <- as.numeric(substr(combined_data$individualID, 
                                                (nchar(combined_data$individualID) - 5), 
                                               nchar(combined_data$individualID)))
  
  write.csv(combined_data, "./NEON_ExpertParaCombined.csv", row.names = FALSE)
}

if (file.exists("./NEON_ExpertParaCombined_Prelim.csv")) {
  combined_data_prelim <- read.csv("./NEON_ExpertParaCombined_Prelim.csv")
} else {
  neon_df <- neonUtilities::loadByProduct(
    dpID = Beetle_dpID,
    token = neon_token,
    include.provisional = TRUE,
    startdate = "2023-01",
    check.size = FALSE
  )
  
  neon_para <- neon_df$bet_parataxonomistID
  neon_expert <- neon_df$bet_expertTaxonomistIDProcessed
  
  neon_para_clean <- neon_para %>%
    filter(!(individualID %in% neon_expert$individualID))
  
  common_cols <- intersect(names(neon_para_clean), names(neon_expert))
  neon_para_common <- neon_para_clean[, common_cols]
  neon_expert_common <- neon_expert[, common_cols]
  
  neon_para_common$ID_status <- "Para"
  neon_expert_common$ID_status <- "Expert"
  
  combined_data_prelim <- bind_rows(neon_para_common, neon_expert_common)
  combined_data_prelim$numbericID <- as.numeric(substr(combined_data_prelim$individualID, 
                                                       (nchar(combined_data_prelim$individualID) - 5), 
                                                       nchar(combined_data_prelim$individualID)))
  
  write.csv(combined_data_prelim, "./NEON_ExpertParaCombined_Prelim.csv", row.names = FALSE)
}

combined_data_prelim<-subset(combined_data_prelim, release=="PROVISIONAL")

dim(combined_data)
combined_data<-rbind(combined_data, combined_data_prelim)
dim(combined_data)

# Add year to combined_data
combined_data$yearCollected <- as.numeric(substr(combined_data$collectDate, 1, 4))

# Extract genus and species only from scientific name
combined_data$scientificName_Species<-gsub(r"{\s*\([^\)]+\)}","",as.character(combined_data$scientificName))
combined_data$scientificName_Species<-gsub(" {2,}", " ", combined_data$scientificName_Species)
combined_data$scientificName_Species<-sub("^(\\S*\\s+\\S+).*", "\\1", combined_data$scientificName_Species)

combined_data$scientificName_Species <-
  gsub("/.*$", "", combined_data$scientificName_Species)

#### Read External Specimen Availability Metadata ####
#Read from Chandra
occurrences<-read.csv("./occurrences.csv")
determinations<-read.csv("./determinations.csv")
shipments<-read.csv("./shipments.csv")

print("occurrences Summary:")
dim(occurrences)
head(occurrences)
print("occurrences availability:")
table(occurrences$availability, useNA = "ifany")

# Filter NEON API data to only include available specimens
combined_data_available<-combined_data %>%
  filter((individualID %in% subset(occurrences, availability==1)$identifierValue))
dim(occurrences)
dim(combined_data_available)
dim(combined_data_available)[1]/dim(combined_data)[1]

#### Load and Format Manual Metadata ####

# Load image tray metadata
firstpass_df <- as.data.frame(read_excel("./BeetleMetadata.xlsx", sheet = 5))
dim(firstpass_df)
 
# Create numeric IDs for filtering
firstpass_df$numbericID_1 <- as.numeric(firstpass_df$IndividualID_1)
firstpass_df$numbericID_2 <- as.numeric(firstpass_df$IndividualID_2)
firstpass_df$numbericID_n1 <- as.numeric(firstpass_df$IndividualID_n1)
firstpass_df$numbericID_n <- as.numeric(firstpass_df$IndividualID_n)

#Save raw IDs
firstpass_df$numbericID_1_save <- firstpass_df$IndividualID_1
firstpass_df$numbericID_2_save <- firstpass_df$IndividualID_2
firstpass_df$numbericID_n1_save <- firstpass_df$IndividualID_n1
firstpass_df$numbericID_n_save <- firstpass_df$IndividualID_n


# # Reformat individual IDs with NEON format
# firstpass_df$IndividualID_1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_1)
# 
# firstpass_df$IndividualID_2 <- ifelse(firstpass_df$IndividualID_2=="NA", NA, 
#                                       paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_2))
# 
# firstpass_df$IndividualID_n1 <- ifelse(firstpass_df$IndividualID_n1=="NA", NA, 
#                                        paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n1))
# 
# firstpass_df$IndividualID_n <- ifelse(firstpass_df$IndividualID_n=="NA", NA, 
#                                       paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n))

# Reformat individual IDs with NEON format for file naming
firstpass_df$IndividualID_1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_1)
firstpass_df$IndividualID_2 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_2)
firstpass_df$IndividualID_n1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n1)
firstpass_df$IndividualID_n <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n)

# Clean and Extract Taxonomic Names 
firstpass_df$scientificName_Species<-sub("^(\\S*\\s+\\S+).*", "\\1", firstpass_df$scientificName)

head(firstpass_df)

# Add year to combined_data
combined_data$yearCollected <- as.numeric(substr(combined_data$collectDate, 1, 4))

#### Create Image IDs ####
#Update imageID to refelct file strucure of small beetles
firstpass_df$imageID<-paste0("./",substr(firstpass_df$imageID, 1, 3),"CANON/",
                             "IMG_",substr(firstpass_df$imageID, 5, nchar(firstpass_df$imageID)))

#Generate standardized new image names
# Concatenate metadata fields to generate unique image IDs
# Loop over character columns and replace "NA" strings with proper NA
for (col in names(firstpass_df)) {
  if (is.character(firstpass_df[[col]])) {
    firstpass_df[[col]][firstpass_df[[col]] == "NA"] <- NA
  }
}

# Updated helper function
format_tray <- function(scientificName, year, tray, id1, idn) {
  name_clean <- gsub(" ", "_", scientificName)
  year_part <- if (!is.na(year)) year else "NA"
  
  # Check if idn is missing or ends in ".NA"
  if (is.na(idn) || grepl("\\.NA$", idn)) {
    idn_part <- ""
  } else {
    idn_part <- paste0("-", idn)
  }
  
  paste0(name_clean, "-Y", year_part, "-", tray, "tray-", id1, idn_part)
}

# Rebuild newImageID with updated function
firstpass_df$newImageID <- mapply(function(sci1, y1, tray, id1_1, id1_n) {
  tray1 <- format_tray(sci1, y1, tray, id1_1, id1_n)
  paste0(tray1, ".JPG")
},
sci1 = firstpass_df$scientificName,
y1 = firstpass_df$yearCollected,
tray = firstpass_df$trayType,
id1_1 = firstpass_df$IndividualID_1,
id1_n = firstpass_df$IndividualID_n,
USE.NAMES = FALSE)

head(firstpass_df$newImageID, 10)

#### Check for metadata that has been entered incorrectly using redundant information ####
firstpass_df$processingNotes<-""

#Check Domain match up by pulling down records with species name, year, and numeric ID
#If all 4 ID queries yield a non-NA value and all of those values match, the domain is updated to those matching values
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  # Filter matching individuals
  ImageQueryID1 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            yearCollected == row$yearCollected &
                            numbericID== row$numbericID_1)
  ImageQueryID2 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            yearCollected == row$yearCollected &
                            numbericID== row$numbericID_2)
  ImageQueryIDN1 <- subset(combined_data_available, 
                           scientificName_Species == row$scientificName_Species &
                             yearCollected == row$yearCollected &
                             numbericID== row$numbericID_n1)
  ImageQueryIDN <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            yearCollected == row$yearCollected &
                            numbericID== row$numbericID_n)
  
  # Collect all domainID values if present
  domains <- c(
    if (nrow(ImageQueryID1) > 0) ImageQueryID1$domainID else NA,
    if (nrow(ImageQueryID2) > 0) ImageQueryID2$domainID else NA,
    if (nrow(ImageQueryIDN1) > 0) ImageQueryIDN1$domainID else NA,
    if (nrow(ImageQueryIDN) > 0) ImageQueryIDN$domainID else NA
  )
  
  print(paste0("Metadata recorded Year: ", row$domainID))
  print(paste0("IndividualID_1 Year: ", domains[1]))
  print(paste0("IndividualID_2 Year: ", domains[2]))
  print(paste0("IndividualID_n1 Year: ", domains[3]))
  print(paste0("IndividualID_n Year: ", domains[4]))
  
  # Check all are not NA and all the same
  if (!any(is.na(domains)) && length(unique(domains)) == 1) {
    new_domain <- unique(domains)
    if (new_domain == row$domainID) {
      print("Match")
    } else {
      firstpass_df$processingNotes[i] <- paste0(
        "domainID updated from ", row$domainID,
        " to ", new_domain,
        " based on IndividualID queries"
      )
      firstpass_df$domainID[i] <- new_domain 
    }
  }
  else {
    print("error")
  }
}

print("Processing Notes:")
table(firstpass_df$processingNotes)

#If the domain was wrong, that means that the derrived IndividualID would have been wrong, so we derive them here
# Reformat individual IDs with NEON format
firstpass_df$IndividualID_1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$numbericID_1_save)
firstpass_df$IndividualID_2 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$numbericID_2_save)
firstpass_df$IndividualID_n1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$numbericID_n1_save)
firstpass_df$IndividualID_n <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$numbericID_n_save)

#If the Year is recorded wrong, then you will get 0 records for the filter. We deal with that in this query
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  # Filter matching individuals
  ImageQueryID1 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_1)
  ImageQueryID2 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_2)
  ImageQueryIDN1 <- subset(combined_data_available, 
                           scientificName_Species == row$scientificName_Species &
                             individualID== row$IndividualID_n1)
  ImageQueryIDN <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_n)
  
  # Collect all yearCollected values if present
  years <- c(
    if (nrow(ImageQueryID1) > 0) ImageQueryID1$yearCollected else NA,
    if (nrow(ImageQueryID2) > 0) ImageQueryID2$yearCollected else NA,
    if (nrow(ImageQueryIDN1) > 0) ImageQueryIDN1$yearCollected else NA,
    if (nrow(ImageQueryIDN) > 0) ImageQueryIDN$yearCollected else NA
  )
  
  print(paste0("Metadata recorded Year: ", row$yearCollected))
  print(paste0("IndividualID_1 Year: ", years[1]))
  print(paste0("IndividualID_2 Year: ", years[2]))
  print(paste0("IndividualID_n1 Year: ", years[3]))
  print(paste0("IndividualID_n Year: ", years[4]))
  
  # Check all are not NA and all the same
  if (!any(is.na(years)) && length(unique(years)) == 1) {
    new_year <- unique(years)
    if (new_year == row$yearCollected) {
      print("Match")
    } else {
      firstpass_df$processingNotes[i] <- paste0(
        "yearCollected updated from ", row$yearCollected,
        " to ", new_year,
        " based on IndividualID queries"
      )
      firstpass_df$yearCollected[i] <- new_year 
    }
  }
  else {
    print("error")
  }
}
print("Processing Notes:")
table(firstpass_df$processingNotes)

#Check Expert/Para match up in the same way as Year
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  # Filter matching individuals
  ImageQueryID1 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_1)
  ImageQueryID2 <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_2)
  ImageQueryIDN1 <- subset(combined_data_available, 
                           scientificName_Species == row$scientificName_Species &
                             individualID== row$IndividualID_n1)
  ImageQueryIDN <- subset(combined_data_available, 
                          scientificName_Species == row$scientificName_Species &
                            individualID== row$IndividualID_n)
  
  # Collect all ID_status values if present
  ID_status <- c(
    if (nrow(ImageQueryID1) > 0) ImageQueryID1$ID_status else NA,
    if (nrow(ImageQueryID2) > 0) ImageQueryID2$ID_status else NA,
    if (nrow(ImageQueryIDN1) > 0) ImageQueryIDN1$ID_status else NA,
    if (nrow(ImageQueryIDN) > 0) ImageQueryIDN$ID_status else NA
  )
  
  print(paste0("Metadata recorded: ", row$ExpertOrPara))
  print(paste0("IndividualID_1: ", ID_status[1]))
  print(paste0("IndividualID_2: ", ID_status[2]))
  print(paste0("IndividualID_n1: ", ID_status[3]))
  print(paste0("IndividualID_n: ", ID_status[4]))
  
  # Check all are not NA and all the same
  if (!any(is.na(ID_status)) && length(unique(ID_status)) == 1) {
    new_ID <- unique(ID_status)
    if (new_ID == row$ExpertOrPara) {
      print("correct")
    } else {
      firstpass_df$processingNotes[i] <- paste0(
        "ExpertOrPara updated from ", row$ExpertOrPara,
        " to ", new_ID,
        " based on IndividualID queries"
      )
      firstpass_df$ExpertOrPara[i] <- new_ID 
    }
  }
  else {
    print("error")
  }
}
print("Processing Notes:")
table(firstpass_df$processingNotes)

#Check Species ID the same way as well
#Check Expert/Para match up in the same way as Year
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  # Filter matching individuals
  ImageQueryID1 <- subset(combined_data_available,
                          individualID== row$IndividualID_1)
  ImageQueryID2 <- subset(combined_data_available,
                          individualID== row$IndividualID_2)
  ImageQueryIDN1 <- subset(combined_data_available, 
                           individualID== row$IndividualID_n1)
  ImageQueryIDN <- subset(combined_data_available,
                          individualID== row$IndividualID_n)
  
  # Collect all ID_status values if present
  ID_status <- c(
    if (nrow(ImageQueryID1) > 0) ImageQueryID1$scientificName_Species else NA,
    if (nrow(ImageQueryID2) > 0) ImageQueryID2$scientificName_Species else NA,
    if (nrow(ImageQueryIDN1) > 0) ImageQueryIDN1$scientificName_Species else NA,
    if (nrow(ImageQueryIDN) > 0) ImageQueryIDN$scientificName_Species else NA
  )
  
  print(paste0("Metadata recorded: ", row$scientificName_Species))
  print(paste0("IndividualID_1: ", ID_status[1]))
  print(paste0("IndividualID_2: ", ID_status[2]))
  print(paste0("IndividualID_n1: ", ID_status[3]))
  print(paste0("IndividualID_n: ", ID_status[4]))
  
  # Check all are not NA and all the same
  if (!any(is.na(ID_status)) && length(unique(ID_status)) == 1) {
    new_ID <- unique(ID_status)
    if (new_ID == row$scientificName_Species) {
      print("correct")
    } else if (new_ID == "Carabidae sp.") {
      print("Skip update: new_ID is 'Carabidae sp.'")
    } else {
      firstpass_df$processingNotes[i] <- paste0(
        "scientificName_Species updated from ", row$scientificName_Species,
        " to ", new_ID,
        " based on IndividualID queries"
      )
      firstpass_df$scientificName_Species[i] <- new_ID 
    }
  }
  else {
    print("error")
  }
}
print("Processing Notes:")
table(firstpass_df$processingNotes)

#### Image Matching by ID Range, Domain, Year, Species, and Para vs Expert Taxonomis ID ####

firstpass_df$NumberOfBeetles<-as.numeric(firstpass_df$NumberOfBeetles)

# Placeholder for all matched cases
matched_df <- data.frame()

# Handle images with 1–4 beetles
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  
  if (row$NumberOfBeetles %in% 1:4) {
    # Get the IDs for however many beetles there are
    beetle_ids <- unlist(row[paste0("IndividualID_", c(1,2,"n1","n"))])
    
    # Filter matching individuals
    inImageQuery <- subset(combined_data_available, individualID %in% beetle_ids)
    
    # Filter by ID Status (ExpertOrPara)
    if (nrow(inImageQuery) == 0) {
      print(paste0(row$newImageID," No record by ID"))
      firstpass_df[i, ]$Notes <- "No record by ID"
      next
    }
    
    # If all queried individuals match the species
    if (all(inImageQuery$scientificName_Species == row$scientificName_Species)) {
      image_id <- row$newImageID
      inImageQuery$imageID <- image_id
      inImageQuery$Order <- 1:nrow(inImageQuery)  # Assign order values sequentially
      inImageQuery$NumberOfBeetlesInTray <- row$NumberOfBeetles
      inImageQuery$notes <- row$Notes
      inImageQuery$processingNotes <- row$processingNotes
      
      matched_df <- rbind(matched_df, inImageQuery)
    } else {
      firstpass_df[i, ]$Notes <- paste0("Species Mismatch: ",
                                        row$scientificName_Species, " entered ",
                                        paste(unique(inImageQuery$scientificName_Species), collapse=" & "),
                                        " queried")
      print(paste0("Species Mismatch: ",
                   row$scientificName_Species, " entered ",
                   paste(unique(inImageQuery$scientificName_Species), collapse=" & "),
                   " queried"))
    }
    
  } else {
    next
  }
}
dim(firstpass_df)
df_remainingmissmatch<-firstpass_df %>%
  filter(!(newImageID %in% matched_df$imageID))
dim(df_remainingmissmatch)

# Loop over all rows in firstpass_df
for (i in 1:nrow(df_remainingmissmatch)) {
  row <- df_remainingmissmatch[i, ]
  
  # Filter matching individuals
  inImageQuery <- subset(combined_data_available, 
                         domainID == row$domainID &
                           scientificName_Species == row$scientificName_Species &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_1 & 
                           numbericID <= row$numbericID_n)
  #Filter by ID Status (ExpertOrPara)
  inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
  
  num_found <- nrow(inImageQuery)
  df_remainingmissmatch$NumberOfBeetlesInQuery[i] <- num_found
  
  # If the query yields the correct number of individuals, we add this data into a growing dataset
  if (num_found == row$NumberOfBeetles) {
    image_id <- row$newImageID
    inImageQuery$imageID <- image_id
    inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
      arrange(individualID)
    inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially
    inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
    inImageQuery$notes<-row$Notes
    inImageQuery$processingNotes<-row$processingNotes
    
    matched_df <- rbind(matched_df, inImageQuery)
  } 
}


df_remainingmissmatch<-df_remainingmissmatch %>%
  filter(!(newImageID %in% matched_df$imageID))
dim(firstpass_df)
dim(df_remainingmissmatch)[1]
dim(table(matched_df$imageID))[1]
dim(df_remainingmissmatch)[1]+dim(table(matched_df$imageID))[1]
dim(table(matched_df$imageID))/dim(firstpass_df)[1]

plot(df_remainingmissmatch$NumberOfBeetles, df_remainingmissmatch$NumberOfBeetlesInQuery)
abline(a = 0, b = 1, col = "red") 

#Boxes are often grouped by scientificNameAuthorship For all those remaining, we will break it out by idntifier or source material.
start<-dim(table(matched_df$imageID))[1]
for (i in 1:nrow(df_remainingmissmatch)) {
  row <- df_remainingmissmatch[i, ]
  
  # Filter matching individuals
  inImageQuery <- subset(combined_data_available, 
                         domainID == row$domainID &
                           scientificName_Species == row$scientificName_Species &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_1 & 
                           numbericID <= row$numbericID_n)
  #Filter by ID Status
  inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

  fineScientificNameAuthorship <- subset(combined_data_available, 
                                         domainID == row$domainID &
                                           scientificName_Species == row$scientificName_Species &
                                           yearCollected == row$yearCollected &
                                           numbericID == row$numbericID_1)$scientificNameAuthorship
  print(table(inImageQuery$scientificNameAuthorship))
  print(paste0("ID1, indicates authorship: ",fineScientificNameAuthorship))
  inImageQuery<-subset(inImageQuery, scientificNameAuthorship==fineScientificNameAuthorship)
  
  num_found <- nrow(inImageQuery)
  df_remainingmissmatch$NumberOfBeetlesInQuery[i] <- num_found
  
  if (num_found == row$NumberOfBeetles) {
    image_id <- row$newImageID
    inImageQuery$imageID <- image_id
    inImageQuery$notes <- row$Notes
    inImageQuery<-inImageQuery %>%
      arrange(individualID)
    inImageQuery$Order<-c(1:nrow(inImageQuery))
    inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
    
    matched_df <- rbind(matched_df, inImageQuery)
  } 
}
start
dim(table(matched_df$imageID))[1]

df_remainingmissmatch<-df_remainingmissmatch %>%
  filter(!(newImageID %in% matched_df$imageID))

#After scientificNameAuthorship refernce material "identificationReferences" is the next big grouping.
start<-dim(table(matched_df$imageID))[1]
for (i in 1:nrow(df_remainingmissmatch)) {
  row <- df_remainingmissmatch[i, ]
  
  # Filter matching individuals
  inImageQuery <- subset(combined_data_available, 
                         domainID == row$domainID &
                           scientificName_Species == row$scientificName_Species &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_1 & 
                           numbericID <= row$numbericID_n)
  #Filter by ID Status
  inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
  fineScientificNameAuthorship <- subset(combined_data_available, 
                                         domainID == row$domainID &
                                           scientificName_Species == row$scientificName_Species &
                                           yearCollected == row$yearCollected &
                                           numbericID == row$numbericID_1)$identificationReferences
  print(table(inImageQuery$identificationReferences))
  print(paste0("ID1, indicates authorship: ",fineScientificNameAuthorship))
  inImageQuery<-subset(inImageQuery, identificationReferences==fineScientificNameAuthorship)
  
  num_found <- nrow(inImageQuery)
  df_remainingmissmatch$NumberOfBeetlesInQuery[i] <- num_found

  if (num_found == row$NumberOfBeetles) {
    image_id <- row$newImageID
    inImageQuery$imageID <- image_id
    inImageQuery$notes <- row$Notes
    inImageQuery<-inImageQuery %>%
      arrange(individualID)
    inImageQuery$Order<-c(1:nrow(inImageQuery))
    inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
    
    matched_df <- rbind(matched_df, inImageQuery)
  } 
}
start
dim(table(matched_df$imageID))[1]

#manual edits from notes:
table(df_remainingmissmatch$Notes)

#Exclude BET.D18.001351
row<-subset(df_remainingmissmatch, Notes=="Exclude BET.D18.001351")
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == row$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
dim(inImageQuery)
inImageQuery<-subset(inImageQuery, individualID!="NEON.BET.D18.001351")
dim(inImageQuery)
row$NumberOfBeetles
image_id <- row$newImageID
inImageQuery$imageID <- image_id
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
inImageQuery$notes <- row$Notes
inImageQuery$processingNotes <- "Manually removed NEON.BET.D18.001351 from query"
inImageQuery<-inImageQuery %>%
  arrange(individualID)


matched_df <- rbind(matched_df, inImageQuery)

#INDIVIDUAL 006078 MISSING
row<-subset(df_remainingmissmatch, Notes=="INDIVIDUAL 006078 MISSING")
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == row$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
dim(inImageQuery)
inImageQuery<-subset(inImageQuery, numbericID!=6078)
dim(inImageQuery)
row$NumberOfBeetles


image_id <- row$newImageID
inImageQuery$imageID <- image_id
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
inImageQuery$notes <- row$Notes
inImageQuery$processingNotes <- "Manually removed 006078 from query"
inImageQuery<-inImageQuery %>%
  arrange(individualID)

matched_df <- rbind(matched_df, inImageQuery)

df_remainingmissmatch<-df_remainingmissmatch %>%
  filter(!(newImageID %in% matched_df$imageID))

dim(df_remainingmissmatch)
dim(matched_df)

print("N of total photos:")
dim(firstpass_df)[1]
print("Percent photos in matched:")
dim(table(matched_df$imageID))/dim(firstpass_df)[1]

colnames(matched_df)
colnames(firstpass_df)
firstpass_df$numbericID_1_save<-NULL
firstpass_df$numbericID_2_save<-NULL
firstpass_df$numbericID_n1_save<-NULL
firstpass_df$numbericID_n_save<-NULL

# Save matched dataset to file
write.csv(matched_df, paste0("./BeetleMetadata",dataset,"Individuals.csv"), row.names = FALSE)

write.csv(firstpass_df, paste0("./BeetleMetadata",dataset,".csv"), row.names = FALSE)


#Write out datasets for images that dont link to be manually checked. 
for (i in 1:nrow(df_remainingmissmatch)) {
  row <- df_remainingmissmatch[i, ]
  # Filter matching individuals
  inImageQuery <- subset(combined_data_available, 
                         domainID == row$domainID &
                           scientificName_Species == row$scientificName_Species &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_1 & 
                           numbericID <= row$numbericID_n)
  #Filter by ID Status
  inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
  
  num_found <- nrow(inImageQuery)
  df_remainingmissmatch$NumberOfBeetlesInQuery[i] <- num_found
  
  if (num_found > row$NumberOfBeetles) {
    inImageQuery$NumberOfBeetlesInTray <- row$NumberOfBeetles
    
    outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/CHECK_",
                      gsub(" ", "_", row$scientificName), "-",
                      row$trayType, "tray-",
                      "Y", row$yearCollected, "-",
                      row$IndividualID_1, "-", row$IndividualID_n, ".csv")
    
    inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
    inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
    inImageQuery$notes<-row$Notes
    inImageQuery$processingNotes<-row$processingNotes
    inImageQuery$newImageID<-row$newImageID
    inImageQuery$imagePath<-paste0("/Images/FinalImages/",finalDataset)
    
    
    write.csv(inImageQuery %>%
                arrange(individualID), outfile, row.names = FALSE)
  } else {
    if (nrow(inImageQuery) == 0) {
      # If there are none in query, then take the ID2 to IDN1 range and output for manual checks
      inImageQuery <- subset(combined_data, 
                             #domainID == row$domainID &
                               scientificName_Species == row$scientificName_Species &
                              #yearCollected == row$yearCollected &
                               numbericID >= row$numbericID_1 & 
                               numbericID <= row$numbericID_n)
      #Filter by ID Status
      inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
      outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/CHECK_",
                        gsub(" ", "_", row$scientificName), "-",
                        row$trayType, "tray-",
                        "Y", row$yearCollected, "-",
                        row$IndividualID_1, "-", row$IndividualID_n, ".csv")
      
      inImageQuery[nrow(inImageQuery) + 1, ] <- NA
      inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
      inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
      inImageQuery$notes<-row$Notes
      inImageQuery$processingNotes<-row$processingNotes
      inImageQuery$newImageID<-row$newImageID
      inImageQuery$imagePath<-paste0("/Images/FinalImages/",finalDataset)
      
      if (nrow(inImageQuery) == 1) {
        outfile <- paste0("./NEONIndividualLinkageChecks/QueryZero/CHECK_",
                          gsub(" ", "_", row$scientificName), "-",
                          row$trayType, "tray-",
                          "Y", row$yearCollected, "-",
                          row$IndividualID_1, "-", row$IndividualID_n, ".csv")
      }
      write.csv(inImageQuery %>%
                  arrange(individualID), outfile, row.names = FALSE)
    } else {
      inImageQuery$NumberOfBeetlesInTray <- row$NumberOfBeetles
      
      outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                        gsub(" ", "_", row$scientificName), "-",
                        row$trayType, "tray-",
                        "Y", row$yearCollected, "-",
                        row$IndividualID_1, "-", row$IndividualID_n, ".csv")
      inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
      inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
      inImageQuery$notes<-row$Notes
      inImageQuery$processingNotes<-row$processingNotes
      inImageQuery$newImageID<-row$newImageID
      inImageQuery$imagePath<-paste0("/Images/FinalImages/",finalDataset)
      
      write.csv(inImageQuery %>%
                  arrange(individualID), outfile, row.names = FALSE)
    }
  }
}

#This is an iterative process, and files that have been checked are in
# /NEONIndividualLinkageChecks/QueryOver/Checked. Here we remove the csv files that 
#Have already been manually quality controlled so we know what is left.


#First we do this for Querys with too many entries
# Define directories
csv_dir <- "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver"
xlsx_dir <- file.path(csv_dir, "Checked")

# List .csv and .xlsx files
csv_files <- list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE)
xlsx_files <- list.files(xlsx_dir, pattern = "\\.xlsx$", full.names = FALSE)

# Get base names (without extensions) of the xlsx files
xlsx_basenames <- tools::file_path_sans_ext(xlsx_files)

# Filter csv files to identify which to delete
csv_to_remove <- csv_files[
  tools::file_path_sans_ext(basename(csv_files)) %in% xlsx_basenames
]

# Confirm what will be deleted
cat("The following CSV files will be removed:\n")
print(csv_to_remove)

# OPTIONAL: Delete the files
# Be careful with this step; uncomment to activate deletion
file.remove(csv_to_remove)
length(list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE))

#Then we do this for Querys with too few entries
# Define directories
csv_dir <- "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder"
xlsx_dir <- file.path(csv_dir, "Checked")

# List .csv and .xlsx files
csv_files <- list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE)
xlsx_files <- list.files(xlsx_dir, pattern = "\\.xlsx$", full.names = FALSE)

# Get base names (without extensions) of the xlsx files
xlsx_basenames <- tools::file_path_sans_ext(xlsx_files)

# Filter csv files to identify which to delete
csv_to_remove <- csv_files[
  tools::file_path_sans_ext(basename(csv_files)) %in% xlsx_basenames
]

# Confirm what will be deleted
cat("The following CSV files will be removed:\n")
print(csv_to_remove)

# OPTIONAL: Delete the files
# Be careful with this step; uncomment to activate deletion
file.remove(csv_to_remove)
length(list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE))

# #Remove Query Zeros once they have been done
csv_dir <- "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryZero"
csv_dir1 <- "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder"
xlsx_dir1 <- file.path(csv_dir, "Checked")
csv_dir2 <- "/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver"
xlsx_dir2 <- file.path(csv_dir, "Checked")

# List .csv files
csv_files <- list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE)

# List .xlsx files
xlsx_files1 <- list.files(xlsx_dir1, pattern = "\\.xlsx$", full.names = FALSE)
xlsx_files2 <- list.files(xlsx_dir2, pattern = "\\.xlsx$", full.names = FALSE)

xlsx_files<-c(xlsx_files1, xlsx_files2)
# Get base names (without extensions) of the xlsx files
xlsx_basenames <- tools::file_path_sans_ext(xlsx_files)

# Filter csv files to identify which to delete
csv_to_remove <- csv_files[
  tools::file_path_sans_ext(basename(csv_files)) %in% xlsx_basenames
]

# Confirm what will be deleted
cat("The following CSV files will be removed:\n")
print(csv_to_remove)

# OPTIONAL: Delete the files
# Be careful with this step; uncomment to activate deletion
file.remove(csv_to_remove)
length(list.files(csv_dir, pattern = "\\.csv$", full.names = TRUE))

