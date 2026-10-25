# Coverage of the non-TLC sources over time and space ----
#
# Exploratory. What is in each source per day / month and per area, to find gaps:
#   - cov_crashes_daily.parquet: crashes per day, share with coordinates and with a borough,
#     persons injured / killed by mode
#   - cov_crashes_cd_year.parquet: crashes per community district and year (geocoded crashes)
#   - cov_persons_month.parquet, cov_vehicles_month.parquet: persons by type and injury, vehicles by
#     class (reference/NYC_vehicle_lookup_table.csv), per month
#   - cov_atr.parquet: automated traffic counts per borough, year and month (counts, requests, segments)
#   - cov_bike_counters_daily.parquet: DOT bike/ped counters reporting per day, and their counts
#   - cov_air_month.parquet: NYC-area monitor observations and means per pollutant, site and month
#   - cov_crz_daily.parquet: congestion relief zone entries per day, region and vehicle class
#   - cov_lion_releases.csv: the LION releases and their dates
# Run from the repo root (a few minutes): Rscript explore/03_coverage.R

library(data.table)
library(arrow)
library(sf)
source("R/nyc_transport.R")

out_dir <- "output/explore"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
say <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n")

# Crashes ----
cr <- crashes_read()
inj <- grep("^number_of_(pedestrians|cyclist|motorist|persons)_(injured|killed)$", names(cr), value = TRUE)
for (v in inj) set(cr, j = v, value = as.numeric(cr[[v]]))
cr[, hurt := number_of_persons_injured > 0 | number_of_persons_killed > 0]
d <- cr[, c(list(crashes = .N, with_injury = sum(hurt, na.rm = TRUE),
                 with_xy = sum(!is.na(latitude)), with_borough = sum(!is.na(borough) & borough != "")),
            lapply(.SD, sum, na.rm = TRUE)), by = .(date = crash_date), .SDcols = inj][order(date)]
write_parquet(d, file.path(out_dir, "cov_crashes_daily.parquet"))
say("crashes:", nrow(cr), "rows,", nrow(d), "days")

# area from the coordinates (the reported borough field is missing for a third of crashes in 2016-2023)
pts <- nyc_points_sf(cr[!is.na(latitude), .(ym = substr(as.character(crash_date), 1, 7), hurt, longitude, latitude)],
                     "longitude", "latitude")
cd <- boundaries_read("community_districts")["boro_cd"]
pts <- as.data.table(st_drop_geometry(st_join(pts, cd)))
pts[, boro := c("1" = "Manhattan", "2" = "Bronx", "3" = "Brooklyn", "4" = "Queens", "5" = "Staten Island")[substr(boro_cd, 1, 1)]]
cdy <- pts[, .(crashes = .N, with_injury = sum(hurt, na.rm = TRUE)), by = .(boro_cd, year = as.integer(substr(ym, 1, 4)))][order(boro_cd, year)]
write_parquet(cdy, file.path(out_dir, "cov_crashes_cd_year.parquet"))
write_parquet(pts[, .(crashes = .N, with_injury = sum(hurt, na.rm = TRUE)), by = .(boro, ym)][order(boro, ym)],
              file.path(out_dir, "cov_crashes_boro_month.parquet"))
say("crashes by community district:", cdy[, uniqueN(boro_cd)], "districts")
rm(pts, cr); gc(verbose = FALSE)

# Persons and vehicles ----
p <- fread(nyc_latest("persons"), select = c("CRASH_DATE", "PERSON_TYPE", "PERSON_INJURY"), showProgress = FALSE)
p[, ym := substr(as.character(as.IDate(CRASH_DATE, format = "%m/%d/%Y")), 1, 7)]
write_parquet(p[, .N, by = .(ym, person_type = PERSON_TYPE, injury = PERSON_INJURY)][order(ym)],
              file.path(out_dir, "cov_persons_month.parquet"))
say("persons:", nrow(p)); rm(p)

