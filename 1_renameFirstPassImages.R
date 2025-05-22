library(neonUtilities)
library(readxl)


setwd("/fs/ess/PAS2136/CarabidImaging/")

firstpass_df<-as.data.frame(read_excel("./catalog_firstPass.xlsx", sheet = 1))
head(firstpass_df)
dim(firstpass_df)
str(firstpass_df)
table(firstpass_df$Good)
table(firstpass_df$NumberOfBeetles)
189/545
table(firstpass_df$Notes)

firstpass_df<-subset(firstpass_df, Good==1)
firstpass_df<-subset(firstpass_df, is.na(Notes))

firstpass_df$newImageID<-paste0(gsub(" ", "_", firstpass_df$scientificName),"-",
                                firstpass_df$trayType,"tray-",
                                "Y",firstpass_df$yearCollected,"-",
                                firstpass_df$IndividualID_1,"-",firstpass_df$IndividualID_n,".jpeg")
head(firstpass_df$newImageID)

table(firstpass_df$scientificName)

write.csv(firstpass_df, "./catalog_firstPass_filesToRename.csv")

firstpass_metadata<-firstpass_df[,c(ncol(firstpass_df),3:(ncol(firstpass_df)-1))]
firstpass_metadata$checkedOrder<-""
firstpass_metadata$Marked<-""
head(firstpass_metadata)

write.csv(firstpass_metadata, "./catalog_firstPass_renamedMetadataTemplate.csv")
