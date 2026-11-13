library(data.table)
library(sf)
source("../R/nyc_transport.R")
S <- "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Dropbox-1-research-5-NYC-bikelanes/229146a7-b4e1-44e3-bc9b-8e236e87a233/scratchpad"
setwd("C:/Users/admin/Dropbox/1_research/papers_active/nyc_bikelanes")

m <- fread(file.path(S, "manual_sheets/dot_2020.csv"), colClasses = "character")
setnames(m, "street...2", "street")

# match to 2020 DOT segments on geometry text, as 002 does ----
dot.sf <- st_read(paste0("/vsizip/", file.path(nyc_data_root(), "raw/street_layout/bike_routes/Archived_nyc_bike_routes_2020.zip/Archived_nyc_bike_routes_2020/nyc_bike_routes_2020.shp")), quiet = TRUE)
dot.sf <- st_transform(dot.sf, "+init=EPSG:4326")
g <- data.table(segmentid = as.numeric(dot.sf$segmentid), boro = dot.sf$boro, geometry = st_as_text(st_geometry(dot.sf)))
mm <- merge(m, unique(g, by = "geometry"), by = "geometry", all.x = TRUE)
cat("manual rows:", nrow(m), "| matched to a 2020 segment:", mm[!is.na(segmentid), .N], "| Manhattan:", mm[boro == 1, .N], "\n")

# effective before type: blank = same class (rules tab) ----
mm[, tf_before := fifelse(tf_bef_mod == "", tf_facilit, tf_bef_mod)]
mm[, ft_before := fifelse(ft_bef_mod == "", ft_facilit, ft_bef_mod)]
mm[, real_change := modified == "1" & (tf_before != tf_facilit | ft_before != ft_facilit)]
cat("\nmanual rows marked modified:", mm[modified == "1", .N], "| with a different type before vs after:", mm[real_change == TRUE, .N], "\n")
print(mm[real_change == TRUE & boro == 1, .N, by = .(tf_before, tf_facilit, ft_before, ft_facilit)][order(-N)][1:15])

# the 149 segments the pipeline dates too early ----
cmp <- fread(file.path(S, "date_comparison.csv"))
bug <- cmp[cat == "differ > 1 year" & prot_pipe < prot_dot]
b <- merge(bug, mm[, .(SegmentID = segmentid, street, install_date, modif_date, modified, tf_before, tf_facilit, ft_before, ft_facilit)], by = "SegmentID", all.x = TRUE)
cat("\nbug segments:", nrow(bug), "| in manual sheet:", b[!is.na(street), .N], "\n")
cat("manual before-type for bug segments:\n")
print(b[!is.na(street), .N, by = .(tf_before, tf_facilit, ft_before, ft_facilit)][order(-N)])
cat("\nby street:\n")
print(b[!is.na(street), .(N = .N, inst = paste(unique(substr(install_date, 1, 4)), collapse = ","), modif = paste(unique(substr(modif_date, 1, 4)), collapse = ","),
                          before = paste(unique(c(tf_before, ft_before)), collapse = "/")), by = street][order(-N)])
fwrite(mm, file.path(S, "manual_with_segmentid.csv"))
