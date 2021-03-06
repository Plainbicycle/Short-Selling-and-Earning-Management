library(rio)
library(foreign)
library(tidyverse)
library(zoo)

file0 <- "/Users/nizhenghui1/Desktop/econometricsII WENLAN/replication/Data/"
file1 <- "compustat.csv"
filepath <- paste0(file0, file1)
file2 <- "pilot.csv"
filepath2 <- paste0(file0, file2)
file3 <- "data.csv.gz"
filepath3 <- paste0(file0, file3)
file4 <- "/Users/nizhenghui1/Desktop/Corporate Finance/mini_study/SIC_to_Fama_French_industry.csv"

fama_french_ind <- read.csv(file4)
data <- import(filepath)
pilot <- import(filepath2)
data <- read.csv(gzfile(filepath3))

pilot[,2] <- 1

summary(data$sic)
summary(data$fyear)

names(data$tic) <- "tic"
data <- merge(data, pilot, by.x ="tic" , by.y = "ticker", all.x = TRUE)
summary(data$V2)
test1 <- data %>% select(tic, exchg, V2)
test1 <- distinct(test1) %>% group_by(exchg, V2) %>% summarise(number=n())
#names(data$V2) <- "pilot"
#library(sqldf)
#data <- sqldf( "select a.*, b.*
#                from data as a
#               left outer join 
#               pilot as b ")
data <- data %>% filter(sic < 4900 | (sic > 4949 & sic < 6000)  | sic > 6999) %>% mutate(pilot = ifelse(is.na(V2)!=1, 1, 0))
summary(data$pilot)

