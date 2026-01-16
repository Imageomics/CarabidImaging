library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)
library(stringr)

setwd("/fs/ess/PAS2136/CarabidImaging/")
#Individuals that link nicely from images from C Trays
C_matched_df<-read.csv("./BeetleMetadataCTraysIndividuals.csv")
C_matched_df$imagePath<-"/Images/FinalImages/CTrays"
C_matched_df$source<-"C_matched"

#Individuals that link nicely from images from AB Trays
AB_matched_df<-read.csv("./BeetleMetadataABTraysIndividuals.csv")
AB_matched_df$imagePath<-"/Images/FinalImages/ABTrays"
AB_matched_df$trayID<-NA
AB_matched_df$source<-"AB_matched"

#Individuals that link nicely from images from first pass
FirstPass_matched_df<-read.csv("./catalog_firstPass_renamedIndividualsMetadata.csv")
FirstPass_matched_df$imagePath<-"/Images/FinalImages/ABTrays"
FirstPass_matched_df$trayID<-NA
FirstPass_matched_df$source<-"FirstPass_matched"

#Individuals that link well from Michael Beltiz's Images
Belitz_matched_df<-read.csv("catalog_Belitz_renamedIndividualsMetadata.csv")
Belitz_matched_df$imagePath<-"/Images/FinalImages/ABTrays"
Belitz_matched_df$trayID<-NA
Belitz_matched_df$source<-"Belitz_matched"

#Individuals that link nicely from images from Small Beetles
Small_matched_df<-read.csv("./BeetleMetadataSmallBeetlesIndividuals.csv")
Small_matched_df$imagePath<-"/Images/FinalImages/SmallBeetles"
Small_matched_df$trayID<-NA
Small_matched_df$source<-"Small_matched"

#Individuals from Manual corrections
Manual_matched_df<-read.csv("./BeetleMetadataManualIndividuals.csv")
Manual_matched_df$source<-"Manual"

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

symdiff(common_all, names(C_matched_df))

symdiff(common_all, names(Small_matched_df))

#Merge the datasets with matching columns
all_out<-rbind(AB_matched_df[, common_all], 
               FirstPass_matched_df[, common_all], 
               Belitz_matched_df[, common_all],
               Manual_matched_df[, common_all],
               C_matched_df[, common_all],
               Small_matched_df[, common_all])
str(all_out)
dim(all_out)

#Remove entries where the photo does not exist
list_images<-read.csv("./allImages.csv")
dim(all_out)
subset(all_out, is.na(imageID))
all_out<-all_out %>%
  filter((substr(imageID, 1, (nchar(imageID)-4)) %in% substr(list_images$imageID, 1 , (nchar(list_images$imageID)-4))))
dim(all_out)

# Look at duplicates
all_out$notUnique<-duplicated(all_out$individualID)

check<-subset(all_out, notUnique==TRUE)
check<-all_out %>%
  filter((individualID %in% check$individualID))
dim(check)

table(check$notes)
table(check$processingNotes, useNA = "ifany")

dim(all_out)
dim(check)

## Resolve duplicated individualID records using hierarchical matching rules ##
# Setup: helper columns and source priority ranks
# We work ONLY on the duplicated subset (`check`) and merge back later.
#Create filtering criteria
priority_case1 <- c(
  "AB_matched",
  "Small_matched",
  "C_matched",
  "Manual",
  "Belitz_matched",
  "FirstPass_matched"
)

priority_case2 <- c(
  "Manual",
  "AB_matched",
  "Small_matched",
  "C_matched",
  "Belitz_matched",
  "FirstPass_matched"
)

check_work <- check %>%
  mutate(
    # Remove file extension (imageID always has a 3-letter extension)
    image_stem = substr(imageID, 1, nchar(imageID) - 4),
    
    # Source priority rankings for different decision cases
    source_rank_case1 = match(source, priority_case1),
    source_rank_case2 = match(source, priority_case2)
  )

