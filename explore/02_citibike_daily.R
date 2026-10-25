# Citi Bike trips per day and per station-month ----
#
# Exploratory. One pass over the monthly trip parquets (citibike_files()):
#   - citibike_daily.parquet: trips, member trips and e-bike trips per start date
#   - citibike_station_month.parquet: trips per start station and month, with its coordinates
# Run from the repo root: Rscript explore/02_citibike_daily.R

library(data.table)
library(arrow)
source("R/nyc_transport.R")

out_dir <- "output/explore"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Every month ----
daily <- list(); stations <- list()
for (f in citibike_files()) {
  cols <- intersect(c("started_at", "member", "rideable_type", "start_station_id", "start_lat", "start_lng"), names(open_dataset(f)))
  x <- as.data.table(read_parquet(f, col_select = tidyselect::all_of(cols)))
  x[, date := as.IDate(format(started_at, "%Y-%m-%d", tz = "America/New_York"))]
  x[, ebike := if ("rideable_type" %in% names(x)) rideable_type == "electric_bike" else NA]
  daily[[f]] <- x[, .(trips = .N, member = sum(member, na.rm = TRUE), ebike = sum(ebike)), by = date]
  stations[[f]] <- x[, .(trips = .N, lat = median(start_lat, na.rm = TRUE), lng = median(start_lng, na.rm = TRUE)),
                     by = .(ym = format(date, "%Y-%m"), station = start_station_id)]
  rm(x); gc(verbose = FALSE)
}

# trips starting in the last hours of a month can sit in the next month's file: add them up
d <- rbindlist(daily)[, .(trips = sum(trips), member = sum(member), ebike = sum(ebike)), by = date][order(date)]
s <- rbindlist(stations)[, .(trips = sum(trips), lat = median(lat, na.rm = TRUE), lng = median(lng, na.rm = TRUE)), by = .(ym, station)]
write_parquet(d, file.path(out_dir, "citibike_daily.parquet"))
write_parquet(s, file.path(out_dir, "citibike_station_month.parquet"))
cat("done:", nrow(d), "days,", s[, uniqueN(station)], "stations\n")
