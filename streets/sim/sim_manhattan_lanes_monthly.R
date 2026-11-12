# Simulated Manhattan monthly lane panel
#
# Real data: data/derived/streets/travel_lanes/manhattan_lanes_monthly.parquet (layers/travel_lanes/
# 02_manhattan_lane_panel.R), 2.5M rows: one row per Manhattan SegmentID and month 2012-07 to
# 2026-08 with lanes (moving lanes, dated with the bike lane projects and the reviews) and
# lanes_flag ("" dated, "undated" where the change date is not known).
#
# Kept: a lane count per segment drawn from the profile, constant over the months except a lane
# removed in about 6% of segments (the road diets that come with protected lanes); lanes_flag
# "undated" for 3% of segments. Not kept: removals at the same month along a corridor.
#
# m <- sim_manhattan_lanes_monthly(300)

sim_manhattan_lanes_monthly <- function(n = 300, seed = NULL, segment_ids = NULL,
                                        from = "2012-07-01", to = "2026-08-01") {
  if (!is.null(seed)) set.seed(seed)
  ids <- if (is.null(segment_ids)) sort(sample.int(330000L, n)) else segment_ids
  n <- length(ids)
  months <- seq(as.Date(from), as.Date(to), by = "month")
  a <- sim_streets_profile("manhattan_lanes_monthly", n)
  drop_at <- ifelse(stats::runif(n) < 0.06, sample(seq_along(months), n, replace = TRUE), NA_integer_)
  out <- data.table(SegmentID = rep(as.integer(ids), each = length(months)), month = rep(months, n),
                    lanes = rep(a[, lanes], each = length(months)),
                    lanes_flag = rep(ifelse(stats::runif(n) < 0.03, "undated", ""), each = length(months)),
                    m = rep(seq_along(months), n), drop = rep(drop_at, each = length(months)))
  out[!is.na(drop) & m >= drop, lanes := pmax(1, lanes - 1)]
  out[, c("m", "drop") := NULL]
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  m <- sim_manhattan_lanes_monthly(100, seed = 1)
  print(m[, .(lanes = mean(lanes)), month][c(1, .N)])
}
