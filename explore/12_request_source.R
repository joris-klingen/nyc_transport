# What is request_source in the 2026 yellow files, and where are those trips? ----
suppressMessages({ library(data.table); library(arrow); library(sf) })
source("R/nyc_transport.R")
z <- taxi_zones_read()
zones <- unique(data.table(PULocationID = as.integer(z$LocationID), borough = z$Borough), by = "PULocationID")
for (m in c("2026-06", "2026-08")) {
  f <- grep(m, tlc_files("yellow"), value = TRUE)
  d <- as.data.table(read_parquet(f, col_select = c("request_source", "PULocationID", "VendorID", "fare_amount", "trip_distance")))
  d <- merge(d, zones, by = "PULocationID", all.x = TRUE)
  cat("\n==", m, ": request_source by pickup borough (share of trips)\n")
  print(dcast(d[, .N, by = .(request_source, borough = fifelse(borough == "Manhattan", "Manhattan", fifelse(is.na(borough), "Unknown", "Outside Manhattan")))],
              request_source ~ borough, value.var = "N", fill = 0))
  cat("vendor by request_source:\n"); print(dcast(d[, .N, by = .(request_source, VendorID)], request_source ~ VendorID, value.var = "N", fill = 0))
  cat("median distance and fare by request_source:\n"); print(d[, .(miles = median(trip_distance), fare = median(fare_amount)), by = request_source])
}
