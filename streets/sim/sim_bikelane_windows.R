# Simulated bike lane time windows
#
# Real data: data/derived/streets/bike_lanes/bike_lanes_time_windows.RDS (version "dot2026", all
# boroughs, 52,202 rows on 25,123 segments) and bike_lanes_time_windows_dot2020.RDS ("dot2020"),
# read with bikelane_windows_read(version) in R/nyc_transport.R and used by nyc_res_bikelanes (101).
# One row per SegmentID x time_window: SegmentID (numeric), time_window (1, 2, ...), date_from,
# date_to (POSIXct, America/New_York), tf_facilit and ft_facilit (Protected, Standard, Sharrows;
# NA = no lane in that direction).
#
# Kept: window 1 runs from 1899-01-01 without a lane; windows follow each other without gaps; the
# last ends 2099-09-09; about half of the lanes are on one side only (one-way streets); first
# facilities Standard 48%, Protected 34%, Sharrows 18%; about 10% of segments get a second change
# (mostly an upgrade to Protected, sometimes a removal). Not kept: install dates clustered by
# project, segments of one street sharing dates.
#
# w <- sim_bikelane_windows(500)                     # SegmentIDs drawn
# w <- sim_bikelane_windows(segment_ids = keys[, key_id])

sim_bikelane_windows <- function(n = 1000, seed = NULL, segment_ids = NULL, version = c("dot2026", "dot2020")) {
  version <- match.arg(version)
  if (!is.null(seed)) set.seed(seed)
  ids <- if (is.null(segment_ids)) sort(sample.int(330000L, n)) else segment_ids
  n <- length(ids)
  tz <- "America/New_York"
  start <- as.POSIXct("1899-01-01", tz = tz)
  end <- as.POSIXct("2099-09-09", tz = tz)
  last_date <- if (version == "dot2026") as.Date("2026-07-31") else as.Date("2020-06-30")
  day <- function(d) as.POSIXct(format(d), tz = tz)
  inst <- sample(seq(as.Date("1995-01-01"), last_date, by = "day"), n, replace = TRUE)
  early <- stats::runif(n) < 0.15
  inst[early] <- sample(seq(as.Date("1970-01-01"), as.Date("1994-12-31"), by = "day"), sum(early), replace = TRUE)
  type <- sample(c("Standard", "Protected", "Sharrows"), n, replace = TRUE, prob = c(0.48, 0.34, 0.18))
  sides <- sample(c("both", "tf", "ft"), n, replace = TRUE, prob = c(0.5, 0.26, 0.24))
  second <- stats::runif(n) < 0.11 & inst < last_date - 365
  nxt <- ifelse(type == "Protected", sample(c(NA, "Standard"), n, replace = TRUE, prob = c(0.7, 0.3)),
                sample(c("Protected", NA, "Sharrows"), n, replace = TRUE, prob = c(0.8, 0.12, 0.08)))
  at <- inst + sample(180:4000, n, replace = TRUE)
  second <- second & at <= last_date
  lane <- function(f, s, side) ifelse(s %in% c("both", side), f, NA_character_)
  w1 <- data.table(SegmentID = as.numeric(ids), time_window = 1L, date_from = start, date_to = day(inst),
                   tf_facilit = NA_character_, ft_facilit = NA_character_)
  w2 <- data.table(SegmentID = as.numeric(ids), time_window = 2L, date_from = day(inst), date_to = end,
                   tf_facilit = lane(type, sides, "tf"), ft_facilit = lane(type, sides, "ft"))
  w2[second, date_to := day(at[second])]
  w3 <- data.table(SegmentID = as.numeric(ids[second]), time_window = 3L, date_from = day(at[second]), date_to = end,
                   tf_facilit = lane(nxt[second], sides[second], "tf"), ft_facilit = lane(nxt[second], sides[second], "ft"))
  out <- rbindlist(list(w1, w2, w3))
  setorder(out, SegmentID, time_window)
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  w <- sim_bikelane_windows(200, seed = 1)
  print(head(w, 10))
  print(w[, .N, .(time_window, tf_facilit)])
}
