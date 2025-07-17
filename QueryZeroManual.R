#### Setup and Package Loading ####
library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)

finalDataset <- "ABTrays"

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

# Add year to combined_data
combined_data$yearCollected <- as.numeric(substr(combined_data$collectDate, 1, 4))

# Extract genus and species only from scientific name
combined_data$scientificName_Species<-gsub(r"{\s*\([^\)]+\)}","",as.character(combined_data$scientificName))
combined_data$scientificName_Species<-gsub(" {2,}", " ", combined_data$scientificName_Species)
combined_data$scientificName_Species<-sub("^(\\S*\\s+\\S+).*", "\\1", combined_data$scientificName_Species)

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






















files<-list.files("./NEONIndividualLinkageChecks/QueryUnder/", pattern = "*.csv")

df<-read.csv(paste0("./NEONIndividualLinkageChecks/QueryUnder/",files[5]))
head(df)

allZero<-read.csv("./QueryZero.csv")
allZero$diff<-allZero$numbericID_n-allZero$numbericID_1

allZero_order<-subset(allZero,diff<=0)

# Loop over all rows in firstpass_df
for (i in 1:nrow(allZero_order)) {
  row <- allZero_order[i, ]
  
  # Filter matching individuals
  inImageQuery <- subset(combined_data_available, 
                         domainID == row$domainID &
                           scientificName_Species == row$scientificName_Species &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_n & 
                           numbericID <= row$numbericID_1)
  #Filter by ID Status (ExpertOrPara)
  inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
  
  num_found <- nrow(inImageQuery)
  
  outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                    gsub(" ", "_", row$scientificName), "-",
                    row$trayType, "tray-",
                    "Y", row$yearCollected, "-",
                    row$IndividualID_1, "-", row$IndividualID_n, ".csv")
  inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
  inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
  inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
  inImageQuery$notes<-row$Notes
  inImageQuery$processingNotes<-row$processingNotes
  inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))
  
  write.csv(inImageQuery %>%
              arrange(individualID), outfile, row.names = FALSE)
  print(outfile)
  print(dim(inImageQuery))
}

allZero<-subset(allZero,diff>0)

##################################################################################################################
row <- allZero[2, ]
row$newImageID
# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
#                         scientificName_Species == row$scientificName_Species)# &
                       yearCollected == row$yearCollected &
                       numbericID >= row$numbericID_1 & 
                       numbericID <= row$numbericID_n & 
                       morphospeciesID== "D06.2015.MorphG")
#Filter by ID Status (ExpertOrPara)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)
dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

#write.csv(inImageQuery %>%
#            arrange(individualID), outfile, row.names = FALSE)

sendChandra <- subset(combined_data_available, 
                      domainID == row$domainID &
                        scientificName=="Carabidae sp.")
#write.csv(sendChandra, "./morphoSpp.csv")

##################################################################################################################
row <- allZero[3, ]
row$newImageID #Done
# ################################################################################################################## COme back to this one
# row <- allZero[4, ]
# row
# 
# subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species
# subset(combined_data_available, individualID==row$IndividualID_n1)$yearCollected
# 
# # Filter matching individuals
# inImageQuery <- subset(combined_data_available, 
#                        domainID == row$domainID &
#                          scientificName_Species == row$scientificName_Species)# &
#                       #   yearCollected == row$yearCollected )
#                       #   numbericID >= row$numbericID_1 & 
#                       #   numbericID <= row$numbericID_n )
# #                         morphospeciesID== "D06.2015.MorphG")
# dim(inImageQuery)
# row$NumberOfBeetles
# outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
#                   gsub(" ", "_", row$scientificName), "-",
#                   row$trayType, "tray-",
#                   "Y", row$yearCollected, "-",
#                   row$IndividualID_1, "-", row$IndividualID_n, ".csv")
# 
# inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles
# 
# inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
#   arrange(individualID)
# inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
# 
# inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
# inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))
# 
# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[5, ]
row$newImageID #Done

##################################################################################################################
row <- allZero[6, ]
row$newImageID #Done
##################################################################################################################
row <- allZero[7, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == row$scientificName_Species &
#                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[10, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[11, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[12, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[13, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[14, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
row <- allZero[15, ]
row$newImageID
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery)) #assign order values sequentially

inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
##################################################################################################################
# Leah Cotton
# July 16 2025 7:39 PM 
# CHECK_Pterostichus_restrictus-Atray-Y2020-NEON.BET.D10.013305-NEON.BET.D10.002525.csv, spreadsheet is empty
all<-read.csv("./BeetleMetadataABTrays.csv")
row<-subset(all, newImageID=="Pterostichus_restrictus-Atray-Y2020-NEON.BET.D10.013305-NEON.BET.D10.002525.png")
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected


# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
#                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected)
#                         numbericID >= row$numbericID_1 & 
#                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-"Mixed Domains in Tray"
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

