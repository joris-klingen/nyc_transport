# Build the data profiles in profiles/ from the data store
#
# Run from the repo root: Rscript profiles/build_profiles.R [source ...]
# Without arguments every source is profiled (about an hour: the taxi months, LION and the bike
# counts are the slow ones); with arguments only those sources. Each source writes
# profiles/<source>.csv (one row per column: kind, NA share, distinct values, quantiles, mean, sd)
# and profiles/<source>_values.csv (most common values and their shares), and updates its row in
# profiles/index.csv. Tables with more than `max_rows` rows are profiled on a random sample.
# Profiles describe what the readers in R/nyc_transport.R return, or the raw file when there is no
# reader. They are used by sim/ to simulate data for code development without the store.

library(data.table)
library(arrow)
library(sf)
source("R/nyc_transport.R")
source("R/simulate.R")

max_rows <- 1e6
set.seed(20261016)
root <- nyc_data_root()
rel <- function(f) sub(paste0("^", root, "/"), "", normalizePath(f, winslash = "/"))

# Helpers ----

# random rows of a parquet file, read as an arrow table first (several files are one row group)
parquet_sample <- function(f, n) {
  tb <- arrow::read_parquet(f, as_data_frame = FALSE)
  i <- sort(sample(tb$num_rows, min(n, tb$num_rows))) - 1L
  x <- as.data.table(tb$Take(arrow::Array$create(i, type = arrow::int64())))
  rm(tb); gc()
  # 64-bit integers in some years, doubles in others; null-typed columns (not yet in use that year) dropped
  for (v in names(x)[vapply(x, inherits, logical(1), "integer64")]) set(x, j = v, value = as.numeric(x[[v]]))
  nulls <- names(x)[vapply(x, function(v) inherits(v, "vctrs_unspecified") || all(is.na(v)), logical(1))]
  if (length(nulls)) x[, (nulls) := NULL]
  x
}

sample_rows <- function(x, n = max_rows) if (nrow(x) > n) x[sort(sample(.N, n))] else x

# Citi Bike stations seen as trip starts, with id, name and location together and their share of
# trips, so that simulated trips use real station triples (<source>_stations.csv)
citibike_station_table <- function(x, source) {
  st <- x[!is.na(start_lat), .(name = start_station_name[1], lat = stats::median(start_lat), lng = stats::median(start_lng), N = .N),
          by = .(station_id = start_station_id)]
  st[, share := signif(N / sum(N), 6)]
  fwrite(st[order(-N), .(station_id, name, lat, lng, share)], file.path(sim_profiles_dir(), paste0(source, "_stations.csv")))
}

# lon/lat column pairs present in a table: a longitude-like name (longitude, long, lon, lng, any
# case, with a prefix or suffix such as From or start_) whose latitude twin exists
lonlat_pairs <- function(x) {
  nm <- names(x)
  out <- list()
  for (v in nm[vapply(x, is.numeric, logical(1))]) {
    m <- regmatches(v, regexec("^(.*?)(longitude|long|lon|lng)(.*)$", v, ignore.case = TRUE))[[1]]
    if (!length(m)) next
    lat <- paste0(m[2], c("latitude", "Latitude", "LATITUDE", "lat", "Lat", "LAT"), m[4])
    lat <- lat[lat %in% nm]
    if (length(lat)) out[[length(out) + 1]] <- c(v, lat[1])
  }
  out
}

