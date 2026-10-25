# Download EPA AQS pre-generated monitor files (national, hourly and daily) into air_pollution/epa_aqs,
# stored as parquet (one per published zip, same name, columns as published)
#
# Usage (from repo root):  Rscript scripts/40_download_epa_aqs.R [first_year] [params] [--keep-zips]
#   first_year  default 2012
#   params      comma-separated subset of the parameter codes below, default all
#   --keep-zips keep the published zips next to the parquet (default: delete, they stay on the EPA site)
#
# Files come from https://aqs.epa.gov/aqsweb/airdata/download_files.html, are published per
# parameter and year for the whole US, and are revised about twice a year (recent years most).
# A file is downloaded when its parquet is missing or its Last-Modified / size differs from the
# manifest; the replaced parquet is kept as *.superseded_YYYYMMDD.parquet. A zip already in the
# folder that matches the manifest is converted without downloading. Site and monitor lists are
# dated snapshots. Codes (state, county, site, parameter, method) are kept as text.

library(data.table)
source("R/config.R")

base <- "https://aqs.epa.gov/aqsweb/airdata/"
params <- c(
  "44201"    = "ozone",
  "42602"    = "NO2",
  "NONOxNOy" = "NO, NOx, NOy",
  "42101"    = "CO",
  "42401"    = "SO2",
  "88101"    = "PM2.5 FRM/FEM",
  "88502"    = "PM2.5 non-FRM",
  "81102"    = "PM10",
  "WIND"     = "wind speed and direction",
  "TEMP"     = "temperature"
)

args <- commandArgs(trailingOnly = TRUE)
keep_zips <- "--keep-zips" %in% args
args <- setdiff(args, "--keep-zips")
first_year <- if (length(args) >= 1) as.integer(args[1]) else 2012L
if (length(args) >= 2) params <- params[strsplit(args[2], ",")[[1]]]
years <- first_year:as.integer(format(Sys.Date(), "%Y"))

root <- file.path(nyc_data_root(), "raw", "air_pollution", "epa_aqs")
for (d in c("hourly", "daily", "sites")) dir.create(file.path(root, d), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nyc_data_root(), "_meta"), showWarnings = FALSE)
manifest_file <- file.path(nyc_data_root(), "_meta", "epa_aqs_manifest.csv")
manifest <- if (file.exists(manifest_file)) fread(manifest_file, colClasses = "character") else
  data.table(file = character(), dir = character(), remote_modified = character(), size = character(), downloaded = character())
today <- format(Sys.Date(), "%Y%m%d")
options(timeout = 3600)

head_info <- function(url) {
  h <- tryCatch(curlGetHeaders(url), error = function(e) NULL)
  if (is.null(h) || attr(h, "status") != 200) return(NULL)
  get <- function(k) { l <- grep(paste0("^", k, ":"), h, ignore.case = TRUE, value = TRUE); trimws(sub("^[^:]*:", "", l[length(l)])) }
  list(modified = get("Last-Modified"), size = get("Content-Length"))
}

# the csv inside a published zip as parquet, codes as text
zip_to_parquet <- function(zip, out) {
  codes <- c("State Code", "County Code", "Site Num", "Site Number", "Parameter Code", "Method Code", "POC")
  hdr <- names(fread(cmd = paste("unzip -p", shQuote(zip)), nrows = 0))
  x <- fread(cmd = paste("unzip -p", shQuote(zip)), colClasses = list(character = intersect(codes, hdr)), showProgress = FALSE)
  arrow::write_parquet(x, paste0(out, ".part"))
  nyc_rename(paste0(out, ".part"), out)
  nrow(x)
}

# dest_name is the published (zip) name; the manifest keeps it, the store keeps the parquet
fetch <- function(fname, subdir, dest_name = fname) {
  url <- paste0(base, fname)
  info <- head_info(url)
  if (is.null(info)) { message(fname, ": not published"); return(invisible()) }
  zip <- file.path(root, subdir, dest_name)
  dest <- sub("\\.zip$", ".parquet", zip)
  known <- manifest[file == dest_name & dir == subdir]
  current <- nrow(known) && known[.N, remote_modified] == info$modified && known[.N, size] == info$size
  if (current && file.exists(dest)) { if (!keep_zips) unlink(zip); return(invisible()) }
  if (!(current && file.exists(zip) && file.size(zip) == as.numeric(info$size))) {
    part <- paste0(zip, ".part")
    ok <- tryCatch({ curl::curl_download(url, part, quiet = TRUE); file.size(part) == as.numeric(info$size) }, error = function(e) FALSE)
    if (!ok) { unlink(part); message(fname, ": FAILED"); return(invisible()) }
    nyc_rename(part, zip)
  }
  if (file.exists(dest) && !current) nyc_rename(dest, sub("\\.parquet$", paste0(".superseded_", today, ".parquet"), dest))
  n <- zip_to_parquet(zip, dest)
  if (!keep_zips) unlink(zip)
  if (!current) {
    manifest <<- rbind(manifest, data.table(file = dest_name, dir = subdir, remote_modified = info$modified, size = info$size, downloaded = today))
    fwrite(manifest, manifest_file)
  }
  message(basename(dest), ": ", n, " rows (", info$modified, ")")
}

# Monitor data ----
for (p in names(params)) for (y in years) {
  fetch(sprintf("hourly_%s_%d.zip", p, y), "hourly")
  fetch(sprintf("daily_%s_%d.zip", p, y), "daily")
}

# Sites and monitors (current lists, dated) ----
# dated zips from before the switch to parquet
for (z in list.files(file.path(root, "sites"), pattern = "^aqs_(sites|monitors)_\\d{8}\\.zip$", full.names = TRUE)) {
  zip_to_parquet(z, sub("\\.zip$", ".parquet", z))
  if (!keep_zips) unlink(z)
}
for (f in c("aqs_sites", "aqs_monitors")) {
  latest <- tail(sort(list.files(file.path(root, "sites"), pattern = paste0("^", f, "_\\d{8}\\.parquet$"))), 1)
  latest <- sub("\\.parquet$", ".zip", latest)
  info <- head_info(paste0(base, f, ".zip"))
  if (!is.null(info) && (!length(latest) || !identical(manifest[file == latest, remote_modified][1], info$modified)))
    fetch(paste0(f, ".zip"), "sites", paste0(f, "_", today, ".zip"))
}
