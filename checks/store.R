# Completeness and basic quality of the whole data store
#
# - every dataset in nyc_snapshots has a snapshot, with its age
# - the Open Data download log: datasets whose last attempt failed
# - TLC: missing months per type, rows per month from parquet metadata (sudden drops), zone ids
#   and pickup months in the latest months
# - Citi Bike: months covered by the archives
# - traffic counts: rows per year, SegmentID found in current LION
# - boundaries and taxi zones: feature counts and valid geometries
# Ends with a list of problems.
#
# Run from the repo root: Rscript checks/store.R

library(data.table)
library(sf)
source("R/nyc_transport.R")

problems <- character()
flag <- function(...) problems <<- c(problems, paste0(...))

# Snapshots ----
snap <- rbindlist(lapply(names(nyc_snapshots), function(n) {
  f <- nyc_snapshot_files(n)
  if (!length(f)) return(data.table(dataset = n, snapshots = 0L))
  data.table(dataset = n, snapshots = length(f), latest = as.IDate(names(f)[length(f)], format = "%Y%m%d"),
             MB = round(file.size(f[length(f)]) / 1e6))
}), fill = TRUE)
snap[, age_days := as.integer(as.IDate(Sys.Date()) - latest)]
print(snap)
for (n in snap[snapshots == 0, dataset]) flag("no snapshot of ", n)

# Open Data download log ----
log_file <- file.path(nyc_data_root(), "_meta", "opendata_download_log.csv")
if (file.exists(log_file)) {
  lg <- fread(log_file)
  last <- lg[, .SD[.N], name]
  print(last[, .(name, time, status, remote_updated, MB = round(size / 1e6), message)])
  for (i in which(last$status != "downloaded" & last$status != "up to date")) flag("last download of ", last$name[i], ": ", last$status[i], " ", last$message[i])
} else flag("no Open Data download log yet (run scripts/10_download_opendata.R)")

# TLC ----
for (t in names(tlc_start)[names(tlc_start) %in% list.files(tlc_data_dir())]) {
  f <- tlc_files(t)
  ym <- regmatches(basename(f), regexpr("\\d{4}-\\d{2}", basename(f)))
  exp <- tlc_months(tlc_start[[t]], max(ym))
  miss <- setdiff(exp, ym)
  rows <- vapply(f, function(x) arrow::ParquetFileReader$create(x)$num_rows, numeric(1))
  m <- data.table(ym, rows)[order(ym)]
  # drop against the median of the surrounding 12 months
  m[, ref := frollapply(rows, 13, median, align = "center", partial = TRUE)]
  cat(sprintf("\nTLC %s: %d months %s to %s, %d missing, %.0fM trips\n", t, length(ym), min(ym), max(ym), length(miss), sum(rows) / 1e6))
  if (length(miss)) flag("TLC ", t, " missing months: ", paste(miss, collapse = ", "))
  drops <- m[rows < .5 * ref]
  if (nrow(drops)) { print(drops); flag("TLC ", t, " months with fewer than half the usual trips: ", paste(drops$ym, collapse = ", ")) }
  # latest three months: zone ids and pickup month
  for (x in tail(f, 3)) {
    d <- as.data.table(arrow::read_parquet(x, col_select = c(grep("pickup_datetime$", names(arrow::open_dataset(x)), value = TRUE), "PULocationID", "DOLocationID")))
    setnames(d, 1, "pickup")
    fm <- regmatches(basename(x), regexpr("\\d{4}-\\d{2}", basename(x)))
    bad_zone <- d[, mean(!PULocationID %in% 1:265 | !DOLocationID %in% 1:265)]
    off_month <- d[, mean(format(pickup, "%Y-%m") != fm)]
    cat(sprintf("  %s: zone ids outside 1-265 %.4f, pickups outside the file month %.4f\n", fm, bad_zone, off_month))
    if (bad_zone > .001) flag("TLC ", t, " ", fm, ": ", round(100 * bad_zone, 2), "% zone ids outside 1-265")
    if (off_month > .01) flag("TLC ", t, " ", fm, ": ", round(100 * off_month, 2), "% pickups outside the file month")
  }
}

# Citi Bike ----
cb <- basename(citibike_files())
have <- sort(sub("^citibike_tripdata_(\\d{4}-\\d{2})\\.parquet$", "\\1", cb))
exp <- tlc_months("2013-06", max(have))
cat(sprintf("\nCiti Bike: %d monthly parquets, %s to %s\n", length(cb), min(have), max(have)))
if (length(setdiff(exp, have))) flag("Citi Bike missing months: ", paste(setdiff(exp, have), collapse = ", "))
if (length(citibike_files("zip"))) flag("Citi Bike: ", length(citibike_files("zip")), " zips not converted (run scripts/20_download_citibike.R)")

# Traffic counts ----
tc <- fread(nyc_latest("traffic_counts"), select = c("Yr", "SegmentID"))
print(tc[, .N, Yr][order(Yr)])
seg <- unique(as.integer(st_drop_geometry(st_read(lion_gdb(), quiet = TRUE, query = "SELECT SegmentID FROM lion"))$SegmentID))
share <- tc[, mean(unique(SegmentID) %in% seg)]
cat(sprintf("traffic counts: SegmentID in current LION %.3f (older segments: use nyc_lion_for_date())\n", share))

# Boundaries ----
geo <- rbindlist(lapply(c("boroughs", "community_districts", "ntas", "tracts", "blocks", "precincts"), function(n) {
  x <- tryCatch(boundaries_read(n), error = function(e) NULL)
  if (is.null(x)) { flag("cannot read boundaries ", n); return(NULL) }
  data.table(layer = n, features = nrow(x), invalid = sum(!st_is_valid(x)), empty = sum(st_is_empty(x)))
}))
z <- taxi_zones_read()
geo <- rbind(geo, data.table(layer = "taxi_zones", features = nrow(z), invalid = sum(!st_is_valid(z)), empty = sum(st_is_empty(z))))
print(geo)
expected <- c(boroughs = 5, community_districts = 71, precincts = 78, taxi_zones = 263)
for (n in intersect(names(expected), geo$layer)) if (geo[layer == n, features] != expected[[n]]) flag(n, ": ", geo[layer == n, features], " features, expected ", expected[[n]])

# Problems ----
cat("\n== Problems\n")
if (length(problems)) cat(paste0("- ", problems), sep = "\n") else cat("none\n")