v <- fread(nyc_latest("vehicles"), select = c("CRASH_DATE", "VEHICLE_TYPE"), showProgress = FALSE)
lk <- fread(file.path(nyc_data_root(), "reference", "NYC_vehicle_lookup_table.csv"))
v[lk, class := i.VehicleType, on = .(VEHICLE_TYPE = VehicleTypeRaw)]
v[is.na(class), class := fifelse(is.na(VEHICLE_TYPE) | VEHICLE_TYPE == "", "Missing", "Unmatched")]
v[, ym := substr(as.character(as.IDate(CRASH_DATE, format = "%m/%d/%Y")), 1, 7)]
write_parquet(v[, .N, by = .(ym, class)][order(ym)], file.path(out_dir, "cov_vehicles_month.parquet"))
say("vehicles:", nrow(v), "; unmatched types:", v[class == "Unmatched", .N]); rm(v)

# Automated traffic counts ----
tc <- as.data.table(st_drop_geometry(traffic_counts_read()))
atr <- tc[, .(counts = .N, requests = uniqueN(RequestID), segments = uniqueN(SegmentID),
              vol = sum(as.numeric(Vol), na.rm = TRUE)), by = .(boro = Boro, year = as.integer(Yr), month = as.integer(M))]
write_parquet(atr[order(boro, year, month)], file.path(out_dir, "cov_atr.parquet"))
say("traffic counts:", nrow(tc), "rows"); rm(tc)

# Bike and pedestrian counters ----
bc <- fread(nyc_latest("bike_ped_counts"), select = c("sensor_id", "travelMode", "timestamp", "counts", "status"), showProgress = FALSE)
# timestamps as 06/04/2018 08:45:00 AM: parse the distinct dates only
ds <- substr(bc[, timestamp], 1, 10); u <- unique(ds)
bc[, date := as.IDate(u, format = "%m/%d/%Y")[match(ds, u)]]; rm(ds, u)
bcd <- bc[, .(sensors = uniqueN(sensor_id), counts = sum(as.numeric(counts), na.rm = TRUE), rows = .N),
          by = .(date, mode = travelMode)][order(date)]
write_parquet(bcd, file.path(out_dir, "cov_bike_counters_daily.parquet"))
write_parquet(bc[, .(first = min(date), last = max(date), days = uniqueN(date), counts = sum(as.numeric(counts), na.rm = TRUE)),
                 by = .(sensor_id, mode = travelMode)], file.path(out_dir, "cov_bike_counters_sensor.parquet"))
say("bike counters:", nrow(bc), "rows"); rm(bc)

# Air pollution (NYC-area monitors, daily) ----
air <- rbindlist(lapply(c(no2 = "42602", pm25 = "88101", ozone = "44201", co = "42101"), function(p) {
  x <- tryCatch(air_pollution_read(p, "daily", nyc_only = TRUE), error = function(e) { say("air", p, "skipped:", conditionMessage(e)); NULL })
  if (is.null(x)) return(NULL)
  x[, .(obs = .N, mean = mean(arithmetic_mean, na.rm = TRUE), lat = latitude[1], lng = longitude[1]),
    by = .(site_id, ym = substr(as.character(date_local), 1, 7))][, parameter := p]
}), idcol = "pollutant")
write_parquet(air, file.path(out_dir, "cov_air_month.parquet"))
say("air:", air[, uniqueN(site_id)], "sites")

# Congestion relief zone entries ----
crz <- fread(nyc_latest("crz_entries"), select = c("Toll Date", "Vehicle Class", "Detection Region", "CRZ Entries"), showProgress = FALSE)
setnames(crz, c("date", "class", "region", "entries"))
crz[, date := as.IDate(date, format = "%m/%d/%Y")]
write_parquet(crz[, .(entries = sum(entries)), by = .(date, region, class)][order(date)], file.path(out_dir, "cov_crz_daily.parquet"))
say("crz:", crz[, uniqueN(date)], "days")

# LION releases ----
fwrite(lion_releases(), file.path(out_dir, "cov_lion_releases.csv"))
say("done")
