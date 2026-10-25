# Parquet copy of the legacy yellow taxi CSVs (2012-01 to 2016-06, the only yellow trips with
# pickup and dropoff coordinates) in derived/taxi_yellow_legacy/yellow_tripdata_YYYY-MM.parquet
#
# Usage (from repo root):  Rscript scripts/02_yellow_legacy_parquet.R [years] [--overwrite]
#   years        comma-separated, default all (e.g. 2012,2013)
#   --overwrite  rebuild months that already have a parquet
#
# One schema for all months, in the names and codes of the TLC parquet files (raw/taxi/yellow):
#   VendorID          int   CMT = 1, VTS = 2 (2012-2014 write the text codes)
#   tpep_*_datetime   timestamp, local clock time stored as UTC, as in the TLC parquet files
#   RatecodeID        int   as published (0, 7, 210, ... kept; the TLC parquet files code these 99)
#   store_and_fwd_flag chr  "" is NA, as in the TLC parquet files
#   payment_type      int   CRD = 1, CSH = 2, NOC = 3, DIS = 4, UNK = 5 (2012-2014 write the text codes)
#   extra             num   `surcharge` in 2012-2014
#   improvement_surcharge   NA before 2015
#   pickup_/dropoff_longitude, _latitude  as published (0 or outside NYC for about 2% of trips)
# Rows are sorted by pickup time and written in row groups of 250,000 trips. The CSVs in
# raw/taxi/yellow_csv_legacy (.csv or, after scripts/03_gzip_yellow_legacy.sh, .csv.gz) stay the
# source; checks/yellow_legacy_parquet.R compares row counts.

library(data.table)
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args
years <- setdiff(args, "--overwrite")
years <- if (length(years)) as.integer(strsplit(years[1], ",")[[1]]) else 2012:2016

src_dir <- file.path(tlc_data_dir(), "yellow_csv_legacy")
out_dir <- tlc_legacy_dir()
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cols <- c("VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime", "passenger_count", "trip_distance",
          "pickup_longitude", "pickup_latitude", "RatecodeID", "store_and_fwd_flag", "dropoff_longitude",
          "dropoff_latitude", "payment_type", "fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount",
          "improvement_surcharge", "total_amount")
renames <- c(vendor_id = "VendorID", pickup_datetime = "tpep_pickup_datetime", dropoff_datetime = "tpep_dropoff_datetime",
             rate_code = "RatecodeID", RateCodeID = "RatecodeID", surcharge = "extra")
vendor_codes <- c(CMT = 1L, VTS = 2L, "1" = 1L, "2" = 2L)
payment_codes <- c(CRD = 1L, CSH = 2L, NOC = 3L, DIS = 4L, UNK = 5L, "1" = 1L, "2" = 2L, "3" = 3L, "4" = 4L, "5" = 5L)

# text code to TLC number; stops on a value the map does not know
recode <- function(x, codes, what) {
  x <- toupper(trimws(x))
  bad <- setdiff(unique(x[!is.na(x) & x != ""]), names(codes))
  if (length(bad)) stop(what, ": unknown codes ", paste(head(bad, 10), collapse = ", "))
  unname(codes[x])
}

files <- list.files(src_dir, pattern = "^yellow_tripdata_\\d{4}-\\d{2}\\.csv(\\.gz)?$", full.names = TRUE)
files <- files[as.integer(substr(basename(files), 17, 20)) %in% years]

for (f in files) {
  out <- file.path(out_dir, sub("\\.csv(\\.gz)?$", ".parquet", basename(f)))
  if (file.exists(out) && !overwrite) next
  t0 <- Sys.time()
  # a blank line follows the header in 2012-2014, and 2014 headers have spaces after the commas
  hdr <- trimws(names(fread(f, nrows = 0, blank.lines.skip = TRUE)))
  x <- fread(f, header = TRUE, blank.lines.skip = TRUE, showProgress = FALSE, tz = "UTC", na.strings = "",
             colClasses = list(character = which(tolower(hdr) %in% c("vendor_id", "vendorid", "payment_type", "store_and_fwd_flag"))))
  setnames(x, trimws(names(x)))
  setnames(x, names(x), ifelse(names(x) %in% names(renames), renames[names(x)], names(x)))
  if (!"improvement_surcharge" %in% names(x)) x[, improvement_surcharge := NA_real_]
  stopifnot(setequal(names(x), cols))
  setcolorder(x, cols)

  x[, VendorID := recode(VendorID, vendor_codes, "VendorID")]
  x[, payment_type := recode(payment_type, payment_codes, "payment_type")]
  for (v in c("passenger_count", "RatecodeID")) set(x, j = v, value = as.integer(x[[v]]))
  for (v in c("trip_distance", "pickup_longitude", "pickup_latitude", "dropoff_longitude", "dropoff_latitude",
              "fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount", "improvement_surcharge", "total_amount"))
    set(x, j = v, value = as.numeric(x[[v]]))
  for (v in c("tpep_pickup_datetime", "tpep_dropoff_datetime"))
    if (!inherits(x[[v]], "POSIXct")) set(x, j = v, value = as.POSIXct(x[[v]], tz = "UTC"))

  setorder(x, tpep_pickup_datetime, na.last = TRUE)
  arrow::write_parquet(x, paste0(out, ".part"), chunk_size = 250000)
  nyc_rename(paste0(out, ".part"), out)
  message(basename(out), ": ", nrow(x), " trips, ", round(as.numeric(Sys.time() - t0, units = "secs")), " s")
  rm(x); gc()
}
