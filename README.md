# Field Boundaries and Crop Classification Processing 

This repository contains a collection of Python and R scripts designed for a multi-stage workflow to process, classify, enrich, and analyze agricultural field data. The workflow starts with raw time-series and geometry data, integrates meteorological information, spatially filters data by country, and concludes with a performance analysis for each field based on crop type.

The initial data sources are provided by Sinergise ([Field boundary data](https://zenodo.org/records/14229033) & [Crop classification data](https://zenodo.org/records/14842659)) and GADM administrative boundaries.

## 📋 Description

The end-to-end process is divided into four main stages:

### 1. Signal & Geometry Processing (R - `chl30.R`)

This script handles the initial processing of raw time-series and geometry data from Parquet files and integrates external data via API.

*   **Package loading & session options**: Increases API timeout and suppresses warnings for smoother execution.
*   **CHL index function**: The `izracunaj_chl()` function calculates the Canopy Chlorophyll Content Index, carefully handling potential division-by-zero errors and missing spectral bands.
*   **Recursive Parquet reading**: `processAllSignals()` recursively scans nested folders to find all `signal` data, processes them, and computes cumulative NDVI and CHL for a defined period (May-July).
*   **Geometry extraction**: `processAllGeometry()` reads geometry from Parquet files, transforms coordinate systems to WGS84, and extracts the centroid (latitude/longitude) for each field.
*   **API-based GDD calculation**: `calculate_gdd()` fetches daily temperature data (Tmin/Tmax) from the `dailymeteo.com` API and calculates the Growing Degree Days (GDD) sum for a given location and time range.
*   **End-to-end execution**: The main part of the script orchestrates the signal and geometry processing, merges the results with classification data from a CSV, and saves the output as a `.csv` file for each main folder.


### 2. Parallel GDD Processing from Rasters (R - `gdd_parallel.R`)

This script provides an efficient, raster-based alternative for calculating and integrating GDD data. It serves as the primary method for enriching data before country-level filtering.

*   **Raster-based GDD calculation**: Loads pre-existing temperature raster files (Tmax/Tmin in `.tif` format) and calculates GDD using fast raster arithmetic with the `terra` package.
*   **Efficient computation**: Uses the formula `(tmax + tmin) / 20 - 10` and sets negative values to zero. The cumulative sum is calculated efficiently across all raster layers.
*   **Cumulative GDD map**: Creates a single cumulative GDD raster covering the entire study area for the specified period.
*   **Spatial extraction**: Reads point data (centroids) from CSVs generated in the previous step and uses `terra::extract()` to append the corresponding GDD value to each point.
*   **Batch processing & Data Merging**: Iterates through multiple `.csv` files, enriches each with GDD data, saves the result as a GeoPackage (`.gpkg`), and finally combines them into a single, comprehensive dataset named `all.gpkg`.

### 3. Geometric Processing (Python - `script.py`)
The Python script performs the following steps **for each country** in the provided GADM geopackage:

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

### 4. Performance Analysis (R - `perf.r`)

The final script in the workflow analyzes the enriched data on a per-country basis to evaluate crop performance.

1.  **Data cleaning**: Loads the `final_points_COUNTRY.gpkg` file and removes records with missing (`NA`) values in key columns (`cum_ndvi`, `cum_chl`, `cum_gdd`, `classification`).
2.  **Classification summary**: Calculates the total number of parcels for each crop type within the country.
3.  **Z-score normalization**: Standardizes the `cum_ndvi`, `cum_chl`, and `cum_gdd` values for each field relative to the mean and standard deviation of its own crop class.
4.  **Composite indexing**: Calculates a single weighted performance index for each field based on the formula: **(Z-NDVI * 0.8) + (Z-CHL * 0.1) + (Z-GDD * 0.1)**.
5.  **Ranking and percentiles**: Ranks each field within its crop category based on the composite index and calculates its performance percentile.
6.  **Spatial output**: Saves the final results, including all calculated metrics, into a new GeoPackage file named `perf_COUNTRY.gpkg`.

> **Note**: The Python script currently processes **only the first country** due to a `break` statement at the end of the loop. Remove it to process all countries.

## 📂 Input Files

### Required for geometric processing:
- `field_boundaries.parquet`: Full set of field boundaries (polygons)
- `all.gpkg`: Points representing the centroids of fields
- `field_boundaries_crop_classification.csv`: CSV file with crop classification labels
- `europe.gpkg`: GADM geopackage with country boundaries across Europe

### Required for signal processing:
- Country folders containing:
  - `signal/` subfolders with Parquet files containing satellite time series data
  - `geometry/` subfolders with Parquet files containing field geometries

### Required for parallel GDD processing:
- Temperature raster files in TIFF format:
  - `tmax*.tif` - Daily maximum temperature rasters
  - `tmin*.tif` - Daily minimum temperature rasters
- CSV files with coordinates (lon, lat columns) for GDD extraction

## 📤 Output Structure

The pipeline creates a comprehensive directory structure:

```
countries/
├── serbia/
│   ├── serbia.gpkg                     
│   ├── f_b_Serbia.gpkg                 
│   ├── classified_boundaries_Serbia.gpkg 
│   ├── filtered_points_Serbia.gpkg      
│   ├── final_points_Serbia.gpkg        
│   ├── serbia.csv                       
│   ├── serbia.gpkg                     
│   └── perf_serbia.gpkg                 
```

## 🛠️ Requirements

### Python Dependencies
- Python 3.9+
- `geopandas`
- `pandas`
- `shapely`
- `pyproj`
- `fiona`

### R Dependencies
- `arrow`
- `geoarrow`
- `sf`
- `terra`
- `dplyr`
- `readr`
- `data.table`
- `jsonlite`
- `parallel`
- `tidyverse`


Install all dependencies with:
```bash
# Python
pip install geopandas pandas

# R
install.packages(c("arrow", "geoarrow", "sf", "terra", "dplyr", "readr", "data.table", "jsonlite", "parallel", "tidyverse"))
```

## ▶️ How to Run

Execute the scripts in the following sequence. Ensure all paths inside the scripts are configured correctly.

1.  **Process Raw Data**: Run `chl30.R` to process signal/geometry data and create initial CSVs.
    ```bash
    Rscript chl30.R
    ```
2.  **Integrate GDD**: Run `gdd_parallel.R` to calculate GDD, enrich the data, and create `all.gpkg`.
    ```bash
    Rscript gdd_parallel.R
    ```
3.  **Filter by Country**: Run `script.py` to split `all.gpkg` into country-specific datasets.
    ```bash
    python script.py
    ```
4.  **Analyze Performance**: Run `per.R` to compute the performance index and rank fields.
    ```bash
    Rscript per.R
    ```


## ✍️ Author
- Gilab Team 


## Acknowledgements
This project has received funding from the European Union’s Horizon 2020 research and innovation programme under grant agreements No. 776115, No. 101004112, No. 101059548 and No. 101086461.
