# Street spells: every layer as spells on the segment key, one table
#
# Schema (one row per spell):
#   key_id          SegmentID in the last LION release (spine/03_segment_key.R)
#   attribute       see streets_attributes() in R/streets.R
#   side            both / tf / ft (direction relative to the key segment's digitizing direction)
#   value           character; numeric attributes are converted by the readers
#   valid_from      first day of the spell (1900-01-01 with date_precision "open": since before the records)
#   valid_to        first day after the spell; NA = still valid
#   date_precision  of valid_from: day / month / year (DOT dates on the 1st of the month or 1 January),
#                   release (changed between two quarterly LION releases), verified (Street View or
#                   aerial review), undated (placeholder date, see the layer), open
#   source          layer output the spell comes from; priority: lower wins where sources overlap
#   source_id       SegmentID in the source; key_cover: share of the key segment it covers
# Sources:
#   in_lion         segment versions mapped to the key (key_cover >= 0.5): when the street exists in LION
#   bike_lane       layers/bike_lanes (keyed windows, main source per key segment)
#   travel_lanes, parking_lanes, total_lanes, street_width, traffic_dir
#                   LION release panel (layers/travel_lanes, keyed); travel_lanes also from the dated
#                   Manhattan monthly panel, which takes priority
# Writes data/derived/streets/spells/street_spells.parquet and key_segments.parquet
# (key_id, borough, street, street code, roadway and feature type, roadbed layer, length).
# Run from repo root: Rscript build/01_street_spells.R

library(data.table)
library(arrow)

source("R/streets.R")
out_dir <- streets_dir("spells")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
open_start <- as.IDate("1900-01-01")

key <- segment_key_read()
key[, `:=`(first_date = as.IDate(first_date), last_date = as.IDate(last_date))]
rel <- unique(rbind(key[, .(release = first_release, date = first_date)], key[, .(release = last_release, date = last_date)]))
rel <- unique(rel[order(date)], by = "release")[, ri := .I]
next_release_date <- function(d) rel[, date][pmin(match(d, rel[, date]) + 1L, nrow(rel))]
final_date <- rel[.N, date]
far <- as.IDate("2100-01-01")

# run-length spells over an ordered sequence of observations of one key segment and attribute
to_spells <- function(x, by, value_col, start_col, end_col) {
  setorderv(x, c(by, start_col))
  x[, run := rleid(get(value_col), cumsum(c(TRUE, head(get(end_col), -1) != tail(get(start_col), -1)))), by = by]
  x[, .(value = get(value_col)[1], valid_from = get(start_col)[1], valid_to = get(end_col)[.N], source_id = source_id[1],
        key_cover = key_cover[1]), by = c(by, "run")][, run := NULL][]
}

# Key segments ----
lion26 <- setDT(read_parquet(streets_dir("spine", "lion_segment_releases.parquet"),
                             col_select = c("segment_id", "release", "boro", "street", "street_code", "rw_type", "feature_typ", "rb_layer")))
lion26 <- unique(lion26[release == rel[.N, release]], by = "segment_id")
ks <- unique(key[key_status == "current", .(key_id, length_ft = key_length_ft)])
ks <- merge(ks, lion26[, .(key_id = segment_id, boro, street, street_code, rw_type, feature_typ, rb_layer)], by = "key_id", all.x = TRUE)
write_parquet(ks, file.path(out_dir, "key_segments.parquet"))

# In LION ----
il <- key[!is.na(key_id), .(key_id, source_id = segment_id, key_cover, from = first_date,
                            to = fifelse(last_date == final_date, far, next_release_date(last_date)))]
il <- il[il[, .I[key_cover >= 0.5 | key_cover == max(key_cover)], by = key_id][, V1]]
setorder(il, key_id, from)
il[, grp := cumsum(from > shift(cummax(as.integer(to)), fill = 0L)), by = key_id]
il <- il[, .(value = "1", valid_from = min(from), valid_to = as.IDate(max(as.integer(to))), source_id = source_id[which.max(key_cover)],
             key_cover = max(key_cover)), by = .(key_id, grp)][, grp := NULL]
il[valid_to >= far, valid_to := NA]
il[, `:=`(attribute = "in_lion", side = "both", date_precision = "release", source = "lion", priority = 1L)]
# in the first release: the street existed before the records (keeps earlier bike lanes in panels)
il[valid_from == rel[1, date], `:=`(valid_from = open_start, date_precision = "open")]