### Part 1
## discretionary accrual
##
#merge to FF industry
earning_mng <- sqldf("select a.*, b.*
                  from data as a
                     left outer join 
                     fama_french_ind as b
                     on  a.sic = b.SIC")

earning_mng$at <- pmax(pmin(earning_mng$at, quantile(earning_mng$at, .99,na.rm = TRUE)), quantile(earning_mng$at, .01,na.rm = TRUE)) 
earning_mng$sale <- pmax(pmin(earning_mng$sale, quantile(earning_mng$sale, .99,na.rm = TRUE)), quantile(earning_mng$sale, .01,na.rm = TRUE)) 
earning_mng$ibc <- pmax(pmin(earning_mng$ibc, quantile(earning_mng$ibc, .99,na.rm = TRUE)), quantile(earning_mng$ibc, .01,na.rm = TRUE)) 
earning_mng$oancf <- pmax(pmin(earning_mng$oancf, quantile(earning_mng$oancf, .99,na.rm = TRUE)), quantile(earning_mng$oancf, .01,na.rm = TRUE)) 
earning_mng$xidoc <- pmax(pmin(earning_mng$xidoc, quantile(earning_mng$xidoc, .99,na.rm = TRUE)), quantile(earning_mng$xidoc, .01,na.rm = TRUE)) 
earning_mng$rect <- pmax(pmin(earning_mng$rect, quantile(earning_mng$rect, .99,na.rm = TRUE)), quantile(earning_mng$rect, .01,na.rm = TRUE)) 
earning_mng$revt <- pmax(pmin(earning_mng$revt, quantile(earning_mng$revt, .99,na.rm = TRUE)), quantile(earning_mng$revt, .01,na.rm = TRUE)) 
earning_mng$oibdp <- pmax(pmin(earning_mng$oibdp, quantile(earning_mng$oibdp, .99,na.rm = TRUE)), quantile(earning_mng$oibdp, .01,na.rm = TRUE)) 

earning_mngment <- earning_mng %>% mutate(tic=as.character(tic)) %>%  group_by(tic) %>% 
  filter( is.na(fyear)!=1) %>% 
  mutate(asset_lag=lag(at),delta_revenue=revt-lag(sale),
         ppe=ppegt,total_accrual=ibc-oancf+xidoc,delta_ar=rect-lag(rect),
         roa=oibdp/asset_lag,size=log(at),mb_ratio=prcc_f*csho/ceq,
         capex=capx/asset_lag,capex_sq=capex*capex,r_and_d=xrd/at,investment=r_and_d+capex,
         cfo=oancf/asset_lag,lev=(dltt+dlc)/(dltt+dlc+seq),cash=che/asset_lag,
         dividends=(dvc+dvp)/asset_lag,sic2=substr(sic,1,2)) %>% 
  ungroup(tic) %>% filter(is.na(asset_lag)!=1&asset_lag!=0) %>%  
  filter(!is.na(total_accrual) & !is.na(delta_revenue)& !is.na(ppe))

####get discretionary acruals
library(broom)
acrual_results <-  earning_mngment %>% 
  group_by(FF_48,fyear) %>% 
  filter(n()>9) %>% 
  ungroup(FF_48,fyear) %>% 
  nest(-FF_48,-fyear) %>% 
  mutate(fit = map(data, ~ lm( I(total_accrual/asset_lag) ~ I(1/asset_lag) + I(delta_revenue/asset_lag) + I(ppe/asset_lag) , data =.,na.action = )),
         results1 = map(fit, glance),
         results2 = map(fit, tidy)) %>% 
  unnest(results1) %>% 
  unnest(results2) %>% select(fyear, FF_48, r.squared, term, estimate)

library(reshape)
acrual_results <- cast(acrual_results,fyear + FF_48 + r.squared ~ term)

discrection_acrual <- merge(earning_mngment, acrual_results, 
                            by.x = c("fyear","FF_48"), by.y = c("fyear","FF_48"))

names(discrection_acrual)[1004]<-"r_square"
names(discrection_acrual)[1005]<-"intercept"
names(discrection_acrual)[1006]<-"beta1"
names(discrection_acrual)[1007]<-"beta2"
names(discrection_acrual)[1008]<-"beta3"

discretion_acrual <- discrection_acrual %>% 
  mutate(normal_acrual=intercept+beta1*1/asset_lag+beta2*delta_revenue/asset_lag+beta3*ppe/asset_lag, 
         discrectionary_acrual = total_accrual/asset_lag - normal_acrual) %>% select(fyear, FF_48, discrectionary_acrual, tic, roa)

discrection_acrual$SIC <- NULL

discretion_acrual <- merge(discretion_acrual, discretion_acrual, by.x = c("FF_48","fyear"),by.y = c("FF_48","fyear"),all.x = TRUE)
discretion_acrual <- discretion_acrual %>% filter(tic.x!=tic.y) %>% group_by(tic.x, fyear) %>% mutate(t= abs(roa.x-roa.y), dif = abs(discrectionary_acrual.x -discrectionary_acrual.y) ) %>%
  filter(t == min(t))

main_sample <- merge(data, discrection_acrual, by.x = c("tic","fyear"),by.y = c("tic","fyear"),all.x = TRUE)

library(sqldf)
discrection_acrual$sich <- NULL
discrection_acrual$sic <- NULL
discrection_acrual$sic2 <- NULL
discrection_acrual$SIC0 <- NULL
discrection_acrual$datadate <- NULL
discrection_acrual$datafmt <- NULL
discrection_acrual$adrr <- NULL
discrection_acrual$ltcm <- NULL
names(discretion_acrual)[4] <- "tic"

main_sample <- sqldf("select a.* , b.dif
                  from discrection_acrual as a
                  outer left join
                  discretion_acrual as b 
                  on a.tic = b.tic and
                    a.fyear = b.fyear
              ")

### Part 2
## balanced and unbalanced sample
##

balanced_sample <-  main_sample %>% filter( (2001 <= fyear & fyear <= 2003) | (2005 <= fyear & fyear <= 2010) ) %>% 
  mutate(tic=as.character(tic)) %>%  
  group_by(tic)%>% 
  filter(n() == 9)
test <- balanced_sample %>% select(tic, pilot) %>% distinct()
test <- distinct(test) %>% group_by(pilot) %>% summarise(number=n())

unbalanced_sample <-  main_sample %>% filter( (2001 <= fyear & fyear <= 2003) | (2005 <= fyear & fyear <= 2010) ) %>% 
  mutate(tic=as.character(tic))
test <- unbalanced_sample %>% select(tic, pilot) %>% distinct()
test <- distinct(test) %>% group_by(pilot) %>% summarise(number=n())

install.packages("plm")
library(plm)
is.pbalanced(main_sample)




