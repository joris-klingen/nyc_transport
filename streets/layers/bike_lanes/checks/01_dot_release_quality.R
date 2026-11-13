library(data.table)
library(sf)
source("../R/nyc_transport.R")
setwd("C:/Users/admin/Dropbox/1_research/papers_active/nyc_bikelanes")
R <- file.path(nyc_data_root(), "raw/street_layout/bike_routes")

# processed time windows ----
tw <- setDT(bikelane_windows_read())
cat("time windows:", nrow(tw), "rows,", uniqueN(tw[, SegmentID]), "segments\n")
print(tw[, .N, by = time_window])
cat("\nsegments with 3 windows (upgraded): types in window 2 vs 3\n")
up <- dcast(tw[SegmentID %in% tw[time_window == 3, SegmentID]], SegmentID ~ time_window, value.var = "tf_facilit", fun.aggregate = function(x) x[1])
print(up[, .N, by = .(w2 = `2`, w3 = `3`)])

# DOT releases: column names ----
r20 <- st_read(paste0("/vsizip/", file.path(R, "Archived_nyc_bike_routes_2020.zip/Archived_nyc_bike_routes_2020/nyc_bike_routes_2020.shp")), quiet = TRUE)
r25 <- st_read(file.path(R, "New York City Bike Routes_20251008.geojson"), quiet = TRUE)
r26 <- st_read(file.path(R, "New York City Bike Routes_20261010.geojson"), quiet = TRUE)
cat("\n2020 cols:", names(r20), "\n2025 cols:", names(r25), "\n2026 cols:", names(r26), "\n")

prep <- function(x, rel) {
  d <- setDT(st_drop_geometry(x))
  d <- d[as.character(boro) == "1"]
  d[, .(release = rel, segmentid = as.numeric(segmentid), facilitycl = toupper(facilitycl),
        inst = as.Date(substr(as.character(instdate), 1, 10)), mod = if ("moddate" %in% names(d)) as.Date(substr(as.character(d$moddate), 1, 10)) else as.Date(NA))]
}
d <- rbind(prep(r20, "2020"), prep(r25, "2025"), prep(r26, "2026"))
cat("\nManhattan segments per release and class\n")
print(dcast(d[, .N, by = .(release, facilitycl)], facilitycl ~ release, value.var = "N"))

# date quality ----
cat("\nmissing install date / mod before install / install on Jan 1 / install on first of month (protected, class I)\n")
print(d[facilitycl == "I", .(N = .N, na_inst = sum(is.na(inst)), mod_before_inst = sum(mod < inst, na.rm = TRUE),
        jan1 = sum(format(inst, "%m-%d") == "01-01", na.rm = TRUE),
        day1 = sum(format(inst, "%d") == "01", na.rm = TRUE)), by = release])

cat("\nprotected (class I) Manhattan segments by install year, per release\n")
print(dcast(d[facilitycl == "I", .N, by = .(release, yr = year(inst))], yr ~ release, value.var = "N", fill = 0))

# date stability across releases for the same segment ----
w <- dcast(unique(d[facilitycl == "I"], by = c("release", "segmentid")), segmentid ~ release, value.var = "inst")
cat("\nclass I segments present in both 2020 and 2026:", w[!is.na(`2020`) & !is.na(`2026`), .N],
    "| install date changed:", w[!is.na(`2020`) & !is.na(`2026`) & `2020` != `2026`, .N], "\n")
print(w[!is.na(`2020`) & !is.na(`2026`) & `2020` != `2026`, .N, by = .(y2020 = year(`2020`), y2026 = year(`2026`))][order(-N)][1:15])
cat("\nclass I in 2026 not in 2020, by install year:\n")
print(w[is.na(`2020`) & !is.na(`2026`), .N, by = .(yr = year(`2026`))][order(yr)])

# same-date clustering: many segments sharing one install date
cat("\nmost common class I install dates in 2026 release (Manhattan)\n")
print(d[release == "2026" & facilitycl == "I", .N, by = inst][order(-N)][1:12])

# history structure in the new releases ----
h <- setDT(st_drop_geometry(r26))[as.character(boro) == "1"]
h[, `:=`(inst = as.Date(substr(as.character(instdate), 1, 10)), ret = as.Date(substr(as.character(ret_date), 1, 10)))]
print(h[, .N, by = status])
cat("ret_date filled:", h[!is.na(ret), .N], "| prevbikeid filled:", h[!is.na(prevbikeid) & as.character(prevbikeid) != "", .N], "
")
print(h[, .N, by = segmentid][, .N, by = .(records = N)][order(records)])
segs <- h[, .N, by = segmentid][N > 1, segmentid]
for (sg in segs[c(1, 50, 200)]) print(h[segmentid == sg][order(inst), .(segmentid, street, bikeid, prevbikeid, cl = facilitycl, tf_facilit, ft_facilit, inst, ret, status)])
cat("
retired records by retirement year, class of retired record:
")
print(dcast(h[!is.na(ret), .N, by = .(yr = year(ret), facilitycl)], yr ~ facilitycl, value.var = "N", fill = 0))
cat("
upgrades = retired record followed by current record on same segment, class change:
")
cur <- h[status == "Current", .(segmentid, cl_new = facilitycl, inst_new = inst)]
ret <- h[status == "Retired", .(segmentid, cl_old = facilitycl, ret)]
m <- merge(ret, cur, by = "segmentid")
print(m[, .N, by = .(cl_old, cl_new)][order(-N)])
cat("retired date == new install date:", m[ret == inst_new, .N], "of", nrow(m), "
")
