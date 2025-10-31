#### Setup and Package Loading ####
library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)


# Set working directory to CarabidImaging project
setwd("/fs/ess/PAS2136/CarabidImaging/")

ABTrays<-read.csv("./BeetleMetadataABTrays.csv")
ABTrays$imageSource<-"ABTray Imaging"
CTrays<-read.csv("./BeetleMetadataCTrays.csv")
CTrays$imageSource<-"CTray Imaging"
firstPass<-read.csv("./catalog_firstPass_renamedMetadataClean.csv")
firstPass$imageSource<-"firstPass Imaging"
Belitz<-read.csv("./catalog_Belitz_renamedMetadataClean.csv")
Belitz$imageSource<-"Belitz Imaging"

firstPass$Photographer<-"IB"
firstPass$dateImaged<-"2024"

bit::symdiff(names(firstPass), names(ABTrays))
bit::symdiff(names(Belitz), names(ABTrays))


common_cols <- intersect(names(ABTrays), names(firstPass))
length(common_cols)
length(colnames(ABTrays))
length(colnames(firstPass))
length(colnames(CTrays))
intersect(names(ABTrays), names(CTrays))
symdiff(names(ABTrays), names(CTrays))


ImageMetadata<-rbind(ABTrays[, common_cols], 
                     firstPass[, common_cols], 
                     Belitz[, common_cols])

symdiff(names(ImageMetadata), names(CTrays))
CTrays$trayType<-"C"
ImageMetadata$Tray<-NA
ImageMetadata$NumberOfTrays<-NA
ImageMetadata$trayID<-NA

common_cols <- intersect(names(ImageMetadata), names(CTrays))
ImageMetadata<-rbind(ImageMetadata[, common_cols], 
                     CTrays[, common_cols])

ImageMetadata$originalImageID<-ImageMetadata$imageID
ImageMetadata$imageID<-ImageMetadata$newImageID
ImageMetadata$newImageID<-NULL

write.csv(ImageMetadata, "./allImages.csv", row.names = FALSE)
