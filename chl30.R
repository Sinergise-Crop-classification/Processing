# Load required packages
library(arrow) 
library(geoarrow) 
library(sf) 
library(tidyverse) 
library(readr)
library(dplyr) 
library(data.table) 
library('jsonlite') 

# R session options
options("timeout" = 600) 
options("warn" = -1)
# options(future.globals.maxSize= 6*1024^3) 


############# Signal data processing

## Calculate CHL index (B07/B05) - 1
izracunaj_chl <- function(tabela, suffix = "") {
  b7_col <- paste0("B07",  suffix)
  b5_col <- paste0("B05",  suffix)
  chl_col  <- paste0("CHL",  suffix)
  
  tabela = tabela[tabela[[b5_col]] != 0, ] # Avoid division by zero
  
  # Check if required bands (B07, B05) are present
  if (all(c(b7_col, b5_col) %in% names(tabela))) {
    tabela[[chl_col]] <- tabela[[b7_col]] / tabela[[b5_col]] - 1
  } else {
    warning(paste("Missing columns", b7_col, "or", b5_col))
  }
  tabela
}


## Read all "signal" Parquet files, calculate CHL and cumulative NDVI/CHL.
processAllSignals <- function(rootFolderPath) {
  # Init results list
  results_list <- list()
  
  # List main folders
  folders <- list.files(path = rootFolderPath, full.names = TRUE, recursive = FALSE, include.dirs = TRUE)
  folders <- folders[file.info(folders)$isdir]
  
  # Loop through main folders
  for (mainFolder in folders) {
    # Find "signal" subfolders
    allSubfolders <- list.files(path = mainFolder, full.names = TRUE, recursive = TRUE, include.dirs = TRUE)
    # Filter for "signal" subfolders
    signalFolder <- grep("signal$", allSubfolders, value = TRUE)
    
    # List Parquet files in "signal" folder
    signalFiles <- list.files(signalFolder, recursive = TRUE, full.names = TRUE, pattern = "\\.parquet$")
    # Loop through Parquet files
    for (file  in signalFiles) {
      # Read Parquet, convert to data.table
      # Calculate CHL index
      sig <- read_parquet(file) %>%  as.data.table() %>%
        izracunaj_chl("") %>%
        rename(datum = TIMESTAMP) %>%
        mutate(
          POLY_ID = as.character(POLY_ID),
          datum   = as.Date(datum),
          dy      = yday(datum),
          across(c(NDVI, CHL), as.numeric)
        )
      
      # Process per POLY_ID
      for(poly_id in unique(sig$POLY_ID)) {
        # Filter by POLY_ID
        pol <- sig %>% filter(POLY_ID == poly_id)
        # Filter by cloud cover (CLM < 0.2)
        pol_filter <- pol %>% filter(CLM < 0.2)
        
        if(length(unique(pol_filter$dy)) >= 4) {
          # Smooth NDVI and predict sum for May-July 2022 period
          ss10_ndvi <- smooth.spline(pol_filter$dy, pol_filter$NDVI, df= min(10, nrow(pol_filter) - 1))
          p365_ndvi = predict(ss10_ndvi,yday(as.Date("01/05/2022", "%d/%m/%y")) : yday(as.Date("31/07/2022", "%d/%m/%y")))
          cum_ndvi = sum(p365_ndvi$y)
          
          # Smooth CHL and predict sum for May-July 2022 period
          ss10_chl <- smooth.spline(pol_filter$dy, pol_filter$CHL,  df= min(10, nrow(pol_filter) - 1))
          p365_chl = predict(ss10_chl,yday(as.Date("01/05/2022", "%d/%m/%y")) : yday(as.Date("31/07/2022", "%d/%m/%y")))
          cum_chl = sum(p365_chl$y)
        }else{
          cum_ndvi = NA
          cum_chl = NA
        }
        
        
        # Add polygon results to list
        results_list[[length(results_list)+1]] <- data.table(
          POLY_ID = poly_id,
          cum_ndvi = cum_ndvi,
          cum_chl = cum_chl
        )
      }
    }
  }
  # Combine all results
  final_dt <- rbindlist(results_list)
  return(final_dt)
}





############# Geometry and GDD processing