## ---------------------------------------------------------------------------
## 1. CASE 1
## Same individualID, same Order, same image_stem
## → keep a single row chosen by source priority (case 1 hierarchy)
## ---------------------------------------------------------------------------

case1_ids <- check_work %>%
  group_by(individualID) %>%
  filter(
    n_distinct(image_stem) == 1,
    n_distinct(Order) == 1
  ) %>%
  distinct(individualID)

case1_resolved <- check_work %>%
  filter(individualID %in% case1_ids$individualID) %>%
  group_by(individualID) %>%
  arrange(source_rank_case1) %>%   # lower rank = higher priority
  slice(1) %>%                     # keep best source
  ungroup() %>%
  mutate(flag = NA_character_)

## ---------------------------------------------------------------------------
## 2. CASE 2
## Same individualID, same image_stem, but different Order
## → keep a single row using alternate source priority (case 2 hierarchy)
## ---------------------------------------------------------------------------

case2_ids <- check_work %>%
  filter(!individualID %in% case1_ids$individualID) %>%
  group_by(individualID) %>%
  filter(
    n_distinct(image_stem) == 1,
    n_distinct(Order) > 1
  ) %>%
  distinct(individualID)

case2_resolved <- check_work %>%
  filter(individualID %in% case2_ids$individualID) %>%
  group_by(individualID) %>%
  arrange(source_rank_case2) %>%   # Manual prioritized first
  slice(1) %>%
  ungroup() %>%
  mutate(flag = NA_character_)

## ---------------------------------------------------------------------------
## 3. CASE 3
## Same individualID, different image_stem
## → keep ALL rows
## → flag incorrect ones based on species name appearing in imageID
## ---------------------------------------------------------------------------

case3 <- check_work %>%
  filter(
    !individualID %in% case1_ids$individualID,
    !individualID %in% case2_ids$individualID
  ) %>%
  mutate(
    # Case-insensitive check:
    # does scientificName_Species appear in the image filename?
    species_in_image = str_detect(
      str_to_lower(imageID),
      gsub(" ", "_", str_to_lower(scientificName_Species))
    )
  )

case3_flagged <- case3 %>%
  group_by(individualID) %>%
  mutate(
    n_match = sum(species_in_image, na.rm = TRUE),
    
    # Flagging rules:
    # - exactly one match → flag the non-matching row(s)
    # - more than one match → flag all (ambiguous)
    flag = case_when(
      n_match == 1 & !species_in_image ~ "Potential IndividualID Error",
      n_match > 1                      ~ "Potential IndividualID Error",
      TRUE                             ~ NA_character_
    )
  ) %>%
  ungroup() %>%
  select(-species_in_image, -n_match)

## ---------------------------------------------------------------------------
## 4. Recombine all resolved duplicated records
## ---------------------------------------------------------------------------

check_resolved <- bind_rows(
  case1_resolved,
  case2_resolved,
  case3_flagged
)

## ---------------------------------------------------------------------------
## 5. Merge back into the full dataset
## Remove original duplicated entries and replace with resolved versions
## ---------------------------------------------------------------------------

all_out_clean <- all_out %>%
  filter(!individualID %in% check$individualID) %>%
  bind_rows(check_resolved)

###############################################################################
## Optional sanity checks (recommended)
###############################################################################

# No remaining duplicate individualIDs
sum(duplicated(all_out_clean$individualID))

# How many rows were flagged?
table(all_out_clean$flag, useNA = "ifany")

# Inspect flagged cases manually
# all_out_clean %>% filter(!is.na(flag)) %>% arrange(individualID)

all_out_clean$source_rank_case1<-NULL
all_out_clean$source_rank_case2<-NULL
all_out_clean$image_stem<-NULL
all_out_clean$notUnique<-NULL
all_out_clean<-all_out_clean%>%
  group_by(individualID, Order)

print("Total Number of individuals:")
dim(all_out_clean)

length(unique(all_out_clean$imageID))

write.csv(all_out_clean, "./allIndividuals.csv", row.names = FALSE)
