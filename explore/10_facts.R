# Stylized facts from the exploration aggregates ----
#
# Exploratory. Reads the outputs of 01-03 in output/explore and prints the tables behind the
# candidate facts: trips by mode and area, speeds by area and hour, time-of-day profiles, Citi Bike
# growth and e-bikes, crash risk per trip, air quality. Writes facts_*.csv next to them.
# Run from the repo root after 01-03: Rscript explore/10_facts.R

library(data.table)
library(arrow)
library(sf)
source("R/nyc_transport.R")

o <- "output/explore"
rd <- function(f) as.data.table(read_parquet(file.path(o, f)))
show <- function(title, x) { cat("\n==", title, "\n"); print(x, nrows = 200) }

# Zones: borough and an approximate congestion relief zone (Manhattan below 60th St) ----
z <- taxi_zones_read()
zc <- st_coordinates(st_transform(st_centroid(st_geometry(z)), 4326))
zones <- data.table(zone = as.integer(z$LocationID), borough = z$Borough, lat = zc[, 2])
zones <- unique(zones, by = "zone")
zones[, area := fifelse(borough == "Manhattan" & lat < 40.764, "Manhattan CBD",
                fifelse(borough == "Manhattan", "Manhattan north of 60th",
                fifelse(borough %in% c("Brooklyn", "Queens", "Bronx", "Staten Island"), "Outer boroughs", "Other")))]
# airports are their own area (JFK 132, LaGuardia 138, Newark 1)
zones[zone %in% c(1L, 132L, 138L), area := "Airports"]

zh <- rd("tlc_zone_hour.parquet")
zh <- merge(zh, zones[, .(zone, borough, area)], by = "zone", all.x = TRUE)
zh[is.na(area), area := "Unknown zone"]
zh[, year := as.integer(substr(ym, 1, 4))]

# Trips by mode ----
yr <- zh[year <= 2025, .(trips = sum(trips)), by = .(year, type)]
show("Trips per year (millions)", dcast(yr[, .(year, type, m = round(trips / 1e6, 1))], year ~ type, value.var = "m"))
mo <- zh[, .(trips = sum(trips)), by = .(ym, type)]
show("Trips per day, same month 2019 vs 2025 (October)", dcast(mo[ym %in% c("2019-10", "2025-10", "2024-10")],
     type ~ ym, value.var = "trips")[, lapply(.SD, function(x) if (is.numeric(x)) round(x / 31) else x)])

# Trips by area, 2019 vs 2025 ----
ar <- zh[year %in% c(2019, 2025), .(trips = sum(trips)), by = .(year, type, area)]
ar <- dcast(ar, type + area ~ year, value.var = "trips")
ar[, change := round(`2025` / `2019` - 1, 3)]
show("Trips by area, 2025 vs 2019 (fhvhv starts 2019-02)", ar[order(type, -`2019`)])

# Speeds ----
# weekday daytime (7-19h), trips with a plausible distance and time; mph = miles / hours
sp <- zh[weekend == FALSE & hour >= 7 & hour < 19 & area %in% c("Manhattan CBD", "Manhattan north of 60th", "Outer boroughs"),
         .(mph = sum(miles) / sum(hours), n = sum(n_ok)), by = .(type, area, year)]
show("Weekday 7-19h speed (mph) by area and year", dcast(sp[year <= 2026][, mph := round(mph, 1)], year ~ type + area, value.var = "mph"))
spm <- zh[weekend == FALSE & hour >= 7 & hour < 19 & area == "Manhattan CBD" & year >= 2023,
          .(mph = round(sum(miles) / sum(hours), 2)), by = .(type, ym)]
show("Manhattan CBD weekday daytime speed by month, 2023 on", dcast(spm, ym ~ type, value.var = "mph"))
fwrite(sp, file.path(o, "facts_speed_area_year.csv"))

# speed by hour, 2019 vs 2025, weekdays, CBD
sh <- zh[weekend == FALSE & area == "Manhattan CBD" & year %in% c(2019, 2022, 2025),
         .(mph = round(sum(miles) / sum(hours), 1)), by = .(type, year, hour)]
show("CBD weekday speed by hour (yellow + fhvhv)", dcast(sh, hour ~ type + year, value.var = "mph"))

