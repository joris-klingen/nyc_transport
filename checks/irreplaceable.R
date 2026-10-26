# Files in the store that cannot be downloaded again, their checksums and their Dropbox copy
#
# Irreplaceable: every file in raw/, docs/ and _archive/ except what the download scripts can fetch
# again (TLC parquet, EPA AQS, Citi Bike parquet from the yearly zips, LION releases 17a+ from DCP's
# archive, and the newest snapshot of each Open Data set). That leaves the legacy yellow CSVs (TLC
# took them offline), the monthly Citi Bike zips 2014-2019 (now yearly), LION 12a-16d (gone from
# DCP), every older snapshot (the portals serve only the current state), manual downloads, the DOT
# presentations and the archive.
#
# - lists them with sizes per folder
# - _meta/irreplaceable_md5.csv: adds the md5 of new files; flags missing files and changed sizes
#   (--verify recomputes every md5, ~35 GB, 5-10 minutes)
# - Dropbox: files that are not in sync with the cloud copy (Windows only)
# Ends with a list of problems.
#
# Run from the repo root: Rscript checks/irreplaceable.R [--verify]

library(data.table)
source("R/nyc_transport.R")

verify <- "--verify" %in% commandArgs(trailingOnly = TRUE)
root <- nyc_data_root()
manifest_file <- file.path(root, "_meta", "irreplaceable_md5.csv")

problems <- character()
flag <- function(...) problems <<- c(problems, paste0(...))

# Classify ----
f <- data.table(path = list.files(file.path(root, c("raw", "docs", "_archive")), recursive = TRUE, full.names = TRUE))
f[, rel := substring(path, nchar(root) + 2)]
f[, bytes := file.size(path)]
f <- f[!grepl("\\.(part|superseded_\\d{8}\\.[^.]+|corrupt_\\d{8}\\.[^.]+)$", rel)]

# newest snapshot of each prefix the download scripts still fetch: re-downloadable today (older
# prefixes, such as NYPD_Motor_Vehicle_Collisions or Bicycle_Counts, are not)
fetched <- c(nyc_opendata[, prefix], "taxi_zones", "taxi_zone_lookup", "station_information")
f[, snap_key := fifelse(grepl("_\\d{8}\\.[^/]+$", rel), sub("_\\d{8}(\\.[^/]+)$", "\\1", rel), NA_character_)]
f[, snap_date := regmatches(rel, regexpr("\\d{8}(?=\\.[^/]+$)", rel, perl = TRUE))[1], by = rel]
f[!is.na(snap_key), newest := snap_date == max(snap_date) & sub("\\.[^/]+$", "", basename(snap_key)) %in% fetched, by = snap_key]

f[, redownload := fcase(
  grepl("^raw/taxi/(yellow|green|fhvhv|fhv)/.*\\.parquet$", rel), "TLC parquet",
  grepl("^raw/air_pollution/epa_aqs/", rel), "EPA AQS",
  grepl("^raw/citibike/trips/.*\\.parquet$", rel), "Citi Bike yearly/monthly zips",
  grepl("^raw/street_layout/lion/nyclion_\\d{2}[a-d]\\.zip$", rel), "DCP LION archive",
  !is.na(snap_key) & newest == TRUE, "newest snapshot",
  default = NA_character_)]
irr <- f[is.na(redownload)]
irr[, folder := dirname(rel)]
print(irr[, .(files = .N, GB = round(sum(bytes) / 1e9, 2)), folder][order(folder)], nrows = 200)
cat(sprintf("\nirreplaceable: %d files, %.1f GB (re-downloadable: %d files, %.1f GB)\n",
            nrow(irr), sum(irr[, bytes]) / 1e9, f[!is.na(redownload), .N], f[!is.na(redownload), sum(bytes)] / 1e9))

# Checksums ----
old <- if (file.exists(manifest_file)) fread(manifest_file, colClasses = c(bytes = "numeric", first_seen = "character")) else
  data.table(rel = character(), bytes = numeric(), md5 = character(), first_seen = character())
for (r in setdiff(old[, rel], f[, rel])) flag("missing from the store: ", r)
m <- merge(irr[, .(rel, bytes_now = bytes, path)], old, by = "rel", all.x = TRUE)
for (r in m[!is.na(bytes) & bytes != bytes_now, rel]) flag("size changed: ", r)
todo <- if (verify) m[, rel] else m[is.na(md5), rel]
if (length(todo)) cat(sprintf("md5 of %d files, %.1f GB ...\n", length(todo), sum(m[rel %in% todo, bytes_now]) / 1e9))
m[rel %in% todo, md5_now := unname(tools::md5sum(path))]
for (r in m[!is.na(md5) & !is.na(md5_now) & md5 != md5_now, rel]) flag("md5 changed: ", r)
new <- m[is.na(md5), .(rel, bytes = bytes_now, md5 = md5_now, first_seen = format(Sys.Date()))]
if (nrow(new)) {
  out <- rbind(old, new)[order(rel)]
  fwrite(out, manifest_file)
  cat(sprintf("added %d files to %s\n", nrow(new), manifest_file))
}

# Dropbox ----
# StorageProviderState: 2 in sync, 3 pinned (in sync, kept on this device); anything else is not
# (yet) in the cloud copy
if (.Platform$OS.type == "windows" && grepl("Dropbox", root)) {
  dirs_file <- tempfile(fileext = ".txt")
  writeLines(normalizePath(unique(irr[, dirname(path)]), winslash = "\\"), dirs_file)
  cmd <- paste0("$sh = New-Object -ComObject Shell.Application; foreach ($d in Get-Content '", dirs_file, "') { ",
                "foreach ($it in $sh.Namespace($d).Items()) { if (-not $it.IsFolder) { ",
                "$s = $it.ExtendedProperty('System.StorageProviderState'); ",
                "if ($s -ne 2 -and $s -ne 3) { [string]$s + ' ' + $it.Path } } } }")
  out <- system2("powershell", c("-NoProfile", "-Command", shQuote(cmd)), stdout = TRUE)
  out <- out[nzchar(out)]
  cat(sprintf("\nDropbox: %d of %d irreplaceable files not in sync\n", length(out), nrow(irr)))
  if (length(out)) { cat(head(out, 20), sep = "\n"); flag(length(out), " irreplaceable files not in sync with Dropbox") }
}

# Problems ----
cat("\n== Problems\n")
if (length(problems)) cat(paste0("- ", problems), sep = "\n") else cat("none\n")
