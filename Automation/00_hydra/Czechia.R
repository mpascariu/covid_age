library(here)
source(here("Automation/00_Functions_automation.R"))

library(tidyverse)
library(googlesheets4)
library(dplyr)
library(xml2)
library(rvest)
library(lubridate)
library(googledrive)


# assigning Drive credentials in the case the script is verified manually  
if (!"email" %in% ls()){
  email <- "e.delfava@gmail.com"
}

# info country and N drive address
ctr <- "Czechia"
dir_n <- "N:/COVerAGE-DB/Automation/Hydra/"

# Drive credentials
drive_auth(email = email)
gs4_auth(email = email)

###########################################
################ CASES ####################
###########################################

NUTS3 <- tibble(
  code = c("CZ010", "CZ020", "CZ031", "CZ032", 
           "CZ041", "CZ042", "CZ051", "CZ052", 
           "CZ053", "CZ063", "CZ064", "CZ071", 
           "CZ072", "CZ080"), 
  name = c("Prague", "Central Bohemia", "South Bohemia", "Plzen", 
           "Karlovy Vary", "Usti nad Labe", "Liberec", "Hradec Kralove", 
           "Pardubice", "Vysocina", "South Moravia", "Olomouc", 
           "Zlin", "Moravia-Silesia")
)
# Getting the data from the Health Ministery website
cases_url <- "https://onemocneni-aktualne.mzcr.cz/api/v2/covid-19/osoby.csv" 

cz_cases <- read.csv(cases_url, 
                   header = TRUE, 
                   col.names = c("Date",
                                 "Age", # exact age
                                 "Sex2", # M=male, Z=female
                                 "NUTS3", #region of hygiene station which provides data, according to NUTS 3
                                 "LAU1", # region on LAU1 structure
                                 "Abroad_inf", # 1=claimed to be infected abroad
                                 "Country_inf" # claimed country of infection
                   )) %>% 
  mutate(Sex = ifelse(Sex2 == "M","m","f"), 
         Date = as.Date(Date, "%Y-%m-%d")) %>% 
  select(-Sex2)

cz_cases %>%  dplyr::pull("Age") %>%  unique()

Ages_All <- c(0,1,seq(5,100,by=5))
DateRange <- range(cz_cases$Date)
Dates_All <- seq(DateRange[1],DateRange[2],by="days")

# extracting NUTS3 from LAU1 when NUTS3 is empty
cz_cases2 <- cz_cases %>% 
  mutate(NUTS3 = ifelse(NUTS3 == "", str_sub(LAU1, 1, 5), NUTS3))

### DATA ON NUTS3 level
cz_cases_region_ss <- 
  cz_cases2 %>% 
  select("NUTS3",  "Date", "Sex", "Age") %>% 
  mutate(Region = as.factor(NUTS3),
         # grouping age
      Age5 = Age - Age %% 5,
      Age = case_when(Age == 0 ~ 0,
                      Age >= 100 ~ 100,
                      TRUE ~ Age5)
  ) %>% 
  ### select
  select(Region, Date, Sex, Age, -Age5) %>% 
  group_by(Region, Date, Age, Sex) %>% 
  summarise(Value = n()) %>% 
  ungroup() %>% 
  ### complete = Turns implicit missing values into explicit missing values => chci 
  ### vektor ttech vek skupin explicitne
  tidyr::complete(Region, 
           Date = Dates_All, 
           Age = Ages_All, 
           Sex, 
           fill = list(Value = 0)) %>% 
  arrange(Region, Sex, Age, Date) %>% 
  group_by(Region, Sex, Age) %>% 
  mutate(Value = cumsum(Value)) %>%  # cumulative!
  ungroup() %>% 
  arrange(Region, Date, Sex, Age) %>% 
  mutate(Country = "Czechia",
         AgeInt = case_when(Age == 0 ~ 1,
                            Age == 1 ~ 4,
                            TRUE ~ 5), # what about the 100+? 
         Metric = "Count", 
         Measure = "Cases",
         Date = paste(sprintf("%02d",day(Date)),    
                      sprintf("%02d",month(Date)),  
                      year(Date),sep="."),
         Code = paste("CZ", Region, Date, sep = "_")) %>% 
  select(Country, 
         Region, 
         Code, 
         Date, 
         Sex, 
         Age, 
         AgeInt, 
         Metric, 
         Measure, 
         Value)%>%
  mutate(Age= as.character(Age))
 

