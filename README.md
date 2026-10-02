# Field Boundaries and Crop Classification Processing 

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.15656419.svg)](https://doi.org/10.5281/zenodo.15656419)

This repository contains a collection of Python and R scripts designed for a multi-stage workflow to process, classify, enrich, and analyze agricultural field data. The workflow starts with raw time-series and geometry data, integrates meteorological information, spatially filters data by country, and concludes with a performance analysis for each field based on crop type.

The initial data sources are provided by Sinergise ([Field boundary data](https://zenodo.org/records/14229033) & [Crop classification data](https://zenodo.org/records/14842659)) and GADM administrative boundaries.

The work was carried out within Task 5.7 of the [OpenEarthMonitor](https://earthmonitor.org/) project.

## 📦 Results Dataset

The outputs of this pipeline are published on Zenodo:

**Field-based Crop Performance Indicators for Europe (May–July 2022)**
DOI: [10.5281/zenodo.15656419](https://doi.org/10.5281/zenodo.15656419) · License: CC-BY-4.0

The dataset contains one `.zip` archive per country (43 countries). Each archive holds the files produced by `script.py` and `perf.R`:

| File | Content |
|---|---|
| `<country>.gpkg` | GADM country boundary |
| `f_b_<Country>.gpkg` | field boundaries within the country |
| `classified_boundaries_<Country>.gpkg` | field boundaries with crop type (`classification`) |
| `filtered_points_<Country>.gpkg` | field centroids within the country |
| `final_points_<Country>.gpkg` | field centroids with `cum_ndvi`, `cum_chl`, `cum_gdd`, `field_boundary_id`, `classification` |
| `perf_<country>.gpkg` (layer `performanse_useva`) | everything above plus `z_ndvi`, `z_chl`, `z_gdd`, `composite_index`, `percentile`, `rank`, `broj_parcela` (number of fields in the crop class) |

All indicators refer to the centroid of each field parcel. Coordinates are in WGS84 (EPSG:4326).

> **Note on the time window**: the published dataset was produced with the scripts as of commit `c09f802`. Because of a date-parsing bug in `chl30.R` (`%y` instead of `%Y`), cumulative NDVI and CHL in that release were integrated over **2 May – 1 August 2022** instead of 1 May – 31 July 2022. The bug is fixed in the current version of the script; cumulative GDD is not affected.

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
*   **Efficient computation**: Uses the formula `(tmax + tmin) / 20 - 10` and sets negative values to zero. The input rasters store temperature as integers in tenths of a degree Celsius, so `(tmax + tmin) / 20` is the daily mean temperature in °C and 10 °C is the base temperature. The cumulative sum is calculated efficiently across all raster layers.
*   **Input period**: All `tmax*.tif` / `tmin*.tif` files in the input folder are summed, so the folder must contain only the days of the analysed period (1 May – 31 July 2022).
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

### 4. Performance Analysis (R - `perf.R`)

The final script in the workflow analyzes the enriched data on a per-country basis to evaluate crop performance.

1.  **Data cleaning**: Loads the `final_points_COUNTRY.gpkg` file and removes records with missing (`NA`) values in key columns (`cum_ndvi`, `cum_chl`, `cum_gdd`, `classification`).
2.  **Classification summary**: Calculates the total number of parcels for each crop type within the country.
3.  **Z-score normalization**: Standardizes the `cum_ndvi`, `cum_chl`, and `cum_gdd` values for each field relative to the mean and standard deviation of its own crop class.
4.  **Composite indexing**: Calculates a single weighted performance index for each field based on the formula: **(Z-NDVI * 0.8) + (Z-CHL * 0.1) + (Z-GDD * 0.1)**.
5.  **Ranking and percentiles**: Ranks each field within its crop category based on the composite index and calculates its performance percentile.
6.  **Spatial output**: Saves the final results, including all calculated metrics, into a new GeoPackage file named `perf_COUNTRY.gpkg` (layer `performanse_useva`).

> **Note**: By default the Python script processes all countries. Set `COUNTRIES` at the top of `script.py` (e.g. `["Serbia"]`) to process only selected ones.

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

Intermediate outputs of the first two steps:

```
<ROOT_DIR>/
├── <FOLDER>.csv                  # chl30.R: POLY_ID, cum_ndvi, cum_chl, lat, lon, classification
<RESULTS_DIR>/
├── <FOLDER>.gpkg                 # gdd_parallel.R: centroids + cum_gdd
<METEO_DIR>/
├── cumulative_gdd.tif            # gdd_parallel.R: cumulative GDD raster
<ALL_GPKG>                        # gdd_parallel.R: all centroids merged (all.gpkg)
```

Per-country outputs of `script.py` and `perf.R` (same layout as the [Zenodo archives](https://doi.org/10.5281/zenodo.15656419)):

```
countries/
├── serbia/
│   ├── serbia.gpkg
│   ├── f_b_Serbia.gpkg
│   ├── classified_boundaries_Serbia.gpkg
│   ├── filtered_points_Serbia.gpkg
│   ├── final_points_Serbia.gpkg
│   └── perf_serbia.gpkg          # layer: performanse_useva
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
- `parallel` (part of base R)
- `tidyverse`


Install all dependencies with:
```bash
# Python
pip install geopandas pandas

# R
install.packages(c("arrow", "geoarrow", "sf", "terra", "dplyr", "readr", "data.table", "jsonlite", "tidyverse"))
```

### dailymeteo.com API key (optional)
The API-based GDD functions in `chl30.R` (`calculate_gdd`, `calculate_gdd_parallel`) read the key from the `DAILYMETEO_API_KEY` environment variable. They are not used in the default run, which takes GDD from rasters (`gdd_parallel.R`).

## ▶️ How to Run

Execute the scripts in the following sequence. Input and output paths are set in the configuration block at the top of each script.

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
4.  **Analyze Performance**: Run `perf.R` to compute the performance index and rank fields.
    ```bash
    Rscript perf.R
    ```

## 📑 Citation

If you use the data, please cite the Zenodo dataset:

> Gilab Ltd (2025). *Field-based Crop Performance Indicators for Europe (May–July 2022)* [Data set]. Zenodo. https://doi.org/10.5281/zenodo.15656419

Citation metadata for this repository is also available in [`CITATION.cff`](CITATION.cff).

## ⚖️ License

The code in this repository is released under the [MIT License](LICENSE). The published dataset on Zenodo is licensed under CC-BY-4.0.

## ✍️ Author
- Gilab Team 


## Acknowledgements
This project has received funding from the European Union’s Horizon 2020 research and innovation programme under grant agreements No. 776115, No. 101004112, No. 101059548 and No. 101086461.
