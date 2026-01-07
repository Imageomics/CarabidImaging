setwd("/fs/ess/PAS2136/CarabidImaging/")

df<-read.csv("./allIndividuals.csv")

table(df$flag)
df<-subset(df, flag!="Possible IndividualID Error")

set.seed(123)
CheckSet<-df[sample(nrow(df), 100), ]
CheckSet$isCorrect<-""
write.csv(CheckSet,"./CheckSet_20260105.csv", row.names = FALSE)
