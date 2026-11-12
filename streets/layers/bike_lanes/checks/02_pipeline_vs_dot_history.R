library(data.table)
library(sf)
setwd("C:/Users/admin/Dropbox/1_research/nyc_res_bikelanes")
source("../R/nyc_transport.R")
R <- file.path(nyc_data_root(), "raw/street_layout/bike_routes")

# pipeline: first date a segment is protected (any direction) ----
tw <- setDT(bikelane_windows_read())
pipe <- tw[tf_facilit == "Protected" | ft_facilit == "Protected", .(prot_pipe = as.Date(min(date_from))), by = SegmentID]

# overlapping windows within a segment (would double count)
tw[, n_win := .N, by = SegmentID]
ov <- tw[order(SegmentID, date_from)][, .(overlap = any(head(date_to, -1) > tail(date_from, -1))), by = SegmentID][overlap == TRUE]
cat("segments with overlapping time windows in pipeline output:", nrow(ov), "\n")

# DOT 2026 history: first install date of a class I record ----
h <- setDT(st_drop_geometry(st_read(file.path(R, "New York City Bike Routes_20261010.geojson"), quiet = TRUE)))
h <- h[as.character(boro) == "1"]
h[, `:=`(SegmentID = as.numeric(segmentid), inst = as.Date(substr(as.character(instdate), 1, 10)))]
dot <- h[toupper(facilitycl) == "I", .(prot_dot = min(inst)), by = SegmentID]

# study-relevant segments: those in the panel's street selection ----
streets <- readRDS("data/intermediate/streets/streets_manhattan_with_bikelanes.RDS")
seg_study <- unique(as.numeric(st_drop_geometry(streets)$SegmentID))
cat("segments in study street network:", length(seg_study), "\n")

m <- merge(pipe, dot, by = "SegmentID", all = TRUE)
m <- m[SegmentID %in% seg_study]
m[, prot_pipe_eff := fifelse(prot_pipe < as.Date("1900-01-02"), as.Date(NA), prot_pipe)]  # 1899 = no lane
m[, cat := fcase(
  is.na(prot_pipe) & !is.na(prot_dot), "protected only in DOT 2026",
  !is.na(prot_pipe) & is.na(prot_dot), "protected only in pipeline",
  abs(as.numeric(prot_pipe - prot_dot)) <= 31, "agree (within 1 month)",
  abs(as.numeric(prot_pipe - prot_dot)) <= 365, "differ 1-12 months",
  default = "differ > 1 year")]

cat("\nall study segments that are protected in either source:\n")
print(m[, .N, by = cat][order(-N)])

cat("\nrestricted to protection dates in the study period (either source 2012-07..2025-08):\n")
mm <- m[(prot_pipe >= as.Date("2012-07-01") & prot_pipe <= as.Date("2025-08-31")) |
        (prot_dot  >= as.Date("2012-07-01") & prot_dot  <= as.Date("2025-08-31"))]
print(mm[, .N, by = cat][order(-N)])

cat("\nlargest disagreements (study period):\n")
mm[, diff_days := as.numeric(prot_pipe - prot_dot)]
print(mm[cat == "differ > 1 year"][order(-abs(diff_days))][1:20])
cat("\nby year pair (pipeline year vs DOT year), study period disagreements > 1 month:\n")
print(mm[!cat %in% c("agree (within 1 month)")][, .N, by = .(y_pipe = year(prot_pipe), y_dot = year(prot_dot))][order(-N)][1:20])
fwrite(mm, "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Dropbox-1-research-5-NYC-bikelanes/229146a7-b4e1-44e3-bc9b-8e236e87a233/scratchpad/date_comparison.csv")
