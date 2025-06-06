# =======================
# Purpose: Validates and projects ecoregion data to  WGS 84 Geographic
# =======================

#------------------------------------------------------------------------------


# ----------------------------------------------------------------
# library
library(tidyverse)        # Load the 'Tidyverse' packages: ggplot2, dplyr, 
#   tidyr, readr, purrr, tibble, stringr, and forcats
library(here)             # A simpler way to find files
library(glue)             # Format and interpolate a string
library(sf)               # Simple features for R
library(janitor)          # Simple tools for cleaning dirty data
library(dataRetrieval)

# set file path for the spatial data folder
file_path <- "data_spatial"
folder_name <- "ecoregions_unprojected"

# load ecoregion level 1 Great Plains -- local path 
file_name <- "us_eco_lev1_GreatPlains_geographic.gpkg"

eco_lev1 <- st_read(
  glue({file_path},{folder_name},{file_name}, .sep = "/"
  ))

# load ecoregion level 2 Great Plains -- local path 
file_name <- "us_eco_lev2_GreatPlains_geographic.gpkg"

eco_lev2 <- st_read(
  glue({file_path},{folder_name},{file_name}, .sep = "/"
  ))

# load ecoregion level 3 Great Plains -- local path 
file_name <- "us_eco_lev3_GreatPlains_geographic.gpkg"

eco_lev3 <- st_read(
  glue({file_path},{folder_name},{file_name}, .sep = "/"
  ))

# load ecoregion level 4 Great Plains -- local path 
file_name <- "us_eco_lev4_GreatPlains_geographic.gpkg"

eco_lev4 <- st_read(
  glue({file_path},{folder_name},{file_name}, .sep = "/"
  ))

# check coords by their wkt == well known text
eco_lev1_coords <- st_crs(eco_lev1)$wkt
eco_lev2_coords <- st_crs(eco_lev2)$wkt
eco_lev3_coords <- st_crs(eco_lev3)$wkt
eco_lev4_coords <- st_crs(eco_lev4)$wkt

# clean up Global Environment
rm(list = ls(pattern = "file"))
rm(list = ls(pattern = "folder"))
rm(list = ls(pattern = "coords"))

# ---------------------------------------------------------
# Define a Bounding Box
# Define maximum allowed width for subdivisions
max_width <- 1.0

# Calculate required number of subdivisions
total_width <- as.numeric(bbox_orig["xmax"] - bbox_orig["xmin"])
num_subdivisions <- ceiling(total_width / max_width)

# Calculate xmin and xmax values for each subdivision
xmin_values <- seq(bbox_orig["xmin"], bbox_orig["xmax"] - max_width, by = max_width)
xmax_values <- pmin(xmin_values + max_width, bbox_orig["xmax"])

# Ensure that the last xmax aligns perfectly with the original xmax
if (xmax_values[length(xmax_values)] != bbox_orig["xmax"]) {
  xmax_values[length(xmax_values)] <- bbox_orig["xmax"]
}

# Create the tibble containing all subdivisions
subdivisions <- tibble(
  index = 1:length(xmin_values),
  xmin = xmin_values,
  xmax = xmax_values,
  ymin = rep(bbox_orig["ymin"], length(xmin_values)),
  ymax = rep(bbox_orig["ymax"], length(xmin_values))
)

# ---------------------------------------------------------
# Get Sites in Bounding Box

for (i in seq_len(nrow(subdivisions))) {
  current_bbox <- subdivisions[i, ]
  
  bbox_vector <- paste(
    current_bbox$xmin,
    current_bbox$ymin,
    current_bbox$xmax,
    current_bbox$ymax,
    sep = ","
  )
  
  message("Trying subdivision ", i, " with bbox: ", bbox_vector)
  
  sites_data <- tryCatch(
    {
      whatNWISsites(
        bBox = bbox_vector,
        siteType = "ST",             # Stream sites
        parameterCd = "00060"        # Discharge
      )
    },
    error = function(e) {
      message(paste("Error in subdivision", i, ":", e$message))
      NULL
    }
  )
  
  if (!is.null(sites_data) && nrow(sites_data) > 0) {
    sites_data$subdivision_id <- i
    sites_data_list[[i]] <- sites_data
  }
}

# Combine all site data into a single data frame
sites_all_data <- bind_rows(sites_data_list)

# Export all sites
write_csv(sites_all_data, "data/sites_all_in_bb")

# clean up Global Environment
rm(subdivisions,
   xmax_values,
   xmin_values,
   bbox_vector,
   max_width,
   num_subdivisions,
   total_width,
   current_bbox
)

# ---------------------------------------------------------
# Drop canal ditch sites

sites_st_data <- sites_all_data %>%
  filter(site_tp_cd == "ST")

sites_other <- anti_join(sites_all_data, sites_st_data)

# ---------------------------------------------------------
# Get all peakflow data in 

# Set batch size
batch_size <- 1000

# Split your sites into batches
site_batches <- split(sites_st_data$site_no, ceiling(seq_along(sites_st_data$site_no) / batch_size))

# Initialize list to store results
pk_data_list <- vector("list", length(site_batches))

# Loop over each batch and query peak flow data
for (i in seq_along(site_batches)) {
  message("Processing batch ", i, " of ", length(site_batches))
  
  pk_data_list[[i]] <- tryCatch(
    {
      whatNWISdata(
        siteNumber = site_batches[[i]],
        service = "pk"
      )
    },
    error = function(e) {
      message("Error in batch ", i, ": ", e$message)
      NULL
    }
  )
  
  # Be kind to the API
  Sys.sleep(0.5)
}

# Combine all batches into one data frame
sites_pk_all <- bind_rows(pk_data_list)

# Export all peakflow sites
write_csv(sites_pk_all, "data/sites_peak_in_bb")

# clean up Global environment
rm(batch_size,
   site_batches,
   pk_data_list,
   sites_data_list,
   i
)

# ---------------------------------------------------------
# drop sites outside of Great Plains ecoregion

# convert stations into a spatial format (sf) object
sites_pk_all <- st_as_sf(sites_pk_all,
                         coords = c("dec_long_va",        # note x goes first
                                    "dec_lat_va"),
                         crs = 4326,               # WGS 84 Geographic; Unit: degree
                         remove = FALSE)                 # don't remove lat/lon cols

sites_pk_eco <- st_intersection(sites_pk_all, eco_lev1)

# ---------------------------------------------------------
# drop sites with l.t 20 observations
sites_pk_gt_20 <- sites_pk_eco %>%
  filter(count_nu >= 20)

# check for duplicates
duplicates <- sites_pk_gt_20 %>%
  filter(duplicated(.) | duplicated(., fromLast = TRUE))

# Export sites
write_csv(sites_pk_gt_20, "data/sites_pk_gt_20")



















