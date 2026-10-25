# Simulated MTA congestion relief zone entries
#
# Real data: raw/congestion_pricing/MTA_Congestion_Relief_Zone_Vehicle_Entries__Beginning_2025_YYYYMMDD.csv
# (data.ny.gov t6yz-b64h, was t2rz-wjj6; ~6.7M rows to 2026-10), read raw with data.table::fread(nyc_latest("crz_entries")).
# One row per 10-minute block, vehicle class and detection group since the toll started on
# 2025-01-05: Toll Date (text MM/DD/YYYY), Toll Hour and Toll 10 Minute Block (text
# MM/DD/YYYY HH:MM:SS AM), Minute of Hour, Hour of Day, Day of Week Int (1 = Sunday), Day of
# Week, Toll Week (the Sunday of the week, text), Time Period (Peak, Overnight), Vehicle Class
# (6 classes: "1 - Cars, Pickups and Vans", ..., "TLC Taxi/FHV"), Detection Group (12 bridges,
# tunnels and avenues at 60th St), Detection Region (Brooklyn, Queens, New Jersey, ...),
# CRZ Entries, Excluded Roadway Entries (on FDR Drive / West Side Highway, not tolled).
#
# Kept: every 10-minute block from `from` to `to` for every class and detection group; the time
# columns consistent with each other and written as in the file; Peak 5 AM to 9 PM on weekdays
# and 9 AM to 9 PM at weekends (the toll's peak hours); each detection group in its region;
# entries following the time of day around a level per class and group drawn from the profile.
# Not kept: the real volumes per crossing, holidays, the change of peak toll in 2026.
#
# crz <- sim_crz_entries(from = "2025-01-05", to = "2025-01-11")

sim_crz_entries <- function(from = "2025-01-05", to = "2025-01-11", seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  regions <- c("Brooklyn Bridge" = "Brooklyn", "Manhattan Bridge" = "Brooklyn", "Williamsburg Bridge" = "Brooklyn",
               "Hugh L. Carey Tunnel" = "Brooklyn", "Queensboro Bridge" = "Queens", "Queens Midtown Tunnel" = "Queens",
               "Holland Tunnel" = "New Jersey", "Lincoln Tunnel" = "New Jersey", "East 60th St" = "East 60th St",
               "West 60th St" = "West 60th St", "FDR Drive at 60th St" = "FDR Drive", "West Side Highway at 60th St" = "West Side Highway")
  classes <- c("1 - Cars, Pickups and Vans", "2 - Single-Unit Trucks", "3 - Multi-Unit Trucks", "4 - Buses", "5 - Motorcycles", "TLC Taxi/FHV")
  tz <- "America/New_York"
  t <- seq(as.POSIXct(from, tz = tz), as.POSIXct(as.Date(to) + 1, tz = tz) - 600, by = "10 min")
  g <- CJ(time = t, `Vehicle Class` = classes, `Detection Group` = names(regions), sorted = FALSE)
  level <- CJ(`Vehicle Class` = classes, `Detection Group` = names(regions))
  share <- c(0.62, 0.06, 0.02, 0.03, 0.01, 0.26)[match(level[, `Vehicle Class`], classes)]
  level[, lvl := stats::median(sim_profile("crz_entries", 2000)[, `CRZ Entries`], na.rm = TRUE) * 6 * share * stats::rlnorm(.N, 0, 0.5)]
  g[level, on = c("Vehicle Class", "Detection Group"), lvl := i.lvl]
  h <- data.table::hour(g[, time]); wd <- data.table::wday(g[, time])
  daily <- 0.15 + 0.85 * pmax(0, sin((h - 4) / 20 * pi))
  g[, `CRZ Entries` := as.integer(stats::rpois(.N, lvl * daily))]
  g[, `Excluded Roadway Entries` := fifelse(`Detection Group` %in% c("FDR Drive at 60th St", "West Side Highway at 60th St"),
                                            as.integer(stats::rpois(.N, lvl * daily * 0.8)), 0L)]
  hour_start <- g[, time] - (data.table::minute(g[, time]) * 60)
  week_start <- as.Date(format(g[, time], "%Y-%m-%d")) - (wd - 1L)
  g[, `:=`(`Toll Date` = format(time, "%m/%d/%Y"), `Toll Hour` = format(hour_start, "%m/%d/%Y %I:%M:%S %p"),
           `Toll 10 Minute Block` = format(time, "%m/%d/%Y %I:%M:%S %p"), `Minute of Hour` = data.table::minute(time),
           `Hour of Day` = h, `Day of Week Int` = wd, `Day of Week` = format(time, "%A"), `Toll Week` = format(week_start, "%m/%d/%Y"),
           `Time Period` = fifelse((wd %in% 2:6 & h >= 5 & h < 21) | (wd %in% c(1L, 7L) & h >= 9 & h < 21), "Peak", "Overnight"),
           `Detection Region` = unname(regions[`Detection Group`]))]
  g[, c("time", "lvl") := NULL]
  setcolorder(g, c("Toll Date", "Toll Hour", "Toll 10 Minute Block", "Minute of Hour", "Hour of Day", "Day of Week Int", "Day of Week",
                   "Toll Week", "Time Period", "Vehicle Class", "Detection Group", "Detection Region", "CRZ Entries", "Excluded Roadway Entries"))
  g[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  crz <- sim_crz_entries(seed = 1)
  print(head(crz, 3))
  print(crz[, .(entries = sum(`CRZ Entries`)), `Time Period`])
}
