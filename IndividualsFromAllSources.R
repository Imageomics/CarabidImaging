library(neonUtilities)
library(readxl)
library(dplyr)

setwd("/fs/ess/PAS2136/CarabidImaging/")

#Individuals that link nicely from images from AB Trays
AB_matched_df<-read.csv("./BeetleMetadataABTraysIndividuals.csv")
AB_matched_df$imagePath<="/Images/FinalImages/ABTrays"
#Individuals that link nicely from images from first pass
FirstPass_matched_df<-read.csv("./catalog_firstPass_renamedIndividualsMetadata.csv")
FirstPass_matched_df$imagePath<="/Images/FinalImages/ABTrays"

#Individuals that had to be manually filtered from query with too many entries
QueryOverCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver/Checked/"
QueryOverCheckedFiles<-list.files(QueryOverCheckedDir, pattern = "*.xlsx")


#Read in first file to create the seed for the dataset
QueryOverChecked_df <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[1]),
                                  sheet = 1))
QueryOverChecked_df$imageID<-paste0(substr(QueryOverCheckedFiles[1], 
                           7, (nchar(QueryOverCheckedFiles[1])-4)),
                    "png")
QueryOverChecked_df<-QueryOverChecked_df %>% #Order by individualID, this is the box order in this case
  arrange(QueryOverChecked_df)
QueryOverChecked_df$Order<-c(1:nrow(QueryOverChecked_df))

for (i in 2:length(QueryOverCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryOverCheckedFiles[i], 
                             7, (nchar(QueryOverCheckedFiles[i])-4)),
                      "png")
  tmp<-tmp %>% #Order by individualID, this is the box order in this case
    arrange(tmp)
  tmp$Order<-c(1:nrow(tmp))
  colnames(tmp)<-colnames(QueryOverChecked_df)
  QueryOverChecked_df<-rbind(QueryOverChecked_df, tmp)
}
table(QueryOverChecked_df$imageID)
table(QueryOverChecked_df$P)
QueryOverChecked_df<-subset(QueryOverChecked_df, P==1)
QueryOverChecked_df$notes<-"QueryOver, Manually Checked"

#Individuals that had to be manually entered when missing from query
QueryUnderCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/"
QueryUnderCheckedFiles<-list.files(QueryUnderCheckedDir, pattern = "*.xlsx")

#Read in first file to create the seed for the dataset
QueryUnderChecked_df <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[1]),
                                                 sheet = 1))
QueryUnderChecked_df$imageID<-paste0(substr(QueryUnderCheckedFiles[1], 
                                            7, (nchar(QueryUnderCheckedFiles[1])-4)),
                                     "png")

for (i in 1:length(QueryUnderCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryUnderCheckedFiles[i], 
                             7, (nchar(QueryUnderCheckedFiles[i])-4)),
                      "png")
  colnames(tmp)<-colnames(QueryUnderChecked_df)
  QueryUnderChecked_df<-rbind(QueryUnderChecked_df, tmp)
}
table(QueryUnderChecked_df$imageID)
table(QueryUnderChecked_df$P)
QueryUnderChecked_df<-subset(QueryUnderChecked_df, P==1)
QueryUnderChecked_df$notes<-"QueryOver, Manually Checked"


#Individuals that link well from Michael Beltiz's Images
Belitz<-read.csv()
Belitz$imagePath<="/Images/FinalImages/ABTrays"

####Merge all of the sources together####
#Find overlapping columns
common_cols <- intersect(names(AB_matched_df), names(FirstPass_matched_df))
length(common_cols)
length(colnames(AB_matched_df))
length(colnames(FirstPass_matched_df))

common_cols_manual<-intersect(names(QueryOverChecked_df), names(QueryUnderChecked_df))
length(common_cols_manual)
length(colnames(QueryOverChecked_df))
length(colnames(QueryUnderChecked_df))

common_all <- intersect(common_cols, common_cols_manual)
length(common_all)
symdiff(common_cols, common_cols_manual)

#Merge the datasets with matching columns
all_out<-rbind(AB_matched_df[, common_all], 
               FirstPass_matched_df[, common_all], 
               QueryOverChecked_df[, common_all], 
               QueryUnderChecked_df[, common_all])

dim(all_out)
str(all_out)

write.csv()
