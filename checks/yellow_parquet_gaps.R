# Which yellow trips are missing from TLC's parquet files in 2012-2013? ----
# TLC's parquet files lack 0.4-2.0M trips in six months of 2012-2013 compared with the legacy CSVs
# (checks/yellow_legacy_parquet.R). This compares the two per day, vendor and payment type, and per
# pickup borough (legacy coordinates in the 2026 zone file), to see whether the gap is whole days, one
# vendor or certain places, i.e. whether counts from the parquet files are biased or only scaled down.
# Result 2026-10-25: the 6.6M missing trips are spread over every day of 2012-01..05 and 2013-08
# (2013-04: 14 of 30 days); borough shares agree to 0.001 and Manhattan zone shares within sampling
# noise (sd of parquet / legacy share 0.005-0.007, 0.006 from sampling alone), so zone counts are
# scaled down, not shifted. In 2012 they are mostly VTS trips (15-25% of VendorID 2 missing against
# 1-5% of VendorID 1); 2013-04 loses both vendors alike. Payment shares agree.
#
# Rscript checks/yellow_parquet_gaps.R [YYYY-MM ...]   (from the repo root; about 10 min a month)

suppressMessages({ library(data.table); library(sf); library(arrow) })
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
months <- if (length(args)) args else c("2012-01", "2012-02", "2012-04", "2012-05", "2013-04", "2013-08")

z <- nyc_latest("taxi_zones")
shp <- grep("\\.shp$", utils::unzip(z, list = TRUE)$Name, value = TRUE)[1]
zones <- st_read(paste0("/vsizip/", z, "/", shp), quiet = TRUE)

# borough of each pickup, by point in polygon (NA outside the zones)
borough_of <- function(lon, lat) {
  ok <- !is.na(lon) & lon %between% c(-74.3, -73.6) & lat %between% c(40.4, 41)
  out <- rep(NA_character_, length(lon))
  pts <- st_transform(st_as_sf(data.table(lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4326), st_crs(zones))
  hit <- st_intersects(pts, zones)
  out[ok] <- vapply(hit, function(i) if (length(i)) zones$borough[i[1]] else NA_character_, character(1))
  out
}
zone_of <- function(lon, lat) {
  ok <- !is.na(lon) & lon %between% c(-74.3, -73.6) & lat %between% c(40.4, 41)
  out <- rep(NA_integer_, length(lon))
  pts <- st_transform(st_as_sf(data.table(lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4326), st_crs(zones))
  hit <- st_intersects(pts, zones)
  out[ok] <- vapply(hit, function(i) if (length(i)) as.integer(zones$LocationID[i[1]]) else NA_integer_, integer(1))
  out
}

res <- list()
for (ym in months) {
  a <- as.data.table(read_parquet(file.path(tlc_legacy_dir(), sprintf("yellow_tripdata_%s.parquet", ym)),
                                  col_select = c("VendorID", "tpep_pickup_datetime", "payment_type", "pickup_longitude", "pickup_latitude")))
  b <- as.data.table(read_parquet(file.path(tlc_data_dir(), "yellow", sprintf("yellow_tripdata_%s.parquet", ym)),
                                  col_select = c("VendorID", "tpep_pickup_datetime", "payment_type", "PULocationID")))
  for (d in list(a, b)) set(d, j = "day", value = as.IDate(as.numeric(d[["tpep_pickup_datetime"]]) %/% 86400))
  a <- a[format(day, "%Y-%m") == ym]; b <- b[format(day, "%Y-%m") == ym]
  cat("\n====", ym, ": legacy", nrow(a), "TLC parquet", nrow(b), "missing", nrow(a) - nrow(b),
      sprintf("(%.1f%%)", 100 * (1 - nrow(b) / nrow(a))), "\n")

  # per day: whole days or a share of every day?
  dd <- merge(a[, .(legacy = .N), day], b[, .(tlc = .N), day], by = "day", all = TRUE)
  dd[is.na(tlc), tlc := 0L][, miss := round(1 - tlc / legacy, 3)]
  cat("days with >1% missing:", dd[miss > 0.01, .N], "of", nrow(dd), "\n")
  print(dd[miss > 0.01])

  # per vendor and payment type
  v <- merge(a[, .(legacy = .N), .(VendorID = as.integer(VendorID))], b[, .(tlc = .N), .(VendorID = as.integer(VendorID))], by = "VendorID", all = TRUE)
  print(v[, miss := round(1 - tlc / legacy, 3)])
  p <- merge(a[, .(legacy = .N), .(payment_type = as.integer(payment_type))], b[, .(tlc = .N), .(payment_type = as.integer(payment_type))], by = "payment_type", all = TRUE)
  print(p[, miss := round(1 - tlc / legacy, 3)])

  # per pickup borough, on the days with a gap (a 2M sample of the legacy trips)
  gap_days <- dd[miss > 0.01, day]
  if (length(gap_days)) {
    s <- a[day %in% gap_days][sample(.N, min(.N, 2e6))]
    s[, borough := borough_of(pickup_longitude, pickup_latitude)]
    lb <- s[, .(legacy_share = .N / nrow(s)), borough]
    tb <- b[day %in% gap_days, .N, .(LocationID = PULocationID)]
    tb <- merge(tb, as.data.table(st_drop_geometry(zones))[, .(LocationID, borough)], by = "LocationID", all.x = TRUE)
    tb <- tb[, .(N = sum(N)), borough][, tlc_share := N / sum(N)][, N := NULL]
    # TLC counts pickups without coordinates in zones 264/265; leave them out of both shares
    bb <- merge(lb[!is.na(borough)], tb[!is.na(borough) & borough != "Unknown"], by = "borough")
    bb[, `:=`(legacy_share = round(legacy_share / sum(legacy_share), 4), tlc_share = round(tlc_share / sum(tlc_share), 4))]
    cat("pickup borough shares on the gap days (legacy sample vs TLC parquet):\n"); print(bb)

    # per Manhattan pickup zone: does the parquet keep the same share of every zone?
    s[, LocationID := zone_of(pickup_longitude, pickup_latitude)]
    zl <- s[borough == "Manhattan", .(legacy = .N), LocationID]
    zt <- b[day %in% gap_days, .(tlc = .N), .(LocationID = PULocationID)]
    zz <- merge(zl, zt, by = "LocationID")[legacy >= 2000]
    zz[, ratio := (tlc / sum(tlc)) / (legacy / sum(legacy))]
    cat("Manhattan zones (>= 2000 sampled pickups):", nrow(zz), "; parquet share / legacy share: weighted sd",
        round(sqrt(weighted.mean((zz[, ratio] - 1)^2, zz[, legacy])), 4), "; range", paste(round(range(zz[, ratio]), 3), collapse = " to "),
        "; sd expected from sampling alone about", round(sqrt(weighted.mean(1 / zz[, legacy], zz[, legacy])), 4), "\n")
  }
  res[[ym]] <- dd[, .(month = ym, day, legacy, tlc, miss)]
  rm(a, b); gc()
}
res <- rbindlist(res)
cat("\nall months:", res[miss > 0.01, .N], "days with a gap;", sum(res[, legacy - tlc]), "trips missing\n")
