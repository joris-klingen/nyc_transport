# Review material for the projects in out/review_list.csv
#
# Writes
#   out/review_segment_lines.csv  segment end points (for drawing the street on the photo sheets)
#   out/review_checklist.csv      one row per project: claims, aerial window, three Street View
#                                 links along the project, and empty columns for the checker
# Run from repo root: Rscript evidence/aerial_labelling/04_review_material.R

library(data.table)
library(sf)

rev <- fread("evidence/aerial_labelling/out/review_list.csv")
pts <- fread("evidence/aerial_labelling/out/projects.csv")
seg <- fread("evidence/aerial_labelling/out/project_segments.csv")
seg[, proj_id := sprintf("M%03d", project)]

st <- setDT(st_drop_geometry(readRDS("../nyc_res_bikelanes/data/intermediate/streets/streets_manhattan_with_bikelanes.RDS")))
st <- unique(st[, .(SegmentID, lat_start, lon_start, lat_end, lon_end, MidP_lat, MidP_lon)], by = "SegmentID")

lines <- merge(seg[proj_id %in% rev[, proj_id], .(proj_id, SegmentID)], st, by = "SegmentID")
fwrite(lines[order(proj_id, MidP_lat)], "evidence/aerial_labelling/out/review_segment_lines.csv")

# Street View links at 25 / 50 / 75 % along each project, looking along the street ----
sv_link <- function(lat, lon, heading) {
  sprintf("https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%.6f,%.6f&heading=%.0f&pitch=-10&fov=90", lat, lon, heading)
}
views <- lines[order(MidP_lat), {
  i <- unique(pmax(1L, round(c(0.25, 0.5, 0.75) * .N)))
  .(view = seq_along(i), lat = MidP_lat[i], lon = MidP_lon[i])
}, by = proj_id]
views <- merge(views, pts[, .(proj_id, bearing)], by = "proj_id")
views[, link := sv_link(lat, lon, bearing)]
links <- dcast(views, proj_id ~ paste0("streetview_", view), value.var = "link")

chk <- merge(rev, links, by = "proj_id")
chk[, `:=`(checked_by = "", checked_on = "", protected_from = "", before_type = "", confidence = "", checker_note = "")]
setcolorder(chk, c("priority", "category", "proj_id", "street", "n_segments", "prot_pipe", "prot_dot", "aerial_window"))
fwrite(chk[order(priority, category, -n_segments)], "evidence/aerial_labelling/out/review_checklist.csv")
cat("checklist:", nrow(chk), "projects;", nrow(lines), "segments\n")
