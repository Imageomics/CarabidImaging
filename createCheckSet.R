setwd("/fs/ess/PAS2136/CarabidImaging/")

df<-read.csv("./allIndividuals.csv")

table(df$flag)
df<-subset(df, is.na(flag))

set.seed(123)
CheckSet<-df[sample(nrow(df), 100), ]
CheckSet$isCorrect<-""
#write.csv(CheckSet,"./CheckSet_20260105.csv", row.names = FALSE)
CheckSet_20260105<-read.csv("./CheckSet_20260105.csv")

library(dplyr)
df2<-df %>%
  filter(!(df$individualID %in% CheckSet_20260105$individualID))
table(df$flag)

CheckSet<-df2[sample(nrow(df2), 50), ]
CheckSet$isCorrect<-""
#write.csv(CheckSet,"./CheckSet_20260111.csv", row.names = FALSE)
CheckSet_20260111<-read.csv("./CheckSet_20260111.csv",)

df3<-df2 %>%
  filter(!(df2$individualID %in% CheckSet_20260111$individualID))

df3<-df3 %>%
  filter(!(df3$imageID %in% CheckSet_20260111$imageID))
df3<-df3 %>%
  filter(!(df3$imageID %in% CheckSet_20260105$imageID))


library(dplyr)

set.seed(124)

CheckSet <- df3 %>%
  group_by(imageID) %>%
  slice_sample(n = 1) %>%
  ungroup() %>%
  sample_n(size = min(160, n()))

table(CheckSet$Order)
hist(CheckSet$Order, breaks = 50)
hist(df3$Order, breaks = 50)

table(table(CheckSet$imageID))

#write.csv(CheckSet,"./CheckSet_20260112.csv", row.names = FALSE)
