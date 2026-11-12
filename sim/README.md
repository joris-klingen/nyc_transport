# Simulators

Simulated data for code development without `data/`. `source("sim/sim.R")` loads all of them (see the repo README); profiles are in `../profiles/`.

Each script starts with what the real data are and what the simulation keeps and does not keep.
This index is made from those headers.

| Script | Source | Real reader or file | Example |
|---|---|---|---|
| [sim_address_points.R](sim_address_points.R) | Simulated address points | `address_points_read()` | `ap <- sim_address_points(10000)` |
| [sim_air_pollution.R](sim_air_pollution.R) | Simulated EPA AQS monitor data (NYC area) | `air_pollution_read(param, freq)` | `ap <- sim_air_pollution("hourly", from = "2019-06-01", to = "2019-06-30")` |
| [sim_arterial_slow_zones.R](sim_arterial_slow_zones.R) | Simulated arterial slow zones | `sf::st_read(nyc_latest('arterial_slow_zones'))` | `x <- sim_arterial_slow_zones(500)` |
| [sim_barnes_dance.R](sim_barnes_dance.R) | Simulated barnes dance | `data.table::fread(nyc_latest('barnes_dance'))` | `x <- sim_barnes_dance(500)` |
| [sim_bike_parking.R](sim_bike_parking.R) | Simulated bike parking | `data.table::fread(nyc_latest('bike_parking'))` | `x <- sim_bike_parking(500)` |
| [sim_bike_ped_counts.R](sim_bike_ped_counts.R) | Simulated bicycle and pedestrian counts | `bike_counts_read()` | `bc <- sim_bike_ped_counts(from = "2019-06-01", to = "2019-07-01")` |
| [sim_bike_ped_sensors.R](sim_bike_ped_sensors.R) | Bicycle and pedestrian count sensors (real list) | `bike_count_sensors()` | `s <- sim_bike_ped_sensors()` |
| [sim_bike_routes.R](sim_bike_routes.R) | Simulated DOT bike routes | `bike_routes_read()` | `br <- sim_bike_routes(lion = sim_lion())` |
| [sim_bike_shelters.R](sim_bike_shelters.R) | Simulated bike shelters | `data.table::fread(nyc_latest('bike_shelters'))` | `x <- sim_bike_shelters(500)` |
| [sim_boundaries.R](sim_boundaries.R) | Simulated administrative boundaries | `boundaries_read(name)` | `nta <- sim_boundaries("ntas")` |
| [sim_bus_lanes.R](sim_bus_lanes.R) | Simulated bus lanes | `sf::st_read(nyc_latest('bus_lanes'))` | `x <- sim_bus_lanes(500)` |
| [sim_census_block_groups.R](sim_census_block_groups.R) | Simulated 2020 census block groups and their population | `census_block_groups_read()` | `bg <- sim_census_block_groups(500); pop <- sim_bg_population(bg)` |
| [sim_citibike_stations.R](sim_citibike_stations.R) | Simulated Citi Bike station list (GBFS) | `jsonlite::fromJSON(nyc_latest("citibike_stations"))[["data"]][["stations"]]` | `st <- sim_citibike_stations()` |
| [sim_citibike_trips.R](sim_citibike_trips.R) | Simulated Citi Bike trips | `citibike_read("YYYY-MM")` | `cb <- sim_citibike_trips(20000, month = "2019-06")` |
| [sim_counts_legacy.R](sim_counts_legacy.R) | Simulated historical count files (no longer updated) | `data.table::fread(file.path(nyc_data_root(), <file>))` | `sim_counts_legacy()                                  # names of the files` |
| [sim_crash_persons.R](sim_crash_persons.R) | Simulated crash persons | `data.table::fread(nyc_latest("persons"))` | `cr <- sim_crashes(2000); veh <- sim_crash_vehicles(cr); per <- sim_crash_persons(cr, veh)` |
| [sim_crash_vehicles.R](sim_crash_vehicles.R) | Simulated crash vehicles | `data.table::fread(nyc_latest("vehicles"))` | `cr <- sim_crashes(2000); veh <- sim_crash_vehicles(cr)` |
| [sim_crashes.R](sim_crashes.R) | Simulated NYPD motor vehicle crashes | `crashes_read()` | `cr <- sim_crashes(5000, from = "2018-01-01", to = "2019-12-31")` |
| [sim_crz_entries.R](sim_crz_entries.R) | Simulated MTA congestion relief zone entries | `data.table::fread(nyc_latest("crz_entries"))` | `crz <- sim_crz_entries(from = "2025-01-05", to = "2025-01-11")` |
| [sim_lion.R](sim_lion.R) | Simulated LION street centerlines | `lion_read()` | `lion <- sim_lion()                               # 12 x 60 grid, ~1,400 segments` |
| [sim_lpi_signals.R](sim_lpi_signals.R) | Simulated lpi signals | `data.table::fread(nyc_latest('lpi_signals'))` | `x <- sim_lpi_signals(500)` |
| [sim_meter_blockfaces.R](sim_meter_blockfaces.R) | Simulated meter blockfaces | `sf::st_read(nyc_latest('meter_blockfaces'))` | `x <- sim_meter_blockfaces(500)` |
| [sim_meter_rate_zones.R](sim_meter_rate_zones.R) | Simulated meter rate zones | `sf::st_read(nyc_latest('meter_rate_zones'))` | `x <- sim_meter_rate_zones(500)` |
| [sim_neighborhood_slow_zones.R](sim_neighborhood_slow_zones.R) | Simulated neighborhood slow zones | `sf::st_read(nyc_latest('neighborhood_slow_zones'))` | `x <- sim_neighborhood_slow_zones(500)` |
| [sim_open_streets.R](sim_open_streets.R) | Simulated open streets | `sf::st_read(nyc_latest('open_streets'))` | `x <- sim_open_streets(500)` |
| [sim_parking_meters.R](sim_parking_meters.R) | Simulated parking meters | `data.table::fread(nyc_latest('parking_meters'))` | `x <- sim_parking_meters(500)` |
| [sim_parking_signs.R](sim_parking_signs.R) | Simulated parking signs | `data.table::fread(nyc_latest('parking_signs'))` | `x <- sim_parking_signs(500)` |
| [sim_pavement_ratings.R](sim_pavement_ratings.R) | Simulated pavement ratings | `data.table::fread(nyc_latest('pavement_ratings'))` | `x <- sim_pavement_ratings(500)` |
| [sim_ped_plazas.R](sim_ped_plazas.R) | Simulated ped plazas | `sf::st_read(nyc_latest('ped_plazas'))` | `x <- sim_ped_plazas(500)` |
| [sim_ped_space_added.R](sim_ped_space_added.R) | Simulated ped space added | `data.table::fread(nyc_latest('ped_space_added'))` | `x <- sim_ped_space_added(500)` |
| [sim_speed_humps.R](sim_speed_humps.R) | Simulated speed humps | `sf::st_read(nyc_latest('speed_humps'))` | `x <- sim_speed_humps(500)` |
| [sim_speed_limits.R](sim_speed_limits.R) | Simulated speed limits | `sf::st_read(nyc_latest('speed_limits'))` | `x <- sim_speed_limits(500)` |
| [sim_srts.R](sim_srts.R) | Simulated srts | `data.table::fread(nyc_latest('srts'))` | `x <- sim_srts(500)` |
| [sim_street_closures.R](sim_street_closures.R) | Simulated street closures | `data.table::fread(nyc_latest('street_closures'))` | `x <- sim_street_closures(500)` |
| [sim_street_network_changes.R](sim_street_network_changes.R) | Simulated street network changes | `data.table::fread(nyc_latest('street_network_changes'))` | `x <- sim_street_network_changes(500)` |
| [sim_taxi_fhvhv.R](sim_taxi_fhvhv.R) | Simulated high-volume for-hire trips (Uber, Lyft, Via, Juno) | `tlc_open("fhvhv")` | `fh <- sim_taxi_fhvhv(10000, month = "2022-06")` |
| [sim_taxi_green.R](sim_taxi_green.R) | Simulated green taxi (boro taxi) trips | `tlc_open("green")` | `tg <- sim_taxi_green(5000, month = "2016-06")` |
| [sim_taxi_yellow.R](sim_taxi_yellow.R) | Simulated yellow taxi trips | `tlc_open("yellow")` | `tt <- sim_taxi_yellow(10000, month = "2019-06")` |
| [sim_taxi_yellow_csv_legacy.R](sim_taxi_yellow_csv_legacy.R) | Simulated legacy yellow taxi CSV (trips with coordinates, 2012-01 to 2016-06) | `data.table::fread(f, header = TRUE, blank.lines.skip = TRUE)` | `tl <- sim_taxi_yellow_csv_legacy(10000, month = "2013-06")` |
| [sim_taxi_zones.R](sim_taxi_zones.R) | Simulated TLC taxi zones | `taxi_zones_read()` | `z <- sim_taxi_zones()` |
| [sim_tract_nta.R](sim_tract_nta.R) | Simulated tract nta | `data.table::fread(nyc_latest('tract_nta'))` | `x <- sim_tract_nta(500)` |
| [sim_traffic_counts.R](sim_traffic_counts.R) | Simulated DOT automated traffic counts (ATR) | `traffic_counts_read()` | `tc <- sim_traffic_counts(30, days = 14, from = "2018-01-01", to = "2019-12-31")` |
| [sim_truck_routes.R](sim_truck_routes.R) | Simulated truck routes | `sf::st_read(nyc_latest('truck_routes'))` | `x <- sim_truck_routes(500)` |
