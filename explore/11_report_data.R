# Compact tables for the exploration report ----
#
# Exploratory. Reads the outputs of 01-03 and writes small CSVs to output/explore/report/, one per
# chart or table of the report page (the page cites every number to one of them).
# Run from the repo root after 01-03: Rscript explore/11_report_data.R

library(data.table)
library(arrow)
library(sf)
source("R/nyc_transport.R")

o <- "output/explore"
r <- file.path(o, "report")
dir.create(r, recursive = TRUE, showWarnings = FALSE)
rd <- function(f) as.data.table(read_parquet(file.path(o, f)))
out <- function(x, f) { fwrite(x, file.path(r, f)); cat(f, nrow(x), "rows\n") }

# Zones and areas (as in 10_facts.R) ----
z <- taxi_zones_read()
zc <- st_coordinates(st_transform(st_centroid(st_geometry(z)), 4326))
zones <- unique(data.table(zone = as.integer(z$LocationID), borough = z$Borough, lat = zc[, 2]), by = "zone")
zones[, area := fifelse(borough == "Manhattan" & lat < 40.764, "Manhattan below 60th St",
                fifelse(borough == "Manhattan", "Manhattan above 60th St", "Outer boroughs"))]
zones[zone %in% c(1L, 132L, 138L), area := "Airports"]
zh <- merge(rd("tlc_zone_hour.parquet"), zones[, .(zone, area)], by = "zone", all.x = TRUE)
zh[is.na(area), area := "Unknown zone"]
zh[, year := as.integer(substr(ym, 1, 4))]
lab <- c(yellow = "Yellow taxi", green = "Green taxi", fhvhv = "Ride-hail")

# Coverage heat map: every source's monthly volume over its own median ----
cov <- rbindlist(list(
  zh[, .(value = sum(trips)), by = .(ym, source = lab[type])],
  rd("citibike_daily.parquet")[, .(value = sum(trips)), by = .(ym = format(date, "%Y-%m"))][, source := "Citi Bike"],
  rd("cov_crashes_daily.parquet")[, .(value = sum(crashes)), by = .(ym = format(date, "%Y-%m"))][, source := "Crashes, all"],
  rd("cov_crashes_daily.parquet")[, .(value = sum(with_injury)), by = .(ym = format(date, "%Y-%m"))][, source := "Crashes with injury"],
  rd("cov_atr.parquet")[, .(value = sum(counts)), by = .(ym = sprintf("%d-%02d", year, month))][, source := "Traffic counts (ATR)"],
  rd("cov_bike_counters_daily.parquet")[mode == "bike", .(value = sum(rows)), by = .(ym = format(date, "%Y-%m"))][, source := "Bike counters"],
  rd("cov_air_month.parquet")[, .(value = sum(obs)), by = .(ym, source = c(no2 = "Air: NO2", pm25 = "Air: PM2.5", ozone = "Air: ozone", co = "Air: CO")[pollutant])],
  rd("cov_crz_daily.parquet")[, .(value = sum(entries)), by = .(ym = format(date, "%Y-%m"))][, source := "Congestion zone entries"]
), use.names = TRUE)
cov <- cov[ym >= "2012-01" & ym <= "2026-09"]
cov[, index := round(value / median(value), 3), by = source]
out(cov[order(source, ym)], "coverage_month.csv")

# Crashes: reporting ----
cr <- rd("cov_crashes_daily.parquet")[year(date) %in% 2013:2025]
cry <- cr[, .(crashes = sum(crashes), with_injury = sum(with_injury), killed = sum(number_of_persons_killed),
              pedestrians_injured = sum(number_of_pedestrians_injured), cyclists_injured = sum(number_of_cyclist_injured),
              with_coordinates = round(sum(with_xy) / sum(crashes), 3), with_borough = round(sum(with_borough) / sum(crashes), 3)),
          by = .(year = year(date))]
cry[, property_damage_only := crashes - with_injury]
out(cry, "crash_year.csv")

