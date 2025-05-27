library(neonUtilities)
library(readxl)
library(dplyr)

setwd("/fs/ess/PAS2136/CarabidImaging/")

firstpass_df <- as.data.frame(read_excel("./BeetleMetadata.xlsx", sheet = 1))
firstpass_df$numbericID_1 <- as.numeric(firstpass_df$IndividualID_1)
firstpass_df$numbericID_2 <- as.numeric(firstpass_df$IndividualID_2)
firstpass_df$numbericID_n1 <- as.numeric(firstpass_df$IndividualID_n1)
firstpass_df$numbericID_n <- as.numeric(firstpass_df$IndividualID_n)

firstpass_df$IndividualID_1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_1)
firstpass_df$IndividualID_2 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_2)
firstpass_df$IndividualID_n1 <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n1)
firstpass_df$IndividualID_n <- paste0("NEON.BET.", firstpass_df$domainID, ".", firstpass_df$IndividualID_n)

neon_token <- read.delim("~/NEON_Token_AE", header = FALSE)[1, 1]
Beetle_dpID <- "DP1.10022.001"

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

# Convert date to year (fixing typo in your original: `as.numberic`)
combined_data$yearCollected <- as.numeric(substr(combined_data$date, 1, 4))

# Placeholder for all matched cases
matched_df <- data.frame()

# Loop over all rows in firstpass_df
for (i in 1:nrow(firstpass_df)) {
  row <- firstpass_df[i, ]
  
  # Filter matching individuals
  inImageQuery <- subset(combined_data, 
                         domainID == row$domainID &
                           scientificName == row$scientificName &
                           yearCollected == row$yearCollected &
                           numbericID >= row$numbericID_1 & 
                           numbericID <= row$numbericID_n)
  
  num_found <- nrow(inImageQuery)
  firstpass_df$NumberOfBeetlesInQuery[i] <- num_found
  
  if (num_found == row$NumberOfBeetles) {
    image_id <- paste0(gsub(" ", "_", row$scientificName), "-",
                       row$trayType, "tray-", 
                       "Y", row$yearCollected, "-",
                       row$IndividualID_1, "-", row$IndividualID_n, ".png")
    inImageQuery$imageID <- image_id
    
    matched_df <- rbind(matched_df, inImageQuery)
  } else {
    inImageQuery$NumberOfBeetlesInTray <- row$NumberOfBeetles
    outfile <- paste0("./NEONIndividualLinkageChecks/CHECK_", 
                      gsub(" ", "_", row$scientificName), "-", 
                      row$trayType, "tray-", 
                      "Y", row$yearCollected, "-",
                      row$IndividualID_1, "-", row$IndividualID_n, ".csv")
    write.csv(inImageQuery, outfile, row.names = FALSE)
  }
}

# Save matched dataset to file
if (nrow(matched_df) > 0) {
  write.csv(matched_df, "./BeetleMetadataIndividuals.csv", row.names = FALSE)
}
