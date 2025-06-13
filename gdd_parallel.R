library(terra)
library(sf)

setwd("C:/Users/gilab/OPENEM/results/meteo")


# Učitavanje podataka
tmax <- rast(list.files(pattern = "tmax.*\\.tif$"))
tmin <- rast(list.files(pattern = "tmin.*\\.tif$"))

gdd <- (tmax + tmin) / 20 - 10  # Oduzimamo baznu temperaturu
gdd[gdd < 0] <- 0   

# Kumulativna suma (najbrže)
cumulative_gdd <- sum(gdd)      # Brže od app(gdd, sum)

# Snimanje (opcionalno)
writeRaster(cumulative_gdd, "cumulative_gdd.tif", overwrite = TRUE)


jv =  read.csv("C:/Users/gilab/OPENEM/results/JV.csv")

jv = jv[!is.na(jv$classification), ]
jv = jv[!is.na(jv$cum_ndvi), ]

jv = st_as_sf(jv, coords = c("lon","lat"), crs=4326)
jv = st_transform(jv, crs(gdd))

egdd = terra::extract(cumulative_gdd, jv)
jv$cum_gdd =  egdd$sum

jv = st_transform(jv, crs=4326)

st_write(jv, "C:/Users/gilab/OPENEM/jv.gpkg")

setwd("C:/Users/gilab/OPENEM/results/")

# Pronađi sve CSV fajlove u folderu
csv_files <- list.files(pattern = "\\.csv$", full.names = TRUE)

# Petlja kroz sve CSV fajlove
for (file in csv_files) {
  
  # Učitaj CSV
  jv <- read.csv(file)
  
  # Filtriranje NA vrijednosti
  # jv <- jv[!is.na(jv$classification) & !is.na(jv$cum_ndvi), ]
  
  jv <- jv[ !is.na(jv$cum_ndvi), ]
  
  # Pretvori u sf objekt
  jv_sf <- st_as_sf(jv, coords = c("lon", "lat"), crs = 4326)
  jv_sf <- st_transform(jv_sf, crs(cumulative_gdd))
  
  # Ekstrakcija GDD vrijednosti
  egdd <- terra::extract(cumulative_gdd, jv_sf)
  jv_sf$cum_gdd <- egdd[, 2]  # Pretpostavka: 'sum' je u drugom stupcu
  
  # Vrati u WGS84 (EPSG:4326)
  jv_sf <- st_transform(jv_sf, crs = 4326)
  
  # Kreiraj ime izlaznog fajla (isti kao CSV, ali .gpkg umjesto .csv)
  output_name <- sub("\\.csv$", ".gpkg", file)
  
  # Spremi u GPKG
  st_write(jv_sf, output_name, delete_dsn = TRUE)
  
  # Statusna poruka
  message("Obradjen fajl: ", basename(file), " -> ", basename(output_name))
}



# List all GPKG files in the directory
gpkg_files <- list.files("C:/Users/gilab/OPENEM/results/", pattern = "\\.gpkg$", full.names = TRUE)

# Read and merge all GPKGs into a single sf object
all <- do.call(rbind, lapply(gpkg_files, st_read))

# Check the output
head(all)
class(all)  # Should be "sf" "data.frame"

# Save merged file (optional)
st_write(all, "C:/Users/gilab/OPENEM/all.gpkg", delete_dsn = TRUE)