## Fetch meteorological data from dailymeteo.com API.
get_data <- function(var, agg_level, time_scale, from=NULL, to=NULL, time=NULL, lat, lon) {
  # Check parameters
  if (is.null(var)) {stop("var parameter is missing")}
  if (is.null(agg_level)) {stop("agg_level parameter is missing")}
  # if (is.null(time_scale)) {stop("time_scale parameter is missing")}
  if (is.null(time) & (is.null(from) | is.null(to))) {stop("time or from/to parameters are missing")}
  if (is.null(lat) | is.null(lon)) {stop("lat/lon parameters are missing")}
  # Construct the URL for the dailymeteo.com API endpoint
  url <- "https://api.dailymeteo.com/meteo/v2/pq/"
  # Set query parameters
  query <- list(
    var = var,
    agg_level = agg_level,
    time_scale = time_scale,
    lat = lat,
    lon = lon,
    api_key="jzyrpmazw6k0weg6ey9ww20j8")
  if (is.null(time)) {
    query <- append(query, list(from=from, to=to))
  } else {
    query <- append(query, list(time=time))
  }
  # Construct the query string
  query_string <- paste0(names(query), "=", unlist(query), collapse = "&")
  full_url <- paste0(url, "?", query_string)
  # Make GET request to the API
  response <- url(full_url)
  # Check if request was successful
  if (inherits(response, "error")) {
    # Print error message if request was not successful
    print("Error: Failed to retrieve data from the API.")
    return(NULL)
  } else {
    # Read the response and parse JSON
    response_content <- readLines(response, warn = FALSE)
    data <- fromJSON(response_content)
    data <- data[, c("timestamp", "value")]
    # Close the connection
    close(response)
    # Convert data to data frame
    if (length(data) > 0) {
      # df <- data.frame(date = as.character(names(unlist(data))),
      #                  value = unlist(data))
      return(data)
    } else {
      print("Error: No data returned from the API.")
      return(NULL)
    }
  }
}

## Calculate GDD sum for a location (lat, lon) for May-July 2022.
calculate_gdd <- function(lat, lon) {
  # Get Tmin data
  tmin_data <- get_data(var = "tmin", agg_level = "agg", time_scale = "day",
                        from = "2022-05-01", to = "2022-07-31", 
                        time = NULL, lat = lat, lon = lon)
  
  # Get Tmax data
  tmax_data <- get_data(var = "tmax", agg_level = "agg", time_scale = "day",
                        from = "2022-05-01", to = "2022-07-31", 
                        time = NULL, lat = lat, lon = lon)
  
  # Combine Tmin/Tmax, sort, calculate GDD
  df <- data.frame(
    times = tmin_data$timestamp,
    tmin = tmin_data$value,
    tmax = tmax_data$value
  ) %>% 
    arrange(times) %>% 
    mutate(
      # Calculate GDD: (Tavg - 10), min 0
      GDD = pmax((tmax + tmin)/2 - 10, 0)
    )
  
  return(sum(df$GDD, na.rm = TRUE))
  
}

## Process "geometry" Parquet files: read geometries, extract centroids.
processAllGeometry <- function(rootFolderPath) {

  
  # List main folders
  rootFolder <- normalizePath(rootFolderPath)
  folders <- list.files(path = rootFolder, full.names = TRUE, recursive = FALSE, include.dirs = TRUE)
  folders <- folders[file.info(folders)$isdir]
  
  # Init results list
  results <- list()
  
  # Loop through main folders
  for (mainFolder in folders) {
    folderName <- tolower(basename(mainFolder))
    
    # Find "geometry" subfolder
    allSubfolders <- list.files(path = mainFolder, full.names = TRUE, recursive = TRUE, include.dirs = TRUE)
    geometryFolder <- grep("geometry$", allSubfolders, value = TRUE)
    # List Parquet files in "geometry" folder
    geometryFiles <- list.files(geometryFolder, recursive = TRUE, full.names = TRUE, pattern = "\\.parquet$")
   
    # Read first Parquet geometry file
    geom_data <- arrow::read_parquet(geometryFiles[1])
    # Extract CRS from WKT
    geom_data$crs = str_extract(geom_data$pixelated_geometry, "(?<=SRID=)\\d+") %>% as.integer()
    # Uklanjanje SRID prefiksa iz WKT stringa geometrije
    geom_data$pixelated_geometry = str_remove(geom_data$pixelated_geometry, "^SRID=\\d+;")
    # Inicijalizacija data.frame-a sa prvim fajlom
    df = geom_data
    
    # Dodavanje podataka iz preostalih Parquet fajlova u isti data.frame
    # Ovo spaja sve geometrije iz JEDNOG glavnog foldera
    for (i in 2:length(geometryFiles)) {
      geom_data <- arrow::read_parquet(geometryFiles[i])
      geom_data$crs = str_extract(geom_data$pixelated_geometry, "(?<=SRID=)\\d+") %>% as.integer()
      geom_data$pixelated_geometry = str_remove(geom_data$pixelated_geometry, "^SRID=\\d+;")
      df = rbind(df, geom_data)
    }
    
    # Procesiranje geometrija za svaki jedinstveni CRS pronađen u podacima
    for (i in unique(df$crs) ){
      sf <- df %>%
        filter(crs == i) %>%
        # Kreiranje 'sf' (simple features) objekta iz WKT geometrije, specificirajući originalni CRS
        st_as_sf(wkt = "pixelated_geometry", crs = i) %>%
        st_transform(4326) %>% # Transformacija geometrije u WGS84 (EPSG:4326 - lat/lon)
        mutate(
          centroid = st_centroid(.), # Izračunavanje centroida poligona 
          lon = st_coordinates(centroid)[, 1], # Ekstrakcija longitude koordinate centroida
          lat = st_coordinates(centroid)[, 2], # Ekstrakcija latitude koordinate centroida
        ) %>%
        st_drop_geometry() %>%
        select(POLY_ID,  lat, lon)
      
      # Dodavanje obrađenih 'sf' objekata u listu rezultata
      results[[paste0(folderName, "_", i)]] <- sf
    }
  }
  bind_rows(results)  # Vraća listu 'sf' objekata
}