write.csv(inImageQuery %>%
           arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
##################################################################################################################
# Leah Cotton
# July 16 2025 7:39 PM 
# CHECK_Pterostichus_panticulatus-Btray-Y2021-NEON.BET.D17.001829-NEON.BET.D17.001889.csv, spreadsheet is empty
row<-subset(all, newImageID=="Pterostichus_panticulatus-Btray-Y2021-NEON.BET.D17.001829-NEON.BET.D17.001889.png")
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected


# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                       scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
#                       yearCollected == row$yearCollected)
                        numbericID >= row$numbericID_1 & 
                        numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-"Mixed Years in Tray"
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

write.csv(inImageQuery %>%
            arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
# Leah Cotton
# July 16 2025 7:39 PM 
# CHECK_Pterostichus_ordinarius-Btray-Y2021-NEON.BET.D17.001812-NEON.BET.D17.001859.csv, spreadsheet is empty
row<-subset(all, newImageID=="Pterostichus_ordinarius-Btray-Y2021-NEON.BET.D17.001812-NEON.BET.D17.001859.png")
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected


# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         #                       yearCollected == row$yearCollected)
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles


outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-"Mixed Years in Tray"
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

write.csv(inImageQuery %>%
          arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
#### July 17th 2025 ####
queryZero<-list.files("./NEONIndividualLinkageChecks/QueryZero/")
write.csv(queryZero, "./NEONIndividualLinkageChecks/QueryZero_listJuly17.csv")
##################################################################################################################
row<-subset(all, newImageID==paste0(substr(queryZero[1],7,nchar(queryZero[1])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected


# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-2
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected


# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_n & 
                         numbericID <= row$numbericID_1)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryUnder/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-3
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_1)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
#                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-"Year recorded incorrectly"
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#             arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-4
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species
row$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_1)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         #                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#           arrange(individualID), outfile, row.names = FALSE)

##################################################################################################################
i<-5
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species
row$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_1)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#           arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-6
queryZero[i]
row<-subset(all, newImageID=="Anisodactylus_(Gynandrotarsus)-Atray-Y2020-NEON.BET.D07.005766-NEON.BET.D07.007539.png")
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_1)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         #                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName_Species), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

 # write.csv(inImageQuery %>%
 #           arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-7
queryZero[i]
row<-subset(all, newImageID=="Carabus_taedatus-Atray-Y2021-NEON.BET.D13.013561-NEON.BET.D13.002714.png")
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_n)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
#                       domainID == row$domainID &
                         scientificName_Species == row$scientificName_Species &
                         yearCollected == row$yearCollected)# &
                         # numbericID >= row$numbericID_n &
                         # numbericID <= row$numbericID_1)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/CHECK_",
                  gsub(" ", "_", row$scientificName), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery<-add_column(inImageQuery, Present = "", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-"Mixed Domains in Tray"
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

write.csv(inImageQuery %>%
            arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-8
queryZero[i]
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_n)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                       scientificName_Species == row$scientificName_Species &
#                         yearCollected == row$yearCollected & 
                         numbericID >= row$numbericID_1 &
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

inImageQuery$yearCollected[1]
row$yearCollected

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName_Species), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-""
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#           arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
i<-9
queryZero[i]
row<-subset(all, newImageID==paste0(substr(queryZero[i],7,nchar(queryZero[i])-4),".png"))
row

subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_2)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n1)$scientificName_Species
subset(combined_data_available, individualID==row$IndividualID_n)$scientificName_Species

subset(combined_data_available, individualID==row$IndividualID_1)$yearCollected
subset(combined_data_available, individualID==row$IndividualID_n)$yearCollected
row$yearCollected

subset(combined_data_available, individualID==row$IndividualID_n)$domainID
row$domainID

# Filter matching individuals
inImageQuery <- subset(combined_data_available, 
                       domainID == row$domainID &
                         scientificName_Species == subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species &
                         yearCollected == row$yearCollected &
                         numbericID >= row$numbericID_1 & 
                         numbericID <= row$numbericID_n)
inImageQuery<-subset(inImageQuery, ID_status==row$ExpertOrPara)

dim(inImageQuery)
row$NumberOfBeetles

outfile <- paste0("./NEONIndividualLinkageChecks/QueryOver/Checked/CHECK_",
                  gsub(" ", "_", row$scientificName_Species), "-",
                  row$trayType, "tray-",
                  "Y", row$yearCollected, "-",
                  row$IndividualID_1, "-", row$IndividualID_n, ".csv")

inImageQuery$NumberOfBeetlesInTray<-row$NumberOfBeetles

inImageQuery<-inImageQuery %>% #Order by individualID, this is the box order in this case
  arrange(individualID)
inImageQuery<-add_column(inImageQuery, Order = "", .after = "individualID")
inImageQuery$Order<-c(1:nrow(inImageQuery))
inImageQuery<-add_column(inImageQuery, Present = "1", .after = "individualID")
inImageQuery$notes<-""
inImageQuery$ProcessingNotes<-paste0("Species updated from ", row$scientificName_Species," to ",
                                     subset(combined_data_available, individualID==row$IndividualID_1)$scientificName_Species,
                                     "by Indivudal ID query")
inImageQuery<-add_column(inImageQuery, imagePath = paste0("/Images/FinalImages/",finalDataset))

# write.csv(inImageQuery %>%
#           arrange(individualID), outfile, row.names = FALSE)
##################################################################################################################
