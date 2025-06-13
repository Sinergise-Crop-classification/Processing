# Učitavanje potrebnih biblioteka
library(sf)
library(dplyr)
library(ggplot2)
library(viridisLite)

# Definisanje radnog direktorijuma
root <- "C:/Users/Sole/Desktop/0_processing"

# Dohvatanje svih neposrednih podfoldera (svaki folder predstavlja jednu državu)
country_folders <- list.dirs(root, recursive = FALSE, full.names = TRUE)

# Petlja kroz svaki folder/drzavu
for (country_folder in country_folders) {
  # Izdvajanje imena države iz putanje
  country_name <- basename(country_folder)
  
  # Pronalaženje GeoPackage fajla sa finalnim podacima o parcelama
  input_gpkg <- list.files(
    path       = country_folder,
    pattern    = "^final_points_.*\\.gpkg$",
    full.names = TRUE
  )
  # Definisanje putanje za izlazni GeoPackage fajl sa rezultatima
  output_gpkg <- file.path(country_folder, paste0("perf_", country_name, ".gpkg"))

  message("\n##### Pocetak obrade za: ", country_name, " #####")
  
  # Učitavanje podataka
  country_data <- st_read(input_gpkg, quiet = TRUE)
  
  # Čišćenje podataka uklanjanje zapisa sa NA vrednostima u ključnim kolonama
  country_data <- country_data %>%
    filter(
      !is.na(cum_ndvi) &
        !is.na(cum_chl) &
        !is.na(cum_gdd) &
        !is.na(classification) &
        !is.na(field_boundary_id)
    )
  
  message("Racunanje performansi...")
  
  # Analiza klasifikacija: broj polja po klasifikacionoj grupi
  summary_df <- country_data %>%
    st_drop_geometry() %>%
    count(classification, name = "broj_parcela") %>%
    arrange(desc(broj_parcela))
  
  # Z-score normalizacija kumulativnih vrednosti unutar svake klase
  all_normalized <- country_data %>%
    st_drop_geometry() %>%
    group_by(classification) %>%
    mutate(
      z_ndvi = (cum_ndvi - mean(cum_ndvi, na.rm = TRUE)) / sd(cum_ndvi, na.rm = TRUE),
      z_chl = (cum_chl - mean(cum_chl, na.rm = TRUE)) / sd(cum_chl, na.rm = TRUE),
      z_gdd = (cum_gdd - mean(cum_gdd, na.rm = TRUE)) / sd(cum_gdd, na.rm = TRUE)
    ) %>%
    # Postavljanje normalizovane vrednosti na 0 za grupe sa jednim poljem 
    mutate(across(starts_with("z_"), ~ ifelse(is.na(.), 0, .)))%>%
    ungroup()
  
  # Kompozitni indeks: NDVI 80%, CHL 10%, GDD 10%
  all_weighted <- all_normalized %>%
    mutate(
      composite_index = (z_ndvi * 0.8) + (z_chl * 0.1) + (z_gdd * 0.1))
  
  # Rangiranje unutar klasifikacija: percentil i rang
  all_ranked <- all_weighted %>%
    group_by(classification) %>%
    mutate(
      percentile = round(percent_rank(composite_index) * 100, 1),
      rank = dense_rank(desc(composite_index))
    ) %>%
    ungroup() %>% 
    # Dodavanje broja parcela iz summary_df u rezultatima
    left_join(
      summary_df %>% select(classification, broj_parcela),
      by = "classification"
    )
  
  message("Spremanje rezultata...")
  # Spojanje rangiranih rezultata sa originalnom spatial tabelom
  country_indexed <- country_data %>%
    left_join(
      all_ranked %>% select(field_boundary_id, 
                            z_ndvi, z_chl, z_gdd, 
                            composite_index, percentile, rank,
                            broj_parcela),
      by = "field_boundary_id"
    )
  
  # Izvoz finalnih rezultata u novi GeoPackage fajl
  st_write(
    obj = country_indexed,
    dsn = output_gpkg,
    layer = "performanse_useva",
    driver = "GPKG",
    delete_dsn = TRUE, # Obriši stari fajl ako postoji
    quiet = TRUE
  )
  
  message("USPESNO: ", country_name, " - Rezultati sacuvani u: ", basename(output_gpkg))
  message("##### Zavrsena obrada za: ", country_name, " #####\n")
}
