# Segment x time-window bike lane facilities, all boroughs, from the DOT 2026 version history
#
# Base: the DOT bike routes release of 2026-10 (data/raw/street_layout/bike_routes), which keeps
#   every version of a segment's facility: Retired rows with instdate and ret_date, and the Current
#   row. Per segment the versions are ordered by instdate; a version lasts until the next one starts
#   (or until its ret_date, when the lane was removed). Facility texts (tf/ft, and tf2/ft2 where a
#   second facility is recorded) are coded with manual/lookup_bikelane_types.xlsx; the best class per
#   direction counts (I > II > III).
# Manual Street View checks (manual/streetview_dot2020.csv, on the DOT 2020 release): for the segments
#   they cover, their dates and before-upgrade types replace the DOT history up to the 2020 release.
# 2020 segments missing from the 2026 release whose street no 2026 segment continues keep their 2020
#   facility up to the 2020 release.
# Street View review overrides (manual/protection_overrides.csv) and the copies to LION 16d ids
#   (manual/segmentid_crosswalk_lion16d.csv) are applied as before.
# Output: data/derived/streets/bike_lanes/bike_lanes_time_windows.RDS, one row per
#   SegmentID x time_window with date_from, date_to and tf_/ft_facilit (Protected / Standard /
#   Sharrows, NA = none), read with bikelane_windows_read(). Until 2026-10-14 the windows came from the
#   DOT 2020 release plus the Manhattan 2025 updates (moved here from nyc_res_bikelanes 002 on
#   2026-10-13): kept as bike_lanes_time_windows_dot2020.RDS.
# Run from repo root: Rscript layers/bike_lanes/scripts/03_time_windows.R

library(data.table)
library(sf)

source("R/streets.R")   # segment key; also sources nyc_transport.R
out_dir <- file.path(nyc_streets_data_root(), "bike_lanes")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

snap_bike_routes <- "20261010"   # DOT release with the version history
start_date <- as.IDate("1899-01-01")
end_date <- as.IDate("2099-09-09")
lane_types <- c(I = "Protected", II = "Standard", III = "Sharrows")

# Facility coding ----
bl_types <- setDT(readxl::read_excel("layers/bike_lanes/manual/lookup_bikelane_types.xlsx"))
bl_types <- setNames(bl_types[, facility_code], bl_types[, facility_text])
to_class <- function(x) unname(fifelse(x %in% c("I", "II", "III"), x, bl_types[x]))
best <- function(...) {   # best class over several facility columns (I > II > III), NA if none
  r <- suppressWarnings(do.call(pmin, c(lapply(list(...), function(x) match(to_class(x), c("I", "II", "III"))), na.rm = TRUE)))
  c("I", "II", "III")[r]
}
best_of <- function(x) {  # best class within a group of rows
  r <- match(x, c("I", "II", "III"))
  if (all(is.na(r))) NA_character_ else c("I", "II", "III")[min(r, na.rm = TRUE)]
}

# DOT 2026 versions ----
d <- setDT(st_drop_geometry(st_read(nyc_latest("bike_routes", as_of = snap_bike_routes), quiet = TRUE)))
unknown <- setdiff(na.omit(unique(c(d[, tf_facilit], d[, ft_facilit], d[, tf2facilit], d[, ft2facilit]))), names(bl_types))
if (length(unknown)) stop("facility texts not in the lookup: ", paste(unknown, collapse = ", "))
d[, `:=`(seg = as.integer(segmentid), inst = as.IDate(instdate), ret = as.IDate(ret_date))]
d[, `:=`(tf = best(tf_facilit, tf2facilit), ft = best(ft_facilit, ft2facilit))]
d <- d[!is.na(seg) & seg != 0]
d[is.na(inst), inst := start_date]

# one version per segment and install date (rows repeat per geometry piece; 23 segments have two
# current rows): the best class per direction, the latest retirement
v <- d[, .(tf = best_of(tf), ft = best_of(ft), retired = all(status == "Retired"), ret = max(ret)), by = .(seg, inst)]
setorder(v, seg, inst)
v[, next_inst := shift(inst, -1), by = seg]
# a retirement date on or before its install date cannot be placed
bad_ret <- v[retired & !is.na(ret) & ret <= inst, .N]
v[retired & !is.na(ret) & ret <= inst, ret := NA]
# end of a version: the next version's start; a retirement before that (the lane removed until the
# next version); open for the current version and for retired versions without a date or successor
v[, end := fcase(!is.na(next_inst) & (!retired | is.na(ret) | ret >= next_inst), next_inst,
                 retired & !is.na(ret), ret,
                 default = end_date)]
w <- v[, .(SegmentID = seg, date_from = inst, date_to = end, tf, ft)]
# no lane before the first version, and between a retirement and the next version
gaps <- v[, .(SegmentID = seg, date_from = c(start_date, end[-.N]), date_to = c(inst[1], inst[-1])), by = seg][date_to > date_from]
after <- v[, .SD[.N], by = seg][end < end_date, .(SegmentID = seg, date_from = end, date_to = end_date)]
w <- rbind(w, gaps[, .(SegmentID, date_from, date_to, tf = NA_character_, ft = NA_character_)],
           after[, .(SegmentID, date_from, date_to, tf = NA_character_, ft = NA_character_)])[date_to > date_from]
