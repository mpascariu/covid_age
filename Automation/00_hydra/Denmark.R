library(here)
source(here("Automation/00_Functions_automation.R"))

# assigning Drive credentials in the case the script is verified manually  
if (!"email" %in% ls()){
  email <- "kikepaila@gmail.com"
}

# info country and N drive address
ctr <- "Denmark"
dir_n <- "N:/COVerAGE-DB/Automation/Hydra/"

# Drive credentials
drive_auth(email = email)
gs4_auth(email = email)

at_rubric <- get_input_rubric() %>% filter(Short == "DK")
ss_i   <- at_rubric %>% dplyr::pull(Sheet)
ss_db  <- at_rubric %>% dplyr::pull(Source)


# reading data from Denmark stored in N drive
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
db_n <- read_rds(paste0(dir_n, ctr, ".rds")) %>% 
  mutate(Date = dmy(Date))

# identifying dates already captured in each measure
dates_cases_n <- db_n %>% 
  filter(Measure == "Cases") %>% 
  dplyr::pull(Date) %>% 
  unique() %>% 
  sort()

dates_deaths_n <- db_n %>% 
  filter(Measure == "Deaths") %>% 
  dplyr::pull(Date) %>% 
  unique() %>% 
  sort()

dates_vacc_n <- db_n %>% 
  filter(Measure %in% c("Vaccination", "Vaccination1", "Vaccination2")) %>% 
  dplyr::pull(Date) %>% 
  unique() %>% 
  sort()

# reading new deaths from Drive
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
db_drive <- get_country_inputDB("DK")

db_drive_deaths <- db_drive %>% 
  mutate(Date = dmy(Date)) %>% 
  select(-Short) %>% 
  filter(Measure == "Deaths")

# filtering deaths not included yet
db_deaths <- db_drive_deaths %>% 
  filter(!Date %in% dates_deaths_n)
  
# reading new cases from the web
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# detecting the link to the xlsx file in the website
# this is a more stable method than using the xpath
m_url_c <- "https://covid19.ssi.dk/overvagningsdata/download-fil-med-overvaagningdata"

# capture all links with excel files
links_c <- scraplinks(m_url_c) %>% 
  filter(str_detect(link, "zip")) %>% 
  separate(link, c("a", "b", "c", "d", "e", "Date", "g", "h")) %>% 
  mutate(Date = dmy(Date)) %>% 
  select(Date, url) %>% 
  drop_na()

links_new_cases <- links_c %>% 
  filter(!Date %in% dates_cases_n)

# downloading new cases data and loading it
dim(links_new_cases)[1] > 0
db_cases <- tibble()
if(dim(links_new_cases)[1] > 0){
  # i <- 1
  for(i in 1:dim(links_new_cases)[1]){
    
    date_c <- links_new_cases[i, 1] %>% dplyr::pull()
    data_source_c <- paste0(dir_n, "Data_sources/", 
                            ctr, "/", ctr, "_data_", as.character(date_c), ".zip")
    
    
    download.file(as.character(links_new_cases[i, 2]), destfile = data_source_c, mode = "wb")
    db_t <- read_csv2(unz(data_source_c, "Cases_by_age.csv"))
    db_sex <- read_csv2(unz(data_source_c, "Cases_by_sex.csv"))
    
    db_t2 <- db_t %>% 
      select(Age = Aldersgruppe, Value = Antal_testede) %>% 
      mutate(Measure = "Tests",
             Sex = "b")
    
    db_sex2 <- 
      db_sex %>% 
      rename(Age = 1,
             f = 2,
             m = 3,
             b = 4) %>% 
      gather(-1, key = "Sex", value = "Values") %>% 
      separate(Values, c("Value", "trash"), sep = " ") %>% 
      mutate(Value = as.numeric(str_replace(Value, "\\.", "")),
             Measure = "Cases") %>% 
      select(-trash)
    
    db_c <- bind_rows(db_t2, db_sex2) %>% 
      separate(Age, c("Age", "trash"), sep = "-") %>% 
      mutate(Age = case_when(Age == "90+" ~ "90",
                             Age == "I alt" ~ "TOT",
                             TRUE ~ Age),
             Date = date_c) %>% 
      select(-trash)
    
      db_cases <- db_cases %>% 
      bind_rows(db_c)
    
  }
}

# reading new vaccines from the web
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
m_url_v <- "https://covid19.ssi.dk/overvagningsdata/download-fil-med-vaccinationsdata"

links_v <- scraplinks(m_url_v) %>% 
  filter(str_detect(link, "zip")) %>% 
  separate(link, c("a", "b", "c", "d", "e", "f", "g", "h")) %>% 
  mutate(Date = make_date(y = h, m = g, d = f)) %>% 
  select(Date, url) %>% 
  drop_na() 

links_new_vacc <- links_v %>% 
  filter(!Date %in% dates_vacc_n)

# downloading new vaccine data and loading it
dim(links_new_vacc)[1] > 0
db_vcc <- tibble()
if(dim(links_new_vacc)[1] > 0){
  for(i in 1:dim(links_new_vacc)[1]){
    
    date_v <- links_new_vacc[i, 1] %>% dplyr::pull()
    data_source_v <- paste0(dir_n, "Data_sources/", 
                            ctr, "/", ctr, "_vaccines_", as.character(date_v), ".zip")
    download.file(as.character(links_new_vacc[i, 2]), destfile = data_source_v, mode = "wb")
    
    try(db_v <- read_csv(unz(data_source_v, "Vaccine_DB/Vaccinationer_region_aldgrp_koen.csv")))
    try(db_v <- read_csv(unz(data_source_v, "ArcGIS_dashboards_data/Vaccine_DB/Vaccinationer_region_aldgrp_koen.csv")))
  
    db_v2 <- db_v %>% 
      rename(Age = 2,
             Sex = sex,
             Vaccination1 = 4,
             Vaccination2 = 5) %>% 
      gather(Vaccination1, Vaccination2, key = Measure, value = Value) %>% 
      group_by(Age, Sex, Measure) %>% 
      summarise(Value = sum(Value)) %>% 
      ungroup() %>%
      mutate(Sex = recode(Sex,
                          "K" = "f",
                          "M" = "m"),
             Age = str_sub(Age, 1, 2),
             Age = case_when(Age == "0-" ~ "0",
                             is.na(Age) ~ "UNK",
                             TRUE ~ Age),
             Date = date_v)
    
    db_vcc <- db_vcc %>% 
      bind_rows(db_v2)
    
  }
}

db_cases_vcc <- tibble()

if(dim(links_new_vacc)[1] > 0 | dim(links_new_cases)[1] > 0){
  db_cases_vcc <- 
    bind_rows(db_cases, db_vcc) %>% 
    mutate(Date = ddmmyyyy(Date),
           Country = "Denmark",
           Code = paste0("DK", Date),
           Region = "All",
           AgeInt = case_when(Age == "90" ~ 15L, 
                              Age == "TOT" ~ NA_integer_,
                              Age == "UNK" ~ NA_integer_,
                              TRUE ~ 10L),
           Metric = "Count") 
}

out <- 
  bind_rows(db_n, db_deaths) %>% 
  mutate(Date = ddmmyyyy(Date)) %>% 
  bind_rows(db_cases_vcc) %>% 
  sort_input_data() 

###########################
#### Saving data in N: ####
###########################
write_rds(out, paste0(dir_n, ctr, ".rds"))
log_update(pp = ctr, N = nrow(out))
