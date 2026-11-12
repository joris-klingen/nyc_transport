# Aerial imagery pilot: select 30 Manhattan test segments with a reliable answer
#
# Writes pilot_segments.csv (id, location, street bearing; no dates) and
# pilot_truth.csv (the answers), kept separate so classification can be done blind.
# Run from repo root: Rscript evidence/pilot_aerial/01_select_sample.R

library(data.table)
library(sf)
sf_use_s2(TRUE)

bl_root <- "../nyc_res_bikelanes"
source("../R/nyc_transport.R")
nyc_data <- nyc_data_root()
set.seed(20261010)

# manual checks with segment ids (geometry match, as in 002) ----
man <- fread("layers/bike_lanes/manual/streetview_dot2020.csv", colClasses = "character")
man <- man[, !duplicated(names(man)), with = FALSE]
dot <- st_read(paste0("/vsizip/", file.path(nyc_data, "raw/street_layout/bike_routes/Archived_nyc_bike_routes_2020.zip/Archived_nyc_bike_routes_2020/nyc_bike_routes_2020.shp")), quiet = TRUE)
dot <- st_transform(dot, 4326)
g <- data.table(SegmentID = as.numeric(dot$segmentid), boro = as.character(dot$boro), geometry = st_as_text(st_geometry(dot)))
man <- merge(man, unique(g, by = "geometry"), by = "geometry")[boro == "1"]

# fixed pipeline time windows and DOT 2026 history ----
tw <- setDT(bikelane_windows_read())
tw[, `:=`(date_from = as.Date(date_from), date_to = as.Date(date_to))]
prot_pipe <- tw[tf_facilit == "Protected" | ft_facilit == "Protected", .(prot_pipe = min(date_from)), by = SegmentID]

r26 <- setDT(st_drop_geometry(st_read(file.path(nyc_data, "raw/street_layout/bike_routes/New York City Bike Routes_20261010.geojson"), quiet = TRUE)))
r26 <- r26[as.character(boro) == "1", .(SegmentID = as.numeric(segmentid), cl = toupper(facilitycl), inst = as.Date(substr(as.character(instdate), 1, 10)))]
prot_dot <- r26[cl == "I", .(prot_dot = min(inst)), by = SegmentID]

# geometry: midpoint, bearing, length ----
# all Manhattan segments of the 2020 release (controls need not be in the manual sheet)
geo <- dot[as.character(dot$boro) == "1", c("segmentid", "street")]
names(geo)[1:2] <- c("SegmentID", "street")
geo$SegmentID <- as.numeric(geo$SegmentID)
geo <- geo[!duplicated(geo$SegmentID) & !st_is_empty(geo), ]
geo$len_m <- as.numeric(st_length(geo))
# first part of each multilinestring, midpoint along the line in NY state plane (feet)
first_line <- st_sfc(lapply(st_geometry(geo), function(m) st_linestring(st_coordinates(m)[st_coordinates(m)[, "L2"] == 1, 1:2])), crs = 4326)
mid <- st_coordinates(st_transform(st_line_sample(st_transform(first_line, 2263), sample = 0.5), 4326))
xy <- lapply(first_line, function(l) { c <- st_coordinates(l); c[c(1, nrow(c)), 1:2] })
bearing <- sapply(xy, function(c) {
  dx <- (c[2, 1] - c[1, 1]) * cos(c[1, 2] * pi / 180); dy <- c[2, 2] - c[1, 2]
  (atan2(dx, dy) * 180 / pi) %% 360
})
geo <- data.table(SegmentID = geo$SegmentID, street = geo$street, len_m = geo$len_m, lon = mid[, 1], lat = mid[, 2], bearing = bearing)

d <- Reduce(function(a, b) merge(a, b, by = "SegmentID", all.x = TRUE), list(geo, prot_pipe, prot_dot))
d <- d[len_m > 60]
d[, in_manual := SegmentID %in% man[, SegmentID]]

# groups ----
# A: became protected 2012-07 .. 2022-06, pipeline and DOT agree within a month, Street View checked
A <- d[in_manual == TRUE & prot_pipe >= as.Date("2012-07-01") & prot_pipe <= as.Date("2022-06-30") & abs(as.numeric(prot_pipe - prot_dot)) <= 31]
# B: protected before 2008 in both sources
B <- d[prot_pipe < as.Date("2008-01-01") & prot_dot < as.Date("2008-01-01")]
# C: conventional (Standard) for the whole 2008-2024 window, never protected
conv <- tw[date_from <= as.Date("2008-01-01") & date_to >= as.Date("2025-01-01") & (tf_facilit == "Standard" | ft_facilit == "Standard"), unique(SegmentID)]
ever_protected <- prot_pipe[, SegmentID]
C <- d[SegmentID %in% conv & !SegmentID %in% ever_protected]

one_per_street <- function(x, n) { x <- x[sample(.N)][!duplicated(street)]; x[seq_len(min(n, nrow(x)))] }
smp <- rbind(cbind(one_per_street(A, 14), group = "A"), cbind(one_per_street(B, 8), group = "B"), cbind(one_per_street(C, 8), group = "C"))
cat("selected:", nrow(smp), "| per group:", paste(smp[, .N, by = group][, paste(group, N)], collapse = ", "), "\n")
cat("available: A", nrow(A), "B", nrow(B), "C", nrow(C), "\n")

smp <- smp[sample(.N)]
smp[, pilot_id := sprintf("P%02d", .I)]

dir.create("evidence/pilot_aerial/out", showWarnings = FALSE)
fwrite(smp[, .(pilot_id, lon, lat, bearing)], "evidence/pilot_aerial/out/pilot_segments.csv")
fwrite(smp[, .(pilot_id, SegmentID, street, group, prot_pipe, prot_dot, len_m)], "evidence/pilot_aerial/out/pilot_truth.csv")
