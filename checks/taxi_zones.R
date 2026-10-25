# Which zone numbering do the TLC trip records use? ----
# Yellow trips of the legacy CSVs (coordinates, derived/taxi_yellow_legacy) are matched to the same
# trips in the TLC parquet files (PULocationID) on vendor, pickup and dropoff time, distance and
# total; the pickup coordinates are then put in the polygons of each zone file in the store.
# Result 2026-10-25 (1M trips per month): the 2026-10 file reproduces TLC's PULocationID for all but
# 1 trip in 2012-07, all in 2014-01, and 99.86% in 2016-01, where every differing pickup lies within
# 1.2 ft of the zone TLC assigned (on the boundary; 2016 coordinates are single precision). The
# 2025-09 file differs further only by its duplicate ids (56, 103).
#
# Rscript checks/taxi_zones.R   (from the repo root; needs scripts/02_yellow_legacy_parquet.R first)

suppressMessages({ library(data.table); library(sf); library(arrow) })
source("R/nyc_transport.R")

zone_files <- nyc_snapshot_files("taxi_zones")
zones <- lapply(zone_files, function(z) {
  shp <- grep("\\.shp$", utils::unzip(z, list = TRUE)$Name, value = TRUE)[1]
  st_read(paste0("/vsizip/", z, "/", shp), quiet = TRUE)
})

# File differences ----
for (d in names(zones)) {
  id <- zones[[d]]$LocationID
  cat(d, ":", length(id), "polygons,", uniqueN(id), "ids; duplicated:", paste(unique(id[duplicated(id)]), collapse = ", "),
      "; missing from 1-263:", paste(setdiff(1:263, id), collapse = ", "), "\n")
}

# Point-in-polygon against TLC's PULocationID ----
key <- c("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime", "trip_distance", "total_amount")
unique_rows <- function(x) x[!duplicated(x, by = key) & !duplicated(x, by = key, fromLast = TRUE)]
set.seed(1)
res <- list()
for (ym in c("2012-07", "2014-01", "2016-01")) {
  lf <- file.path(tlc_legacy_dir(), sprintf("yellow_tripdata_%s.parquet", ym))
  if (!file.exists(lf)) { cat(ym, ": no legacy parquet\n"); next }
  a <- as.data.table(read_parquet(lf, col_select = all_of(c(key, "pickup_longitude", "pickup_latitude"))))
  b <- as.data.table(read_parquet(file.path(tlc_data_dir(), "yellow", sprintf("yellow_tripdata_%s.parquet", ym)),
                                  col_select = all_of(c(key, "PULocationID"))))
  b[, VendorID := as.integer(VendorID)]
  for (v in key[2:3]) { attr(a[[v]], "tzone") <- "UTC"; attr(b[[v]], "tzone") <- "UTC" }
  m <- merge(unique_rows(a), unique_rows(b), by = key)
  m <- m[pickup_longitude %between% c(-74.3, -73.6) & pickup_latitude %between% c(40.4, 41)][sample(.N, min(.N, 1e6))]
  pts <- st_as_sf(m, coords = c("pickup_longitude", "pickup_latitude"), crs = 4326)
  for (d in names(zones)) {
    hit <- st_intersects(st_transform(pts, st_crs(zones[[d]])), zones[[d]])
    pip <- vapply(hit, function(i) if (length(i)) zones[[d]]$LocationID[i[1]] else NA_integer_, integer(1))
    res[[length(res) + 1]] <- data.table(month = ym, zone_file = d, trips = nrow(m), in_polygon = sum(!is.na(pip)),
                                         same_id = sum(pip == m[, PULocationID], na.rm = TRUE))
  }
  rm(a, b, m, pts); gc()
}
res <- rbindlist(res)
res[, share_same := round(same_id / in_polygon, 6)]
print(res)