###########################################
################ DEATHS ###################
###########################################

# Getting the data from the Health Ministery website
deaths_url <- "https://onemocneni-aktualne.mzcr.cz/api/v2/covid-19/umrti.csv"

cz_deaths<-read.csv(deaths_url, 
                    header = TRUE, 
                    col.names = c("Date", 
                                  "Age", 
                                  "Sex2", 
                                  "NUTS3", # "kraj" - NUTS 3 administrative unit
                                  "LAU1") # "okres" - LAU 1 administrative unit
) %>% 
  mutate(Sex = ifelse(Sex2 == "M","m","f"),  # no unknown Sex?
         Date = as.Date(Date, "%Y-%m-%d")) %>% 
  select(-Sex2)

cz_deaths %>%  dplyr::pull("Age") %>%  unique()


# we'll use the same Ages_All

DateRangeD <- range(cz_deaths$Date)
Dates_AllD <- seq(DateRange[1],DateRange[2],by="days")

### DATA ON NUTS3 level
cz_deaths_region_ss <- 
  cz_deaths %>% 
  select("NUTS3",  "Date", "Sex", "Age") %>% 
  mutate(Region = as.factor(NUTS3),
         # grouping age
         Age5 = Age - Age %% 5,
         Age = case_when(Age == 0 ~ 0,
                        Age >= 100 ~ 100,
                        TRUE ~ Age5)
  ) %>% 
  select(Region, Date, Sex, Age) %>% 
  group_by(Region, Date, Age, Sex) %>% 
  summarise(Value = n(),
            .groups = "drop") %>% 
  ungroup() %>% 
  tidyr::complete(Region, 
           Date = Dates_AllD, 
           Age = Ages_All, 
           Sex, 
           fill = list(Value = 0)) %>% 
  arrange(Region, Sex, Age, Date) %>% 
  group_by(Region, Sex, Age) %>% 
  mutate(Value = cumsum(Value)) %>%  # cumulative!
  ungroup() %>% 
  arrange(Region, Date, Sex,Age) %>% 
  mutate(AgeInt = 5, # what about the 100+? 
         Metric = "Count", 
         Measure = "Deaths",
         Date = paste(sprintf("%02d",day(Date)),    
                      sprintf("%02d",month(Date)),  
                      year(Date),sep="."),
         Code = paste("CZ", Region, Date, sep = "_"),
         Country = "Czechia") %>% 
  select(Country, 
         Region, 
         Code, 
         Date, 
         Sex, 
         Age, 
         AgeInt, 
         Metric, 
         Measure, 
         Value)%>%
  mutate(Age= as.character(Age))



###########################################
################ VACCINATION ##############
###########################################

vaccine_url <- "https://onemocneni-aktualne.mzcr.cz/api/v2/covid-19/ockovani.csv"

vaccines <- read.csv(vaccine_url, 
                     header = T, 
                     encoding = "UTF-8",
                     col.names = c("Date", 
                                   "vaccine", # Comirnaty, Moderna, AstraZeneca
                                   "NUTS3", 
                                   "Region", # names of the regions
                                   "AgeGroup",
                                   "first_dose", 
                                   "second_dose", 
                                   "n_dose")) %>% 
  mutate(Date = as.Date(Date, "%Y-%m-%d"))


# unfortunatelly only age 80+ is registered, although the 80+ group 
# is the group of first preference in vaccination


#Original Code from Anna Altova 

#cz_vaccines <- vaccines %>% 
 # mutate(Region = as.factor(Region), 
         #NUTS3 = as.factor(NUTS3)) %>% 
  #tidyr::complete(nesting(NUTS3,Region), Date, AgeGroup, vaccine, fill = list(first_dose = 0, 
                                                                       #second_dose = 0, 
                                                                       #n_dose = 0)) %>% 
  #arrange(Date, Region, NUTS3, AgeGroup, vaccine) %>%
  #group_by(Region, NUTS3, AgeGroup, vaccine) %>% 
  #mutate(Vaccination1 = cumsum(first_dose), 
        # Vaccination2 = cumsum(second_dose), 
         #Vaccinations = cumsum(n_dose)) %>% 
  #ungroup() %>% 
  #select(Date, Region, NUTS3, AgeGroup, VaccineType = vaccine, 
         #Vaccination1, Vaccination2, Vaccinations) %>% 
  #pivot_longer(-c(Date, Region, NUTS3, AgeGroup, VaccineType), names_to = "Measure", values_to = "Value") %>% 
  #mutate(AgeGroup = na_if(AgeGroup, "neza?azeno"), 
         #Country = "Czechia") %>% 
  #select(Country, Region, NUTS3, Date, AgeGroup, VaccineType, Measure, Value)


