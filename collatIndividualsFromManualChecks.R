library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)


#Read in the NEON data
combined_data <- read.csv("./NEON_ExpertParaCombined.csv")
combined_data$scientificName_Species<-gsub(r"{\s*\([^\)]+\)}","",as.character(combined_data$scientificName))
combined_data$scientificName_Species<-gsub(" {2,}", " ", combined_data$scientificName_Species)
combined_data$scientificName_Species<-sub("^(\\S*\\s+\\S+).*", "\\1", combined_data$scientificName_Species)


#### Query Over ####

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

#Loop over the rest of the files and rbind them together
for (i in 2:length(QueryOverCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryOverCheckedDir,QueryOverCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryOverCheckedFiles[i], 
                             7, (nchar(QueryOverCheckedFiles[i])-4)),
                      "png")
  if (!"Order" %in% names(tmp)) {
    tmp<-tmp %>% #Order by individualID, this is the box order in this case
      arrange(individualID)
    tmp<-add_column(tmp, Order = "", .before = "sampleCondition")
    tmp$Order <- 1:nrow(tmp)
  }
  colnames(tmp)<-colnames(QueryOverChecked_df)
  QueryOverChecked_df<-rbind(QueryOverChecked_df, tmp)
}
table(QueryOverChecked_df$imageID)
table(QueryOverChecked_df$P)
QueryOverChecked_df<-subset(QueryOverChecked_df, P==1)
QueryOverChecked_df$notes<-"QueryOver, Manually Checked"
table(QueryOverChecked_df$P)

table(QueryOverChecked_df$domainID, useNA = "ifany")

#Pull out files where there were manuall aditions to the dataset, so the rest of the NEON columns are NAs
QueryOverChecked_df_manualAdditions<-subset(QueryOverChecked_df, is.na(uid))
#List the images where that happened
Images_w_Additions<-unique(QueryOverChecked_df_manualAdditions$imageID)

tmp <- data.frame()
#for each Image in Images_w_Additions
for (i in 1:length(Images_w_Additions)) {
  QueryOverChecked_df_manualAdditions<-QueryOverChecked_df%>%
    filter((imageID %in% Images_w_Additions[i]))
  
  QueryOverChecked_df_manualAdditions_NEON<-combined_data%>%
    filter((individualID %in% QueryOverChecked_df_manualAdditions$individualID))
  
  #ensure they are the same size
  dim(QueryOverChecked_df_manualAdditions_NEON)[1]
  dim(QueryOverChecked_df_manualAdditions)[1]
  
  #Order both by individual ID to make sure that we can move columns from on to the next
  QueryOverChecked_df_manualAdditions_NEON<-QueryOverChecked_df_manualAdditions_NEON %>% #Order by individualID, this is the box order in this case
    arrange(individualID)
  QueryOverChecked_df_manualAdditions<-QueryOverChecked_df_manualAdditions %>% #Order by individualID, this is the box order in this case
    arrange(individualID)
  
  #Add all of the appropriate column names in to the right places
  colnames(QueryOverChecked_df_manualAdditions)
  colnames(QueryOverChecked_df_manualAdditions_NEON)
  
  symdiff(colnames(QueryOverChecked_df_manualAdditions), colnames(QueryOverChecked_df_manualAdditions_NEON))
  
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       P = "1", .after = "individualID")
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       Order = QueryOverChecked_df_manualAdditions$Order, .before = "sampleCondition")
  
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       yearCollected = substr(QueryOverChecked_df_manualAdditions_NEON$setDate,1,4), .after = "numbericID")
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       NumberOfBeetlesInTray = max(QueryOverChecked_df_manualAdditions$NumberOfBeetlesInTray, na.rm = T), .after = "scientificName_Species")
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       imagePath = unique(QueryOverChecked_df_manualAdditions$imagePath)[2], .after = "NumberOfBeetlesInTray")
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       imageID = QueryOverChecked_df_manualAdditions$imageID, .after = "NumberOfBeetlesInTray")
  QueryOverChecked_df_manualAdditions_NEON<-add_column(QueryOverChecked_df_manualAdditions_NEON, 
                                                       notes = QueryOverChecked_df_manualAdditions$notes, .after = "NumberOfBeetlesInTray")
  
  tmp<-rbind(tmp,QueryOverChecked_df_manualAdditions_NEON)
}
dim(QueryOverChecked_df)
QueryOverChecked_df<-QueryOverChecked_df%>%
  filter(!(imageID %in% Images_w_Additions[i]))
dim(QueryOverChecked_df)
QueryOverChecked_df<-rbind(QueryOverChecked_df,tmp)
dim(QueryOverChecked_df)

#### Query Under####

#Individuals that had to be manually entered when missing from query
QueryUnderCheckedDir<-"/fs/ess/PAS2136/CarabidImaging/NEONIndividualLinkageChecks/QueryUnder/Checked/"
QueryUnderCheckedFiles<-list.files(QueryUnderCheckedDir, pattern = "*.xlsx")

