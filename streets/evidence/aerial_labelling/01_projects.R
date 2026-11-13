# Direct aerial labelling: define protected-lane projects on north-south streets in the study zones
#
# Universe: north-south (NB/SB) street segments in the nyc_res_bikelanes study zones that become
# protected between 2010-01 and 2025-08 in the fixed pipeline or in the DOT 2026 history.
# Projects: same street, same claimed protection month, contiguous (gap < 300 m along the street).
# Writes projects.csv (location only, for blind labelling) and project_claims.csv (dates).
# Run from repo root: Rscript evidence/aerial_labelling/01_projects.R

library(data.table)
library(sf)

bl_root <- "../../papers_active/nyc_res_bikelanes"
source("../R/nyc_transport.R")
nyc_data <- nyc_data_root()
out <- "evidence/aerial_labelling/out"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

# study street segments: north-south, inside zones ----
st <- setDT(st_drop_geometry(readRDS(file.path(bl_root, "data/intermediate/streets/streets_manhattan_with_bikelanes.RDS"))))
st <- unique(st[!is.na(zone) & grepl("NB|SB", TrafDir_WD),
                .(SegmentID, Street, StreetCode, corridor, lat_start, lon_start, lat_end, lon_end, MidP_lat, MidP_lon, SegmentLength)],
             by = "SegmentID")

# protection dates: fixed pipeline and DOT 2026 history ----
tw <- setDT(bikelane_windows_read())
pipe <- tw[tf_facilit == "Protected" | ft_facilit == "Protected", .(prot_pipe = as.Date(min(date_from))), by = SegmentID]

r26 <- setDT(st_drop_geometry(st_read(file.path(nyc_data, "raw/street_layout/bike_routes/New York City Bike Routes_20261010.geojson"), quiet = TRUE)))
r26 <- r26[as.character(boro) == "1", .(SegmentID = as.numeric(segmentid), cl = toupper(facilitycl), inst = as.Date(substr(as.character(instdate), 1, 10)))]
dot <- r26[cl == "I", .(prot_dot = min(inst)), by = SegmentID]

d <- merge(merge(st, pipe, by = "SegmentID", all.x = TRUE), dot, by = "SegmentID", all.x = TRUE)
in_window <- function(x) !is.na(x) & x >= as.Date("2010-01-01") & x <= as.Date("2025-08-31")
d <- d[in_window(prot_pipe) | in_window(prot_dot)]
d[, claim := fifelse(in_window(prot_dot), prot_dot, prot_pipe)]   # date used to group into projects
d[, claim_month := format(claim, "%Y-%m")]
cat("segments:", nrow(d), "| streets:", uniqueN(d$Street), "\n")

# projects: contiguous runs along the street within street x claim month ----
d <- d[order(Street, claim_month, MidP_lat)]
d[, gap_m := c(Inf, diff(MidP_lat) * 111000), by = .(Street, claim_month)]
d[, run := cumsum(gap_m > 300), by = .(Street, claim_month)]
d[, project := .GRP, by = .(Street, claim_month, run)]

proj <- d[, {
  i <- which.min(abs(MidP_lat - median(MidP_lat)))           # middle segment
  dx <- (lon_end[i] - lon_start[i]) * cos(lat_start[i] * pi / 180); dy <- lat_end[i] - lat_start[i]
  .(street = Street[1], corridor = corridor[1], n_segments = .N, length_m = round(sum(SegmentLength, na.rm = TRUE) * 0.3048),
    lon = MidP_lon[i], lat = MidP_lat[i], bearing = (atan2(dx, dy) * 180 / pi) %% 360,
    claim = min(claim), prot_pipe = min(prot_pipe), prot_dot = min(prot_dot),
    sources_agree = all(!is.na(prot_pipe) & !is.na(prot_dot) & abs(as.numeric(prot_pipe - prot_dot)) <= 31))
}, by = project]
proj[, proj_id := sprintf("M%03d", .I)]
cat("projects:", nrow(proj), "| sources agree:", proj[sources_agree == TRUE, .N], "\n")
print(proj[, .N, by = .(yr = year(claim))][order(yr)])

fwrite(proj[, .(proj_id, lon, lat, bearing)], file.path(out, "projects.csv"))
fwrite(proj[, .(proj_id, street, corridor, n_segments, length_m, claim, prot_pipe, prot_dot, sources_agree)], file.path(out, "project_claims.csv"))
fwrite(d[, .(SegmentID, project, Street, claim, prot_pipe, prot_dot)], file.path(out, "project_segments.csv"))
