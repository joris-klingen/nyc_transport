# Citywide segment x release panel of lane counts from quarterly LION releases
#
# Reads every LION release in data/raw/street_layout/lion (nyc_lion12a.zip ... nyclion_26c.zip),
# attributes only, and stacks: release, release_date (latest file date inside the zip),
# SegmentID, SegmentTyp, borough, street, roadway type, traffic direction, travel / parking /
# total lanes, street width. Writes data/derived/streets/travel_lanes/lion_lanes_panel.parquet and
# a per-release change summary lanes/out/release_changes.csv.
# Run from repo root: Rscript layers/travel_lanes/01_lion_panel.R

library(data.table)
library(sf)
library(arrow)

source("../R/nyc_transport.R")
root <- nyc_data_root()
lion_dir <- file.path(root, "raw/street_layout/lion")
out_dir <- file.path(nyc_streets_data_root(), "travel_lanes")
tmp <- "C:/code/lion_tmp"          # unzip outside Dropbox
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create("layers/travel_lanes/out", showWarnings = FALSE, recursive = TRUE)

want <- c("SegmentID", "SegmentTyp", "LBoro", "RBoro", "Street", "FeatureTyp", "RW_TYPE", "TrafDir",
          "Number_Travel_Lanes", "Number_Park_Lanes", "Number_Total_Lanes", "StreetWidth_Min", "StreetWidth_Max",
          "BikeLane", "Status")

# Releases on disk ----
zips <- list.files(lion_dir, pattern = "^nyc_?lion_?\\d\\d[a-d]\\.zip$", full.names = TRUE)
rel <- data.table(zip = zips, release = sub(".*lion_?(\\d\\d[a-d])\\.zip$", "\\1", basename(zips)))
rel <- rel[order(release)][!duplicated(release)]
rel[, release_date := sapply(zip, function(z) { l <- unzip(z, list = TRUE); as.character(as.Date(max(l$Date[grepl("gdbtable$", l$Name)]))) })]
print(rel[, .(release, release_date)])

read_release <- function(z) {
  unlink(tmp, recursive = TRUE); dir.create(tmp)
  unzip(z, exdir = tmp)
  gdb <- list.dirs(tmp, recursive = TRUE)
  gdb <- gdb[grepl("lion\\.gdb$", gdb)][1]
  probe <- st_read(gdb, query = "SELECT * FROM lion WHERE OBJECTID = 1", quiet = TRUE)
  cols <- intersect(want, names(probe))
  x <- setDT(st_drop_geometry(st_read(gdb, query = sprintf("SELECT %s FROM lion", paste(cols, collapse = ", ")), quiet = TRUE)))
  for (c in setdiff(want, cols)) x[, (c) := NA]
  x[, SegmentID := as.integer(SegmentID)]
  x[, boro := fifelse(!is.na(as.integer(LBoro)) & as.integer(LBoro) %in% 1:5, as.integer(LBoro), as.integer(RBoro))]
  x[, .(SegmentID, SegmentTyp = trimws(as.character(SegmentTyp)), boro, Street = trimws(Street),
        FeatureTyp = trimws(as.character(FeatureTyp)), RW_TYPE = trimws(as.character(RW_TYPE)), TrafDir = trimws(as.character(TrafDir)),
        trav = suppressWarnings(as.numeric(Number_Travel_Lanes)), park = suppressWarnings(as.numeric(Number_Park_Lanes)),
        tot = suppressWarnings(as.numeric(Number_Total_Lanes)),
        width_min = suppressWarnings(as.numeric(StreetWidth_Min)), width_max = suppressWarnings(as.numeric(StreetWidth_Max)),
        bikelane = trimws(as.character(BikeLane)))]
}

# Stack releases ----
panel <- rbindlist(lapply(seq_len(nrow(rel)), function(i) {
  x <- read_release(rel$zip[i])
  x[, `:=`(release = rel$release[i], release_date = as.IDate(rel$release_date[i]))]
  message(rel$release[i], ": ", nrow(x), " records")
  x
}))
unlink(tmp, recursive = TRUE)

# streets only (roadway type 1), one record per segment and release: prefer the generic
# centreline record over roadbed pieces when both exist
panel <- panel[RW_TYPE == "1"]
panel[, typ_rank := fcase(SegmentTyp %in% c("U", "B"), 1L, SegmentTyp == "G", 2L, default = 3L)]
setorder(panel, release, SegmentID, typ_rank)
panel <- panel[!duplicated(panel[, .(release, SegmentID)])][, typ_rank := NULL]
write_parquet(panel, file.path(out_dir, "lion_lanes_panel.parquet"))
message("panel: ", nrow(panel), " rows, ", uniqueN(panel$SegmentID), " segments, ", uniqueN(panel$release), " releases")

# Change summary: travel lanes changed vs the previous release, by borough ----
setorder(panel, SegmentID, release)
panel[, prev_trav := shift(trav), by = SegmentID]
chg <- panel[!is.na(prev_trav) & !is.na(trav), .(segments = .N, changed = sum(trav != prev_trav)), by = .(release, release_date, boro)]
chg <- dcast(chg, release + release_date ~ boro, value.var = "changed", fill = 0)
setnames(chg, as.character(1:5), c("manhattan", "bronx", "brooklyn", "queens", "staten_island"), skip_absent = TRUE)
fwrite(chg, "layers/travel_lanes/out/release_changes.csv")
print(chg)
