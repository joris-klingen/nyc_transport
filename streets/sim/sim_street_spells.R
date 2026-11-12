# Simulated street spells
#
# Real data: data/derived/streets/spells/street_spells.parquet (build/01_street_spells.R), read with
# streets_spells_read(); 997,002 rows. Every street attribute as spells on the key segments:
# key_id, attribute (in_lion, bike_lane, travel_lanes, parking_lanes, total_lanes, street_width,
# traffic_dir; see streets_attributes()), side (both, or tf / ft for bike lanes), value (text:
# "1", "2", "Protected", "T", ...), valid_from, valid_to (IDate; NA = still valid),
# date_precision (open, release, day, month, year, verified, undated), source (lion, bike_lanes,
# manhattan_lane_panel), priority (1 wins over 2 where sources overlap), source_id, key_cover.
# streets_panel() and streets_state() turn the spells into a panel; they take spells = and keys =
# so they run on simulated spells.
#
# Kept (from profiles/street_spells_attributes.csv and street_spells_attribute_values.csv): which
# share of key segments has each attribute, the value shares per attribute, when each LION
# attribute starts (traffic_dir 2012-05, lanes 2016-02, width 2016-11) and how often it changes
# at a later release; Manhattan travel lanes from 2012-07 with occasional lane removals; bike
# lanes per direction as none -> Standard / Protected / Sharrows -> sometimes Protected, about
# half on one side only, with the precision shares of the real install dates.
# Not kept: consistency between attributes (total = travel + parking lanes), bike lanes on the
# streets that have them, more than one change per attribute.
#
# keys <- sim_key_segments(2000); sp <- sim_street_spells(keys)
# streets_panel("2018-01-01", "2019-12-01", spells = sp, keys = keys)

sim_street_spells <- function(keys = sim_key_segments(), seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  rel <- sim_lion_releases()
  att <- fread(file.path(streets_profiles_dir(), "street_spells_attributes.csv"))
  vals <- fread(file.path(streets_profiles_dir(), "street_spells_attribute_values.csv"), colClasses = c(value = "character"))
  prec <- fread(file.path(streets_profiles_dir(), "street_spells_bike_lane_precision.csv"))
  open_from <- as.IDate("1900-01-01")
  draw <- function(a, s, n) { v <- vals[attribute == a & source == s]; sample(v[, value], n, replace = TRUE, prob = v[, share]) }
  spell <- function(k, a, side, value, from, to, precision, source, priority)
    data.table(key_id = k, attribute = a, side = side, value = value, valid_from = as.IDate(from), valid_to = as.IDate(to),
               date_precision = precision, source = source, priority = as.integer(priority), source_id = k, key_cover = 1)
  out <- list()
  # in LION from the start
  out$in_lion <- spell(keys[, key_id], "in_lion", "both", "1", open_from, NA, "open", "lion", 1)
  # LION attributes: a first value at the first release that has it, sometimes one change later
  for (a in c("traffic_dir", "parking_lanes", "street_width", "total_lanes", "travel_lanes")) {
    r <- att[attribute == a & source == "lion"]
    k <- keys[stats::runif(.N) < r[, keys_share], key_id]
    if (!length(k)) next
    from <- as.IDate(r[, first_from])
    later <- rel[release_date > from, release_date]
    ch <- stats::runif(length(k)) < r[, changed_share]
    at <- as.IDate(rep(NA_integer_, length(k)))
    at[ch] <- sample(later, sum(ch), replace = TRUE)
    v1 <- draw(a, "lion", length(k))
    out[[a]] <- spell(k, a, "both", v1, from, at, "release", "lion", 2)
    if (any(ch)) out[[paste0(a, "_2")]] <- spell(k[ch], a, "both", draw(a, "lion", sum(ch)), at[ch], NA, "release", "lion", 2)
  }
  # Manhattan travel lanes, dated with the bike lane projects: from 2012-07, sometimes one lane fewer later
  r <- att[attribute == "travel_lanes" & source == "manhattan_lane_panel"]
  man <- keys[boro == 1, key_id]
  if (length(man)) {
    k <- man[stats::runif(length(man)) < min(1, r[, keys_share] / mean(keys[, boro == 1]))]
    if (length(k)) {
      ch <- stats::runif(length(k)) < r[, changed_share]
      at <- as.IDate(rep(NA_integer_, length(k)))
      at[ch] <- sample(seq(as.IDate("2013-01-01"), as.IDate("2026-03-01"), by = "month"), sum(ch), replace = TRUE)
      v1 <- draw("travel_lanes", "manhattan_lane_panel", length(k))
      out$man <- spell(k, "travel_lanes", "both", v1, "2012-07-01", at, "month", "manhattan_lane_panel", 1)
      if (any(ch)) out$man2 <- spell(k[ch], "travel_lanes", "both", as.character(pmax(1, as.integer(v1[ch]) - 1L)), at[ch], NA,
                                     "month", "manhattan_lane_panel", 1)
    }
  }
  # bike lanes per direction: none until installed, then a facility, sometimes upgraded to Protected
  r <- att[attribute == "bike_lane" & side == "tf"]
  k <- keys[stats::runif(.N) < r[, keys_share], key_id]
  if (length(k)) {
    n <- length(k)
    # install dates: 70% from 2007 on (most of the network), the rest from 1990
    inst <- as.IDate(sample(seq(as.Date("1990-01-01"), as.Date("2026-07-01"), by = "day"), n, replace = TRUE))
    late <- stats::runif(n) < 0.7
    inst[late] <- as.IDate(sample(seq(as.Date("2007-01-01"), as.Date("2026-07-01"), by = "day"), sum(late), replace = TRUE))
    type <- sample(c("Standard", "Protected", "Sharrows"), n, replace = TRUE, prob = c(0.48, 0.34, 0.18))
    up <- type != "Protected" & stats::runif(n) < 0.12 & inst < as.IDate("2024-01-01")
    up_at <- as.IDate(rep(NA_integer_, n))
    up_at[up] <- inst[up] + sample(180:3000, sum(up), replace = TRUE)
    up[up_at > as.IDate("2026-07-01") & !is.na(up_at)] <- FALSE
    sides <- sample(c("both", "tf", "ft"), n, replace = TRUE, prob = c(0.5, 0.25, 0.25))
    pr <- function(m) sample(prec[, date_precision], m, replace = TRUE, prob = prec[, share])
    for (sd in c("tf", "ft")) {
      has <- sides %in% c("both", sd)
      out[[paste0("bl_none_", sd)]] <- spell(k, "bike_lane", sd, "none", open_from, fifelse(has, inst, as.IDate(NA)), "open", "bike_lanes", 1)
      if (any(has)) {
        out[[paste0("bl_lane_", sd)]] <- spell(k[has], "bike_lane", sd, type[has], inst[has], fifelse(up[has], up_at[has], as.IDate(NA)),
                                               pr(sum(has)), "bike_lanes", 1)
        u <- has & up
        if (any(u)) out[[paste0("bl_up_", sd)]] <- spell(k[u], "bike_lane", sd, "Protected", up_at[u], NA, pr(sum(u)), "bike_lanes", 1)
      }
    }
  }
  sp <- rbindlist(out)
  setorder(sp, key_id, attribute, side, valid_from)
  sp[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  keys <- sim_key_segments(1000, seed = 1)
  sp <- sim_street_spells(keys)
  print(sp[, .N, .(attribute, source)])
  print(sp[key_id == sp[attribute == "bike_lane" & value == "Protected", key_id[1]]])
}