# Bike lanes ----
w <- bikelane_windows_keyed_read()[main_source == TRUE]
ov <- fread("layers/bike_lanes/manual/protection_overrides.csv", colClasses = "character")[grepl("^\\d{4}-\\d{2}", protected_from)]
ov[, `:=`(SegmentID = as.numeric(SegmentID), ym = substr(protected_from, 1, 7))]
bl <- rbind(w[, .(key_id, side = "tf", value = tf_facilit, valid_from = date_from, valid_to = date_to, source_id = as.integer(SegmentID), key_cover)],
            w[, .(key_id, side = "ft", value = ft_facilit, valid_from = date_from, valid_to = date_to, source_id = as.integer(SegmentID), key_cover)])
bl[is.na(value), value := "none"]
bl <- to_spells(bl, c("key_id", "side"), "value", "valid_from", "valid_to")
bl <- bl[valid_to > open_start]                      # windows that ended before 1900 (old bridge dates)
bl[valid_from <= open_start, valid_from := open_start]
bl[valid_to >= as.IDate("2099-01-01"), valid_to := NA]
bl[, date_precision := fcase(valid_from == open_start, "open", mday(valid_from) == 1 & month(valid_from) == 1, "year",
                             mday(valid_from) == 1, "month", default = "day")]
bl[ov, on = .(source_id = SegmentID), ov_ym := i.ym]
bl[value == "Protected" & !is.na(ov_ym) & format(valid_from, "%Y-%m") == ov_ym, date_precision := "verified"][, ov_ym := NULL]
bl[, `:=`(attribute = "bike_lane", source = "bike_lanes", priority = 1L)]

# LION release panel ----
p <- setDT(read_parquet(streets_dir("travel_lanes", "lion_lanes_panel_keyed.parquet")))
p[rel, ri := i.ri, on = "release"]
rd <- rel[, date]
p[, `:=`(from = rd[ri], to = fifelse(ri == length(rd), far, rd[pmin(ri + 1L, length(rd))]))]
lion_attr <- c(travel_lanes = "trav", parking_lanes = "park", total_lanes = "tot", street_width = "width_min", traffic_dir = "TrafDir")
ln <- rbindlist(lapply(names(lion_attr), function(a) {
  x <- p[, .(key_id, value = as.character(get(lion_attr[[a]])), from, to, source_id, key_cover)][!is.na(value) & value != ""]
  x <- to_spells(x, "key_id", "value", "from", "to")
  x[, attribute := a]
}))
ln[valid_to >= far, valid_to := NA]
ln[, `:=`(side = "both", date_precision = "release", source = "lion", priority = 2L)]

# Manhattan dated travel lanes ----
m <- setDT(read_parquet(streets_dir("travel_lanes", "manhattan_lanes_monthly_keyed.parquet")))
m_end <- m[, max(month)]
um <- sort(unique(m[, month]))
m[data.table(month = um, to = as.IDate(seq(um[1], by = "month", length.out = length(um) + 1)[-1])), to := i.to, on = "month"]
m[, from := month]
m[, value := paste(lanes, lanes_flag, sep = "|")]
ml <- to_spells(m[!is.na(lanes)], "key_id", "value", "from", "to")
ml[, c("value", "flag") := tstrsplit(value, "|", fixed = TRUE)]
ml[is.na(flag), flag := ""]
ml[valid_to > m_end, valid_to := NA]
ml[, `:=`(attribute = "travel_lanes", side = "both", date_precision = fifelse(flag == "undated", "undated", "month"),
          source = "manhattan_lane_panel", priority = 1L)][, flag := NULL]

# Combine ----
cols <- c("key_id", "attribute", "side", "value", "valid_from", "valid_to", "date_precision", "source", "priority", "source_id", "key_cover")
sp <- rbindlist(list(il[, ..cols], bl[, ..cols], ln[, ..cols], ml[, ..cols]))
setorder(sp, key_id, attribute, side, source, valid_from)
bad <- sp[!is.na(valid_to) & valid_to <= valid_from]
if (nrow(bad)) { print(bad[, .N, by = .(attribute, source)]); print(head(bad)); stop(nrow(bad), " spells end before they start") }
write_parquet(sp, file.path(out_dir, "street_spells.parquet"))

print(sp[, .(spells = .N, key_segments = uniqueN(key_id), from = min(valid_from[date_precision != "open"]), open_ended = sum(is.na(valid_to))),
         by = .(attribute, source)])
print(dcast(sp[, .N, by = .(attribute, date_precision)], attribute ~ date_precision, value.var = "N", fill = 0))
