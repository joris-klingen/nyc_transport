# Simulated LION lane panel
#
# Real data: data/derived/streets/travel_lanes/lion_lanes_panel.parquet (layers/travel_lanes/
# 01_lion_panel.R), 6.6M rows: one row per SegmentID and LION release with SegmentTyp, boro,
# Street, FeatureTyp, RW_TYPE, TrafDir, trav (moving lanes), park (parking lanes), tot (total
# lanes), width_min, width_max (ft), bikelane (LION's bike lane code, "" none), release,
# release_date. Lane counts and widths are NA before 2016 (LION had none) and for about 30% of rows.
#
# Kept: each segment's attributes drawn once and repeated over the releases from 12a to 26c, lane
# and width columns NA before release 16a (2016-02), with one change in about 20% of segments at a
# later release; tot = trav + park where both are known. Not kept: recounts across the network in
# one release (LION 2024).
#
# p <- sim_lion_lanes_panel(500)

sim_lion_lanes_panel <- function(n = 500, seed = NULL, segment_ids = NULL) {
  if (!is.null(seed)) set.seed(seed)
  rel <- sim_lion_releases()
  ids <- if (is.null(segment_ids)) sort(sample.int(330000L, n)) else segment_ids
  n <- length(ids)
  a <- sim_streets_profile("lion_lanes_panel", n)
  a[, c("release", "release_date") := NULL]
  a[, SegmentID := as.integer(ids)]
  a[!is.na(trav) & !is.na(park), tot := trav + park]
  lanes_from <- as.IDate("2016-02-25")
  ch_at <- ifelse(stats::runif(n) < 0.2, sample(rel[release_date > lanes_from, release_date], n, replace = TRUE), NA)
  out <- a[rep(seq_len(n), each = nrow(rel))]
  out[, `:=`(release = rep(rel[, release], n), release_date = as.Date(rep(rel[, release_date], n)),
             change_at = rep(as.Date(ch_at, origin = "1970-01-01"), each = nrow(rel)))]
  out[release_date < lanes_from, c("trav", "park", "tot", "width_min", "width_max") := NA_real_]
  out[!is.na(change_at) & release_date >= change_at & !is.na(trav), `:=`(trav = pmax(1, trav - 1), tot = pmax(1, tot - 1))]
  out[, change_at := NULL]
  setcolorder(out, c("SegmentID", "SegmentTyp", "boro", "Street", "FeatureTyp", "RW_TYPE", "TrafDir", "trav", "park", "tot",
                     "width_min", "width_max", "bikelane", "release", "release_date"))
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  p <- sim_lion_lanes_panel(50, seed = 1)
  print(p[SegmentID == SegmentID[1], .(release, trav, park, tot)])
}
