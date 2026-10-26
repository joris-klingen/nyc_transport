# Refresh the whole store: every download, then what is built from it, then the checks
#
# Usage (from repo root):  Rscript scripts/00_update.R [steps] [--profiles] [--dry-run]
#   steps      comma-separated subset of the step names below, default all
#   --profiles also rebuild profiles/ (about an hour; needed when a schema changed)
#   --dry-run  list the steps and stop
#
# Each step runs as its own Rscript; a failing step is logged and the next one runs. Steps after
# the downloads run only when their input changed in this run (new or changed files under raw/):
# the vehicle lookup after a new crash snapshot, the NYC air extract after new EPA files. The
# street network history (streets/) is not rebuilt: its bike lane dating needs manual review.
# Output of each step goes to _meta/update_logs/<run>/<step>.log; one row per step is added to
# _meta/update_log.csv (run, step, status, minutes, new raw files). Takes 30-90 minutes, most of
# it the TLC and Citi Bike downloads in the months they publish.

library(data.table)
source("R/config.R")

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args
profiles <- "--profiles" %in% args
only <- args[!startsWith(args, "--")]
only <- if (length(only)) strsplit(only[1], ",")[[1]] else NULL

root <- nyc_data_root()
run <- format(Sys.time(), "%Y%m%d_%H%M")
log_dir <- file.path(root, "_meta", "update_logs", run)
log_csv <- file.path(root, "_meta", "update_log.csv")

# Steps ----
# when: NULL runs always; else a regex on the raw files that changed earlier in this run
steps <- rbindlist(list(
  list("tlc",             "scripts/01_download_tlc.R",               "",        NA),
  list("opendata",        "scripts/10_download_opendata.R",          "",        NA),
  list("lion",            "scripts/11_download_lion_releases.R",     "",        NA),
  list("citibike",        "scripts/20_download_citibike.R",          "",        NA),
  list("citibike_stations", "scripts/21_snapshot_citibike_stations.R", "",      NA),
  list("epa",             "scripts/40_download_epa_aqs.R",           "",        NA),
  list("crashes_parquet", "scripts/30_crashes_parquet.R",            "",        NA),
  list("vehicle_lookup",  "scripts/31_vehicle_lookup.R",             "--write", "^raw/crashes/Motor_Vehicle_Collisions_-_Crashes_"),
  list("air_nyc",         "scripts/41_air_pollution_nyc.R",          "",        "^raw/air_pollution/epa_aqs/(hourly|daily)/"),
  list("profiles",        "profiles/build_profiles.R",               "",        NA),
  list("catalog",         "scripts/50_build_catalog.R",              "",        NA),
  list("check_store",     "checks/store.R",                          "",        NA),
  list("check_irreplaceable", "checks/irreplaceable.R",              "",        NA)
))
setnames(steps, c("step", "script", "args", "when"))
if (!profiles) steps <- steps[step != "profiles"]
if (length(only)) {
  bad <- setdiff(only, steps[, step])
  if (length(bad)) stop("unknown step(s): ", paste(bad, collapse = ", "), "; steps: ", paste(steps[, step], collapse = ", "))
  steps <- steps[step %in% only]
}
print(steps[, .(step, script, args, when = fifelse(is.na(when), "always", paste("if changed:", when)))])
if (dry_run) quit(save = "no")

# Raw files and their state ----
raw_state <- function() {
  f <- list.files(file.path(root, "raw"), recursive = TRUE, full.names = TRUE)
  i <- file.info(f, extra_cols = FALSE)
  data.table(rel = substring(f, nchar(root) + 2), size = i$size, mtime = as.numeric(i$mtime))
}
changed_since <- function(before, after) {
  m <- merge(after, before, by = "rel", all.x = TRUE, suffixes = c("", "_before"))
  m[is.na(size_before) | size != size_before | mtime != mtime_before, rel]
}

# Run ----
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
rscript <- file.path(R.home("bin"), "Rscript")
changed <- character()
res <- list()
for (i in seq_len(nrow(steps))) {
  s <- steps[i]
  if (!is.na(s$when) && !any(grepl(s$when, changed))) {
    cat(sprintf("%-20s skipped (input unchanged)\n", s$step))
    res[[i]] <- data.table(step = s$step, status = "skipped", minutes = 0, new_raw = 0L)
    next
  }
  before <- raw_state()
  t0 <- Sys.time()
  log_file <- file.path(log_dir, paste0(s$step, ".log"))
  cat(sprintf("%-20s running %s %s ... ", s$step, s$script, s$args))
  code <- suppressWarnings(system2(rscript, c(s$script, if (nzchar(s$args)) s$args), stdout = log_file, stderr = log_file))
  new_raw <- changed_since(before, raw_state())
  changed <- c(changed, new_raw)
  status <- if (code == 0) "ok" else paste("failed, exit", code)
  minutes <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  cat(sprintf("%s, %.1f min, %d new or changed raw files\n", status, minutes, length(new_raw)))
  if (code != 0) cat(paste0("    ", tail(readLines(log_file, warn = FALSE), 10)), sep = "\n")
  res[[i]] <- data.table(step = s$step, status, minutes, new_raw = length(new_raw))
}
res <- rbindlist(res)
res[, run := run]

# Log ----
fwrite(res[, .(run, step, status, minutes, new_raw)], log_csv, append = file.exists(log_csv))
writeLines(changed, file.path(log_dir, "changed_raw_files.txt"))

cat("\n== Update", run, "\n")
print(res[, .(step, status, minutes, new_raw)])
if (length(changed)) cat("\nnew or changed raw files:\n", paste0("  ", changed, "\n"), sep = "")
cat("\nlogs:", log_dir, "\n")
# the checks end with their list of problems
for (k in intersect(c("check_store", "check_irreplaceable"), res[status == "ok", step])) {
  l <- readLines(file.path(log_dir, paste0(k, ".log")), warn = FALSE)
  cat("\n", k, ":\n", paste0(l[max(1, grep("^== Problems", l)):length(l)], "\n"), sep = "")
}
if (any(startsWith(res[, status], "failed"))) quit(save = "no", status = 1)
