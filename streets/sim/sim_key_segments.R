# Simulated key segments
#
# Real data: data/derived/streets/spells/key_segments.parquet, read with key_segments_read(). One row
# per key segment, the street segments the history is keyed on: the LION SegmentIDs of the last
# release (26c), 180,800 rows. Columns: key_id, length_ft, boro (1 Manhattan, 2 Bronx, 3 Brooklyn,
# 4 Queens, 5 Staten Island), street, street_code (borough + 5-digit street code), rw_type (1
# street, 2 highway, 3 bridge, ...), feature_typ, rb_layer. See profiles/key_segments.csv.
#
# Kept: types and value shares; key_id unique; one street_code per street name.
# Not kept: geography (streets are not where their borough is), lengths per street type.
#
# keys <- sim_key_segments(2000, boro = 1)

sim_key_segments <- function(n = 2000, seed = NULL, boro = NULL) {
  k <- sim_streets_profile("key_segments", n, seed)
  k[, key_id := sort(sample.int(330000L, n))]
  b <- boro
  if (!is.null(b)) k[, boro := as.integer(rep_len(b, .N))]
  k[, street_code := street_code[1], by = street]
  setcolorder(k, "key_id")
  setkey(k, key_id)
  k[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(sim_key_segments(10, seed = 1))
}
