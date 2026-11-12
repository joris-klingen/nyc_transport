# Stack the identifying attributes of every LION record over the quarterly releases
#
# Reads the attribute table (no geometry) of each release in data/raw/street_layout/lion through
# /vsizip, all feature types: SegmentID, LegacyID, feature and segment type, roadbed layer, roadway
# type, street code, from/to nodes and coordinates, length, physical and generic ids.
# Writes data/derived/streets/spine/lion_segment_releases.parquet (one row per record
# and release) and spine/out/release_counts.csv.
# Run from repo root: Rscript spine/01_lion_segments.R

library(data.table)
library(sf)
library(arrow)

source("../R/nyc_transport.R")
out_dir <- file.path(nyc_streets_data_root(), "spine")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create("spine/out", showWarnings = FALSE)

cols <- c("SegmentID", "LegacyID", "FeatureTyp", "SegmentTyp", "RB_Layer", "RW_TYPE", "Status", "StreetCode", "Street",
          "LBoro", "RBoro", "NodeIDFrom", "NodeIDTo", "XFrom", "YFrom", "XTo", "YTo", "SHAPE_Length", "PhysicalID", "GenericID")

rel <- lion_releases()
print(rel[, .(release, release_date)])

read_release <- function(file) {
  gdb <- lion_gdb(file)
  x <- setDT(st_drop_geometry(st_read(gdb, quiet = TRUE, query = sprintf("SELECT %s FROM lion", paste(cols, collapse = ", ")))))
  int <- function(v) suppressWarnings(as.integer(trimws(as.character(v))))
  chr <- function(v) trimws(as.character(v))
  x[, .(segment_id = int(SegmentID), legacy_id = int(LegacyID), feature_typ = chr(FeatureTyp), segment_typ = chr(SegmentTyp),
        rb_layer = chr(RB_Layer), rw_type = chr(RW_TYPE), status = chr(Status), street_code = chr(StreetCode), street = chr(Street),
        boro = fifelse(int(LBoro) %in% 1:5, int(LBoro), int(RBoro)),
        node_from = int(NodeIDFrom), node_to = int(NodeIDTo),
        x_from = as.numeric(XFrom), y_from = as.numeric(YFrom), x_to = as.numeric(XTo), y_to = as.numeric(YTo),
        length_ft = as.numeric(SHAPE_Length), physical_id = int(PhysicalID), generic_id = int(GenericID))]
}

segs <- rbindlist(lapply(seq_len(nrow(rel)), function(i) {
  t0 <- Sys.time()
  x <- read_release(rel[i, file])
  x[, `:=`(release = rel[i, release], release_date = as.IDate(rel[i, release_date]))]
  message(rel[i, release], ": ", nrow(x), " records, ", round(as.numeric(Sys.time() - t0, units = "secs")), " s")
  x
}))
write_parquet(segs, file.path(out_dir, "lion_segment_releases.parquet"))

counts <- segs[, .(records = .N, segment_ids = uniqueN(segment_id), streets = sum(feature_typ %in% c("0", "6", "A", "C")),
                   legacy_id_set = sum(!is.na(legacy_id) & legacy_id != segment_id)), by = .(release, release_date)]
fwrite(counts, "spine/out/release_counts.csv")
print(counts)
