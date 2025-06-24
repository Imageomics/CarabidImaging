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

write.csv(all_out, "./allIndividuals.csv", row.names = FALSE)
