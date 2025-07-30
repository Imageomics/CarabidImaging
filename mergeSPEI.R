library(neonUtilities)
library(readxl)
library(dplyr)
library(tibble)

# Set working directory to CarabidImaging project
setwd("/fs/ess/PAS2136/CarabidImaging/")

allIndividuals<-read.csv("./allIndividuals.csv")

SPEI<-read.csv("./gridmet_data_gap_filled.csv")
head(SPEI)

allIndividuals$eventID<-paste0(allIndividuals$domainID,"_",allIndividuals$siteID,"_",substr(allIndividuals$collectDate,1,10))
head(allIndividuals$eventID)
dim(table(allIndividuals$eventID))

SPEI$eventID<-paste0(SPEI$domain,"_",SPEI$site,"_",SPEI$date)

allIndividuals_SPEI<-merge(allIndividuals, SPEI, by="eventID", all.x = TRUE)

dim(allIndividuals)
dim(subset(allIndividuals_SPEI, is.na(SPEI_1y)))

table(subset(allIndividuals_SPEI, is.na(SPEI_1y))$domainID)
table(subset(allIndividuals_SPEI, is.na(SPEI_1y))$siteID)
table(subset(allIndividuals_SPEI, is.na(SPEI_1y))$year)


blanks<-subset(allIndividuals_SPEI, is.na(SPEI_1y))

allIndividuals_SPEI$date<-NULL
allIndividuals_SPEI$domain<-NULL
allIndividuals_SPEI$site<-NULL

write.csv(allIndividuals_SPEI, "./allIndividuals_SPEI.csv")
