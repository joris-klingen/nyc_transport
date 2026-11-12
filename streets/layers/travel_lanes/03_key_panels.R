# Travel-lane panels on the segment key
#
# lion_lanes_panel (segment x release) carries the SegmentIDs of each release; the version in force
# in that release is mapped to its 26c key segments. manhattan_lanes_monthly (segment x month) uses
# the latest version of each id. Each key segment takes its values from the source segment that
# covers most of it (key_cover); n_sources counts the sources, cover_total sums their cover.
# TrafDir W (with) and A (against) swap where the key segment is drawn the other way.
# Writes, in data/derived/streets/travel_lanes/: lion_lanes_panel_keyed.parquet
# (key_id x release) and manhattan_lanes_monthly_keyed.parquet (key_id x month). The unkeyed
# panels stay as they are.
# Run from repo root: Rscript layers/travel_lanes/03_key_panels.R

library(data.table)
library(arrow)

source("R/streets.R")
key <- segment_key_read()

dominant <- function(x, by) {
  x <- x[!is.na(key_id)]
  x[, `:=`(n_sources = .N, cover_total = pmin(sum(key_cover), 1)), by = by]
  setorderv(x, c(by, "key_cover"), c(rep(1, length(by)), -1))
  x[!duplicated(x[, ..by])]
}

# LION release panel ----
p <- setDT(read_parquet(streets_dir("travel_lanes", "lion_lanes_panel.parquet")))
pk <- segment_key_attach(p, "SegmentID", release_col = "release", key = key)
cat("panel rows:", nrow(p), "| attached:", nrow(pk), "| without key segment:", pk[is.na(key_id), .N], "\n")
pk[reversed == TRUE & TrafDir %in% c("W", "A"), TrafDir := fifelse(TrafDir == "W", "A", "W")]
pk <- dominant(pk, c("release", "key_id"))
setnames(pk, "SegmentID", "source_id")
setcolorder(pk, c("key_id", "release", "release_date", "source_id", "key_cover", "n_sources", "cover_total"))
pk[, c("share", "reversed", "key_status") := NULL]
write_parquet(pk, streets_dir("travel_lanes", "lion_lanes_panel_keyed.parquet"))
cat("keyed panel:", nrow(pk), "rows,", pk[, uniqueN(key_id)], "key segments; rows from several sources:", pk[n_sources > 1, .N], "\n")

# Manhattan monthly panel ----
m <- setDT(read_parquet(streets_dir("travel_lanes", "manhattan_lanes_monthly.parquet")))
mk <- segment_key_attach(m, "SegmentID", key = key)
cat("monthly rows:", nrow(m), "| without key segment:", mk[is.na(key_id), .N], "\n")
# the monthly panel has every id ever seen for every month, so a retired id and its successor both
# claim the street: keep the sources whose id was in LION in that month (first release up to the
# release after its last), unless none was
span <- key[, .(first_date = min(first_date), last_date = max(last_date)), by = .(SegmentID = segment_id)]
rel_dates <- sort(unique(c(key[, first_date], key[, last_date])))
span[, until := rel_dates[pmin(match(last_date, rel_dates) + 1L, length(rel_dates))]]
span[last_date == max(rel_dates), until := as.IDate("2099-12-31")]
mk[span, `:=`(alive_from = i.first_date, alive_until = i.until), on = "SegmentID"]
mk[, alive := month >= alive_from - 31 & month < alive_until]
mk <- mk[!is.na(key_id)][, keep := alive | !any(alive), by = .(key_id, month)][keep == TRUE]
mk[, c("alive_from", "alive_until", "alive", "keep") := NULL]
dis <- mk[, .(n = .N, lanes_differ = uniqueN(lanes) > 1), by = .(key_id, month)][n > 1]
mk <- dominant(mk, c("key_id", "month"))
setnames(mk, "SegmentID", "source_id")
mk <- mk[, .(key_id, month, lanes, lanes_flag, source_id, key_cover, n_sources, cover_total)]
write_parquet(mk, streets_dir("travel_lanes", "manhattan_lanes_monthly_keyed.parquet"))
cat("keyed monthly:", nrow(mk), "rows,", mk[, uniqueN(key_id)], "key segments; rows from several sources:", nrow(dis),
    "| of which the sources differ in lanes:", dis[lanes_differ == TRUE, .N], "\n")
