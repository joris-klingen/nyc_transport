# Car-free dates for the Central Park drive projects (decision 2026-10-11: park drives count as
# protected from the date they became fully car-free)
#
#   north of 72nd St: permanently car-free from 2015-06-29 (Mayor's Office press release 416-15, 18 June 2015)
#   rest of the loop: car-free from 2018-06-27 (Central Park Conservancy; announcement 20 April 2018)
#
# A project is north when its segment midpoints lie north of the 72nd Street line across the
# park (Central Park West & W 72 St to Fifth Avenue & E 72 St). Writes manual/park_drive_dates.csv.
# Run from repo root: Rscript layers/bike_lanes/manual/03_park_drive_dates.R

library(data.table)
library(sf)

chk <- fread("evidence/aerial_labelling/out/review_checklist.csv")
park <- chk[category == "park_drive_definition", .(proj_id, street)]
seg <- fread("evidence/aerial_labelling/out/project_segments.csv")[, proj_id := sprintf("M%03d", project)]
st <- setDT(st_drop_geometry(readRDS("../nyc_res_bikelanes/data/intermediate/streets/streets_manhattan_with_bikelanes.RDS")))
st <- unique(st[, .(SegmentID, MidP_lat, MidP_lon)], by = "SegmentID")

# 72nd St across the park: CPW & W 72 St to Fifth Av & E 72 St
a <- c(lon = -73.9767, lat = 40.7766); b <- c(lon = -73.9670, lat = 40.7720)
north_of_72 <- function(lon, lat) ((b["lon"] - a["lon"]) * (lat - a["lat"]) - (b["lat"] - a["lat"]) * (lon - a["lon"])) > 0

p <- merge(merge(park, seg[, .(proj_id, SegmentID)], by = "proj_id"), st, by = "SegmentID")
p[, north := north_of_72(MidP_lon, MidP_lat)]
out <- p[, .(street = street[1], segments = .N, share_north = round(mean(north), 2)), by = proj_id]
out[, carfree_from := fifelse(share_north >= 0.5, "2015-06", "2018-06")]
out[, source := fifelse(carfree_from == "2015-06",
                        "Car-free north of 72nd St from 2015-06-29 (NYC Mayor's Office, 18 June 2015)",
                        "Rest of the loop car-free from 2018-06-27 (Central Park Conservancy)")]
print(out)
fwrite(out, "layers/bike_lanes/manual/park_drive_dates.csv")
