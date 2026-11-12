# Simulated Manhattan monthly lane panel on the segment key
#
# Real data: data/derived/streets/travel_lanes/manhattan_lanes_monthly_keyed.parquet (layers/
# travel_lanes/03_key_panels.R): key_id, month, lanes, lanes_flag, source_id, key_cover,
# n_sources, cover_total. The Manhattan lane panel on the key segments.
#
# Kept: sim_manhattan_lanes_monthly() on the Manhattan key segments, one source per key.
#
# m <- sim_manhattan_lanes_monthly_keyed(sim_key_segments(300, boro = 1))

sim_manhattan_lanes_monthly_keyed <- function(keys = sim_key_segments(300, boro = 1), seed = NULL) {
  m <- sim_manhattan_lanes_monthly(segment_ids = keys[boro == 1, key_id], seed = seed)
  m[, `:=`(key_id = SegmentID, source_id = SegmentID, key_cover = 1, n_sources = 1L, cover_total = 1)]
  m[, SegmentID := NULL]
  setcolorder(m, c("key_id", "month", "lanes", "lanes_flag", "source_id", "key_cover", "n_sources", "cover_total"))
  m[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(head(sim_manhattan_lanes_monthly_keyed(sim_key_segments(20, seed = 1, boro = 1))))
}
