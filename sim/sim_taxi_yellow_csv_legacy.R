# Simulated legacy yellow taxi CSV (trips with coordinates, 2012-01 to 2016-06)
#
# Real data: raw/taxi/yellow_csv_legacy/yellow_tripdata_YYYY-MM.csv.gz (54 months, 26 GB gzipped), read with
# data.table::fread(f, header = TRUE, blank.lines.skip = TRUE) (a blank line follows the header in
# the 2012-2014 files). The only TLC trips with pickup and dropoff coordinates (lon/lat). Two
# column sets:
#   2012-2014: vendor_id (CMT, VTS), pickup_datetime, dropoff_datetime, passenger_count,
#              trip_distance, pickup_longitude, pickup_latitude, rate_code, store_and_fwd_flag,
#              dropoff_longitude, dropoff_latitude, payment_type (CRD, CSH, ...), fare_amount,
#              surcharge, mta_tax, tip_amount, tolls_amount, total_amount
#   2015-2016: VendorID (1, 2), tpep_pickup_datetime, tpep_dropoff_datetime, passenger_count,
#              trip_distance, pickup_longitude, pickup_latitude, RateCodeID, store_and_fwd_flag,
#              dropoff_longitude, dropoff_latitude, payment_type (1-4), fare_amount, extra,
#              mta_tax, tip_amount, tolls_amount, improvement_surcharge, total_amount
# Coordinates are 0 for some trips (no GPS fix).
#
# Kept: the column set and order of the month's era; pickup and dropoff points where trips start
# and end (cells of the real coordinates, mostly Manhattan); dropoff after pickup; total the sum
# of the parts. Not kept: distance consistent with the two points.
#
# tl <- sim_taxi_yellow_csv_legacy(10000, month = "2013-06")

sim_taxi_yellow_csv_legacy <- function(n = 1000, month = "2013-06", seed = NULL) {
  x <- sim_profile("taxi_yellow_csv_legacy", n, seed)
  yr <- as.integer(substr(month, 1, 4))
  r <- sim_month_range(month, tz = "UTC")
  pick <- sim_times(n, r[["from"]], r[["to"]], tz = "UTC")
  dist <- pmax(0, x[, trip_distance])
  drop <- pick + round(60 + pmin(dist, 80) / stats::rlnorm(n, log(11), 0.35) * 3600)
  common <- x[, .(passenger_count, trip_distance = dist, pickup_longitude, pickup_latitude, store_and_fwd_flag,
                  dropoff_longitude, dropoff_latitude, fare_amount, mta_tax = 0.5, tip_amount, tolls_amount)]
  if (yr <= 2014) {
    out <- data.table(vendor_id = sample(c("CMT", "VTS"), n, replace = TRUE), pickup_datetime = pick, dropoff_datetime = drop)
    out <- cbind(out, common)
    out[, `:=`(rate_code = sample(c(1L, 2L, 5L), n, replace = TRUE, prob = c(0.97, 0.02, 0.01)),
               payment_type = sample(c("CRD", "CSH", "NOC", "DIS"), n, replace = TRUE, prob = c(0.55, 0.44, 0.005, 0.005)),
               surcharge = sample(c(0, 0.5, 1), n, replace = TRUE, prob = c(0.5, 0.3, 0.2)))]
    out[, total_amount := round(fare_amount + surcharge + mta_tax + tip_amount + tolls_amount, 2)]
    setcolorder(out, c("vendor_id", "pickup_datetime", "dropoff_datetime", "passenger_count", "trip_distance",
                       "pickup_longitude", "pickup_latitude", "rate_code", "store_and_fwd_flag", "dropoff_longitude",
                       "dropoff_latitude", "payment_type", "fare_amount", "surcharge", "mta_tax", "tip_amount",
                       "tolls_amount", "total_amount"))
  } else {
    out <- data.table(VendorID = sample(1:2, n, replace = TRUE), tpep_pickup_datetime = pick, tpep_dropoff_datetime = drop)
    out <- cbind(out, common)
    out[, `:=`(RateCodeID = sample(c(1L, 2L, 5L), n, replace = TRUE, prob = c(0.97, 0.02, 0.01)),
               payment_type = sample(1:4, n, replace = TRUE, prob = c(0.62, 0.37, 0.005, 0.005)),
               extra = sample(c(0, 0.5, 1), n, replace = TRUE, prob = c(0.5, 0.3, 0.2)), improvement_surcharge = 0.3)]
    out[, total_amount := round(fare_amount + extra + mta_tax + tip_amount + tolls_amount + improvement_surcharge, 2)]
    setcolorder(out, c("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime", "passenger_count", "trip_distance",
                       "pickup_longitude", "pickup_latitude", "RateCodeID", "store_and_fwd_flag", "dropoff_longitude",
                       "dropoff_latitude", "payment_type", "fare_amount", "extra", "mta_tax", "tip_amount",
                       "tolls_amount", "improvement_surcharge", "total_amount"))
  }
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(head(sim_taxi_yellow_csv_legacy(5, "2013-06", seed = 1)))
  print(head(sim_taxi_yellow_csv_legacy(5, "2015-06", seed = 1)))
}