# profile a table (or sf) and write it, with the source-level facts in meta. Character columns
# holding dates or times are profiled as such (and simulated back as text in their format);
# raw = TRUE also looks for a WKT geometry column. time_col: a timestamp whose shares by hour of
# the week (Monday 0:00 = 1 ... Sunday 23:00 = 168, local time) go to <source>_hour_of_week.csv;
# weight_col: weigh the rows (counts, where rows are evenly spaced in time).
run_profile <- function(source, x, reader, files, rows_total = nrow(x), sample = "all rows",
                        notes = "", xy = NULL, cell = NULL, raw = FALSE, time_col = NULL, weight_col = NULL) {
  t0 <- Sys.time()
  if (!is.null(time_col)) {
    t <- x[[time_col]]
    w <- if (is.null(weight_col)) rep(1, length(t)) else as.numeric(x[[weight_col]])
    ok <- !is.na(t) & !is.na(w)
    t <- t[ok]; w <- w[ok]
    how <- ((data.table::wday(t) + 5L) %% 7L) * 24L + data.table::hour(t) + 1L
    h <- data.table(hour_of_week = how, w = w)[, .(N = sum(w)), hour_of_week][CJ(hour_of_week = 1:168), on = "hour_of_week"]
    h[is.na(N), N := 0]
    h[, share := signif(N / sum(N), 6)]
    fwrite(h[, .(hour_of_week, share)], file.path(sim_profiles_dir(), paste0(source, "_hour_of_week.csv")))
  }
  formats <- NULL; wkt <- NULL
  if (!inherits(x, "sf")) {
    if (raw) wkt <- profile_detect_wkt(x)
    formats <- profile_detect_formats(x[, setdiff(names(x), wkt), with = FALSE])
  }
  if (is.null(xy) && !inherits(x, "sf")) xy <- lonlat_pairs(x)
  if (is.null(cell) && length(xy)) cell <- 0.005
  rows_profiled <- nrow(x)
  p <- profile_dt(x, xy = xy, cell = cell, formats = formats, wkt = wkt)
  profile_write(p, source, list(reader = reader, files = paste(files, collapse = "; "),
                                rows_total = format(rows_total, scientific = FALSE),
                                rows_profiled = rows_profiled, sample = sample, notes = notes))
  message(sprintf("%-28s %9s rows, %3d columns, %4.0f s", source, format(rows_profiled, big.mark = ","),
                  nrow(p$columns), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# Sources ----
# each entry profiles one source; names are the profile names

sources <- list()

# TLC trips: 100k random trips from June of three years, so that the schema changes show
tlc_months_profiled <- list(yellow = c("2013-06", "2019-06", "2025-06"), green = c("2015-06", "2019-06", "2025-06"),
                            fhvhv = c("2019-06", "2022-06", "2025-06"))
for (type in names(tlc_months_profiled)) local({
  tp <- type
  sources[[paste0("taxi_", tp)]] <<- function() {
    files <- file.path(tlc_data_dir(), tp, tlc_file_name(tp, tlc_months_profiled[[tp]]))
    x <- rbindlist(lapply(files, function(f) {
      d <- parquet_sample(f, 1e5)
      d[, .file_month := substr(basename(f), nchar(tp) + 11, nchar(tp) + 17)]
    }), use.names = TRUE, fill = TRUE)
    x[, .file_month := NULL]
    all_files <- tlc_files(tp)
    rows <- sum(vapply(all_files, function(f) arrow::ParquetFileReader$create(f)$num_rows, numeric(1)))
    # columns and types by year (first month of each year), from the parquet schemas
    sch <- rbindlist(lapply(split(all_files, substr(basename(all_files), nchar(tp) + 11, nchar(tp) + 14)), function(f) {
      s <- arrow::open_dataset(f[1])$schema
      data.table(year = substr(basename(f[1]), nchar(tp) + 11, nchar(tp) + 14), column = names(s),
                 type = vapply(s$fields, function(fl) fl$type$ToString(), character(1)))
    }))
    fwrite(sch, file.path(sim_profiles_dir(), paste0("taxi_", tp, "_schema_by_year.csv")))
    run_profile(paste0("taxi_", tp), x, reader = sprintf("tlc_open('%s') / arrow::read_parquet(tlc_files('%s'))", tp, tp),
                files = sprintf("raw/taxi/%s/%s_tripdata_YYYY-MM.parquet (%d months, %s to %s)", tp, tp, length(all_files),
                                substr(basename(all_files[1]), nchar(tp) + 11, nchar(tp) + 17),
                                substr(basename(tail(all_files, 1)), nchar(tp) + 11, nchar(tp) + 17)),
                rows_total = rows, sample = paste("100,000 random trips from each of", paste(tlc_months_profiled[[tp]], collapse = ", ")),
                notes = sprintf("columns and types change across years: see taxi_%s_schema_by_year.csv; columns missing in a month are NA in the profile", tp),
                time_col = c(yellow = "tpep_pickup_datetime", green = "lpep_pickup_datetime", fhvhv = "pickup_datetime")[[tp]])
  }
})

sources$taxi_yellow_csv_legacy <- function() {
  files <- file.path(tlc_data_dir(), "yellow_csv_legacy", c("yellow_tripdata_2012-06.csv", "yellow_tripdata_2015-06.csv"))
  x <- rbindlist(lapply(files, fread, nrows = 2e5, header = TRUE, blank.lines.skip = TRUE), use.names = TRUE, fill = TRUE)
  run_profile("taxi_yellow_csv_legacy", x, reader = "data.table::fread(file.path(tlc_data_dir(), 'yellow_csv_legacy', ...))",
              files = "raw/taxi/yellow_csv_legacy/yellow_tripdata_YYYY-MM.csv (2012-01 to 2016-06)", rows_total = NA,
              sample = "first 200,000 rows of 2012-06 and of 2015-06 (files are in time order, so early days of the month)",
              notes = "2012-2014 files use vendor_id/pickup_datetime/rate_code; 2015-16 use VendorID/tpep_pickup_datetime/RateCodeID (both sets in the profile, NA where absent). Coordinates as lon/lat.",
              raw = TRUE)
}

sources$taxi_zones <- function() {
  z <- taxi_zones_read()
  run_profile("taxi_zones", z, reader = "taxi_zones_read()", files = rel(nyc_latest("taxi_zones")),
              notes = "TLC zones with the lookup columns (borough, zone, service_zone); the full lookup table is in taxi_zone_lookup_full.csv")
  fwrite(fread(nyc_latest("taxi_zone_lookup")), file.path(sim_profiles_dir(), "taxi_zone_lookup_full.csv"))
}

# Crashes: crashes_read() harmonizes names and types; persons and vehicles are read raw
sources$crashes <- function() {
  x <- crashes_read()
  run_profile("crashes", sample_rows(x), reader = "crashes_read()", files = rel(nyc_latest("crashes")), rows_total = nrow(x),
              sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
              notes = "crash_time is text H:MM; coordinates NA outside NYC; house-number crashes geocoded to address points from 2024-11 (use crashes_relocate())")
}
for (nm in c("persons", "vehicles")) local({
  s <- nm
  sources[[paste0("crash_", s)]] <<- function() {
    x <- fread(nyc_latest(s), na.strings = "")
    run_profile(paste0("crash_", s), sample_rows(x), reader = sprintf("data.table::fread(nyc_latest('%s'))", s),
                files = rel(nyc_latest(s)), rows_total = nrow(x), sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
                notes = "one row per person / vehicle in a crash; COLLISION_ID links to crashes collision_id", raw = TRUE)
  }
})

# Citi Bike: old (to 2019-12, with rider gender and birth year) and new format (2020 on)
sources$citibike_trips_2013_2019 <- function() {
  x <- rbindlist(lapply(c("2014-06", "2019-06"), citibike_read, nrows = 2e5), fill = TRUE)
  run_profile("citibike_trips_2013_2019", x, reader = "citibike_read('YYYY-MM')", files = "raw/citibike/trips/citibike_tripdata_YYYY-MM.parquet (2013-06 to 2019-12)",
              rows_total = NA, sample = "first 200,000 trips of each csv part of 2014-06 and 2019-06",
              notes = "station ids are numbers stored as text; gender 0 unknown, 1 male, 2 female", xy = list(c("start_lng", "start_lat"), c("end_lng", "end_lat")), cell = 0.005, time_col = "started_at")
  citibike_station_table(x, "citibike_trips_2013_2019")
}
sources$citibike_trips_2020_on <- function() {
  x <- rbindlist(lapply(c("2021-06", "2025-06"), citibike_read, nrows = 1e5), fill = TRUE)
  run_profile("citibike_trips_2020_on", x, reader = "citibike_read('YYYY-MM')", files = "raw/citibike/trips/citibike_tripdata_YYYY-MM.parquet (2020-01 on)",
              rows_total = NA, sample = "first 100,000 trips of each csv part of 2021-06 and 2025-06",
              notes = "station ids like 5329.03 (text); ride_id 16 hex characters", xy = list(c("start_lng", "start_lat"), c("end_lng", "end_lat")), cell = 0.005, time_col = "started_at")
  citibike_station_table(x, "citibike_trips_2020_on")
}
sources$citibike_stations <- function() {
  j <- jsonlite::fromJSON(nyc_latest("citibike_stations"))
  x <- as.data.table(j$data$stations)
  x <- x[, names(x)[vapply(x, function(v) is.atomic(v), logical(1))], with = FALSE]
  run_profile("citibike_stations", x, reader = "jsonlite::fromJSON(nyc_latest('citibike_stations'))$data$stations",
              files = rel(nyc_latest("citibike_stations")), notes = "GBFS station_information; list columns (rental_uris, ...) left out")
}

# Counts
sources$traffic_counts <- function() {
  x <- traffic_counts_read()
  run_profile("traffic_counts", sample_rows(x), reader = "traffic_counts_read()", files = rel(nyc_latest("traffic_counts")), rows_total = nrow(x),
              sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
              notes = "one row per 15 minutes, direction and count location; x, y in EPSG 2263", xy = list(c("x", "y")), cell = 2000, time_col = "time", weight_col = "Vol")
  # count locations with their attributes together, and their share of rows
  loc <- x[, .(WktGeom = WktGeom[1], x = x[1], y = y[1], Boro = Boro[1], street = street[1], fromSt = fromSt[1], toSt = toSt[1], N = .N), by = SegmentID]
  loc[, share := signif(N / sum(N), 6)]
  fwrite(loc[order(-N), !"N"], file.path(sim_profiles_dir(), "traffic_counts_locations.csv"))
}
sources$bike_ped_sensors <- function() {
  x <- bike_count_sensors()
  run_profile("bike_ped_sensors", x, reader = "bike_count_sensors()", files = rel(nyc_latest("bike_ped_sensors")),
              notes = "one row per sensor; segment_id is the nearest LION centerline; all sensors in bike_ped_sensors_full.csv", xy = list(c("longitude", "latitude")), cell = 0.005)
  fwrite(x, file.path(sim_profiles_dir(), "bike_ped_sensors_full.csv"))
}
sources$bike_ped_counts <- function() {
  x <- fread(nyc_latest("bike_ped_counts"), colClasses = list(character = c("timestamp", "flowName")))
  rows <- nrow(x)
  x <- sample_rows(x)
  # the transformations of bike_counts_read(), without the sensor and device joins
  setnames(x, c("travelMode", "flowID", "flowName"), c("travel_mode", "flow_id", "flow_name"))
  x <- x[status != "deleted"]
  x[, time := as.POSIXct(timestamp, format = "%m/%d/%Y %I:%M:%S %p", tz = "America/New_York")]
  x[, c("timestamp", "granularity") := NULL]
  run_profile("bike_ped_counts", x, reader = "bike_counts_read() (profiled before its sensor and device joins: add sensor columns from bike_ped_sensors)",
              files = rel(nyc_latest("bike_ped_counts")), rows_total = rows, sample = "1,000,000 random rows, deleted rows dropped",
              notes = "one row per sensor, flow (direction) and 15 minutes; time in NYC local time", time_col = "time", weight_col = "counts")
}
legacy <- list.files(file.path(root, "traffic_counts", "legacy"), "\\.csv$", full.names = TRUE)
legacy <- c(legacy, file.path(root, "traffic_counts", "bicycle", c("Bicycle_Counts_20200204.csv", "Bicycle_Counters_20200204.csv",
                                                                     "NYCDCP_Manhattan_Bike_Counts_-_On_Street_Weekday.csv",
                                                                     "NYCDCP_Manhattan_Bike_Counts_-_Off_Street.csv")))
for (f in legacy) local({
  ff <- f
  nm <- paste0("counts_", gsub("_+", "_", gsub("[^a-z0-9]+", "_", tolower(sub("\\.csv$", "", basename(ff))))))
  nm <- sub("_$", "", nm)
  sources[[nm]] <<- function() {
    x <- fread(ff, na.strings = "")
    run_profile(nm, sample_rows(x), reader = sprintf("data.table::fread(file.path(nyc_data_root(), '%s'))", rel(ff)),
                files = rel(ff), rows_total = nrow(x), sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
                notes = "historical file, no longer updated", raw = TRUE)
  }
})

# Streets (raw layers; the street network history in streets/ is profiled in streets/profiles)
sources$lion <- function() {
  x <- lion_read()
  all_cols <- names(sf::st_read(lion_gdb(nyc_latest("lion")), quiet = TRUE, query = "SELECT * FROM lion WHERE 1 = 0"))
  run_profile("lion", x, reader = "lion_read() (centerlines, default columns)", files = rel(nyc_latest("lion")),
              notes = paste("LION street segments in EPSG 2263; 57 quarterly releases in raw/street_layout/lion (lion_releases(), nyc_lion_for_date()).",
                            "All columns of the lion layer:", paste(all_cols, collapse = " ")))
}
sources$lion_releases <- function() {
  r <- lion_releases()[, .(release, file = basename(file), release_date)]
  fwrite(r, file.path(sim_profiles_dir(), "lion_releases_full.csv"))
  message("lion_releases: ", nrow(r), " releases written to lion_releases_full.csv")
}
sources$address_points <- function() {
  x <- address_points_read()
  run_profile("address_points", sample_rows(x), reader = "address_points_read()", files = rel(nyc_latest("address_points")), rows_total = nrow(x),
              sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows")
}
sources$bike_routes <- function() {
  x <- bike_routes_read()
  run_profile("bike_routes", x, reader = "bike_routes_read()", files = rel(nyc_latest("bike_routes")),
              notes = "DOT bike routes, one row per segment version (status Current/Retired, bikeid/prevbikeid) in EPSG 2263")
}
for (nm in c("boroughs", "community_districts", "ntas", "tracts", "blocks", "precincts")) local({
  s <- nm
  sources[[paste0("boundaries_", s)]] <<- function() {
    x <- boundaries_read(s)
    run_profile(paste0("boundaries_", s), x, reader = sprintf("boundaries_read('%s')", s), files = rel(nyc_latest(s)))
  }
})

sources$census_block_groups <- function() {
  x <- census_block_groups_read()
  run_profile("census_block_groups", x, reader = "census_block_groups_read()",
              files = "raw/boundaries/census_block_groups_2020/tl_2020_36_bg.shp",
              notes = "TIGER/Line 2020 block groups of New York State as published (EPSG 4269); NYC counties 005, 047, 061, 081, 085")
  p <- jsonlite::fromJSON(nyc_latest("bg_population"))
  pop <- setnames(as.data.table(p[-1, , drop = FALSE]), p[1, ])
  run_profile("bg_population", pop, reader = "jsonlite::fromJSON(nyc_latest('bg_population')) (first row holds the names)",
              files = rel(nyc_latest("bg_population")), notes = "2020 census population P1_001N per block group (state, county, tract, block group), all text", raw = TRUE)
}
sources$crz_entries <- function() {
  x <- fread(nyc_latest("crz_entries"), na.strings = "")
  run_profile("crz_entries", sample_rows(x), reader = "data.table::fread(nyc_latest('crz_entries'))", files = rel(nyc_latest("crz_entries")),
              rows_total = nrow(x), sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
              notes = "MTA congestion relief zone entries per 10-minute block, vehicle class and detection group from 2025-01-05", raw = TRUE)
}

# Air pollution (NYC-area extract; the national files are not profiled)
for (fq in c("hourly", "daily")) local({
  f <- fq
  sources[[paste0("air_pollution_", f)]] <<- function() {
    x <- air_pollution_read("44201", f)
    run_profile(paste0("air_pollution_", f), sample_rows(x), reader = sprintf("air_pollution_read('44201', '%s')", f),
                files = sprintf("derived/air_pollution/%s_44201.parquet", f), rows_total = nrow(x),
                sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows",
                notes = "ozone (44201); other parameters have the same columns", xy = list(c("longitude", "latitude")), cell = 0.02)
  }
})

# Other open data snapshots, read as published (csv with fread, geojson with sf)
done <- c("crashes", "persons", "vehicles", "bike_routes", "lion", "address_points", "traffic_counts", "bike_ped_counts",
          "bike_ped_sensors", "boroughs", "community_districts", "ntas", "tracts", "blocks", "precincts")
for (nm in setdiff(nyc_opendata[, name], done)) local({
  s <- nm
  sources[[s]] <<- function() {
    f <- nyc_latest(s)
    if (grepl("\\.geojson$", f)) {
      x <- sf::st_read(f, quiet = TRUE)
      run_profile(s, x, reader = sprintf("sf::st_read(nyc_latest('%s'))", s), files = rel(f), notes = "geojson in EPSG 4326, read as published")
    } else {
      x <- fread(f, na.strings = "")
      run_profile(s, sample_rows(x), reader = sprintf("data.table::fread(nyc_latest('%s'))", s), files = rel(f), rows_total = nrow(x),
                  sample = if (nrow(x) > max_rows) "1,000,000 random rows" else "all rows", notes = "csv read as published", raw = TRUE)
    }
  }
})

# Run ----

args <- commandArgs(trailingOnly = TRUE)
todo <- if (length(args)) args else names(sources)
bad <- setdiff(todo, names(sources))
if (length(bad)) stop("unknown sources: ", paste(bad, collapse = ", "), "\navailable: ", paste(names(sources), collapse = ", "))
failed <- character()
for (s in todo) {
  ok <- tryCatch({ sources[[s]](); TRUE }, error = function(e) { message(s, " FAILED: ", conditionMessage(e)); FALSE })
  if (!ok) failed <- c(failed, s)
  gc()
}
if (length(failed)) message("failed: ", paste(failed, collapse = ", "))
