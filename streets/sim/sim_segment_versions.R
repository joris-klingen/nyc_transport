# Simulated segment versions (lines)
#
# Real data: data/derived/streets/spine/segment_versions.gpkg, read with segment_versions_read(date)
# (spine/02_segment_versions.R). One row per LION SegmentID x distinct geometry (228,389 rows):
# segment_id, version, first_release, last_release, first_date, last_date, geometry (LINESTRING,
# EPSG 2263). streets_state(geometry = TRUE) takes the 26c versions as the key segments' lines.
#
# Kept: the versions of sim_segment_key(), lines of the right length placed where LION segments
# are (cells of the real centroids). Not kept: a connected street network; segments are straight
# and unrelated to each other (use sim_lion(grid = TRUE) in the repo-level sim/ for a network).
#
# v <- sim_segment_versions(sim_segment_key())

sim_segment_versions <- function(segment_key = sim_segment_key(), seed = NULL) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  if (!is.null(seed)) set.seed(seed)
  v <- unique(segment_key, by = c("segment_id", "version"))
  g <- sim_streets_profile("segment_versions", nrow(v))
  x <- v[, .(segment_id, version, first_release, last_release, first_date, last_date)]
  cc <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_geometry(g))))
  x[, `:=`(.geom_x = cc[, 1], .geom_y = cc[, 2], .geom_length = v[, length_ft])]
  sim_geometry(x, "LINESTRING", 2263)
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(sim_segment_versions(sim_segment_key(sim_key_segments(50, seed = 1))))
}
