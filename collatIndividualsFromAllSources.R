library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)

setwd("/fs/ess/PAS2136/CarabidImaging/")

#Individuals that link nicely from images from AB Trays
AB_matched_df<-read.csv("./BeetleMetadataABTraysIndividuals.csv")
AB_matched_df$imagePath<-"/Images/FinalImages/ABTrays"

#Individuals that link nicely from images from first pass
FirstPass_matched_df<-read.csv("./catalog_firstPass_renamedIndividualsMetadata.csv")
FirstPass_matched_df$imagePath<-"/Images/FinalImages/ABTrays"

#Individuals that link well from Michael Beltiz's Images
Belitz_matched_df<-read.csv("catalog_Belitz_renamedIndividualsMetadata.csv")
Belitz_matched_df$imagePath<-"/Images/FinalImages/ABTrays"

#Individuals from Manual corrections
Manual_matched_df<-read.csv("./BeetleMetadataManualIndividuals.csv")

####Merge all of the sources together####
#Find overlapping columns
common_cols <- intersect(names(AB_matched_df), names(FirstPass_matched_df))
length(common_cols)
length(colnames(AB_matched_df))
length(colnames(FirstPass_matched_df))

common_cols2 <- intersect(names(Belitz_matched_df), names(Manual_matched_df))
length(common_cols2)
length(colnames(Belitz_matched_df))
length(colnames(Manual_matched_df))


common_all <- intersect(common_cols2, common_cols)
length(common_all)
length(common_cols2)
symdiff(common_cols, names(Manual_matched_df))

#Merge the datasets with matching columns
all_out<-rbind(AB_matched_df[, common_all], 
               FirstPass_matched_df[, common_all], 
               Belitz_matched_df[, common_all],
               Manual_matched_df[, common_all])
str(all_out)
dim(all_out)

# Remove duplicates
all_out$unique<-duplicated(all_out$individualID)

check<-subset(all_out, unique==TRUE)
check<-all_out %>%
  filter((individualID %in% check$individualID))

table(check$notes)
table(check$processingNotes)

dim(all_out)
dim(check)
all_int<-all_out
all_out<-all_out %>%
  filter(!(individualID %in% check$individualID))
dim(all_out)

list_images<-read.csv("./allImages.csv")
dim(check)
check_real<-check %>%
  filter((imageID %in% list_images$imageID))

table(table(check$individualID))

# Step 1: Keep only the best row for each individualID + imageID based on longest processingNotes
check_tagged <- check_real %>%
  group_by(individualID, imageID) %>%
  mutate(max_note_len = max(nchar(processingNotes)),
         keep = nchar(processingNotes) == max_note_len) %>%
  slice_max(nchar(processingNotes), with_ties = FALSE) %>%
  ungroup()

# Step 2: Identify which combos had duplicates removed
filtered_out <- check_real %>%
  group_by(individualID, imageID) %>%
  filter(n() > 1) %>%
  summarise(duplicates_filtered = TRUE, .groups = "drop")

# Step 3: Join filter info back in
check_flagged <- check_tagged %>%
  left_join(filtered_out, by = c("individualID", "imageID")) %>%
  group_by(individualID) %>%
  mutate(flag = case_when(
    any(duplicates_filtered, na.rm = TRUE) ~ "",  # Don't flag if any filtering occurred
    n_distinct(imageID) > 1 ~ "Possible IndividualID Error",  # Flag if multiple imageIDs remain
    TRUE ~ ""
  )) %>%
  ungroup() %>%
  select(-max_note_len, -keep, -duplicates_filtered)

all_out$flag<-""
all_out<-rbind(all_out, check_flagged)

all_out$unique<-NULL
all_out<-all_out%>%
  group_by(individualID, Order)
write.csv(all_out, "./allIndividuals.csv", row.names = FALSE)
