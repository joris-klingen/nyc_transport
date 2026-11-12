# Manhattan travel-lane panel: LION 2016/2024 counts dated with bike lane changes
#
# LION carries lane counts from release 16a (Feb 2016) and was recounted once, in 24b (Apr 2024);
# in between the counts are frozen (see lanes/out/release_changes.csv). So LION gives a "2016"
# and a "2024" value per segment but not when a change happened. Dating rules per segment:
#   no change                         constant
#   fewer lanes, bike facility change dated at the (latest) facility change between the releases,
#     between 16a and 24b             using the reviewed date where one exists
#   fewer lanes, no facility change   review
#   more lanes, no facility change    correction: the 2024 value applies to the whole period
#   more lanes, facility change       review
# Segments that got a protected lane between 2012-07 and 16a are flagged: their 2016 value may
# already reflect the project, so the pre-project count is unknown.
#
# Writes lanes/out/manhattan_lane_spells.csv (one row per segment), lanes/out/lane_review.csv
# and data/derived/streets/travel_lanes/manhattan_lanes_monthly.parquet (segment x month).
# Run from repo root: Rscript layers/travel_lanes/02_manhattan_lane_panel.R

library(data.table)
library(arrow)
library(sf)

source("R/streets.R")   # segment_versions_read(); also sources nyc_transport.R
root <- nyc_data_root()
p <- setDT(read_parquet(file.path(nyc_streets_data_root(), "travel_lanes/lion_lanes_panel.parquet")))[boro == 1]

d16 <- as.IDate("2016-02-01")   # first release with lane counts (16a, data as of early 2016)
d24 <- as.IDate("2024-04-29")   # release with the citywide recount (24b)
months <- seq(as.IDate("2012-07-01"), as.IDate("2026-08-01"), by = "month")

# LION values: first and last release with a lane count ----
setorder(p, SegmentID, release)
lv <- p[!is.na(trav), .(street = Street[.N], trav_first = trav[1], rel_first = release[1],
                        trav_last = trav[.N], rel_last = release[.N],
                        n_values = uniqueN(trav), rel_changes = paste(release[c(FALSE, diff(trav) != 0)], collapse = " "),
                        trafdir = TrafDir[.N], width = width_min[.N]), by = SegmentID]

# Bike facility changes per segment (fixed pipeline) ----
tw <- setDT(bikelane_windows_read())
tw[, date_from := as.IDate(date_from)]
fac <- tw[time_window > 1 & date_from > as.IDate("1900-01-01"), .(fac_dates = list(sort(unique(date_from)))), by = SegmentID]
prot <- tw[tf_facilit == "Protected" | ft_facilit == "Protected", .(prot_from = min(date_from)), by = SegmentID]

# Reviewed protection dates (review page answers, exported to manual/) override the pipeline ----
rev_path <- "layers/bike_lanes/manual/streetview_review_answers.csv"
rev <- if (file.exists(rev_path)) fread(rev_path, colClasses = "character") else data.table(proj_id = character(), protected_from = character())
rev <- rev[grepl("^\\d{4}-\\d{2}$", protected_from)]
rev[, rev_date := as.IDate(paste0(protected_from, "-01"))]
seg_proj <- fread("evidence/aerial_labelling/out/project_segments.csv")[, proj_id := sprintf("M%03d", project)]
reviewed <- merge(seg_proj[, .(SegmentID, proj_id)], rev[, .(proj_id, rev_date)], by = "proj_id")

s <- Reduce(function(a, b) merge(a, b, by = "SegmentID", all.x = TRUE), list(lv, fac, prot, reviewed[, .(SegmentID, rev_date)]))

# facility changes strictly between the two LION snapshots
s[, fac_between := mapply(function(x) { x <- x[!is.null(x)]; if (!length(x)) as.IDate(NA) else { y <- x[x > d16 & x <= d24]; if (length(y)) max(y) else as.IDate(NA) } }, fac_dates)]
s[, fac_between := as.IDate(fac_between)]
s[!is.na(rev_date) & rev_date > d16 & rev_date <= d24, fac_between := rev_date]

s[, case := fcase(
  n_values == 1, "constant",
  trav_last < trav_first & !is.na(fac_between), "decrease_dated_by_facility",
  trav_last < trav_first, "review_decrease_no_facility",
  trav_last > trav_first & is.na(fac_between), "correction_increase",
  trav_last > trav_first, "review_increase_with_facility",
  default = "review_other")]
