# Citi Bike keyed trips: the input of the pseudo-cyclist panel ----
#
# Citi Bike has no rider id. A pseudo-cyclist is built at query time by citibike_panel()
# (R/nyc_transport.R, DuckDB) from recurring trips on one route, departure-time bin and period, with
# cutoffs chosen per analysis. This script writes the slim trip table it queries: every cleaned trip
# with its keys, one parquet per year, built in DuckDB from the monthly trip parquets.
#   - Trips: start != end station, duration > 60 s, straight-line distance x 1.3 / duration between
#     0.1 and 30 km/h (as Klingen and van Ommeren 2020). Distances use the median coordinates of each
#     station in the year.
#   - Columns: date and dep_s (second of the day) in NYC local time, start/end_station_id, dist_km
#     (straight line), duration_s, member, ebike (from 2020; NA before, when Citi Bike's first e-bikes,
#     about 2018-08 to 2019-04, are not flagged), label = birth_year * 10 + gender for members with a
#     known gender (to 2019-12; NA after and for casual riders). Sorted by route, date, dep_s.
#   - A year uses its own monthly files; trips whose local start falls in another year are dropped
#     (minutes around New Year).
# Output: derived/citibike_panel/citibike_keyed_trips_YYYY.parquet, citibike_keyed_trips_summary.csv
# Run from the repo root: Rscript scripts/60_citibike_keyed_trips.R [years, e.g. 2019 or 2013:2026]

suppressMessages({library(data.table); library(arrow); library(DBI)})
source("R/nyc_transport.R")

args <- commandArgs(trailingOnly = TRUE)
fs <- citibike_files()
file_year <- as.integer(substr(basename(fs), 19, 22))
years <- if (length(args)) eval(parse(text = args[1])) else sort(unique(file_year))
out_dir <- file.path(nyc_data_root(), "derived", "citibike_panel")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

con <- dbConnect(duckdb::duckdb(shared_home = FALSE))
dbExecute(con, "SET TimeZone = 'UTC'")
hav <- function(a, b) sprintf(
  "2 * 6371 * asin(sqrt(pow(sin(radians(%s.lat - %s.lat) / 2), 2) +
     cos(radians(%s.lat)) * cos(radians(%s.lat)) * pow(sin(radians(%s.lng - %s.lng) / 2), 2)))", b, a, a, b, b, a)

summary_rows <- list()
for (yr in years) {
  fy <- fs[file_year == yr]
  if (!length(fy)) next
  t0 <- Sys.time()
  nm <- unique(unlist(lapply(fy, function(f) names(open_dataset(f)))))
  ebike <- if ("rideable_type" %in% nm) "rideable_type = 'electric_bike'" else "CAST(NULL AS BOOLEAN)"
  demo <- if ("birth_year" %in% nm) "TRY_CAST(birth_year AS INTEGER) AS byr, TRY_CAST(gender AS INTEGER) AS g" else
    "CAST(NULL AS INTEGER) AS byr, CAST(NULL AS INTEGER) AS g"
  out <- file.path(out_dir, sprintf("citibike_keyed_trips_%d.parquet", yr))
  sql <- sprintf("
    COPY (
      WITH r AS (
        SELECT timezone('America/New_York', started_at::TIMESTAMPTZ) AS lt,
               epoch(ended_at) - epoch(started_at) AS duration_s,
               CAST(start_station_id AS VARCHAR) AS o, CAST(end_station_id AS VARCHAR) AS d,
               start_lat, start_lng, end_lat, end_lng, member, %s AS ebike, %s
        FROM read_parquet([%s], union_by_name = true)
        WHERE start_station_id IS NOT NULL AND end_station_id IS NOT NULL),
      r2 AS (SELECT * FROM r WHERE o <> d AND year(lt) = %d),
      st AS (
        SELECT id, median(lat) AS lat, median(lng) AS lng FROM (
          SELECT o AS id, start_lat AS lat, start_lng AS lng FROM r2 UNION ALL
          SELECT d, end_lat, end_lng FROM r2) WHERE lat IS NOT NULL AND lat <> 0 GROUP BY id),
      j AS (
        SELECT r2.*, %s AS dist FROM r2 JOIN st so ON r2.o = so.id JOIN st sd ON r2.d = sd.id)
      SELECT CAST(lt AS DATE) AS date,
             CAST(hour(lt) * 3600 + minute(lt) * 60 + second(lt) AS INTEGER) AS dep_s,
             o AS start_station_id, d AS end_station_id, CAST(dist AS FLOAT) AS dist_km,
             CAST(round(duration_s) AS INTEGER) AS duration_s, member, ebike,
             CASE WHEN member AND g IN (1, 2) AND byr IS NOT NULL THEN byr * 10 + g END AS label
      FROM j
      WHERE duration_s > 60 AND dist > 0 AND dist * 1.3 / (duration_s / 3600) > 0.1
        AND dist * 1.3 / (duration_s / 3600) <= 30
      ORDER BY start_station_id, end_station_id, date, dep_s
    ) TO '%s' (FORMAT parquet, COMPRESSION zstd)",
    ebike, demo, paste0("'", gsub("\\\\", "/", fy), "'", collapse = ", "), yr, hav("so", "sd"), gsub("\\\\", "/", out))
  dbExecute(con, sql)
  s <- as.data.table(dbGetQuery(con, sprintf(
    "SELECT count(*) AS trips_kept, round(avg(CAST(member AS DOUBLE)), 3) AS member_share,
            round(avg(CAST(ebike AS DOUBLE)), 3) AS ebike_share, round(avg(CAST(label IS NOT NULL AS DOUBLE)), 3) AS labelled_share
     FROM read_parquet('%s')", gsub("\\\\", "/", out))))
  s <- cbind(data.table(year = yr, months = length(fy),
                        trips_read = sum(sapply(fy, function(f) open_dataset(f)$num_rows))), s,
             data.table(mb = round(file.size(out) / 1e6), seconds = round(as.numeric(Sys.time() - t0, units = "secs"))))
  summary_rows[[as.character(yr)]] <- s
  print(s)
}
dbDisconnect(con, shutdown = TRUE)

# Summary: merge with rows of years not rebuilt this run ----
sf <- file.path(out_dir, "citibike_keyed_trips_summary.csv")
s <- rbindlist(summary_rows)
if (file.exists(sf)) s <- rbind(fread(sf)[!year %in% s[, year]], s, fill = TRUE)
fwrite(s[order(year)], sf)
print(s[order(year)])
