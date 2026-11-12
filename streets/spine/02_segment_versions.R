# Segment versions: one row per LION SegmentID and distinct geometry, over the quarterly releases
#
# Reads the street features (FeatureTyp 0, 6, A, C, W; every roadbed layer) of each release with
# geometry, linearized, in EPSG 2263. A geometry counts as the same version when its coordinates
# rounded to 0.1 ft are identical. Writes data/derived/streets/spine/segment_versions.gpkg
# (layer segment_versions): segment_id, version, first and last release (and dates), geometry.
# Run from repo root: Rscript spine/02_segment_versions.R [n_releases]   (n: first n releases, for testing)

library(data.table)
library(sf)

source("../R/nyc_transport.R")
out_dir <- file.path(nyc_streets_data_root(), "spine")
street_types <- c("0", "6", "A", "C", "W")

rel <- lion_releases()
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1) rel <- rel[seq_len(as.integer(args[1]))]

# reading the older releases inside the zip (/vsizip) takes minutes, unzipped seconds
tmp <- "C:/code/lion_tmp"

read_geom <- function(file) {
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  unzip(file, exdir = tmp)
  gdb <- list.dirs(tmp)[grepl("\\.gdb$", list.dirs(tmp))][1]
  q <- sprintf("SELECT SegmentID, SHAPE FROM lion WHERE FeatureTyp IN (%s)", paste0("'", street_types, "'", collapse = ","))
  x <- st_zm(st_read(gdb, quiet = TRUE, type = 5, query = q))
  unlink(tmp, recursive = TRUE)
  x <- x[!st_is_empty(x), ]
  x$segment_id <- as.integer(trimws(as.character(x$SegmentID)))
  x <- x[!duplicated(x$segment_id), ]
  g <- st_geometry(x)
  sig <- vapply(g, function(l) digest::digest(round(unclass(l)[[1]] * 10)), character(1))
  data.table(segment_id = x$segment_id, sig = sig, wkb = lapply(st_as_binary(g), as.raw))
}

versions <- NULL   # open and closed versions
open <- NULL       # versions present in the previous release
for (i in seq_len(nrow(rel))) {
  t0 <- Sys.time()
  cur <- read_geom(rel[i, file])
  cur[, `:=`(release = rel[i, release], release_date = as.IDate(rel[i, release_date]))]
  if (is.null(open)) {
    new <- cur
  } else {
    same <- merge(open[, .(segment_id, sig, vid)], cur[, .(segment_id, sig)], by = c("segment_id", "sig"))
    versions[vid %in% same[, vid], `:=`(last_release = rel[i, release], last_date = as.IDate(rel[i, release_date]))]
    new <- cur[!same, on = c("segment_id", "sig")]
  }
  if (nrow(new)) {
    start <- if (is.null(versions)) 0L else nrow(versions)
    new <- new[, .(vid = start + seq_len(.N), segment_id, sig, wkb, first_release = release, first_date = release_date,
                   last_release = release, last_date = release_date)]
    versions <- rbind(versions, new)
  }
  open <- versions[last_release == rel[i, release], .(segment_id, sig, vid)]
  message(rel[i, release], ": ", nrow(cur), " segments, ", nrow(new), " new versions, ", round(as.numeric(Sys.time() - t0, units = "secs")), " s")
}

versions[, version := seq_len(.N), by = segment_id]
setcolorder(versions, c("segment_id", "version", "first_release", "last_release", "first_date", "last_date"))
versions[, `:=`(vid = NULL, sig = NULL)]
geom <- st_as_sfc(structure(versions[, wkb], class = "WKB"), crs = 2263)
versions <- st_sf(versions[, !"wkb"], geometry = geom)
out <- file.path(out_dir, if (length(args)) "segment_versions_test.gpkg" else "segment_versions.gpkg")
st_write(versions, out, layer = "segment_versions", delete_dsn = TRUE, quiet = TRUE)
v <- setDT(st_drop_geometry(versions))
message("versions: ", nrow(v), " for ", v[, uniqueN(segment_id)], " segment ids; ", v[version > 1, uniqueN(segment_id)],
        " ids with more than one geometry")
