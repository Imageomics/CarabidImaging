library(neonUtilities)
library(readxl)


setwd("/fs/ess/PAS2136/CarabidImaging/")

firstpass_df<-as.data.frame(read_excel("./catalog_Belitz.xlsx", sheet = 1))
head(firstpass_df)
dim(firstpass_df)
str(firstpass_df)
table(firstpass_df$Good)
table(firstpass_df$Good)[2]/dim(firstpass_df)[1]
table(firstpass_df$NumberOfBeetles)
table(firstpass_df$Notes)

firstpass_df<-subset(firstpass_df, Good==1)

firstpass_df$IndividualID_1<-paste0("NEON.BET.", firstpass_df$domainID, ".",firstpass_df$IndividualID_1)
firstpass_df$IndividualID_2<-paste0("NEON.BET.", firstpass_df$domainID, ".",firstpass_df$IndividualID_2)
firstpass_df$IndividualID_n1<-paste0("NEON.BET.", firstpass_df$domainID, ".",firstpass_df$IndividualID_n1)
firstpass_df$IndividualID_n<-paste0("NEON.BET.", firstpass_df$domainID, ".",firstpass_df$IndividualID_n)

firstpass_df$newImageID<-paste0(gsub(" ", "_", firstpass_df$scientificName),"-",
                                firstpass_df$trayType,"tray-",
                                "Y",firstpass_df$yearCollected,"-",
                                firstpass_df$IndividualID_1,"-",
                                firstpass_df$IndividualID_n,".png")
head(firstpass_df$newImageID)
head(firstpass_df)

table(firstpass_df$scientificName)

write.csv(firstpass_df, "./catalog_Belitz_filesToRename.csv")

firstpass_metadata<-firstpass_df[,c(ncol(firstpass_df),3:(ncol(firstpass_df)-1))]
firstpass_metadata$checkedOrder<-""
firstpass_metadata$Marked<-""
head(firstpass_metadata)

write.csv(firstpass_metadata, "./catalog_Belitz_renamedMetadataTemplate.csv")
