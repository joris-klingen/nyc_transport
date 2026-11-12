# Simulated LION records per release
#
# Real data: data/derived/streets/spine/lion_segment_releases.parquet (spine/01_lion_segments.R),
# 6.7M rows: the attributes of every LION record in each of the 57 releases 12a-26c, no geometry.
# Columns: segment_id, legacy_id, feature_typ, segment_typ, rb_layer, rw_type, status,
# street_code, street, boro, node_from, node_to, x_from, y_from, x_to, y_to (EPSG 2263),
# length_ft, physical_id, generic_id, release, release_date.
#
# Kept: one row per segment version and release it was in (from sim_segment_key()), with the
# attributes of its key segment (street, boro, length) and the rest drawn once per segment, so
# attributes stay the same across releases. Not kept: nodes shared between connected segments;
# end points match the length but not the street grid.
#
# rows <- sim_lion_segment_releases(sim_segment_key(sim_key_segments(500)))

sim_lion_segment_releases <- function(segment_key = sim_segment_key(), keys = NULL, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  rel <- sim_lion_releases()
  v <- unique(segment_key, by = c("segment_id", "version"))
  a <- sim_streets_profile("lion_segment_releases", nrow(v))
  a[, c("segment_id", "release", "release_date", "length_ft") := NULL]
  a[, `:=`(segment_id = v[, segment_id], version = v[, version], length_ft = v[, length_ft],
           first_ri = match(v[, first_release], rel[, release]), last_ri = match(v[, last_release], rel[, release]))]
  if (!is.null(keys)) a[keys, on = c(segment_id = "key_id"), `:=`(street = i.street, street_code = i.street_code, boro = i.boro)]
  # end points: a straight segment of the right length from the start point
  ang <- stats::runif(nrow(a), 0, 2 * pi)
  a[, `:=`(x_to = x_from + cos(ang) * length_ft, y_to = y_from + sin(ang) * length_ft)]
  out <- a[rep(seq_len(.N), last_ri - first_ri + 1L)]
  out[, ri := first_ri + sequence(a[, last_ri - first_ri + 1L]) - 1L]
  out[, `:=`(release = rel[ri, release], release_date = as.Date(rel[ri, release_date]))]
  out[, c("first_ri", "last_ri", "ri", "version") := NULL]
  setcolorder(out, c("segment_id", "legacy_id", "feature_typ", "segment_typ", "rb_layer", "rw_type", "status", "street_code",
                     "street", "boro", "node_from", "node_to", "x_from", "y_from", "x_to", "y_to", "length_ft",
                     "physical_id", "generic_id", "release", "release_date"))
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  k <- sim_key_segments(100, seed = 1)
  x <- sim_lion_segment_releases(sim_segment_key(k), keys = k)
  print(x[, .N, release][order(release)])
}
