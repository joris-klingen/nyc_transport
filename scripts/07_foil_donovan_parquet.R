# Parquet copy of the Donovan and Work (2016) FOIL taxi files (raw/taxi/foil_2010_2013/FOILyyyy.zip: the
# 2010-2013 yellow trips of their Freedom of Information Law request, Illinois Data Bank
# doi:10.13012/J8PN93H8, with medallion and hack licence pseudonyms drawn anew each year) in
# derived/taxi_foil/foil_tripdata_yyyy-MM.parquet, the schema of scripts/06_foil_2013_parquet.R. The
# 2013 months come from Chris Whong's release (06, hashed ids); FOIL2013.zip holds the same trips
# relabelled and is not converted.
#
# Usage (from repo root):  Rscript scripts/07_foil_donovan_parquet.R [year] [months] [--overwrite]
#   year         2010, 2011 or 2012 (default 2012)
#   months       comma-separated month numbers, default all (e.g. 1,2)
#   --overwrite  rebuild months that already have a parquet
#
# FOILyyyy.zip holds FOILyyyy/trip_data_M.zip and trip_fare_M.zip, one CSV each. The outer archive's
# offsets wrapped at 4 GB (no Zip64), which bsdtar and Python's zipfile reject, so scripts/zipfix.py
# corrects them and extracts a member with a CRC check into a temporary directory (FOIL_TMP, else
# tempdir()); bsdtar then streams the CSV out of the inner zip into fread, as in 06. The two files
# list the same trips in the same order; rows are joined by position once medallion, hack_license,
# vendor_id and pickup_datetime agree on every row, else by these keys with a within-key sequence
# number. Rows, join checks and the taxi_yellow_legacy row count of the month go to
# _meta/foil_donovan_parquet_log.csv. The archives in raw/ stay the source.

library(data.table)
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args
year <- 2012L
months <- 1:12
for (a in setdiff(args, "--overwrite")) {
  if (grepl("^\\d{4}$", a)) year <- as.integer(a) else months <- as.integer(strsplit(a, ",")[[1]])
}
stopifnot(year %in% 2010:2012)

src <- file.path(tlc_data_dir(), "foil_2010_2013", sprintf("FOIL%d.zip", year))
stopifnot(file.exists(src))
out_dir <- tlc_foil_dir()
tmp_dir <- Sys.getenv("FOIL_TMP", file.path(tempdir(), "foil_donovan"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nyc_data_root(), "_meta"), showWarnings = FALSE)
log_file <- file.path(nyc_data_root(), "_meta", "foil_donovan_parquet_log.csv")
tar <- if (.Platform$OS.type == "windows") "C:/Windows/System32/tar.exe" else "bsdtar"
python <- Sys.which(c("python3", "python"))
python <- python[nzchar(python)][1]
stopifnot(!is.na(python))

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

# one inner zip out of the outer archive (offsets corrected, CRC checked), into tmp_dir
extract_inner <- function(member) {
  out <- file.path(tmp_dir, basename(member))
  status <- system2(python, c("-I", "scripts/zipfix.py", "extract", shQuote(src), member, shQuote(out)))
  if (status != 0) stop("zipfix.py failed on ", member)
  out
}

# the CSV inside an inner zip; columns 1-3 are the ids and vendor, column 5 the flag or payment code
# (headers have spaces after the commas)
read_member <- function(archive, member) {
  x <- fread(cmd = sprintf('"%s" -xOf "%s" %s', tar, archive, member), header = TRUE, showProgress = FALSE,
             tz = "UTC", na.strings = "", colClasses = list(character = c(1, 2, 3, 5)))
  setnames(x, trimws(names(x)))
  x
}

legacy_rows <- function(ym) {
  f <- tlc_legacy_files(year)
  f <- f[grepl(ym, basename(f), fixed = TRUE)]
  if (length(f) != 1) return(NA_real_)
  arrow::ParquetFileReader$create(f)$num_rows
}

# Months ----
for (m in months) {
  ym <- sprintf("%d-%02d", year, m)
  out <- file.path(out_dir, paste0("foil_tripdata_", ym, ".parquet"))
  if (file.exists(out) && !overwrite) next
  t0 <- Sys.time()

  z_trip <- extract_inner(sprintf("FOIL%d/trip_data_%d.zip", year, m))
  z_fare <- extract_inner(sprintf("FOIL%d/trip_fare_%d.zip", year, m))
  trip <- read_member(z_trip, sprintf("trip_data_%d.csv", m))
  fare <- read_member(z_fare, sprintf("trip_fare_%d.csv", m))
  file.remove(z_trip, z_fare)
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