s[n_values > 2, case := "review_multiple_changes"]

# Central Park drives: lanes dropped when the drives went car-free (decision 2026-10-11): north of
# 72nd St 2015-06, the rest 2018-06 (manual/park_drive_dates.csv); north or south of the line along
# 72nd St from Central Park West to Fifth Av
park_drives <- c("EAST DRIVE", "WEST DRIVE", "TERRACE DRIVE", "CENTER DRIVE")
pd <- s[street %in% park_drives & trav_last < trav_first, SegmentID]
if (length(pd)) {
  g <- segment_versions_read()
  g <- g[g$segment_id %in% pd, ]
  g <- g[order(g$segment_id, -g$version), ]
  g <- g[!duplicated(g$segment_id), ]
  ctr <- st_coordinates(st_centroid(st_transform(st_geometry(g), 4326)))
  a <- c(-73.9776, 40.7766); b <- c(-73.9665, 40.7712)   # 72nd St at Central Park West, at Fifth Av
  north <- ((b[1] - a[1]) * (ctr[, 2] - a[2]) - (b[2] - a[2]) * (ctr[, 1] - a[1])) > 0
  carfree <- data.table(SegmentID = g$segment_id, carfree = as.IDate(fifelse(north, "2015-06-01", "2018-06-01")))
  s[carfree, on = "SegmentID", `:=`(case = "decrease_dated_by_carfree", fac_between = i.carfree)]
  cat("park drive segments dated at the car-free date:", nrow(carfree), "(north of 72nd St:", sum(north), ")\n")
}
s[, pre2016_project := !is.na(prot_from) & prot_from >= as.IDate("2012-07-01") & prot_from < d16]

s[, `:=`(
  lanes_before = fcase(case == "correction_increase", trav_last, default = trav_first),
  lanes_after = trav_last,
  change_date = fcase(case %in% c("decrease_dated_by_facility", "decrease_dated_by_carfree"), fac_between, default = as.IDate(NA)),
  date_source = fcase(case == "decrease_dated_by_carfree", "car-free date (park drives)",
                      case == "decrease_dated_by_facility" & !is.na(rev_date) & fac_between == rev_date, "street view review",
                      case == "decrease_dated_by_facility", "bike facility date (pipeline)", default = ""))]

spells <- s[, .(SegmentID, street, case, lanes_before, lanes_after, change_date, date_source, pre2016_project,
                prot_from, trav_lion16 = trav_first, trav_lion_last = trav_last, rel_changes, trafdir, width)]
fwrite(spells[order(street, SegmentID)], "layers/travel_lanes/out/manhattan_lane_spells.csv")

cat("Manhattan street segments with lane counts:", nrow(spells), "\n")
print(spells[, .N, by = case][order(-N)])
cat("segments with a protected lane installed 2012-07 .. 2016-02 (pre-project count unknown):", spells[pre2016_project == TRUE, .N], "\n")

# Review list, grouped by street ----
rv <- spells[grepl("^review", case) | pre2016_project == TRUE]
rv_st <- rv[, .(segments = .N, cases = paste(sort(unique(case)), collapse = ", "),
                lanes = paste(unique(paste0(trav_lion16, "->", trav_lion_last)), collapse = " "),
                pre2016 = sum(pre2016_project)), by = street][order(-segments)]
fwrite(rv_st, "layers/travel_lanes/out/lane_review.csv")
cat("\nreview: ", nrow(rv), "segments on", nrow(rv_st), "streets; largest:\n")
print(rv_st[1:15])

# Monthly panel ----
m <- CJ(SegmentID = spells$SegmentID, month = months)
m <- merge(m, spells[, .(SegmentID, lanes_before, lanes_after, change_date, case)], by = "SegmentID")
m[, lanes := fifelse(!is.na(change_date) & month >= change_date, lanes_after, lanes_before)]
# undated review cases: LION's own timing (the recount release) as a placeholder, flagged
m[grepl("^review", case) & month >= d24, lanes := lanes_after]
m[, lanes_flag := fifelse(grepl("^review", case), "undated", "")]
write_parquet(m[, .(SegmentID, month, lanes, lanes_flag)], file.path(nyc_streets_data_root(), "travel_lanes/manhattan_lanes_monthly.parquet"))
cat("\nmonthly panel:", nrow(m), "rows,", length(months), "months\n")
