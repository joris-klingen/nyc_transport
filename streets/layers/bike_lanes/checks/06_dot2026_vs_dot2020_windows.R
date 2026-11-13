# The bike lane windows from the DOT 2026 version history against the earlier build (DOT 2020 release
# plus the Manhattan 2025 updates), compared on the segment key (the two builds use the SegmentIDs of
# different LION releases): best facility over both directions per key segment and month
#
# - key segments with a facility in each build, by borough
# - monthly 2012-07 to 2025-08 in Manhattan (the nyc_bikelanes study period): key segment-months
#   whose facility differs, by kind of difference, and the key segments whose first protected month moves
# Run from repo root: Rscript layers/bike_lanes/checks/06_dot2026_vs_dot2020_windows.R

library(data.table)

source("R/streets.R")
key <- segment_key_read()
ks <- key_segments_read()
rank_fac <- c("Protected", "Standard", "Sharrows", "none")

keyed <- function(version) {
  w <- setDT(bikelane_windows_read(version))
  w[, `:=`(date_from = as.IDate(date_from), date_to = as.IDate(date_to))]
  w[, fac := rank_fac[pmin(match(fcoalesce(tf_facilit, "none"), rank_fac), match(fcoalesce(ft_facilit, "none"), rank_fac))]]
  k <- segment_key_attach(w, "SegmentID", key = key)[!is.na(key_id) & key_cover >= 0.5]
  k[, .(key_id, date_from, date_to, fac)]
}
new <- keyed("dot2026")
old <- keyed("dot2020")

cat("key segments with a facility at some time, by borough:\n")
kb <- rbind(new[fac != "none", .(key_id, build = "dot2026")], old[fac != "none", .(key_id, build = "dot2020")])[, unique(.SD)]
print(dcast(merge(kb, ks[, .(key_id, boro)], by = "key_id")[, .N, by = .(boro, build)], boro ~ build, value.var = "N"))

months <- as.IDate(seq(as.Date("2012-07-01"), as.Date("2025-08-01"), by = "month"))
state <- function(w) {
  x <- w[data.table(month = months), on = .(date_from <= month, date_to > month), .(key_id, month = i.month, fac), allow.cartesian = TRUE, nomatch = 0]
  x[, .(fac = rank_fac[min(match(fac, rank_fac))]), by = .(key_id, month)]
}
man <- ks[boro == 1, key_id]
cmp <- merge(state(new[key_id %in% man]), state(old[key_id %in% man]), by = c("key_id", "month"), all = TRUE, suffixes = c("_new", "_old"))
cmp[, `:=`(fac_new = fcoalesce(fac_new, "none"), fac_old = fcoalesce(fac_old, "none"))]
cmp <- cmp[!(fac_new == "none" & fac_old == "none")]
cat("Manhattan key segment-months with a facility in either build, 2012-07 to 2025-08:", nrow(cmp), "| differ:", cmp[fac_new != fac_old, .N],
    sprintf("(%.1f%%)", 100 * cmp[, mean(fac_new != fac_old)]), "\n")
print(dcast(cmp[fac_new != fac_old, .N, by = .(fac_old, fac_new)], fac_old ~ fac_new, value.var = "N", fill = 0))
fp <- function(x) x[fac == "Protected", .(first = min(month)), by = key_id]
p <- merge(fp(cmp[, .(key_id, month, fac = fac_new)]), fp(cmp[, .(key_id, month, fac = fac_old)]), by = "key_id", all = TRUE, suffixes = c("_new", "_old"))
p[, shift_months := round(as.numeric(first_new - first_old) / 30.4)]
cat("Manhattan key segments protected in the study period: new", p[!is.na(first_new), .N], "| old", p[!is.na(first_old), .N],
    "| same first month", p[shift_months == 0, .N], "| moved", p[shift_months != 0, .N], "| only new", p[is.na(first_old), .N],
    "| only old", p[is.na(first_new), .N], "\n")
print(p[shift_months != 0, .N, by = .(shift = cut(shift_months, c(-Inf, -24, -6, -1, 0, 6, 24, Inf)))][order(shift)])
