# Lineage of LION segment versions and the crosswalk to the current release (the segment key)
#
# For every geometry version that ends before the last release, find the versions in the next
# release that overlap it: each line is buffered by `buf` ft and the length of the other line inside
# the buffer is measured both ways. A link needs an overlap of at least 15 ft and half of either line:
#   share_old  share of the ended version's length that lies on the successor
#   share_new  share of the successor's length that lies on the ended version
# A split gives several links with share_new near 1, a merge several with share_old near 1, a
# re-drawn segment one link with both near 1. Ended versions without such a link are linked from
# LION's own identifiers: the same SegmentID with a redrawn line in the next release (moved up to
# 500 ft), or a later segment within 100 ft that names it as LegacyID (possibly after a gap of
# releases). The links are then chained forward to the last
# release: every version gets the last-release SegmentIDs it continues as, with the share of its
# length that maps to each.
# Writes, in data/derived/streets/spine/:
#   segment_links.parquet  links ended version -> successor version, method overlap / same_id / legacy_id
#   segment_key.parquet    segment_id, version, first/last release -> key_id (SegmentID in the last
#                          release), share (of the version's length), key_cover (of the key segment's
#                          length), lengths, reversed (key segment drawn against the source version:
#                          from-to and to-from attributes swap); key_status current / continued / retired
# and spine/out/link_summary.csv (per release: ended versions, linked, retired).
# Run from repo root: Rscript spine/03_segment_key.R

library(data.table)
library(sf)
library(arrow)

source("../R/nyc_transport.R")
out_dir <- file.path(nyc_streets_data_root(), "spine")
buf <- 10

v <- st_read(file.path(out_dir, "segment_versions.gpkg"), quiet = TRUE)
rels <- unique(rbind(setDT(st_drop_geometry(v))[, .(release = first_release, date = first_date)],
                     setDT(st_drop_geometry(v))[, .(release = last_release, date = last_date)]))[order(date)][, ri := .I]
d <- setDT(st_drop_geometry(v))
d[rels, first_ri := i.ri, on = .(first_release = release)]
d[rels, last_ri := i.ri, on = .(last_release = release)]
d[, `:=`(row = .I, len = as.numeric(st_length(v)))]
n_rel <- nrow(rels)

# Links between consecutive releases ----
links <- rbindlist(lapply(seq_len(n_rel - 1), function(r) {
  ended <- d[last_ri == r]
  if (!nrow(ended)) return(NULL)
  cand <- d[first_ri <= r + 1 & last_ri >= r + 1]
  old <- st_sf(old_row = ended[, row], geometry = st_geometry(v)[ended[, row]])
  new <- st_sf(new_row = cand[, row], geometry = st_geometry(v)[cand[, row]])
  # only candidates near an ended version
  new <- new[lengths(st_intersects(new, st_buffer(old, buf))) > 0, ]
  if (!nrow(new)) return(NULL)
  # length of each new line inside each old buffer, and of each old line inside each new buffer
  overlap <- function(lines, buffers, id_line, id_buf) {
    x <- suppressWarnings(st_intersection(lines, st_buffer(buffers, buf)))
    data.table(a = x[[id_line]], b = x[[id_buf]], len = as.numeric(st_length(x)))[, .(len = sum(len)), by = .(a, b)]
  }
  on <- overlap(new, old, "new_row", "old_row")[, .(new_row = a, old_row = b, ov_new = len)]
  oo <- overlap(old, new, "old_row", "new_row")[, .(old_row = a, new_row = b, ov_old = len)]
  pairs <- merge(on, oo, by = c("old_row", "new_row"), all = TRUE)
  pairs[is.na(ov_new), ov_new := 0][is.na(ov_old), ov_old := 0]
  pairs[d, `:=`(old_len = i.len), on = .(old_row = row)][d, `:=`(new_len = i.len), on = .(new_row = row)]
  pairs[, `:=`(share_old = pmin(ov_old / old_len, 1), share_new = pmin(ov_new / new_len, 1))]
  out <- pairs[pmax(ov_old, ov_new) >= 15 & (share_old >= 0.5 | share_new >= 0.5)]
  message(rels[r + 1, release], ": ", nrow(ended), " ended versions, ", out[, uniqueN(old_row)], " linked")
  out[, .(release = rels[r + 1, release], old_row, new_row, share_old, share_new, method = "overlap")]
}))

# Links from LION's own identifiers, for ended versions without an overlap link ----
max_vertex_dist <- function(a, b) mapply(function(i, j) max(as.numeric(st_distance(st_cast(st_geometry(v)[i], "POINT"), st_geometry(v)[j]))), a, b)
unlinked <- d[last_ri < n_rel & !row %in% links[, old_row]]
# same SegmentID continuing with a redrawn line in the next release (unless moved > 500 ft: a reused id)
same <- unlinked[, .(old_row = row, segment_id, version, last_ri)][
  d[, .(segment_id, version = version - 1L, new_row = row, first_ri)], on = .(segment_id, version), nomatch = 0][first_ri == last_ri + 1]
