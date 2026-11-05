# Month-by-month checks of the FOIL trips with driver ids (derived/taxi_foil) ----
# Per month: rows and days, days with too few or too many trips, duplicated rows, rows that cannot be
# right (pickup outside the month, negative or day-long durations, negative fares or MTA tax, totals
# that do not add up), the share of trips with both ids, with NYC coordinates at both ends, paid by card
# and tipped; vendor shares (CMT 1, VTS 2, DDS 3); whether trip_time_in_secs is filled and matches
# dropoff minus pickup; the fare schedule (share of metered fares on the $0.40 and $0.50 unit grids
# above the $2.50 drop, the modal JFK-Manhattan fare); and per vendor the share of whole-mile
# distances (the FOIL 2012 CMT distances are whole miles from 2012-06, where taxi_yellow_legacy keeps
# tenths). Per vendor and day: trips against the vendor's median day (gap below half), duplicated
# rows, the share of trips whose straight-line distance is longer than the meter allows (coordinates
# that do not belong to the trip) and the share of card trips with a tip. Writes
# _meta/foil_months_check.csv, foil_vendor_days_check.csv and foil_years_check.csv (medallions and
# drivers per year); the years checked replace their rows there.
#
# Rscript checks/taxi_foil_months.R [year ...]   (from the repo root; default 2010-2013, ~30 s a month)

suppressMessages({ library(data.table); library(arrow) })
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
years <- if (length(args)) as.integer(args) else 2010:2013
out_file <- file.path(nyc_data_root(), "_meta", "foil_months_check.csv")

in_nyc <- function(lon, lat) !is.na(lon) & !is.na(lat) & lon %between% c(-74.3, -73.6) & lat %between% c(40.4, 41)
at_jfk <- function(lon, lat) !is.na(lon) & lon %between% c(-73.83, -73.74) & lat %between% c(40.62, 40.67)
in_manhattan <- function(lon, lat) !is.na(lon) & lon %between% c(-74.02, -73.92) & lat %between% c(40.70, 40.88)
on_grid <- function(fare, unit) { k <- (fare - 2.5) / unit; fare >= 2.5 & abs(k - round(k)) < 1e-6 }

# Months ----
res <- list(); ids <- list(); days <- list()
for (f in tlc_foil_files(years)) {
  ym <- substr(basename(f), 15, 21)
  x <- as.data.table(read_parquet(f))
  t0 <- as.POSIXct(paste0(ym, "-01"), tz = "UTC")
  t1 <- seq(t0, by = "month", length.out = 2)[2]
  x[, day := as.IDate(tpep_pickup_datetime)]
  x[, dur := as.numeric(tpep_dropoff_datetime - tpep_pickup_datetime, units = "secs")]

  # days: count per calendar day of the month, exact duplicate rows per day
  x[, dup := duplicated(x, by = setdiff(names(x), c("day", "dur")))]
  d <- x[tpep_pickup_datetime >= t0 & tpep_pickup_datetime < t1, .(n = .N, dups = sum(dup)), day]
  all_days <- seq(as.IDate(t0), as.IDate(t1) - 1L, by = 1L)
  d <- merge(data.table(day = all_days), d, by = "day", all.x = TRUE)[is.na(n), `:=`(n = 0L, dups = 0L)]
  med <- median(d[, n])
  low <- d[n < 0.5 * med, paste(format(day, "%d"), collapse = " ")]
  high <- d[n > 1.5 * med, paste(format(day, "%d"), collapse = " ")]
  dup_days <- d[dups > 0.01 * n, paste(format(day, "%d"), collapse = " ")]

  # vendor-days: trips against the vendor's median day, duplicates, coordinates that cannot belong to
  # the trip (straight line from pickup to dropoff longer than 1.2 x the metered distance + 0.5 mile),
  # card trips with a tip
  x[, far := in_nyc(pickup_longitude, pickup_latitude) & in_nyc(dropoff_longitude, dropoff_latitude) & trip_distance >= 0.5 &
        3958.8 * 2 * asin(sqrt(sin((dropoff_latitude - pickup_latitude) * pi / 360)^2 + cos(pickup_latitude * pi / 180) *
        cos(dropoff_latitude * pi / 180) * sin((dropoff_longitude - pickup_longitude) * pi / 360)^2)) > 1.2 * trip_distance + 0.5]
  vd <- x[tpep_pickup_datetime >= t0 & tpep_pickup_datetime < t1,
          .(n = .N, dups = sum(dup), coords_far = mean(far), card_tipped = mean(tip_amount[payment_type == 1L] > 0)), by = .(day, VendorID)]
  vd <- merge(CJ(day = all_days, VendorID = unique(vd[, VendorID])), vd, by = c("day", "VendorID"), all.x = TRUE)[is.na(n), n := 0L]
  vd[, `:=`(vendor_median = median(n), ym = ym), by = VendorID]
  vd[, gap := n < 0.5 * vendor_median]
  days[[ym]] <- vd
  vendor_names <- c("CMT", "VTS", "DDS")
  gaps <- vd[gap == TRUE, paste(vendor_names[VendorID[1]], paste(format(day, "%d"), collapse = " ")), by = VendorID][, paste(V1, collapse = "; ")]
  far_days <- vd[coords_far > 0.05, paste(vendor_names[VendorID[1]], paste(format(day, "%d"), collapse = " ")), by = VendorID][, paste(V1, collapse = "; ")]

  jfk_mh <- x[RatecodeID != 5L & ((at_jfk(pickup_longitude, pickup_latitude) & in_manhattan(dropoff_longitude, dropoff_latitude)) |
                                  (at_jfk(dropoff_longitude, dropoff_latitude) & in_manhattan(pickup_longitude, pickup_latitude))), fare_amount]
  metered <- x[RatecodeID == 1L & fare_amount > 2.5, fare_amount]
  card <- x[payment_type == 1L]

  res[[ym]] <- data.table(
    ym, rows = nrow(x), days = d[n > 0, .N], days_in_month = length(all_days),
    min_day = d[, min(n)], max_day = d[, max(n)], low_days = low, high_days = high, vendor_gap_days = gaps,
    coords_far = x[, mean(far)], coords_far_days = far_days,
    outside_month = x[!(tpep_pickup_datetime >= t0 & tpep_pickup_datetime < t1), .N],
    dup_rows = x[, sum(dup)], dup_days = dup_days,
    dup_trip_keys = x[, sum(duplicated(x, by = c("medallion", "hack_license", "tpep_pickup_datetime")))],
    medallions = uniqueN(x[, medallion]), drivers = uniqueN(x[, hack_license]),
    both_ids = x[, mean(!is.na(medallion) & medallion != "" & !is.na(hack_license) & hack_license != "")],
    coords_valid = x[, mean(in_nyc(pickup_longitude, pickup_latitude) & in_nyc(dropoff_longitude, dropoff_latitude))],
    card = x[, mean(payment_type == 1L)], cash = x[, mean(payment_type == 2L)], pay_unknown = x[, mean(payment_type == 5L)],
    card_tipped = card[, mean(tip_amount > 0)], card_tip_pct = card[fare_amount > 0, median(tip_amount / fare_amount)],
    cash_tipped = x[payment_type == 2L, mean(tip_amount > 0)],
    cmt = x[, mean(VendorID == 1L)], vts = x[, mean(VendorID == 2L)], dds = x[, mean(VendorID == 3L)],
    rate1 = x[, mean(RatecodeID == 1L)], rate2 = x[, mean(RatecodeID == 2L)],
    grid_040 = mean(on_grid(metered, 0.4)), grid_050 = mean(on_grid(metered, 0.5)),
    jfk_trips = length(jfk_mh), jfk_modal_fare = if (length(jfk_mh)) as.numeric(names(which.max(table(jfk_mh)))) else NA_real_,
    jfk_at_45 = mean(jfk_mh == 45), jfk_at_52 = mean(jfk_mh == 52),
    trip_time_filled = x[, mean(!is.na(trip_time_in_secs) & trip_time_in_secs > 0)],
    trip_time_match = x[, mean(abs(trip_time_in_secs - dur) <= 60, na.rm = TRUE)],
    neg_duration = x[dur < 0, .N], day_long = x[dur > 86400, .N],
    neg_fare = x[fare_amount < 0, .N], neg_mta_tax = x[mta_tax < 0, .N],
    total_off = x[abs(fare_amount + extra + mta_tax + tip_amount + tolls_amount - total_amount) > 0.011, .N],
    dist_over_100 = x[trip_distance > 100, .N], pass_0_or_7plus = x[passenger_count == 0L | passenger_count > 6L, .N],
    whole_miles_cmt = x[VendorID == 1L & trip_distance > 0, mean(trip_distance == round(trip_distance))],
    whole_miles_vts = x[VendorID == 2L & trip_distance > 0, mean(trip_distance == round(trip_distance))],
    whole_miles_dds = x[VendorID == 3L & trip_distance > 0, mean(trip_distance == round(trip_distance))]
  )
  ids[[ym]] <- list(m = unique(x[, medallion]), h = unique(x[, hack_license]))
  message(ym, ": ", nrow(x), " trips")
  rm(x, card); gc()
}
res <- rbindlist(res)
days <- rbindlist(days)[, year := substr(ym, 1, 4)]