cat("DOT 2026:", d[, uniqueN(seg)], "segments,", nrow(v), "versions;", nrow(after), "lanes removed for good;",
    "retirement dates before install dropped:", bad_ret, "\n")

# Segments of the 2020 release that DOT 2026 dropped ----
# some 2020 segments are in neither the current nor the retired rows of the 2026 release (rebuilt
# bridges, the Brooklyn Bridge promenade, greenway pieces). Where their street is not continued by a
# 2026 segment (segment key), the 2020 facility is kept from install up to the 2020 release; no
# record after that.
d20 <- st_read(paste0("/vsizip/", file.path(nyc_data_root(), "raw/street_layout/bike_routes/Archived_nyc_bike_routes_2020.zip/Archived_nyc_bike_routes_2020/nyc_bike_routes_2020.shp")), quiet = TRUE)
d20 <- st_transform(d20, "+init=EPSG:4326")
g20 <- data.table(geometry = st_as_text(st_geometry(d20)), SegmentID = as.integer(d20[["segmentid"]]),
                  moddate = as.IDate(substr(as.character(d20[["moddate"]]), 1, 10)),
                  instdate = as.IDate(substr(as.character(d20[["instdate"]]), 1, 10)),
                  tf = to_class(d20[["tf_facilit"]]), ft = to_class(d20[["ft_facilit"]]))
cutoff <- g20[, max(c(moddate, instdate), na.rm = TRUE)]   # the 2020 release's last recorded change
key <- segment_key_read()
k26 <- segment_key_attach(data.table(SegmentID = unique(v[, seg])), key = key)[!is.na(key_id) & key_cover >= 0.5, unique(key_id)]
dropped <- setdiff(g20[SegmentID != 0, unique(SegmentID)], v[, seg])
kd <- segment_key_attach(data.table(SegmentID = dropped), key = key)[, .(continued = any(key_id %in% k26)), by = SegmentID]
dropped <- kd[continued == FALSE, SegmentID]
s20 <- g20[SegmentID %in% dropped, .(inst = min(fcoalesce(instdate, start_date)), tf = best_of(tf), ft = best_of(ft)), by = SegmentID]
s20 <- s20[inst < cutoff]
w <- rbind(w, s20[, .(SegmentID, date_from = start_date, date_to = inst, tf = NA_character_, ft = NA_character_)],
           s20[, .(SegmentID, date_from = inst, date_to = cutoff, tf, ft)],
           s20[, .(SegmentID, date_from = cutoff, date_to = end_date, tf = NA_character_, ft = NA_character_)])[date_to > date_from]
cat("2020 segments dropped from DOT 2026 and not continued:", nrow(s20), "kept up to", format(cutoff), "\n")

# Manual Street View checks on the 2020 release ----
# rows are matched to segments by geometry in the 2020 shapefile (g20), as when the checks were made
man <- fread("layers/bike_lanes/manual/streetview_dot2020.csv", colClasses = "character")
man <- merge(man[, .(geometry, install_date, modif_date, tf_facilit, ft_facilit, tf_bef_mod, ft_bef_mod)],
             unique(g20[, .(geometry, SegmentID)]), by = "geometry")
man <- unique(man[!is.na(SegmentID) & SegmentID != 0], by = "SegmentID")
man[, `:=`(inst = as.IDate(install_date), modif = as.IDate(fifelse(modif_date == "", NA_character_, modif_date)))]
man[is.na(inst), inst := start_date]
before_mod <- function(bef, after) fifelse(is.na(bef) | bef == "", to_class(after), to_class(bef))
man[, `:=`(tf_a = to_class(tf_facilit), ft_a = to_class(ft_facilit), tf_b = before_mod(tf_bef_mod, tf_facilit), ft_b = before_mod(ft_bef_mod, ft_facilit))]
upgraded <- man[!is.na(modif) & modif > inst]
mw <- rbind(man[, .(SegmentID, date_from = start_date, date_to = inst, tf = NA_character_, ft = NA_character_)],
            upgraded[, .(SegmentID, date_from = inst, date_to = modif, tf = tf_b, ft = ft_b)],
            man[, .(SegmentID, date_from = fifelse(!is.na(modif) & modif > inst, modif, inst), date_to = end_date, tf = tf_a, ft = ft_a)])
mw <- mw[date_to > date_from]
# manual windows up to the cutoff, DOT 2026 after it
mw <- mw[date_from < cutoff][, date_to := pmin(date_to, cutoff)]
cmp <- merge(w[SegmentID %in% man[, SegmentID] & date_from <= cutoff & date_to > cutoff, .(SegmentID, tf26 = tf, ft26 = ft)],
             mw[date_to == cutoff, .(SegmentID, tf_man = tf, ft_man = ft)], by = "SegmentID")
