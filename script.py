import os
import geopandas as gpd
import pandas as pd

PARQUET_DATA = gpd.read_parquet("C:\\Users\\srpp0\\Projects\\SInergise-klasifikacija\\field_boundaries.parquet")
GDF_ALL_POINTS = gpd.read_file("C:\\Users\\srpp0\\Projects\\SInergise-klasifikacija\\all.gpkg")
DF_LABELS = pd.read_csv("C:\\Users\\srpp0\\Projects\\SInergise-klasifikacija\\field_boundaries_crop_classification.csv")
GADM_DATA = "C:\\Users\\srpp0\\Projects\\SInergise-klasifikacija\\europe.gpkg"

gadm_gdf = gpd.read_file(GADM_DATA)

country_col = 'COUNTRY'
output_dir = "C:\\Users\\srpp0\\Projects\\SInergise-klasifikacija\\countries"
os.makedirs(output_dir, exist_ok=True)

# Ceo workflow radimo za svaku zemlju posebno
for country in gadm_gdf[country_col].unique():
    # Uzimamo podatke za zemlju i pravimo folder i cuvamo u GPKG geometriju
    country_gdf = gadm_gdf[gadm_gdf[country_col] == country]
    country_folder = os.path.join(output_dir, country.lower().replace(' ', '_'))
    os.makedirs(country_folder, exist_ok=True)
    country_gpkg = os.path.join(country_folder, f"{country.lower().replace(' ', '_')}.gpkg")
    country_gdf.to_file(country_gpkg, driver="GPKG")
    print(f"Saved {country} to {country_gpkg}")    
    
    # Filtriamo parcele iz parquet podataka po zemlji i pravimo granicu kao jedan entitet
    country_boundary = gpd.read_file(country_gpkg)
    boundary_geom = country_boundary.unary_union
    # Filtriramo podatke unutar granice
    parquet_filtered = PARQUET_DATA[PARQUET_DATA.geometry.within(boundary_geom)]
    # Sacuvamo u fajl
    rezultat_path = os.path.join(country_folder, f"f_b_{country}.gpkg")
    parquet_filtered.to_file(rezultat_path, driver="GPKG")
    print(f"Rezultat parcela za zemlju: {country} sacuvan u {rezultat_path}")
    
    # Rename kolone da bi se spojili sa DF_LABELS csv podacima
    parquet_filtered = parquet_filtered.rename(columns={"id": "field_boundary_id"})
    # sve u str da bi imali isti tip podataka
    parquet_filtered["field_boundary_id"] = parquet_filtered["field_boundary_id"].astype(str)
    DF_LABELS["field_boundary_id"] = DF_LABELS["field_boundary_id"].astype(str)
    
    # dodavanje novih attr
    gdf_joined = parquet_filtered.merge(DF_LABELS, on="field_boundary_id", how="left") # dodajemo left - jer zelimo da sacuvamo sve podatke iz parquet_filtered
    # cuvamo kao novi fajl
    gdf_joined_path = os.path.join(country_folder, f"classified_boundaries_{country}.gpkg")
    gdf_joined.to_file(gdf_joined_path, driver="GPKG")
    # Filtriramo podatke unutar granice
    points_filtered = GDF_ALL_POINTS[GDF_ALL_POINTS.geometry.within(boundary_geom)]
    # Sacuvamo u fajl
    gdf_filtered_points_path = os.path.join(country_folder, f"filtered_points_{country}.gpkg")
    points_filtered.to_file(gdf_filtered_points_path, driver="GPKG")
    
    
    gdf_points = gpd.read_file(gdf_filtered_points_path)
    # Ucitavamo poligone
    gdf_polygons = gpd.read_file(gdf_joined_path)
    polygons_selected = gdf_polygons[["field_boundary_id", "classification", "geometry"]]
    # Spatial join: tacke unutar poligona
    gdf_joined = gpd.sjoin(gdf_points, polygons_selected, how="left", predicate="within")
    gdf_joined = gdf_joined.drop(columns=["classification_left", "index_right"], errors="ignore")
    gdf_joined = gdf_joined.rename(columns={"classification_right": "classification"})
    gdf_filtered_points_path = os.path.join(country_folder, f"final_points_{country}.gpkg")
    gdf_joined.to_file(gdf_filtered_points_path, driver="GPKG")
    print(f"Points for {country} has been saved in {gdf_filtered_points_path}")
    print(f"Finished processing {country}")
    print("-" * 50)
    break # Ovo je samo primer za jednu zemlju, da ne bi dugo trajalo


 