####### Funkcija za paralelno racunanje GDD


library(parallel)

# Паралелна верзија функције
calculate_gdd_parallel <- function(lat, lon) {
  # Број језгара (подесите према вашим потребама)
  n_cores <- detectCores() - 1
  
  # Направи кластер
  cl <- makeCluster(n_cores)
  
  # Експортуј потребне функције и пакете на кластер
  clusterExport(cl, c("calculate_gdd", "get_data", "lat", "lon"))
  clusterEvalQ(cl, {
    library(jsonlite)
    library(dplyr)
  })
  
  # Подели податке на партиције
  chunks <- split(1:length(lat), cut(1:length(lat), n_cores))
  
  # Паралелно израчунавање
  results <- clusterMap(
    cl = cl,
    fun = function(i) calculate_gdd(lat[i], lon[i]),
    i = 1:length(lat)
  )
  
  # Заустави кластер
  stopCluster(cl)
  
  # Конвертуј резултате у вектор
  unlist(results)
}


#Sys.time()
#sig = processAllSignals()
#Sys.time()
#geo = processAllGeometry()
#all = left_join(sig, geo, by = POLY_ID)


csv_file_path = "C:/Users/gilab/OPENEM/field_boundaries_crop_classification.csv"

# Učitavanje klasifikacije useva iz CSV fajla
data_from_csv <- read_csv(csv_file_path, show_col_types = FALSE) %>%
  mutate(
    field_boundary_id = as.integer(field_boundary_id),
    classification = as.character(classification)
  )


rootFolderPath="C:/Users/gilab/OPENEM" 

folders <- list.files(path = rootFolderPath, full.names = TRUE, recursive = FALSE, include.dirs = TRUE)
folders <- folders[file.info(folders)$isdir]
  
# for (mainFolder in folders[30]) {
mainFolder = "C:/Users/gilab/OPENEM/PI"
    folder_name <- basename("C:/Users/gilab/OPENEM/PI")
    message("Obradjuje se folder: ", folder_name)
    
    sig = processAllSignals(rootFolderPath = mainFolder)
    geo = processAllGeometry(rootFolderPath = mainFolder)
    # lat=geo$lat
    # lon=geo$lon
    # geo$GDD = calculate_gdd_parallel(lat, lon)
    
    sig <- sig %>% mutate(POLY_ID = as.integer(POLY_ID))
    geo <- geo %>% mutate(POLY_ID = as.integer(POLY_ID))
    
    all = left_join(sig, geo, by = "POLY_ID")
    
    # Konverzija POLY_ID u karakter i spajanje sa podacima o klasifikaciji useva
    all <-   left_join(all, data_from_csv, by = c("POLY_ID" = "field_boundary_id"))
    
    
    csv_path <- file.path(rootFolderPath, paste0(folder_name, ".csv"))
    write.csv(all, csv_path, row.names = FALSE)
    
    message(paste("Folder", folder_name, "završen. CSV sačuvan u:", csv_path))    
  # }
