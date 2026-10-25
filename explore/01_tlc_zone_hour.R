# TLC trips by pickup zone, hour and day type, every month ----
#
# Exploratory (not part of the readers). For every yellow, green and fhvhv month file:
#   - tlc_zone_hour.parquet: trips by month x pickup zone x hour of day x weekend, and for trips with
#     a plausible distance and duration their total miles and hours (speed = miles / hours)
#   - tlc_daily.parquet: trips per pickup date (finds missing or thin days inside a month)
#   - tlc_files.csv: rows per file and the share of pickups outside the file's month
# Plausible: 0.1-100 miles, 1 minute to 4 hours, 1-80 mph.
# Run from the repo root (about 40 minutes): Rscript explore/01_tlc_zone_hour.R

library(data.table)
library(arrow)
source("R/nyc_transport.R")

out_dir <- "output/explore"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# TLC timestamps are local clock times stored without a zone: read and bin them as UTC
Sys.setenv(TZ = "UTC")

cols <- list(
  yellow = c(t0 = "tpep_pickup_datetime", t1 = "tpep_dropoff_datetime", miles = "trip_distance"),
  green  = c(t0 = "lpep_pickup_datetime", t1 = "lpep_dropoff_datetime", miles = "trip_distance"),
  fhvhv  = c(t0 = "pickup_datetime",      secs = "trip_time",          miles = "trip_miles")
)

# Aggregate one month file ----
agg_file <- function(type, f) {
  ym <- regmatches(basename(f), regexpr("\\d{4}-\\d{2}", basename(f)))
  cc <- cols[[type]]
  d <- as.data.table(read_parquet(f, col_select = c(unname(cc), "PULocationID")))
  setnames(d, unname(cc), names(cc))
  s0 <- as.numeric(d[, t0])
  hours <- if (type == "fhvhv") as.numeric(d[, secs]) / 3600 else (as.numeric(d[, t1]) - s0) / 3600
  lo <- as.numeric(as.POSIXct(paste0(ym, "-01"), tz = "UTC"))
  hi <- as.numeric(seq(as.POSIXct(paste0(ym, "-01"), tz = "UTC"), by = "month", length.out = 2)[2])
  day <- s0 %/% 86400
  d <- data.table(zone = as.integer(d[, PULocationID]),
                  miles = as.numeric(d[, miles]),
                  hours = hours,
                  hour = as.integer((s0 %/% 3600) %% 24),
                  weekend = ((day + 4) %% 7) %in% c(0, 6),   # 1970-01-01 was a Thursday; 0 = Sunday
                  date = as.IDate(day),
                  in_month = s0 >= lo & s0 < hi)
  d[, ok := !is.na(miles) & !is.na(hours) & miles > 0.1 & miles < 100 & hours > 1 / 60 & hours < 4 &
          miles / hours > 1 & miles / hours < 80]
  zh <- d[in_month == TRUE, .(trips = .N, n_ok = sum(ok), miles = sum(miles[ok]), hours = sum(hours[ok])),
          by = .(zone, hour, weekend)]
  zh[, `:=`(type = type, ym = ym)]
  dl <- d[in_month == TRUE, .(trips = .N), by = date][, `:=`(type = type, ym = ym)]
  fl <- data.table(type = type, ym = ym, rows = nrow(d), out_of_month = d[, mean(!in_month)], ok_share = d[, mean(ok)])
  list(zh = zh, dl = dl, fl = fl)
}

# Run every file (an optional argument limits the files per type, for a test run) ----
lim <- if (length(commandArgs(TRUE))) as.integer(commandArgs(TRUE)[1]) else Inf
res <- list()
for (type in names(cols)) {
  ff <- head(tlc_files(type), lim)
  for (i in seq_along(ff)) {
    t0 <- Sys.time()
    res[[length(res) + 1]] <- agg_file(type, ff[i])
    cat(sprintf("%s %s (%d/%d) %.1fs\n", type, basename(ff[i]), i, length(ff), as.numeric(Sys.time() - t0, units = "secs")))
    gc(verbose = FALSE)
  }
}

write_parquet(rbindlist(lapply(res, `[[`, "zh")), file.path(out_dir, "tlc_zone_hour.parquet"))
write_parquet(rbindlist(lapply(res, `[[`, "dl")), file.path(out_dir, "tlc_daily.parquet"))
fwrite(rbindlist(lapply(res, `[[`, "fl")), file.path(out_dir, "tlc_files.csv"))
cat("done\n")