bm <- rd("cov_crashes_boro_month.parquet")[!is.na(boro)][, year := as.integer(substr(ym, 1, 4))]
bmy <- dcast(bm[year %in% c(2019, 2025), .(crashes = sum(crashes), with_injury = sum(with_injury)), by = .(borough = boro, year)],
             borough ~ year, value.var = c("crashes", "with_injury"))
bmy[, `:=`(change_all = round(crashes_2025 / crashes_2019 - 1, 3), change_injury = round(with_injury_2025 / with_injury_2019 - 1, 3))]
out(bmy, "crash_borough.csv")

# For-hire trips ----
out(zh[, .(trips = sum(trips)), by = .(ym, mode = lab[type])][order(mode, ym)], "trips_month.csv")
ar <- dcast(zh[year %in% c(2019, 2025) & area != "Unknown zone", .(trips = sum(trips)), by = .(mode = lab[type], area, year)],
            mode + area ~ year, value.var = "trips")
setnames(ar, c("2019", "2025"), c("trips_2019", "trips_2025"))
ar[, change := round(trips_2025 / trips_2019 - 1, 3)]
ar[, key := paste(mode, area, sep = " | ")]
out(ar[mode != "Green taxi"], "trips_area.csv")

# Speeds ----
sh <- zh[weekend == FALSE & area == "Manhattan below 60th St" & year %in% c(2019, 2025) & type %in% c("fhvhv", "yellow"),
         .(mph = round(sum(miles) / sum(hours), 2)), by = .(mode = lab[type], year, hour)]
out(sh[order(mode, year, hour)], "speed_hour.csv")
sm <- zh[weekend == FALSE & hour >= 7 & hour < 19 & type == "fhvhv" & area %in% c("Manhattan below 60th St", "Outer boroughs"),
         .(mph = round(sum(miles) / sum(hours), 2)), by = .(ym, area)]
out(sm[order(area, ym)], "speed_month.csv")

pk <- zh[weekend == FALSE & type %in% c("fhvhv", "yellow") & year <= 2025,
         .(am_peak = round(sum(trips[hour %in% 7:9]) / sum(trips), 4), pm_peak = round(sum(trips[hour %in% 16:18]) / sum(trips), 4)),
         by = .(mode = lab[type], year)]
out(pk[order(mode, year)], "peak_share.csv")

# Citi Bike and two-wheelers ----
cb <- rd("citibike_daily.parquet")[, .(trips = sum(trips), member = sum(member), ebike = sum(ebike, na.rm = TRUE)), by = .(ym = format(date, "%Y-%m"))]
st <- rd("citibike_station_month.parquet")[trips >= 10, .(stations = uniqueN(station)), by = ym]
cb <- merge(cb, st, by = "ym")[ym >= "2013-06" & ym <= "2026-09"]
cb[, `:=`(ebike_share = round(ebike / trips, 4), member_share = round(member / trips, 4))]
out(cb[, .(ym, trips, stations, ebike_share, member_share)][order(ym)], "citibike_month.csv")

cby <- rd("citibike_daily.parquet")[year(date) %in% 2014:2025, .(citibike_trips = sum(trips)), by = .(year = year(date))]
risk <- merge(cry[, .(year, cyclists_injured)], cby, by = "year")
risk[, injured_per_million_trips := round(cyclists_injured / (citibike_trips / 1e6), 1)]
out(risk, "cyclist_risk.csv")

veh <- rd("cov_vehicles_month.parquet")[, year := as.integer(substr(ym, 1, 4))]
tw <- dcast(veh[class %in% c("Bike", "Scooter", "Motorcycle") & year %in% 2013:2025, .(N = sum(N)), by = .(year, class)],
            year ~ class, value.var = "N", fill = 0)
setnames(tw, c("Bike", "Motorcycle", "Scooter"), c("bicycles", "motorcycles_mopeds", "e_scooters"))
out(tw, "two_wheelers.csv")
