# Simulated DOT bike lane updates (Manhattan, 2025)
#
# Real data: data/derived/streets/bike_lanes/bike_lane_updates.gpkg (818 rows), the 2025 DOT updates
# for Manhattan used by the time windows: DOT bike route columns (segmentid, street, fromstreet,
# tostreet, facilitycl, allclasses, tf_facilit / ft_facilit with DOT facility names, bikeid,
# prevbikeid, instdate, ret_date, status, ...), in_prev_streets_data, bike_lane_found, and
# MULTILINESTRING geometry in EPSG 2263.
#
# Kept: column types and value shares, lines of the profiled lengths where the updates are.
# Not kept: links between bikeid and prevbikeid, segment ids that exist in LION.
#
# u <- sim_bike_lane_updates(200)

sim_bike_lane_updates <- function(n = 200, seed = NULL) {
  u <- sim_streets_profile("bike_lane_updates", n, seed)
  u[["bikeid"]] <- sprintf("%d", seq_len(nrow(u)) + 100000L)
  u
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(sim_bike_lane_updates(5, seed = 1))
}