#Read in first file to create the seed for the dataset
QueryUnderChecked_df <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[1]),
                                                 sheet = 1))
QueryUnderChecked_df$imageID<-paste0(substr(QueryUnderCheckedFiles[1], 
                                            7, (nchar(QueryUnderCheckedFiles[1])-4)),
                                     "png")
if (!"imagePath" %in% names(QueryUnderChecked_df)) {
  QueryUnderChecked_df<-add_column(QueryUnderChecked_df, imagePath = "/Images/FinalImages/ABTrays", .after = "NumberOfBeetlesInTray")
}

for (i in 1:length(QueryUnderCheckedFiles)) {
  tmp <- as.data.frame(read_excel(paste0(QueryUnderCheckedDir,QueryUnderCheckedFiles[i]),
                                  sheet = 1))
  tmp$imageID<-paste0(substr(QueryUnderCheckedFiles[i], 
                             7, (nchar(QueryUnderCheckedFiles[i])-4)),
                      "png")
  if (!"imagePath" %in% names(tmp)) {
    tmp<-add_column(tmp, imagePath = "/Images/FinalImages/ABTrays", .after = "NumberOfBeetlesInTray")
  }
  colnames(tmp)<-colnames(QueryUnderChecked_df)
  QueryUnderChecked_df<-rbind(QueryUnderChecked_df, tmp)
}
table(QueryUnderChecked_df$imageID)
table(QueryUnderChecked_df$P)
QueryUnderChecked_df<-subset(QueryUnderChecked_df, P==1)
QueryUnderChecked_df$notes<-"QueryOver, Manually Checked"

#Pull out files where there were manuall aditions to the dataset, so the rest of the NEON columns are NAs
QueryUnderChecked_df_manualAdditions<-subset(QueryUnderChecked_df, is.na(uid))
#List the images where that happened
Images_w_Additions<-unique(QueryUnderChecked_df_manualAdditions$imageID)

tmp <- data.frame()
#for each Image in Images_w_Additions
for (i in 1:length(Images_w_Additions)) {
  QueryUnderChecked_df_manualAdditions<-QueryUnderChecked_df%>%
    filter((imageID %in% Images_w_Additions[i]))
  
  QueryUnderChecked_df_manualAdditions<-distinct(QueryUnderChecked_df_manualAdditions, individualID, .keep_all = TRUE)
  
  QueryUnderChecked_df_manualAdditions_NEON<-combined_data%>%
    filter((individualID %in% QueryUnderChecked_df_manualAdditions$individualID))
  
  #ensure they are the same size
  dim(QueryUnderChecked_df_manualAdditions_NEON)[1]
  dim(QueryUnderChecked_df_manualAdditions)[1]
  
  #Order both by individual ID to make sure that we can move columns from on to the next
  QueryUnderChecked_df_manualAdditions_NEON<-QueryUnderChecked_df_manualAdditions_NEON %>% #Order by individualID, this is the box order in this case
    arrange(individualID)
  QueryUnderChecked_df_manualAdditions<-QueryUnderChecked_df_manualAdditions %>% #Order by individualID, this is the box order in this case
    arrange(individualID)
  
  #Add all of the appropriate column names in to the right places
  colnames(QueryUnderChecked_df_manualAdditions)
  colnames(QueryUnderChecked_df_manualAdditions_NEON)
  
  symdiff(colnames(QueryUnderChecked_df_manualAdditions), colnames(QueryUnderChecked_df_manualAdditions_NEON))
  
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       P = "1", .after = "individualID")
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       Order = QueryUnderChecked_df_manualAdditions$Order, .before = "sampleCondition")
  
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       yearCollected = substr(QueryUnderChecked_df_manualAdditions_NEON$setDate,1,4), .after = "numbericID")
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       NumberOfBeetlesInTray = max(QueryUnderChecked_df_manualAdditions$NumberOfBeetlesInTray, na.rm = T), .after = "scientificName_Species")
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       imagePath = unique(QueryUnderChecked_df_manualAdditions$imagePath)[2], .after = "NumberOfBeetlesInTray")
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       imageID = QueryUnderChecked_df_manualAdditions$imageID, .after = "NumberOfBeetlesInTray")
  QueryUnderChecked_df_manualAdditions_NEON<-add_column(QueryUnderChecked_df_manualAdditions_NEON, 
                                                       notes = QueryUnderChecked_df_manualAdditions$notes, .after = "NumberOfBeetlesInTray")
  
  tmp<-rbind(tmp,QueryUnderChecked_df_manualAdditions_NEON)
}
dim(QueryUnderChecked_df)
dim(tmp)
QueryUnderChecked_df<-tmp

queryAll<-rbind(QueryUnderChecked_df, QueryOverChecked_df)
write.csv(queryAll, "./BeetleMetadataManualIndividuals.csv")
