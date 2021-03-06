# source("https://raw.githubusercontent.com/timriffe/covid_age/master/Automation/00_Functions_automation.R")
library(here)
source(here("Automation/00_Functions_automation.R"))

library(RSelenium)
library(rvest)

email <- "kikepaila@gmail.com"

ctr <- "Brazil"

# Drive credentials
drive_auth(email = email)
gs4_auth(email = email)

# TR: pull urls from rubric instead 
rubric_i <- get_input_rubric() %>% filter(Short == "BR_all")
ss_i     <- rubric_i %>% dplyr::pull(Sheet)
ss_db    <- rubric_i %>% dplyr::pull(Source)

db_drive <- get_country_inputDB("BR_all")

db_drive2 <- db_drive %>% 
  mutate(date_f = dmy(Date))

last_date_drive <- max(db_drive2$date_f)

# donloading file
url <- "https://transparencia.registrocivil.org.br/dados-covid-download"

system("taskkill /im java.exe /f", intern=FALSE, ignore.stdout=FALSE)
driver <- RSelenium::rsDriver(browser = "chrome",
                              port = 4601L,
                              chromever =
                                system2(command = "wmic",
                                        args = 'datafile where name="C:\\\\Program Files (x86)\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe" get Version /value',
                                        stdout = TRUE,
                                        stderr = TRUE) %>%
                                stringr::str_extract(pattern = "(?<=Version=)\\d+\\.\\d+\\.\\d+\\.") %>%
                                magrittr::extract(!is.na(.)) %>%
                                stringr::str_replace_all(pattern = "\\.",
                                                         replacement = "\\\\.") %>%
                                paste0("^",  .) %>%
                                stringr::str_subset(string =
                                                      binman::list_versions(appname = "chromedriver") %>%
                                                      dplyr::last()) %>% 
                                as.numeric_version() %>%
                                max() %>%
                                as.character())

remote_driver <- driver[["client"]] 
remote_driver$navigate(url)

Sys.sleep(30)

# read date
date_lb <- remote_driver$findElement(using = "xpath", '/html/body/div[1]/div[2]/div/div/div[2]/div/div[2]/div[1]/div[2]/p/p[1]')
date_lb2 <- date_lb$findElement(using='css selector',"body")$getElementText()[[1]]
date_f <- str_sub(date_lb2, -10) %>% dmy()

if (date_f > last_date_drive){
  
  # locate button and click it
  button <- remote_driver$findElement(using = "xpath", '//*[@id="app"]/div[2]/div/div/div[2]/div/div[2]/div[1]/div[2]/a')
  button$clickElement()
  
  Sys.sleep(3)
  
  db <- read_csv("C:/Users/kikep/Downloads/obitos-2021.csv")
  
  db2 <- 
    db %>% 
    select(reg = uf,
           Cause = tipo_doenca,
           Age = faixa_etaria,
           Sex = sexo,
           Value = total)
  
  db3 <- 
    db2 %>% 
    filter(Cause == "COVID") %>% 
    select(reg, Age, Sex, Value) %>% 
    group_by(reg, Age, Sex) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    separate(Age, c("Age", "trash"), sep = " - ") %>% 
    mutate(Age = case_when(Age == "< 9" ~ "0",
                           Age == "> 100" ~ "100",
                           Age == "N/I" ~ "UNK",
                           TRUE ~ Age),
           Sex = case_when(Sex == "F" ~ "f",
                           Sex == "M" ~ "m",
                           TRUE ~ "o")) %>% 
    select(-trash)
  
  regs <- unique(db3$reg)
  ages <- db3 %>% arrange(suppressWarnings(as.integer(Age))) %>% dplyr::pull(Age) %>% unique()
  sexs <- unique(db3$Sex)
  
  db4 <- 
    db3 %>% 
    tidyr::complete(reg = regs, Age = ages, Sex = sexs, fill = list(Value = 0))
  
  db_sex <- 
    db4 %>% 
    group_by(reg, Age) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Sex = "b") %>% 
    filter(Age != "UNK")
  
  db_age <- 
    db4 %>% 
    group_by(reg, Sex) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Age = "TOT") %>% 
    filter(Sex != "o")
  
  db_sex_age <- 
    db4 %>% 
    group_by(reg) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Age = "TOT",
           Sex = "b")
  
  db5 <- 
    db4 %>% 
    filter(Sex != "o" & Age != "UNK") %>% 
    bind_rows(db_age, db_sex, db_sex_age) %>% 
    mutate(Region = case_when(reg == 'AC' ~ 'Acre',
                              reg == 'AL' ~ 'Alagoas',
                              reg == 'AP' ~ 'Amapa',
                              reg == 'AM' ~ 'Amazonas',
                              reg == 'BA' ~ 'Bahia',
                              reg == 'CE' ~ 'Ceara',
                              reg == 'DF' ~ 'Distrito Federal',
                              reg == 'ES' ~ 'Espirito Santo',
                              reg == 'GO' ~ 'Goias',
                              reg == 'MA' ~ 'Maranhao',
                              reg == 'MT' ~ 'Mato Grosso',
                              reg == 'MS' ~ 'Mato Grosso do Sul',
                              reg == 'MG' ~ 'Minas Gerais',
                              reg == 'PA' ~ 'Para',
                              reg == 'PB' ~ 'Paraiba',
                              reg == 'PR' ~ 'Parana',
                              reg == 'PE' ~ 'Pernambuco',
                              reg == 'PI' ~ 'Piaui',
                              reg == 'RJ' ~ 'Rio de Janeiro',
                              reg == 'RN' ~ 'Rio Grande do Norte',
                              reg == 'RS' ~ 'Rio Grande do Sul',
                              reg == 'RO' ~ 'Rondonia',
                              reg == 'RR' ~ 'Roraima',
                              reg == 'SC' ~ 'Santa Catarina',
                              reg == 'SP' ~ 'Sao Paulo',
                              reg == 'SE' ~ 'Sergipe',
                              reg == 'TO' ~ 'Tocantins',
                              TRUE ~ "other")) 
  
  
  db6 <- 
    db5 %>%
    group_by(Age, Sex) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Region = "All",
           reg = "")
  
  unique(db6$Age)
  
  out <- 
    bind_rows(db6, db5) %>%   
    mutate(Country = "Brazil",
           date_f = date_f,
           Date = paste(sprintf("%02d",day(date_f)),
                        sprintf("%02d",month(date_f)),
                        year(date_f),
                        sep="."),
           Code = paste0("BR_TRC_", reg, Date),
           AgeInt = case_when(Age == "100" ~ 5,
                              Age == "TOT" ~ NA_real_,
                              TRUE ~ 10),
           Metric = "Count",
           Measure = "Deaths") %>% 
    sort_input_data()
  
  unique(out$Region)
  
  ############################################
  #### uploading database to Google Drive ####
  ############################################
  
  sheet_append(out,
               ss = ss_i,
               sheet = "database")
  log_update(pp = ctr, N = nrow(out))
  
  
  sheet_name <- paste0(ctr, "_all_deaths_", today())
  meta <- drive_create(sheet_name,
                       path = ss_db, 
                       type = "spreadsheet",
                       overwrite = TRUE)
  
  write_sheet(db,
              ss = meta$id,
              sheet = "data")
  
  sheet_delete(meta$id, "Sheet1")
  
  file.remove("C:/Users/kikep/Downloads/obitos-2021.csv")
  
  
} else if (date_f == last_date_drive) {
  cat(paste0("no new updates so far, last date: ", date_f))
  log_update(pp = ctr, N = 0)
}


