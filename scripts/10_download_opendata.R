# Download dated snapshots of NYC Open Data datasets into nyc_transport_data
#
# Usage (from repo root):  Rscript scripts/10_download_opendata.R [names]
#   names  comma-separated subset of the datasets in nyc_opendata (R/config.R), default all
#
# A new snapshot is only downloaded when the dataset was updated after the
# most recent local snapshot. Snapshots are named <prefix>_YYYYMMDD.<ext>.
# A download identical to the latest snapshot is not kept (logged as "unchanged",
# and not downloaded again until the remote date moves).
# Every attempt is logged to opendata_download_log.csv at the data root.

library(data.table)
source("R/config.R")

urls <- c(
  csv     = "https://%s/api/views/%s/rows.csv?accessType=DOWNLOAD",
  geojson = "https://%s/api/geospatial/%s?method=export&format=GeoJSON",
  zip     = "https://%s/download/%s/application/zip"
)
# the geospatial export is empty for some sets (bus lanes); the API endpoint then has the features
url_geojson_api <- "https://%s/resource/%s.geojson?$limit=10000000"

datasets <- copy(nyc_opendata)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1) datasets <- datasets[name %in% strsplit(args[1], ",")[[1]]]

root <- nyc_data_root()
today <- format(Sys.Date(), "%Y%m%d")
dir.create(file.path(root, "_meta"), showWarnings = FALSE)
log_file <- file.path(root, "_meta", "opendata_download_log.csv")
options(timeout = 7200)

last_updated <- function(domain, id) {
  j <- jsonlite::fromJSON(sprintf("https://%s/api/views/%s.json", domain, id))
  ts <- j$rowsUpdatedAt %||% j$viewLastModified
  as.Date(as.POSIXct(ts, origin = "1970-01-01"))
}

log_row <- function(d, status, remote, size = NA_real_, msg = "") {
  fwrite(data.table(time = format(Sys.time()), name = d[, name], id = d[, id], status, remote_updated = format(remote),
                    size, message = msg), log_file, append = file.exists(log_file))
}

# remote dates already found identical to the latest snapshot
unchanged <- if (file.exists(log_file)) fread(log_file, colClasses = "character")[status == "unchanged"] else data.table()
unchanged <- if (nrow(unchanged)) unchanged[, .(remote = max(as.Date(remote_updated))), by = name] else
  data.table(name = character(), remote = as.Date(character()))

# an error page or empty export instead of data
looks_valid <- function(f, ext) {
  if (!file.exists(f) || file.size(f) < 200) return(FALSE)
  head <- readChar(f, 200, useBytes = TRUE)
  if (grepl("^\\s*<", head) || grepl('"error"\\s*:\\s*true', head)) return(FALSE)
  if (ext == "geojson") return(grepl("FeatureCollection", head) && grepl('"Feature"', readChar(f, 5000, useBytes = TRUE)))
  TRUE
}

# Download loop ----
for (i in seq_len(nrow(datasets))) {
  d <- datasets[i]
  out_dir <- file.path(root, "raw", d[, dir])
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  pattern <- nyc_snapshot_pattern(d[, prefix], d[, ext])
  local <- sort(list.files(out_dir, pattern = pattern))
  latest_local <- if (length(local)) as.Date(sub(pattern, "\\1", local[length(local)]), "%Y%m%d") else as.Date("1900-01-01")
  latest_seen <- max(latest_local, unchanged[name == d[, name], remote])
  updated <- tryCatch(last_updated(d[, domain], d[, id]), error = function(e) NA)
  if (is.na(updated)) { message(d[, name], ": metadata FAILED"); log_row(d, "metadata failed", NA); next }

  message(d[, name], ": remote updated ", updated, ", latest local snapshot ", latest_local)
  if (updated <= latest_seen) { log_row(d, "up to date", updated); next }

  dest <- file.path(out_dir, paste0(d[, prefix], "_", today, ".", d[, ext]))
  part <- paste0(dest, ".part")
  # curl handles multi-GB exports more reliably than download.file
  fetch <- function(url) tryCatch({
    if (requireNamespace("curl", quietly = TRUE)) curl::curl_download(url, part, quiet = TRUE)
    else if (download.file(url, part, mode = "wb", quiet = TRUE) != 0) stop("download.file returned non-zero")
    if (looks_valid(part, d[, ext])) "" else "response is not data"
  }, error = function(e) conditionMessage(e))
  err <- fetch(sprintf(urls[[d[, ext]]], d[, domain], d[, id]))
  if (err != "" && d[, ext] == "geojson") err <- fetch(sprintf(url_geojson_api, d[, domain], d[, id]))
  if (err != "") {
    unlink(part)
    log_row(d, "FAILED", updated, msg = err)
    message(d[, name], ": FAILED (", err, ")")
  } else if (length(local) && unname(tools::md5sum(part)) == unname(tools::md5sum(file.path(out_dir, local[length(local)])))) {
    unlink(part)
    log_row(d, "unchanged", updated, msg = paste("same as", local[length(local)]))
    message(d[, name], ": unchanged since ", local[length(local)])
  } else {
    nyc_rename(part, dest)
    log_row(d, "downloaded", updated, file.size(dest))
    message(d[, name], ": saved ", basename(dest), " ", round(file.size(dest) / 1e6), " MB")
  }
}
