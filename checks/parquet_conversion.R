# Check the Citi Bike and EPA AQS parquet conversion (2026-10-25) ----
# Citi Bike: trips per year in the monthly parquets against a lean count of the published CSVs
# (explore/02_citibike_daily.R run on the zips, saved before the conversion), and one month read
# from parquet against the same month read from its zip. EPA: the NYC extract rebuilt from the
# parquets (scripts/41_air_pollution_nyc.R) against the extract built from the zips.
# Usage (from repo root): Rscript checks/parquet_conversion.R <dir with citibike_daily_zips.parquet and air_before/>
suppressMessages({ library(data.table); library(arrow) })
source("R/nyc_transport.R")
ref <- commandArgs(TRUE)[1]

# Citi Bike trips per year ----
z <- as.data.table(read_parquet(file.path(ref, "citibike_daily_zips.parquet")))[, .(zips = sum(trips)), by = .(year = year(date))]
t0 <- Sys.time()
p <- as.data.table(dplyr::collect(dplyr::count(dplyr::mutate(citibike_open(), year = year(started_at)), year)))
cat(sprintf("Citi Bike: %d monthly parquets, query over all months in %.0f s\n", length(citibike_files()), as.numeric(Sys.time() - t0, units = "secs")))
cmp <- merge(z, p[, .(year = as.integer(year), parquet = n)], by = "year", all = TRUE)
cmp[, diff := parquet - zips]
print(cmp)
cat("total trips: zips", sum(cmp[, zips], na.rm = TRUE), " parquet", sum(cmp[, parquet], na.rm = TRUE), "\n")

# One month from parquet against its zip ----
for (m in c("2016-07", "2024-06")) {
  zf <- citibike_files("zip")
  zf <- zf[basename(zf) %in% paste0(c(gsub("-", "", m), substr(m, 1, 4)), "-citibike-tripdata.zip")]
  if (!length(zf)) { cat(m, ": zip already deleted\n"); next }
  a <- citibike_read_zip(zf[1], m); b <- citibike_read(m)
  cat(m, ": identical to the zip read:", isTRUE(all.equal(a, b, check.attributes = FALSE)), "(", nrow(b), "trips )\n")
}

# EPA NYC extract ----
cat("\nEPA NYC extract, rebuilt from parquet against the zip build:\n")
for (f in list.files(file.path(ref, "air_before"), pattern = "\\.parquet$")) {
  a <- as.data.table(read_parquet(file.path(ref, "air_before", f)))
  b <- as.data.table(read_parquet(file.path(nyc_data_root(), "derived", "air_pollution", f)))
  setkeyv(a, intersect(c("site_id", "poc", "date_local", "time_local", "sample_duration", "pollutant_standard"), names(a))); setkeyv(b, key(a))
  cat(sprintf("  %-22s rows %d vs %d, identical %s\n", f, nrow(a), nrow(b), isTRUE(all.equal(a, b, check.attributes = FALSE))))
}
