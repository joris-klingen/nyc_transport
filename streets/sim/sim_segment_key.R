# Simulated segment key
#
# Real data: data/derived/streets/spine/segment_key.parquet, read with segment_key_read() and used by
# segment_key_map() and segment_key_attach(). One row per LION SegmentID x geometry version x key
# segment (256,309 rows): segment_id, version (1 = first geometry of that id since 12a),
# first_release / last_release ("12a" ... "26c") with first_date / last_date, length_ft, key_id
# (the 26c SegmentID it continues as; NA when retired), share (of the version's length on key_id),
# key_status (current: still in 26c; continued: replaced, split, merged or redrawn; retired),
# key_length_ft, key_cover (of the key segment's length), reversed (drawn the other way).
#
# Kept: every key segment has its current version (segment_id = key_id, last release 26c); about
# 14% also have older versions, under the same id (redrawn) or another id (split or merged into
# it); about 1% of rows are retired segments without a key. Releases and dates follow the real
# release list. Not kept: lengths of split pieces adding up exactly.
#
# keys <- sim_key_segments(2000); sk <- sim_segment_key(keys)

sim_segment_key <- function(keys = sim_key_segments(), seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  rel <- sim_lion_releases()
  nr <- nrow(rel)
  n <- nrow(keys)
  # current versions: first release mostly 12a, some streets added later
  first <- ifelse(stats::runif(n) < 0.8, 1L, sample.int(nr, n, replace = TRUE))
  cur <- data.table(segment_id = keys[, key_id], first_ri = first, last_ri = nr, length_ft = keys[, length_ft],
                    key_id = keys[, key_id], share = 1, key_status = "current", key_length_ft = keys[, length_ft],
                    key_cover = 1, reversed = stats::runif(n) < 0.02)
  # older versions of some keys: redrawn under the same id, or another id merged or split into it
  old_keys <- which(stats::runif(n) < 0.14 & first > 1L)
  old <- cur[old_keys]
  same <- stats::runif(nrow(old)) < 0.5
  old[, `:=`(last_ri = first_ri - 1L, first_ri = pmax(1L, first_ri - sample.int(12L, .N, replace = TRUE)),
             key_status = "continued", reversed = FALSE)]
  old[!same, `:=`(segment_id = 400000L + seq_len(.N), share = round(stats::runif(.N, 0.3, 1), 3),
                  key_cover = round(stats::runif(.N, 0.3, 1), 3))]
  old[, length_ft := key_length_ft * key_cover / share]
  old <- old[first_ri <= last_ri]
  # retired segments: no key
  nret <- max(1L, round(0.012 * n))
  ret <- data.table(segment_id = 500000L + seq_len(nret), first_ri = 1L, last_ri = sample.int(nr - 1L, nret, replace = TRUE),
                    length_ft = sample(keys[, length_ft], nret, replace = TRUE), key_id = NA_integer_, share = NA_real_,
                    key_status = "retired", key_length_ft = NA_real_, key_cover = NA_real_, reversed = FALSE)
  out <- rbindlist(list(cur, old, ret))
  setorder(out, segment_id, first_ri)
  out[, version := seq_len(.N), by = segment_id]
  out[, `:=`(first_release = rel[first_ri, release], last_release = rel[last_ri, release],
             first_date = as.Date(rel[first_ri, release_date]), last_date = as.Date(rel[last_ri, release_date]))]
  out[, c("first_ri", "last_ri") := NULL]
  setcolorder(out, c("segment_id", "version", "first_release", "last_release", "first_date", "last_date", "length_ft",
                     "key_id", "share", "key_status", "key_length_ft", "key_cover", "reversed"))
  out[]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  sk <- sim_segment_key(sim_key_segments(200, seed = 1))
  print(sk[, .N, key_status])
  print(head(sk[key_status == "continued"]))
}