# JD Adaption to database 

cz_vaccines <- vaccines %>% 
  mutate(Region = as.factor(NUTS3)) %>%  
  rename(Age= AgeGroup)%>% 
  tidyr::complete(nesting(Region), Date, Age, fill = list(first_dose = 0, 
                                                          second_dose = 0, 
                                                          n_dose = 0)) %>% 
  arrange(Date, Region, Age) %>%
  group_by(Region, Age) %>% 
  mutate(Vaccination1 = cumsum(first_dose), 
         Vaccination2 = cumsum(second_dose), 
         Vaccinations = cumsum(n_dose)) %>% 
  ungroup() %>% 
  select(Date, Region, Age, 
         Vaccination1, Vaccination2, Vaccinations) %>% 
  pivot_longer(-c(Date, Region, Age), names_to = "Measure", values_to = "Value") %>% 
  mutate(Age= case_when ( 
                  Age ==  "0-17"~"0",
                  Age ==  "18-24"~"18",
                  Age ==  "25-29"~"25",
                  Age ==  "30-34"~"30",
                  Age ==  "35-39"~"35",
                  Age ==  "40-44"~"40",
                  Age ==  "45-49"~"45",
                  Age ==  "50-54"~"50",
                  Age ==  "55-59"~"55",
                  Age ==  "60-64"~"60",
                  Age ==  "65-69"~"65",
                  Age ==  "70-74"~"70",
                  Age ==  "75-79"~"75",
                  Age ==  "80+"~"80",
                  Age == "nezařazeno" ~ "UNK"))%>% # not sure if best way to rename nezařazeno to UNK, returns NA is this step
  mutate(Age = case_when(
    is.na(Age)~ "UNK",
    TRUE~ as.character(Age))) %>%
  mutate(AgeInt = case_when(
    Age == "0" ~ 18L,
    Age == "18" ~ 7L,
    Age == "80" ~ 25L,
    Age == "UNK" ~ NA_integer_,
    TRUE ~ 5L))%>% 
  mutate(
    Country = "Czechia",
    Sex= "b",
    Date = ymd(Date),
    Date = paste(sprintf("%02d",day(Date)),    
                 sprintf("%02d",month(Date)),  
                 year(Date),sep="."),
    Code = paste("CZ", Region, Date, sep = "_"),
    Metric= "Count") %>% 
  select(Country, Region, Code, Date, Sex, 
         Age, AgeInt, Metric, Measure, Value)



#Anna Altova:
# comments: As of today (15 Feb 2021) only selected population groups 
# are allowed to get the vaccine. These are people over 80 y.o., medical 
# professionals (with the priority of those working with the COVID-19+ patients etc), 
# members of the army helping to handle the pandemic, members of the emergency services, 
# other workers in the critical infrastructure for the pandemic.
# Kids <18 should not be vaccinated (although there are some according to the data)


#JD:
#could not combine them because of different class types for Age 
#Did not want to mess with numeric class types for case and death
#Maybe upload/store vaccine cases/ death separately? 


# final spreadsheet 

cz_spreadsheet_region <-
  bind_rows(cz_cases_region_ss, 
            cz_deaths_region_ss,
            cz_vaccines) %>% 
  left_join(NUTS3, by = c("Region" = "code")) %>% 
  select(Country, Region = name, Code, Date, Sex, Age, AgeInt, Metric, Measure, Value) %>% 
  sort_input_data()


#############################################3
# CZ All should be in single ages

Ages_all_single <- 0:100

