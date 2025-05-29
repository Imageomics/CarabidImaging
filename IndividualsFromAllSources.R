library(neonUtilities)
library(readxl)
library(dplyr)

setwd("/fs/ess/PAS2136/CarabidImaging/")

#Individuals that link nicely from images
matched_df<-read.csv("./BeetleMetadataABTraysIndividuals.csv")

#Individuals that had to be manually filtered from query with too many entries
QueryOverCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryOver/Checked/"
QueryOverCheckedFiles<-list.files(QueryOverCheckedDir)

QueryOverChecked_df <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[1]),
                                  sheet = 1))
QueryOverChecked_df$imageID<-paste0(substr(QueryOverCheckedFiles[1], 
                           7, (nchar(QueryOverCheckedFiles[i])-4)),
                    "png")
for (i in 2:length(QueryOverCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryOverCheckedFiles[i], 
                             7, (nchar(QueryOverCheckedFiles[i])-4)),
                      "png")
  colnames(tmp)<-colnames(QueryOverChecked_df)
  QueryOverChecked_df<-rbind(QueryOverChecked_df, tmp)
}
table(QueryOverChecked_df$imageID)

#Individuals that had to be manually entered when missing from query
QueryUnderCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/"
QueryUnderCheckedFiles<-list.files(QueryUnderCheckedDir)

QueryUnderChecked_df <- data.frame()
for (i in 1:length(QueryUnderCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryUnderCheckedFiles[i], 
                             7, (nchar(QueryUnderCheckedFiles[i])-4)),
                      "png")
  QueryUnderChecked_df<-rbind(QueryUnderChecked_df, tmp)
}

colnames(QueryUnderChecked_df)
colnames(tmp)

#Individuals from first pass


