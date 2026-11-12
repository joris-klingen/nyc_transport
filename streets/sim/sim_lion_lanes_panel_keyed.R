# Simulated LION lane panel on the segment key
#
# Real data: data/derived/streets/travel_lanes/lion_lanes_panel_keyed.parquet (layers/travel_lanes/
# 03_key_panels.R), 6.3M rows: the LION lane panel moved onto the key segments: key_id, release,
# release_date, source_id (the source SegmentID), key_cover (of the key segment), n_sources,
# cover_total, then the lane panel columns (SegmentTyp, boro, Street, FeatureTyp, RW_TYPE, TrafDir,
# trav, park, tot, width_min, width_max, bikelane).
#
# Kept: sim_lion_lanes_panel() for the key segments, one source per key (key_cover 1,
# n_sources 1) as for 99% of the real rows.
#
# p <- sim_lion_lanes_panel_keyed(sim_key_segments(500))

sim_lion_lanes_panel_keyed <- function(keys = sim_key_segments(500), seed = NULL) {
  p <- sim_lion_lanes_panel(segment_ids = keys[, key_id], seed = seed)
  p[keys, on = c(SegmentID = "key_id"), `:=`(boro = i.boro, Street = i.street)]
  p[, `:=`(key_id = SegmentID, source_id = SegmentID, key_cover = 1, n_sources = 1L, cover_total = 1)]
  p[, SegmentID := NULL]
  setcolorder(p, c("key_id", "release", "release_date", "source_id", "key_cover", "n_sources", "cover_total"))
  p[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(head(sim_lion_lanes_panel_keyed(sim_key_segments(20, seed = 1))))
}
