# NYC-area monitor data from the national EPA AQS files, one parquet per parameter and frequency
#
# Usage (from repo root):  Rscript scripts/41_air_pollution_nyc.R [params]
#
# Keeps monitors in the box lon -74.5 to -73.4, lat 40.4 to 41.2 (the five boroughs plus the
# adjacent NJ counties, Westchester and Nassau); `nyc` flags the five boroughs. Writes
# derived/air_pollution/{hourly,daily}_<param>.parquet with snake_case columns, read with
# air_pollution_read(). Rebuild after scripts/40_download_epa_aqs.R has fetched new files.

library(data.table)
library(arrow)
source("R/config.R")

root <- file.path(nyc_data_root(), "raw", "air_pollution", "epa_aqs")
out_dir <- file.path(nyc_data_root(), "derived", "air_pollution")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(trailingOnly = TRUE)
files <- list.files(file.path(root, c("hourly", "daily")), pattern = "^(hourly|daily)_[A-Za-z0-9]+_\\d{4}\\.parquet$", full.names = TRUE)
key <- sub("^(hourly|daily)_([A-Za-z0-9]+)_\\d{4}\\.parquet$", "\\1_\\2", basename(files))
if (length(args) >= 1) { keep <- sub("^[a-z]+_", "", key) %in% strsplit(args[1], ",")[[1]]; files <- files[keep]; key <- key[keep] }

nyc_counties <- c("005", "047", "061", "081", "085")

read_area <- function(f) {
  x <- setDT(dplyr::collect(dplyr::filter(open_dataset(f), Longitude > -74.5, Longitude < -73.4, Latitude > 40.4, Latitude < 41.2)))
  setnames(x, gsub("[^a-z0-9]+", "_", tolower(names(x))))
  for (d in intersect(c("date_local", "date_gmt", "date_of_last_change"), names(x))) x[, (d) := as.character(get(d))]
  # POC is text in the raw parquets (with the other codes), a number in the extract
  if ("poc" %in% names(x)) x[, poc := as.integer(poc)]
  x[, site_id := paste(state_code, county_code, site_num, sep = "-")]
  x[, nyc := state_code == "36" & county_code %in% nyc_counties]
  for (d in intersect(c("date_local", "date_gmt", "date_of_last_change"), names(x))) x[, (d) := as.IDate(get(d))]
  x
}

for (k in unique(key)) {
  t0 <- Sys.time()
  x <- rbindlist(lapply(sort(files[key == k]), read_area), fill = TRUE)
  write_parquet(x, file.path(out_dir, paste0(k, ".parquet")))
  message(k, ": ", nrow(x), " rows, ", x[, uniqueN(site_id)], " sites (", x[nyc == TRUE, uniqueN(site_id)], " in NYC), ",
          x[, paste(range(year(date_local)), collapse = "-")], ", ", round(as.numeric(Sys.time() - t0, units = "secs")), " s")
}
