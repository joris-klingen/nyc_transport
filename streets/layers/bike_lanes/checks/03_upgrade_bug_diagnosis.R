library(data.table)
library(sf)
source("../R/nyc_transport.R")
setwd("C:/Users/admin/Dropbox/1_research/papers_active/nyc_bikelanes")
S <- "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Dropbox-1-research-5-NYC-bikelanes/229146a7-b4e1-44e3-bc9b-8e236e87a233/scratchpad"
mm <- fread(file.path(S, "date_comparison.csv"))
tw <- setDT(bikelane_windows_read())
tw[, n_win := .N, by = SegmentID]
w3 <- tw[time_window == 3, .(SegmentID, modif = as.Date(date_from))]

d <- mm[cat == "differ > 1 year" & prot_pipe < prot_dot]
cat("pipeline earlier than DOT by > 1 year:", nrow(d), "segments\n")
d <- merge(d, w3, by = "SegmentID", all.x = TRUE)
cat("  of which have an upgrade window in pipeline:", d[!is.na(modif), .N], "\n")
cat("  and the pipeline's upgrade date is within 31 days of the DOT protection date:", d[!is.na(modif) & abs(as.numeric(modif - as.IDate(prot_dot))) <= 31, .N], "\n")

# streets involved
r26 <- setDT(st_drop_geometry(st_read(file.path(nyc_data_root(), "raw/street_layout/bike_routes/New York City Bike Routes_20261010.geojson"), quiet = TRUE)))
r26[, SegmentID := as.numeric(segmentid)]
st <- unique(r26[, .(SegmentID, street)], by = "SegmentID")
cat("\nstreets where pipeline dates protection > 1 year too early:\n")
print(merge(d, st, by = "SegmentID")[, .(N = .N, pipe = paste(unique(year(prot_pipe)), collapse = ","), dot = paste(unique(year(prot_dot)), collapse = ",")), by = street][order(-N)][1:15])
cat("\nstreets protected only in pipeline (study period):\n")
print(merge(mm[cat == "protected only in pipeline"], st, by = "SegmentID", all.x = TRUE)[, .(N = .N, yrs = paste(sort(unique(year(prot_pipe))), collapse = ",")), by = street][order(-N)][1:12])