differ <- cmp[(fcoalesce(tf26, "-") != fcoalesce(tf_man, "-")) | (fcoalesce(ft26, "-") != fcoalesce(ft_man, "-")), .N]
dw <- w[SegmentID %in% man[, SegmentID] & date_to > cutoff][, date_from := pmax(date_from, cutoff)]
w <- rbind(w[!SegmentID %in% man[, SegmentID]], mw, dw)
cat("manual checks:", man[, .N], "segments, replacing the DOT history before", format(cutoff), "; the facility at that date differs from",
    "DOT 2026 for", differ, "of", nrow(cmp), "\n")

# Windows ----
w[, `:=`(tf_facilit = lane_types[tf], ft_facilit = lane_types[ft])]
setorder(w, SegmentID, date_from)
# merge consecutive windows with the same facilities
w[, run := rleid(tf_facilit, ft_facilit), by = SegmentID]
w <- w[, .(date_from = min(date_from), date_to = max(date_to)), by = .(SegmentID, run, tf_facilit, ft_facilit)][, run := NULL]
w <- w[date_to > start_date][date_from < start_date, date_from := start_date]
tz <- "America/New_York"
dot_export <- w[, .(SegmentID = as.numeric(SegmentID), time_window = 0L, date_from = as.POSIXct(as.character(date_from), tz = tz),
                    date_to = as.POSIXct(as.character(date_to), tz = tz), tf_facilit, ft_facilit)]
start_ct <- as.POSIXct("1899-01-01", tz = tz)
end_ct <- as.POSIXct("2099-09-09", tz = tz)

# Street View review overrides ----
# segment-level protection dates from manual/04_build_overrides.R; the directions that carry the lane
# are taken from the windows (both if none)
ov <- fread("layers/bike_lanes/manual/protection_overrides.csv", colClasses = c(SegmentID = "numeric"))
ov <- ov[SegmentID %in% dot_export[, SegmentID] | protected_from != "never"]
dirs <- dot_export[SegmentID %in% ov[, SegmentID], .(tf = any(!is.na(tf_facilit)), ft = any(!is.na(ft_facilit))), by = SegmentID]
ov <- merge(ov, dirs, by = "SegmentID", all.x = TRUE)
ov[is.na(tf) | (!tf & !ft), `:=`(tf = TRUE, ft = TRUE)]
windows_for <- function(o) {
  if (o[, protected_from] == "never") {
    x <- dot_export[SegmentID == o[, SegmentID]]
    x[tf_facilit == "Protected", tf_facilit := "Standard"][ft_facilit == "Protected", ft_facilit := "Standard"]
    return(x)
  }
  fac <- function(x, on) if (on) x else NA_character_
  if (o[, protected_from] == "always") {
    return(data.table(SegmentID = o[, SegmentID], time_window = 1L, date_from = start_ct, date_to = end_ct,
                      tf_facilit = fac("Protected", o[, tf]), ft_facilit = fac("Protected", o[, ft])))
  }
  dd <- as.POSIXct(o[, protected_from], tz = tz)
  before <- if (o[, before_class] == "none") NA_character_ else o[, before_class]
  data.table(SegmentID = o[, SegmentID], time_window = 1:2, date_from = c(start_ct, dd), date_to = c(dd, end_ct),
             tf_facilit = c(fac(before, o[, tf]), fac("Protected", o[, tf])), ft_facilit = c(fac(before, o[, ft]), fac("Protected", o[, ft])))
}
dot_ov <- rbindlist(lapply(split(ov, by = "SegmentID"), windows_for))
dot_export <- rbind(dot_export[!SegmentID %in% ov[, SegmentID]], dot_ov)
cat("overrides applied to", uniqueN(dot_ov[, SegmentID]), "segments\n")

# Copies for LION 16d segments missing from the DOT data ----
# the windows of a DOT segment are copied to the LION 16d SegmentID of the same street piece (the
# nyc_res_bikelanes street network); the copy replaces windows the target has of its own
xw <- fread("layers/bike_lanes/manual/segmentid_crosswalk_lion16d.csv")
dot_xw <- dot_export[SegmentID %in% xw[, dot_segmentid]]
dot_xw[, SegmentID := xw[match(dot_xw[, SegmentID], xw[, dot_segmentid]), lion16d_segmentid]]
dot_xw <- unique(dot_xw)
dot_export <- rbind(dot_export[!SegmentID %in% dot_xw[, SegmentID]], dot_xw)

# Checks and output ----
setorder(dot_export, SegmentID, date_from)
overlap <- dot_export[, .(n = sum(shift(date_from, -1) < date_to, na.rm = TRUE)), SegmentID][n > 0]
if (nrow(overlap)) stop(nrow(overlap), " segments with overlapping windows, e.g. ", paste(head(overlap[, SegmentID]), collapse = ", "))
dot_export[, time_window := seq_len(.N), by = SegmentID]
saveRDS(dot_export, file.path(out_dir, "bike_lanes_time_windows.RDS"))
cat("windows:", nrow(dot_export), "for", dot_export[, uniqueN(SegmentID)], "segments\n")
