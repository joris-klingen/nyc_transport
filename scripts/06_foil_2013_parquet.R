# Parquet copy of the 2013 FOIL taxi files (raw/taxi/foil_2013: the 2013 yellow trips as released
# under Chris Whong's Freedom of Information Law request, with hashed medallion and hack licence ids)
# in derived/taxi_foil/foil_tripdata_2013-MM.parquet (tlc_foil_dir(); the 2010-2012 months of the
# Donovan and Work release are added by scripts/07_foil_donovan_parquet.R in the same schema)
#
# Usage (from repo root):  Rscript scripts/06_foil_2013_parquet.R [months] [--overwrite]
#   months       comma-separated month numbers, default all (e.g. 1,2)
#   --overwrite  rebuild months that already have a parquet
#
# Each month streams trip_data_M.csv and trip_fare_M.csv out of the 7z archives with bsdtar (the
# Windows tar.exe reads 7z) into fread, joins the two and writes one parquet in the taxi_yellow_legacy
# schema (TLC parquet names and codes, clock time stored as UTC, sorted by pickup time) plus
#   medallion, hack_license   chr  MD5 hashes as published (reversible: use as opaque ids only)
#   trip_time_in_secs         int  the meter's trip time
# The two files list the same trips in the same order; rows are joined by position once medallion,
# hack_license, vendor_id and pickup_datetime agree on every row, else by these keys with a
# within-key sequence number. Rows, join checks and the taxi_yellow_legacy row count of the month go
# to _meta/foil_2013_parquet_log.csv. The archives in raw/ stay the source.

library(data.table)
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args
months <- setdiff(args, "--overwrite")
months <- if (length(months)) as.integer(strsplit(months[1], ",")[[1]]) else 1:12

src_dir <- file.path(tlc_data_dir(), "foil_2013")
out_dir <- tlc_foil_dir()
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nyc_data_root(), "_meta"), showWarnings = FALSE)
log_file <- file.path(nyc_data_root(), "_meta", "foil_2013_parquet_log.csv")
tar <- if (.Platform$OS.type == "windows") "C:/Windows/System32/tar.exe" else "bsdtar"

cols <- c("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime", "passenger_count", "trip_distance",
          "pickup_longitude", "pickup_latitude", "RatecodeID", "store_and_fwd_flag", "dropoff_longitude",
          "dropoff_latitude", "payment_type", "fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount",
          "improvement_surcharge", "total_amount", "medallion", "hack_license", "trip_time_in_secs")
renames <- c(vendor_id = "VendorID", pickup_datetime = "tpep_pickup_datetime", dropoff_datetime = "tpep_dropoff_datetime",
             rate_code = "RatecodeID", surcharge = "extra")
vendor_codes <- c(CMT = 1L, VTS = 2L)
payment_codes <- c(CRD = 1L, CSH = 2L, NOC = 3L, DIS = 4L, UNK = 5L)
key_cols <- c("medallion", "hack_license", "vendor_id", "pickup_datetime")

# text code to TLC number; stops on a value the map does not know
recode <- function(x, codes, what) {
  x <- toupper(trimws(x))
  bad <- setdiff(unique(x[!is.na(x) & x != ""]), names(codes))
  if (length(bad)) stop(what, ": unknown codes ", paste(head(bad, 10), collapse = ", "))
  unname(codes[x])
}

# one CSV out of an archive; columns 1-3 are the ids and vendor, column 5 the flag or payment code
# (headers of some months have spaces after the commas)
read_member <- function(archive, member) {
  x <- fread(cmd = sprintf('"%s" -xOf "%s" %s', tar, archive, member), header = TRUE, showProgress = FALSE,
             tz = "UTC", na.strings = "", colClasses = list(character = c(1, 2, 3, 5)))
  setnames(x, trimws(names(x)))
  x
}

legacy_rows <- function(ym) {
  f <- tlc_legacy_files(2013)
  f <- f[grepl(ym, basename(f), fixed = TRUE)]
  if (length(f) != 1) return(NA_real_)
  arrow::ParquetFileReader$create(f)$num_rows
}

# Months ----
for (m in months) {
  ym <- sprintf("2013-%02d", m)
  out <- file.path(out_dir, paste0("foil_tripdata_", ym, ".parquet"))
  if (file.exists(out) && !overwrite) next
  t0 <- Sys.time()

  trip <- read_member(file.path(src_dir, "trip_data.7z"), paste0("trip_data_", m, ".csv"))
  fare <- read_member(file.path(src_dir, "trip_fare.7z"), paste0("trip_fare_", m, ".csv"))
  stopifnot(all(key_cols %in% names(trip)), all(key_cols %in% names(fare)))

  # Join ----
  aligned <- nrow(trip) == nrow(fare) &&
    isTRUE(all(trip[, medallion] == fare[, medallion] & trip[, hack_license] == fare[, hack_license] &
               trip[, vendor_id] == fare[, vendor_id] & trip[, pickup_datetime] == fare[, pickup_datetime]))
  fare_cols <- c("payment_type", "fare_amount", "surcharge", "mta_tax", "tip_amount", "tolls_amount", "total_amount")
  if (aligned) {
    x <- cbind(trip, fare[, ..fare_cols])
  } else {
    trip[, seq := seq_len(.N), by = key_cols]
    fare[, seq := seq_len(.N), by = key_cols]
    x <- merge(trip, fare[, c(key_cols, "seq", fare_cols), with = FALSE], by = c(key_cols, "seq"), all.x = TRUE, sort = FALSE)
    x[, seq := NULL]
  }
  unmatched <- x[is.na(total_amount), .N]
  n_trip <- nrow(trip); n_fare <- nrow(fare)
  rm(trip, fare); gc()

  # Schema ----
  setnames(x, names(x), ifelse(names(x) %in% names(renames), renames[names(x)], names(x)))
  x[, improvement_surcharge := NA_real_]
  stopifnot(setequal(names(x), cols))
  setcolorder(x, cols)
  x[, VendorID := recode(VendorID, vendor_codes, "VendorID")]
  x[, payment_type := recode(payment_type, payment_codes, "payment_type")]
  for (v in c("passenger_count", "RatecodeID", "trip_time_in_secs")) set(x, j = v, value = as.integer(x[[v]]))
  for (v in c("trip_distance", "pickup_longitude", "pickup_latitude", "dropoff_longitude", "dropoff_latitude",
              "fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount", "total_amount"))
    set(x, j = v, value = as.numeric(x[[v]]))
  for (v in c("tpep_pickup_datetime", "tpep_dropoff_datetime"))
    if (!inherits(x[[v]], "POSIXct")) set(x, j = v, value = as.POSIXct(x[[v]], tz = "UTC"))

  setorder(x, tpep_pickup_datetime, na.last = TRUE)
  arrow::write_parquet(x, paste0(out, ".part"), chunk_size = 250000)
  nyc_rename(paste0(out, ".part"), out)

  secs <- round(as.numeric(Sys.time() - t0, units = "secs"))
  row <- data.table(time = format(Sys.time()), ym, trip_rows = n_trip, fare_rows = n_fare, aligned, unmatched,
                    rows = nrow(x), legacy_rows = legacy_rows(ym), medallions = uniqueN(x[, medallion]),
                    drivers = uniqueN(x[, hack_license]), secs)
  fwrite(row, log_file, append = file.exists(log_file))
  message(basename(out), ": ", nrow(x), " trips (legacy ", row[, legacy_rows], "), ",
          if (aligned) "joined by position" else paste("joined by key,", unmatched, "without fare"), ", ",
          row[, drivers], " drivers, ", secs, " s")
  rm(x); gc()
}
