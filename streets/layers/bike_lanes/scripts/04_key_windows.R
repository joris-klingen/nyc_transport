# Bike lane time windows on the segment key
#
# The windows from 03_time_windows.R are on the SegmentIDs of the DOT 2020 release (plus copies to
# LION 16d ids). Attaches the segment key: one row per window and 26c key segment; a segment that
# was later split gives every piece its windows, segments that were merged give the key segment one
# set of windows per source (weight by key_cover, or keep main_source, the source covering most of
# the key segment). Where the key segment is drawn the other way,
# tf_facilit and ft_facilit are swapped. Retired segments (no key segment) are dropped and counted.
# Writes data/derived/streets/bike_lanes/bike_lanes_windows_keyed.parquet, read with
# bikelane_windows_keyed_read(). The unkeyed windows (bike_lanes_time_windows.RDS) stay as they are.
# Run from repo root: Rscript layers/bike_lanes/scripts/04_key_windows.R

library(data.table)
library(arrow)

source("R/streets.R")

tw <- setDT(bikelane_windows_read())
tw[, `:=`(date_from = as.IDate(date_from), date_to = as.IDate(date_to))]
kw <- segment_key_attach(tw, "SegmentID")
kw[reversed == TRUE, c("tf_facilit", "ft_facilit") := .(ft_facilit, tf_facilit)]

ids <- unique(kw[, .(SegmentID, key_status)])
cat("source segments:", tw[, uniqueN(SegmentID)], "| by key status:",
    paste(ids[, .N, by = key_status][, paste(key_status, N)], collapse = ", "), "\n")
cat("rows on a reversed key segment:", kw[reversed == TRUE, .N], "\n")
kw <- kw[!is.na(key_id)]

out <- kw[, .(key_id, SegmentID, time_window, date_from, date_to, tf_facilit, ft_facilit, share, key_cover, reversed, key_status)]
# main_source: the source segment covering most of the key segment (ties: the key segment's own id)
src <- unique(out[, .(key_id, SegmentID, key_cover)])[order(key_id, -key_cover, SegmentID != key_id)]
out[src[!duplicated(key_id)], main_source := TRUE, on = .(key_id, SegmentID)][is.na(main_source), main_source := FALSE]
setorder(out, key_id, SegmentID, time_window)
write_parquet(out, streets_dir("bike_lanes", "bike_lanes_windows_keyed.parquet"))

# key segments fed by more than one source: do the sources disagree at some date?
multi <- out[, .(n_src = uniqueN(SegmentID)), by = key_id][n_src > 1]
cat("key segments:", out[, uniqueN(key_id)], "| with more than one source segment:", nrow(multi), "\n")
chk <- out[key_id %in% multi[, key_id]]
dates <- as.IDate(c("2014-01-01", "2018-01-01", "2022-01-01"))
conf <- rbindlist(lapply(dates, function(dt) chk[date_from <= dt & date_to > dt,
  .(differ = uniqueN(paste(tf_facilit, ft_facilit)) > 1), by = key_id][, .(date = dt, differ = sum(differ), n = .N)]))
print(conf)
