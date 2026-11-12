# Simulated links between segment versions
#
# Real data: data/derived/streets/spine/segment_links.parquet (spine/03_segment_key.R, 66,903 rows).
# One row per link from a version in one release to a version in the next: release (of the new
# version), old_id, old_version, new_id, new_version, share_old (of the old version's length),
# share_new, method (overlap 96%, same_id 3%, legacy_id). Chained to 26c they give the key.
#
# Kept: one link per continued version of sim_segment_key(), pointing at the key segment's
# version that followed it, with the method implied by the ids. Not kept: links between two
# retired versions, many-to-many splits.
#
# sk <- sim_segment_key(); links <- sim_segment_links(sk)

sim_segment_links <- function(segment_key = sim_segment_key()) {
  sk <- segment_key[key_status != "retired"]
  old <- sk[key_status == "continued"]
  nxt <- sk[key_status == "current", .(key_id, new_id = segment_id, new_version = version, release = first_release)]
  out <- nxt[old, on = "key_id", nomatch = 0]
  out[, .(release, old_id = segment_id, old_version = version, new_id, new_version,
          share_old = share, share_new = key_cover,
          method = fifelse(segment_id == new_id, "same_id", "overlap"))][]
}

if (sys.nframe() == 0) {
  source("sim/sim.R")
  print(head(sim_segment_links(sim_segment_key(sim_key_segments(500, seed = 1)))))
}