cz_cases_all_ss <- 
  cz_cases2 %>% 
  select("NUTS3",  "Date", "Sex", "Age") %>% 
  mutate(Region = "All",
         # grouping age
         Age = ifelse(Age >= 100, 100, Age)) %>% 
  ### select
  select(Region, Date, Sex, Age,) %>% 
  group_by(Region, Date, Age, Sex) %>% 
  summarise(Value = n()) %>% 
  ungroup() %>% 
  ### complete = Turns implicit missing values into explicit missing values => chci 
  ### vektor ttech vek skupin explicitne
  tidyr::complete(Region = "All",
           Date = Dates_All, 
           Age = Ages_all_single, 
           Sex, 
           fill = list(Value = 0)) %>% 
  arrange(Region, Sex, Age, Date) %>% 
  group_by(Region, Sex, Age) %>% 
  mutate(Value = cumsum(Value)) %>%  # cumulative!
  ungroup() %>% 
  arrange(Region, Date, Sex, Age) %>% 
  mutate(Country = "Czechia",
         AgeInt = ifelse(Age == 100,5,1), 
         Metric = "Count", 
         Measure = "Cases",
         Date = paste(sprintf("%02d",day(Date)),    
                      sprintf("%02d",month(Date)),  
                      year(Date),sep="."),
         Code = paste("CZ", Date, sep = "_")) %>% 
  select(Country, 
         Region, 
         Code, 
         Date, 
         Sex, 
         Age, 
         AgeInt, 
         Metric, 
         Measure, 
         Value)

cz_deaths_all_ss <- 
  cz_deaths %>% 
  select("NUTS3",  "Date", "Sex", "Age") %>% 
  mutate(Region = "All",
         # grouping age
         Age = ifelse(Age >= 100, 100, Age)) %>% 
  select(Region, Date, Sex, Age) %>% 
  group_by(Region, Date, Age, Sex) %>% 
  summarise(Value = n(),
            .groups = "drop") %>% 
  ungroup() %>% 
  tidyr::complete(Region = "All",
           Date = Dates_AllD, 
           Age = Ages_all_single, 
           Sex, 
           fill = list(Value = 0)) %>% 
  arrange(Region, Sex, Age, Date) %>% 
  group_by(Region, Sex, Age) %>% 
  mutate(Value = cumsum(Value)) %>%  # cumulative!
  ungroup() %>% 
  arrange(Region, Date, Sex, Age) %>% 
  mutate(AgeInt = ifelse(Age == 100,5,1), 
         Metric = "Count", 
         Measure = "Deaths",
         Date = paste(sprintf("%02d",day(Date)),    
                      sprintf("%02d",month(Date)),  
                      year(Date),sep="."),
         Code = paste("CZ", Date, sep = "_"),
         Country = "Czechia") %>% 
  select(Country, 
         Region, 
         Code, 
         Date, 
         Sex, 
         Age, 
         AgeInt, 
         Metric, 
         Measure, 
         Value)


cz_spreadsheet_all <-
   bind_rows(cz_cases_all_ss,
             cz_deaths_all_ss) %>% 
  select(Country, 
         Region, 
         Code, 
         Date, 
         Sex, 
         Age, 
         AgeInt, 
         Metric, 
         Measure, 
         Value) %>% 
  arrange(dmy(Date), Sex, Measure, Age) %>% 
  mutate(Age = as.character(Age))

out <- bind_rows(cz_spreadsheet_all, cz_spreadsheet_region)

unique(out$Region)
###########################
#### Saving data in N: ####
###########################

write_rds(out, paste0(dir_n, ctr, ".rds"))
log_update(pp = ctr, N = nrow(out))

#### uploading metadata to N Drive ####

data_source_c <- paste0(dir_n, "Data_sources/", ctr, "/deaths_",today(), ".csv")
data_source_d <- paste0(dir_n, "Data_sources/", ctr, "/cases_",today(), ".csv")
data_source_v <- paste0(dir_n, "Data_sources/", ctr, "/vaccine_",today(), ".csv")

download.file(cases_url, destfile = data_source_c)
download.file(deaths_url, destfile = data_source_d)
download.file(vaccine_url, destfile = data_source_v)


data_source <- c(data_source_c, data_source_d,data_source_v )

zipname <- paste0(dir_n, 
                  "Data_sources/", 
                  ctr,
                  "/", 
                  ctr,
                  "_data_",
                  today(), 
                  ".zip")

zipr(zipname, 
     data_source, 
     recurse = TRUE, 
     compression_level = 9,
     include_directories = TRUE)

# clean up file chaff
file.remove(data_source)

