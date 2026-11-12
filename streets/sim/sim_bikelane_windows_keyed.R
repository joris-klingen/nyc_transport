# Simulated bike lane windows on the segment key
#
# Real data: data/derived/streets/bike_lanes/bike_lanes_windows_keyed.parquet, read with
# bikelane_windows_keyed_read() (layers/bike_lanes/scripts/04_key_windows.R); 52,319 rows. The
# windows of bikelane_windows_read() moved onto the key: key_id, SegmentID (the source segment),
# time_window, date_from, date_to (Date), tf_facilit, ft_facilit (in the key segment's direction),
# share, key_cover, reversed, key_status (current, continued), main_source (TRUE for one set of
# windows per key segment: filter on it).
#
# Kept: the windows of sim_bikelane_windows() on key segments, mostly one source per key
# (main_source TRUE); about 2% of keys get a second, continued source with main_source FALSE, and
# 2% are reversed (tf and ft swapped).
#
# kw <- sim_bikelane_windows_keyed(keys = sim_key_segments(2000))

sim_bikelane_windows_keyed <- function(keys = sim_key_segments(), share_with_lanes = 0.14, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  k <- keys[stats::runif(.N) < share_with_lanes, key_id]
  w <- sim_bikelane_windows(segment_ids = k)
  w[, `:=`(key_id = as.integer(SegmentID), date_from = as.Date(format(date_from)), date_to = as.Date(format(date_to)),
           share = 1, key_cover = 1, reversed = FALSE, key_status = "current", main_source = TRUE)]
  rev <- unique(w[, key_id])[stats::runif(uniqueN(w[, key_id])) < 0.02]
  w[key_id %in% rev, `:=`(tf_facilit = ft_facilit, ft_facilit = tf_facilit, reversed = TRUE)]
  extra <- unique(w[, key_id])[stats::runif(uniqueN(w[, key_id])) < 0.02]
  if (length(extra)) {
    e <- w[key_id %in% extra]
    e[, `:=`(SegmentID = SegmentID + 400000, share = round(stats::runif(.N, 0.2, 1), 3),
             key_cover = round(stats::runif(.N, 0.05, 0.5), 3), key_status = "continued", main_source = FALSE)]
    w <- rbind(w, e)
  }
  setcolorder(w, c("key_id", "SegmentID", "time_window", "date_from", "date_to", "tf_facilit", "ft_facilit",
                   "share", "key_cover", "reversed", "key_status", "main_source"))
  setorder(w, key_id, SegmentID, time_window)
  w[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  kw <- sim_bikelane_windows_keyed(sim_key_segments(1000, seed = 1))
  print(kw[, .N, .(main_source, key_status)])
}