same[, moved := max_vertex_dist(old_row, new_row)]
same <- same[moved <= 500]
# LegacyID: a later segment that names the ended one as its legacy id, within 100 ft, possibly after a gap
lion <- setDT(read_parquet(file.path(out_dir, "lion_segment_releases.parquet"), col_select = c("segment_id", "legacy_id")))
leg <- unique(lion[!is.na(legacy_id) & legacy_id != segment_id, .(old_id = legacy_id, new_id = segment_id)])
leg <- merge(leg, unlinked[!row %in% same[, old_row], .(old_id = segment_id, old_row = row, last_ri)], by = "old_id")
leg <- merge(leg, d[, .SD[1], by = segment_id][, .(new_id = segment_id, new_row = row, first_ri)], by = "new_id")[first_ri > last_ri]
leg <- leg[as.numeric(st_distance(st_geometry(v)[old_row], st_geometry(v)[new_row], by_element = TRUE)) <= 100]
links <- rbind(links,
               same[, .(release = rels[first_ri, release], old_row, new_row, share_old = 1, share_new = 1, method = "same_id")],
               leg[, .(release = rels[first_ri, release], old_row, new_row, share_old = 1, share_new = 1, method = "legacy_id")])
message("links: ", paste(links[, .N, by = method][, paste(method, N)], collapse = ", "))
links[d, `:=`(old_id = i.segment_id, old_version = i.version), on = .(old_row = row)]
links[d, `:=`(new_id = i.segment_id, new_version = i.version), on = .(new_row = row)]

# Chain to the last release ----
# key for versions alive in the last release: themselves; then backwards by last release
key <- d[last_ri == n_rel, .(row, key_id = segment_id, share = 1)]
for (r in rev(seq_len(n_rel - 1))) {
  l <- links[old_row %in% d[last_ri == r, row]]
  if (!nrow(l)) next
  # share of the old version carried by each successor, normalized to the overlap found
  l[, w := share_old / pmax(sum(share_old), 1), by = old_row]
  k <- merge(l[, .(old_row, new_row, w)], key, by.x = "new_row", by.y = "row", allow.cartesian = TRUE)
  k <- k[, .(share = sum(w * share)), by = .(row = old_row, key_id)]
  key <- rbind(key, k)
}
key <- merge(d[, .(row, segment_id, version, first_release, last_release, first_date, last_date, length_ft = len)], key, by = "row", all.x = TRUE)
key[, key_status := fcase(last_release == rels[n_rel, release] & key_id == segment_id, "current",
                          !is.na(key_id), "continued", default = "retired")]
# share of the key segment's length that this version covers, for attaching old attributes to key segments
key[d[last_ri == n_rel, .(key_id = segment_id, key_length_ft = len)], key_length_ft := i.key_length_ft, on = "key_id"]
key[, key_cover := pmin(share * length_ft / key_length_ft, 1)]
# digitizing direction: reversed when the key segment runs against the source version (from -> to),
# so that from-to / to-from attributes (bike lane direction, traffic direction) swap
xy <- as.data.table(st_coordinates(v))
fid <- names(xy)[ncol(xy)]                       # last L column indexes the feature
ends <- xy[, .(x0 = X[1], y0 = Y[1], x1 = X[.N], y1 = Y[.N]), by = fid]
setnames(ends, fid, "row")
ends[, `:=`(dx = x1 - x0, dy = y1 - y0)]
key[ends, `:=`(dx = i.dx, dy = i.dy), on = "row"]
key[d[last_ri == n_rel, .(key_id = segment_id, krow = row)], krow := i.krow, on = "key_id"]
key[ends, `:=`(kdx = i.dx, kdy = i.dy), on = .(krow = row)]
key[, reversed := !is.na(key_id) & (dx * kdx + dy * kdy) < 0]
key[, c("row", "krow", "dx", "dy", "kdx", "kdy") := NULL]
setorder(key, segment_id, version, -share)

write_parquet(links[, .(release, old_id, old_version, new_id, new_version, share_old, share_new, method)], file.path(out_dir, "segment_links.parquet"))
write_parquet(key, file.path(out_dir, "segment_key.parquet"))

summ <- d[last_ri < n_rel, .(ended = .N, linked = sum(row %in% links[, old_row])), by = .(release = last_release)]
summ[, retired := ended - linked]
dir.create("spine/out", showWarnings = FALSE)
fwrite(summ, "spine/out/link_summary.csv")
print(summ[, lapply(.SD, sum), .SDcols = c("ended", "linked", "retired")])
print(unique(key, by = c("segment_id", "version"))[, .N, by = key_status])
print(key[key_status == "continued", .(rows = .N, reversed = sum(reversed))])
