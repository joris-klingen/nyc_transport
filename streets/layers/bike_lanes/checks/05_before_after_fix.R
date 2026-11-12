library(data.table)
setwd("C:/Users/admin/Dropbox/1_research/nyc_res_bikelanes")
cat("new file modified:", format(file.mtime("data/archive/normalized_moved_20261013/bike_lanes_time_windows.RDS")), "\n")
old <- setDT(readRDS("data/archive/normalized_pre_fix_20261010/bike_lanes_time_windows.RDS"))
new <- setDT(readRDS("data/archive/normalized_moved_20261013/bike_lanes_time_windows.RDS"))
cat("rows old/new:", nrow(old), nrow(new), "| segments:", uniqueN(old$SegmentID), uniqueN(new$SegmentID), "\n")

cat("\nupgraded segments: type in window 2 -> window 3 (new)\n")
up <- dcast(new[SegmentID %in% new[time_window == 3, SegmentID]], SegmentID ~ time_window, value.var = "tf_facilit", fun.aggregate = function(x) x[1])
print(up[, .N, by = .(w2 = `2`, w3 = `3`)][order(-N)])

prot <- function(d) d[tf_facilit == "Protected" | ft_facilit == "Protected", .(prot_from = as.Date(min(date_from))), by = SegmentID]
p <- merge(prot(old), prot(new), by = "SegmentID", all = TRUE, suffixes = c("_old", "_new"))
cat("\nsegments whose first protected date changed:", p[!(prot_from_old %in% prot_from_new) | is.na(prot_from_old) != is.na(prot_from_new), .N], "\n")
print(p[prot_from_old != prot_from_new | is.na(prot_from_old) != is.na(prot_from_new),
        .N, by = .(old = year(prot_from_old), new = year(prot_from_new))][order(-N)][1:15])

# against DOT 2026 history, as before
S <- "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Dropbox-1-research-5-NYC-bikelanes/229146a7-b4e1-44e3-bc9b-8e236e87a233/scratchpad"
cmp <- fread(file.path(S, "date_comparison.csv"))[, .(SegmentID, prot_dot)]
x <- merge(p, cmp, by = "SegmentID")
x <- x[(prot_from_new >= as.Date("2012-07-01") & prot_from_new <= as.Date("2025-08-31")) | (prot_dot >= as.Date("2012-07-01") & prot_dot <= as.Date("2025-08-31")) |
       (prot_from_old >= as.Date("2012-07-01") & prot_from_old <= as.Date("2025-08-31"))]
agree <- function(a, b) fcase(is.na(a) | is.na(b), "only one source", abs(as.numeric(a - b)) <= 31, "agree (1 month)", abs(as.numeric(a - b)) <= 365, "1-12 months", default = "> 1 year")
cat("\nagreement with DOT 2026 history, study period segments (old vs new pipeline):\n")
print(merge(x[, .N, by = .(cat = agree(prot_from_old, as.Date(prot_dot)))], x[, .N, by = .(cat = agree(prot_from_new, as.Date(prot_dot)))], by = "cat", suffixes = c("_old", "_new")))
