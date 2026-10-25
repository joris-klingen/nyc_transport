# Simulated Citi Bike trips
#
# Real data: raw/citibike/trips/citibike_tripdata_YYYY-MM.parquet (2013-06 onward, ~35M trips a year lately), read with
# citibike_read("YYYY-MM"). One row per trip, in one schema across the 2020 format change:
#   started_at, ended_at (POSIXct, America/New_York), start_station_id, start_station_name,
#   start_lat, start_lng, end_station_id, end_station_name, end_lat, end_lng (text ids),
#   member (TRUE for members / subscribers)
#   to 2019-12 also: bikeid, birth_year, gender (text: 0 unknown, 1 male, 2 female)
#   from 2020 also:  rideable_type (classic_bike, electric_bike), ride_id (16 hex characters)
# Station ids are numbers like "519" before 2020 and "5329.03" after.
#
# Kept: real stations (id, name and location together) with their share of trips
# (profiles/citibike_trips_*_stations.csv); end stations near the start (weighted by popularity
# and distance, median trip about 1.5 km); start times by the real hour-of-week pattern;
# durations of about 10 minutes (members shorter than casual riders); the columns of the month's
# format. Not kept: seasonality, the network growing over the years, round trips.
#
# cb <- sim_citibike_trips(20000, month = "2019-06")

sim_citibike_trips <- function(n = 1000, month = "2025-06", seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  old <- as.integer(substr(month, 1, 4)) < 2020
  src <- if (old) "citibike_trips_2013_2019" else "citibike_trips_2020_on"
  x <- sim_profile(src, n)
  st <- sim_ref(paste0(src, "_stations.csv"), colClasses = c(station_id = "character"))
  st <- st[!is.na(lat) & !is.na(lng)]
  r <- sim_month_range(month)
  x[, started_at := sim_times(n, r[["from"]], r[["to"]], src)]
  # start stations by popularity, end stations by popularity and distance from the start
  s <- sample(nrow(st), n, replace = TRUE, prob = st[, share])
  e <- integer(n)
  km <- function(i) sqrt(((st[, lat] - st[i, lat]) * 111)^2 + ((st[, lng] - st[i, lng]) * 84)^2)
  for (i in unique(s)) {
    w <- st[, share] * exp(-km(i) / 1.2)
    idx <- which(s == i)
    e[idx] <- sample(nrow(st), length(idx), replace = TRUE, prob = w)
  }
  x[, `:=`(start_station_id = st[s, station_id], start_station_name = st[s, name], start_lat = st[s, lat], start_lng = st[s, lng],
           end_station_id = st[e, station_id], end_station_name = st[e, name], end_lat = st[e, lat], end_lng = st[e, lng])]
  mins <- pmin(180, stats::rlnorm(n, log(fifelse(x[, member], 9, 15)), 0.6))
  x[, ended_at := started_at + round(mins * 60)]
  if (!old) x[, ride_id := sim_ids(.N, "HEX", 16, 16)]
  x[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  cb <- sim_citibike_trips(2000, "2019-06", seed = 1)
  str(cb)
  print(cb[, .(med_km = median(sqrt(((end_lat - start_lat) * 111)^2 + ((end_lng - start_lng) * 84)^2)))])
}