# Time of day ----
tod <- zh[weekend == FALSE & year %in% c(2019, 2022, 2025) & type %in% c("yellow", "fhvhv"), .(trips = sum(trips)), by = .(year, type, hour)]
tod[, share := round(100 * trips / sum(trips), 2), by = .(year, type)]
show("Weekday share of trips by hour (%)", dcast(tod, hour ~ type + year, value.var = "share"))
pk <- zh[weekend == FALSE & type %in% c("yellow", "fhvhv") & year <= 2025,
         .(am_peak = sum(trips[hour %in% 7:9]) / sum(trips), pm_peak = sum(trips[hour %in% 16:18]) / sum(trips),
           night = sum(trips[hour %in% c(22, 23, 0:4)]) / sum(trips)), by = .(type, year)]
show("Weekday peak and night shares", pk[, lapply(.SD, function(x) if (is.numeric(x) && max(x) < 1) round(100 * x, 1) else x)][order(type, year)])

# Weekend share of trips
we <- zh[year <= 2025 & type %in% c("yellow", "fhvhv"), .(weekend_share = round(100 * sum(trips[weekend]) / sum(trips), 1)), by = .(type, year)]
show("Share of trips on weekends (%)", dcast(we, year ~ type, value.var = "weekend_share"))

# Citi Bike ----
cb <- rd("citibike_daily.parquet")
cby <- cb[year(date) <= 2025, .(trips_m = round(sum(trips) / 1e6, 1), member = round(sum(member) / sum(trips), 3),
                                ebike = round(sum(ebike, na.rm = TRUE) / sum(trips), 3)), by = .(year = year(date))]
st <- rd("citibike_station_month.parquet")[, .(stations = uniqueN(station)), by = .(year = as.integer(substr(ym, 1, 4)))]
show("Citi Bike per year", merge(cby, st, by = "year"))

# Crash risk per trip ----
cr <- rd("cov_crashes_daily.parquet")
cry <- cr[year(date) %in% 2013:2025, .(crashes = sum(crashes), with_injury = sum(with_injury), cyc_inj = sum(number_of_cyclist_injured),
                                     cyc_killed = sum(number_of_cyclist_killed), ped_inj = sum(number_of_pedestrians_injured),
                                     ped_killed = sum(number_of_pedestrians_killed), mot_inj = sum(number_of_motorist_injured),
                                     killed = sum(number_of_persons_killed)), by = .(year = year(date))]
cry <- merge(cry, cby[, .(year, cb_trips_m = trips_m)], by = "year", all.x = TRUE)
cry[, `:=`(pdo_crashes = crashes - with_injury, cyc_inj_per_m_cb = round(cyc_inj / cb_trips_m))]
show("Crashes: with injury vs property damage only; cyclist injuries per million Citi Bike trips", cry)

bm <- rd("cov_crashes_boro_month.parquet")[!is.na(boro)]
bm[, year := as.integer(substr(ym, 1, 4))]
bmy <- bm[year %in% c(2019, 2025), .(crashes = sum(crashes), with_injury = sum(with_injury)), by = .(boro, year)]
bmy <- dcast(bmy, boro ~ year, value.var = c("crashes", "with_injury"))
bmy[, `:=`(all_change = round(crashes_2025 / crashes_2019 - 1, 3), injury_change = round(with_injury_2025 / with_injury_2019 - 1, 3))]
show("Geocoded crashes by borough, 2025 vs 2019", bmy)

veh <- rd("cov_vehicles_month.parquet")[, .(N = sum(N)), by = .(year = as.integer(substr(ym, 1, 4)), class)]
show("Crash-involved two-wheelers per year", dcast(veh[class %in% c("Bike", "Scooter", "Motorcycle") & year <= 2025], year ~ class, value.var = "N"))

pr <- rd("cov_persons_month.parquet")
show("Persons per year by injury status (the table holds every person from 2016 on?)",
     dcast(pr[, .(N = sum(N)), by = .(year = substr(ym, 1, 4), injury)], year ~ injury, value.var = "N"))

# Air ----
air <- rd("cov_air_month.parquet")
show("NYC-area monitors: sites and mean per year", dcast(air[, .(sites = uniqueN(site_id), mean = round(weighted.mean(mean, obs), 3)),
     by = .(pollutant, year = substr(ym, 1, 4))], year ~ pollutant, value.var = c("mean", "sites")))

# Congestion relief zone ----
crz <- rd("cov_crz_daily.parquet")
crm <- crz[, .(per_day = round(sum(entries) / uniqueN(date))), by = .(ym = substr(as.character(date), 1, 7))]
show("CRZ entries per day by month", crm)
show("CRZ entries by vehicle class, first vs last full quarter", dcast(crz[date < as.IDate("2025-04-01") | date >= max(date) - 90,
     .(per_day = round(sum(entries) / uniqueN(date))), by = .(period = fifelse(date < as.IDate("2025-04-01"), "2025Q1", "last 90 days"), class)],
     class ~ period, value.var = "per_day"))