# Years ----
res[, year := substr(ym, 1, 4)]
yr <- res[, .(months = .N, rows = sum(rows), card = weighted.mean(card, rows), card_tipped = weighted.mean(card_tipped, card * rows),
              both_ids = weighted.mean(both_ids, rows), coords_valid = weighted.mean(coords_valid, rows),
              cmt = weighted.mean(cmt, rows), vts = weighted.mean(vts, rows), dds = weighted.mean(dds, rows)), year]
yr[, medallions := vapply(year, function(y) uniqueN(unlist(lapply(ids[startsWith(names(ids), y)], `[[`, "m"))), integer(1))]
yr[, drivers := vapply(year, function(y) uniqueN(unlist(lapply(ids[startsWith(names(ids), y)], `[[`, "h"))), integer(1))]
print(yr)

# the years checked replace their rows in the files; other years stay
year_file <- sub("months", "years", out_file)
day_file <- sub("months", "vendor_days", out_file)
if (file.exists(out_file)) res <- rbind(fread(out_file, colClasses = list(character = c("ym", "year")))[!year %in% res[, year]], res, fill = TRUE)
if (file.exists(year_file)) yr <- rbind(fread(year_file, colClasses = list(character = "year"))[!year %in% yr[, year]], yr, fill = TRUE)
if (file.exists(day_file)) days <- rbind(fread(day_file, colClasses = list(character = c("ym", "year")))[!year %in% days[, year]], days, fill = TRUE)
setorder(res, ym); setorder(yr, year); setorder(days, day, VendorID)
fwrite(res, out_file); fwrite(yr, year_file); fwrite(days, day_file)
cat("total rows, all years in", basename(out_file), ":", format(sum(res[, rows]), big.mark = ","), "\n")
print(res[, .(ym, rows, days, min_day, max_day, low_days, high_days, vendor_gap_days, coords_far, coords_far_days,
              outside_month, dup_rows, dup_days, both_ids, coords_valid,
              card, card_tipped, cmt, vts, dds, grid_040, grid_050, jfk_modal_fare, trip_time_filled, trip_time_match,
              whole_miles_cmt, whole_miles_vts, whole_miles_dds)], nrows = 100)
