# Field Boundaries and Crop Classification Processing

This repository contains a Python and R code that processes and classifies agricultural field boundary data per country. The process uses GADM administrative boundaries, field geometry in Parquet format, and classification labels from a CSV file provided by Sinergise (https://zenodo.org/records/14229033 & https://zenodo.org/records/14842659).

## 📋 Description

The script performs the following steps **for each country** in the provided GADM geopackage:

1. **Extract country boundary**: Filters the GADM file for a single country's geometry and saves it as a `.gpkg` file.
2. **Filter field boundaries**: Loads all polygons from the input Parquet file and keeps only those within the selected country's boundary.
3. **Merge classification data**: Joins the filtered field boundaries with a CSV file that contains `field_boundary_id` and `classification` columns.
4. **Filter point data (centroids)**: Selects all point features located within the country's boundary and performs a spatial join with the classified field boundaries.
5. **Save results**: For each country, a folder is created containing the following output files:
   - `COUNTRY.gpkg` – country boundary geometry
   - `f_b_COUNTRY.gpkg` – filtered field boundaries within the country
   - `classified_boundaries_COUNTRY.gpkg` – classified polygons
   - `filtered_points_COUNTRY.gpkg` – points within the country's boundary
   - `final_points_COUNTRY.gpkg` – points enriched with classification attribute

> **Note**: The script currently processes **only the first country** due to a `break` statement at the end of the loop. Remove it to process all countries.

## 📂 Input Files

- `field_boundaries.parquet`: Full set of field boundaries (polygons)
- `all.gpkg`: Points representing the centroids of fields
- `field_boundaries_crop_classification.csv`: CSV file with crop classification labels
- `europe.gpkg`: GADM geopackage with country boundaries across Europe

## 📤 Output Structure

The script creates a `countries/` directory with one subfolder per country. For example:

```
countries/
├── serbia/
│   ├── serbia.gpkg
│   ├── f_b_Serbia.gpkg
│   ├── classified_boundaries_Serbia.gpkg
│   ├── filtered_points_Serbia.gpkg
│   └── final_points_Serbia.gpkg
```

## 🛠️ Requirements

- Python 3.9+
- `geopandas`
- `pandas`
- `shapely`
- `pyproj`
- `fiona`

Install dependencies with:

```bash
pip install geopandas pandas
```

## ▶️ How to Run

Run the script using:

```bash
python script.py
```

## ✍️ Author

- Gilab Team 
