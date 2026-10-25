# Download Citi Bike (NYC, not Jersey City) trip data and store it as one parquet per month
# in nyc_transport_data/raw/citibike/trips (citibike_tripdata_YYYY-MM.parquet)
#
# Usage (from repo root):  Rscript scripts/20_download_citibike.R [pattern] [--keep-zips]
#   pattern      regular expression on the zip names to process, default all (e.g. "^201[3-6]")
#   --keep-zips  keep the published zips after conversion (default: delete, they stay on S3)
#
# Files are listed from the public S3 bucket. A zip is (re)processed when the manifest lacks it,
# its size on S3 changed (republished), or one of its months has no parquet. Each month is written
# in the schema of citibike_read() (one schema across the 2020 format change). Parquets replaced by
# a republished zip are kept as *.superseded_YYYYMMDD.parquet. A zip already in the folder is
# converted without downloading it again.

library(data.table)
source("R/nyc_transport.R")

bucket <- "https://s3.amazonaws.com/tripdata"
raw_dir <- citibike_dir()
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nyc_data_root(), "_meta"), showWarnings = FALSE)
manifest_file <- file.path(nyc_data_root(), "_meta", "citibike_manifest.csv")
options(timeout = 7200)
today <- format(Sys.Date(), "%Y%m%d")

args <- commandArgs(trailingOnly = TRUE)
keep_zips <- "--keep-zips" %in% args
pattern <- setdiff(args, "--keep-zips")[1]

# List bucket ----
x <- paste(readLines(paste0(bucket, "?list-type=2"), warn = FALSE), collapse = "")
keys <- regmatches(x, gregexpr("<Key>[^<]+</Key>", x))[[1]]
sizes <- regmatches(x, gregexpr("<Size>\\d+</Size>", x))[[1]]
if (grepl("<IsTruncated>true", x)) warning("bucket listing truncated; add pagination")

files <- data.table(obj = gsub("</?Key>", "", keys), size = as.numeric(gsub("</?Size>", "", sizes)))
files <- files[grepl("citibike-tripdata\\.zip$", obj) & !grepl("^JC", obj)]
if (!is.na(pattern)) files <- files[grepl(pattern, obj)]

# manifest: one row per zip with its size on S3 and the months it holds
read_manifest <- function() {
  if (file.exists(manifest_file) && "months" %in% names(fread(manifest_file, nrows = 0))) fread(manifest_file, colClasses = "character")
  else data.table(file = character(), size = character(), months = character(), converted = character())
}
manifest <- read_manifest()

pq_path <- function(m) file.path(raw_dir, sprintf("citibike_tripdata_%s.parquet", m))

# months held by a zip, from the file names inside it (YYYYMM-...)
zip_months <- function(z) {
  n <- basename(utils::unzip(z, list = TRUE)$Name)
  m <- unique(sub("^(\\d{4})(\\d{2}).*", "\\1-\\2", grep("^\\d{6}", n, value = TRUE)))
  sort(m[startsWith(gsub("-", "", m), sub("-citibike.*", "", basename(z)))])
}

# Download and convert ----
for (i in seq_len(nrow(files))) {
  k <- files[i, obj]; s <- files[i, size]
  known <- manifest[file == k]
  dest <- file.path(raw_dir, k)
  if (nrow(known) && as.numeric(known[.N, size]) == s &&
      all(file.exists(pq_path(strsplit(known[.N, months], ";")[[1]])))) {
    if (!keep_zips) unlink(dest)
    next
  }
  if (!file.exists(dest) || file.size(dest) != s) {
    message(k, ": downloading (", round(s / 1e6), " MB)")
    part <- paste0(dest, ".part")
    ok <- tryCatch(download.file(paste0(bucket, "/", k), part, mode = "wb", quiet = TRUE) == 0,
                   error = function(e) FALSE)
    if (!ok || file.size(part) != s) { unlink(part); message(k, ": FAILED"); next }
    nyc_rename(part, dest)
  }

  months <- zip_months(dest)
  republished <- nrow(known) && as.numeric(known[.N, size]) != s
  for (m in months) {
    out <- pq_path(m)
    # converted by an earlier, interrupted run
    if (!republished && file.exists(out)) next
    t0 <- Sys.time()
    trips <- citibike_read_zip(dest, m)
    # sorted by start time in row groups of 250,000 trips (2-3 days), so time filters skip row groups
    data.table::setorder(trips, started_at, na.last = TRUE)
    if (republished && file.exists(out)) nyc_rename(out, sub("\\.parquet$", paste0(".superseded_", today, ".parquet"), out))
    arrow::write_parquet(trips, paste0(out, ".part"), chunk_size = 250000)
    nyc_rename(paste0(out, ".part"), out)
    message(k, " ", m, ": ", nrow(trips), " trips, ", round(as.numeric(Sys.time() - t0, units = "secs")), " s")
    rm(trips); gc()
  }
  # re-read first: parallel runs on different patterns share the manifest
  manifest <- read_manifest()
  manifest <- rbind(manifest[file != k], data.table(file = k, size = as.character(s), months = paste(months, collapse = ";"), converted = today))
  setorder(manifest, file)
  fwrite(manifest, manifest_file)
  if (!keep_zips) unlink(dest)
}

pq <- citibike_files()
message("citibike: ", length(pq), " months, ", round(sum(file.size(pq)) / 1e9, 1), " GB of parquet")
