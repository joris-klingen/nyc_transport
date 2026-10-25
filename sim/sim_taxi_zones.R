# Simulated TLC taxi zones
#
# Real data: raw/taxi/zones/taxi_zones_YYYYMMDD.zip (shapefile) with taxi_zone_lookup_YYYYMMDD.csv,
# read with taxi_zones_read(): sf in EPSG 2263 with LocationID, Borough, Zone, service_zone and
# MULTIPOLYGON geometry, 263 zones (264/265 are "unknown" and have no polygon). PULocationID and
# DOLocationID in all TLC trips refer to these. nyc_res_bikelanes uses the 2025 version
# (taxi_zones_20250923.zip): the same polygons, but ids 56 and 103 duplicated where 2026 has 57, 104, 105.
#
# Kept: the real lookup table (profiles/taxi_zone_lookup_full.csv: all ids, boroughs, zone names),
# one square polygon per zone of the profiled zone areas, placed where zones are. Not kept: zone
# shapes, adjacency, which zone lies where (squares overlap and ignore boroughs).
#
# z <- sim_taxi_zones()

sim_taxi_zones <- function(seed = NULL) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  lk <- sim_ref("taxi_zone_lookup_full.csv")
  lk <- lk[!LocationID %in% c(264L, 265L)]
  g <- sim_profile("taxi_zones", nrow(lk), seed)
  out <- sf::st_sf(lk[seq_len(nrow(g))], geometry = sf::st_geometry(g))
  out
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(sim_taxi_zones(seed = 1))
}
