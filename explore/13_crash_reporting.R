# Diagnose the collapse of property-damage-only (PDO) crash reports ----
# NYPD stopped responding to PDO crashes on Staten Island from 2019-03-18 (pilot) and citywide
# from 2020-04-06; drivers now file an MV-104 with the DMV. This script dates the break by
# borough and precinct, checks revisions across snapshots, compares the composition of PDO crashes
# before and after, and benchmarks NYPD counts against the DMV crash cases (2021-2024).
# Run from the repo root: Rscript explore/13_crash_reporting.R
suppressMessages({ library(data.table); library(sf) })
source("R/nyc_transport.R")
out <- "output/explore/crash_reporting"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
sink(file.path(out, "crash_reporting.txt"), split = TRUE)

# Crashes with a borough from their precinct ----
cols <- c("CRASH DATE", "CRASH TIME", "BOROUGH", "LATITUDE", "LONGITUDE", "ON STREET NAME", "CROSS STREET NAME",
          "OFF STREET NAME", "NUMBER OF PERSONS INJURED", "NUMBER OF PERSONS KILLED",
          "CONTRIBUTING FACTOR VEHICLE 1", "VEHICLE TYPE CODE 1", "VEHICLE TYPE CODE 2", "COLLISION_ID")
cr <- crashes_read(select = cols)
cr[, `:=`(ym = as.IDate(format(crash_date, "%Y-%m-01")), year = year(crash_date),
          injury = number_of_persons_injured + number_of_persons_killed > 0)]
cr[is.na(injury), injury := FALSE]

pc <- boundaries_read("precincts")
pc <- pc[, "precinct"]
xy <- cr[!is.na(latitude), .(collision_id, longitude, latitude)]
pts <- st_transform(st_as_sf(xy, coords = c("longitude", "latitude"), crs = 4326), st_crs(pc))
xy[, precinct := as.integer(pc[["precinct"]][as.integer(st_intersects(pts, pc, sparse = TRUE) |> vapply(function(i) if (length(i)) i[1] else NA_integer_, integer(1)))])]
cr[xy, precinct := i.precinct, on = "collision_id"]
pboro <- function(p) fcase(p < 40, "Manhattan", p < 60, "Bronx", p < 100, "Brooklyn", p < 120, "Queens", p < 130, "Staten Island")
cr[, boro := pboro(precinct)]
# fall back on the reported borough when the crash has no coordinates
cr[is.na(boro) & !is.na(borough), boro := tools::toTitleCase(tolower(borough))]
cat("Crashes:", nrow(cr), " with a borough:", round(100 * mean(!is.na(cr[, boro])), 1), "%\n")

# Monthly PDO and injury crashes by borough ----
m <- cr[year >= 2016 & ym < as.IDate("2026-06-01") & !is.na(boro), .(pdo = sum(!injury), inj = sum(injury)), by = .(boro, ym)]
setorder(m, boro, ym)
m[, ratio := pdo / inj]
fwrite(m, file.path(out, "pdo_boro_month.csv"))

cat("\n== PDO crashes per injury crash, by borough and year\n")
y <- cr[year >= 2016 & year <= 2025 & !is.na(boro), .(ratio = round(sum(!injury) / sum(injury), 2)), by = .(boro, year)]
print(dcast(y, boro ~ year, value.var = "ratio"))

cat("\n== PDO crashes per injury crash by month around the two policy dates\n")
w <- m[ym >= as.IDate("2018-10-01") & ym <= as.IDate("2020-09-01")]
print(dcast(w[, .(boro, ym = format(ym, "%Y-%m"), ratio = round(ratio, 2))], ym ~ boro, value.var = "ratio"))

# Weekly city series around 2020-04-06 (excluding Staten Island) ----
wk <- cr[crash_date >= as.IDate("2020-01-06") & crash_date < as.IDate("2020-07-06") & boro != "Staten Island",
         .(pdo = sum(!injury), inj = sum(injury)), by = .(week = crash_date - (wday(crash_date) + 5L) %% 7L)]
setorder(wk, week)
cat("\n== Weekly crashes outside Staten Island, Jan-Jun 2020 (weeks start Monday)\n")
print(wk[, .(week, pdo, inj, ratio = round(pdo / inj, 2))])

# Break date per borough: the month that best splits the PDO/injury ratio in 2018-2021 ----
cat("\n== Best single break in log(PDO/injury), 2018-2021, by borough\n")
brk <- m[ym >= as.IDate("2018-01-01") & ym < as.IDate("2022-01-01"),
         { r <- log(ratio); k <- seq(6, .N - 6)
           sse <- vapply(k, function(i) sum((r[1:i] - mean(r[1:i]))^2) + sum((r[(i + 1):.N] - mean(r[(i + 1):.N]))^2), numeric(1))
           i <- k[which.min(sse)]
           .(break_after = format(ym[i], "%Y-%m"), ratio_before = round(exp(mean(r[1:i])), 2), ratio_after = round(exp(mean(r[(i + 1):.N])), 2)) },
         by = boro]
print(brk)

# Revisions: 2019 counts in each snapshot ----
cat("\n== Crashes in Jan-Sep 2019 by snapshot (are 2019 PDO crashes deleted later?)\n")
snap <- function(f) {
  d <- fread(f, select = c(1, which(names(fread(f, nrows = 0)) %in% c("NUMBER OF PERSONS INJURED", "NUMBER OF PERSONS KILLED"))))
  setnames(d, c("date", "inj", "kil"))
  d[, date := as.IDate(date, format = "%m/%d/%Y")]
  d <- d[date >= as.IDate("2019-01-01") & date < as.IDate("2019-10-01")]
  d[, .(snapshot = basename(f), pdo = sum(inj + kil == 0, na.rm = TRUE), injury = sum(inj + kil > 0, na.rm = TRUE))]
}
fs <- c(list.files(file.path(nyc_data_root(), "raw", "crashes"), "^NYPD_Motor_Vehicle_Collisions_\\d{8}\\.csv$", full.names = TRUE),
        nyc_snapshot_files("crashes"))
print(rbindlist(lapply(fs, snap)))

# Composition of PDO crashes before and after (outside Staten Island) ----
cat("\n== Composition of PDO crashes outside Staten Island: 2018-2019 against 2022-2025\n")
cr[, period := fcase(year %in% 2018:2019, "2018-19", year %in% 2022:2025, "2022-25")]
p <- cr[!injury & !is.na(period) & boro != "Staten Island",
        .(crashes_per_year = .N / 4 * fifelse(period[1] == "2018-19", 2, 1),
          single_vehicle = mean(is.na(vehicle_type_code_2) | vehicle_type_code_2 == ""),
          factor_unspecified = mean(contributing_factor_vehicle_1 %in% c("Unspecified", NA)),
          intersection = mean(!is.na(cross_street_name) & cross_street_name != ""),
          off_street = mean(!is.na(off_street_name) & off_street_name != ""),
          night_0_6 = mean(as.integer(sub(":.*", "", crash_time)) < 6),
          with_coords = mean(!is.na(latitude))),
        by = period]
print(p[, lapply(.SD, function(x) round(x, 3)), by = period])
cat("\nTop vehicle types in PDO crashes (share):\n")
vt <- cr[!injury & !is.na(period) & boro != "Staten Island", .N, by = .(period, v = toupper(vehicle_type_code_1))]
vt[, share := round(N / sum(N), 3), by = period]
print(dcast(vt[v %in% vt[order(-N), unique(v)][1:12]], v ~ period, value.var = "share"))
cat("\nTop contributing factors in PDO crashes (share):\n")
cf <- cr[!injury & !is.na(period) & boro != "Staten Island", .N, by = .(period, f = contributing_factor_vehicle_1)]
cf[, share := round(N / sum(N), 3), by = period]
print(dcast(cf[f %in% cf[order(-N), unique(f)][1:12]], f ~ period, value.var = "share"))

# Precincts: size of the drop ----
cat("\n== PDO per injury crash by precinct, 2018-19 against 2022-25\n")
pp <- cr[!is.na(period) & !is.na(precinct), .(pdo = sum(!injury), inj = sum(injury)), by = .(precinct, boro, period)]
pp <- dcast(pp, precinct + boro ~ period, value.var = c("pdo", "inj"))
setnames(pp, gsub("-", "_", names(pp)))
pp[, `:=`(ratio_before = pdo_2018_19 / inj_2018_19, ratio_after = pdo_2022_25 / inj_2022_25)]
pp[, change := ratio_after / ratio_before - 1]
fwrite(pp, file.path(out, "pdo_precinct.csv"))
print(pp[, .(precincts = .N, median_change = round(median(change), 2), p10 = round(quantile(change, 0.1), 2),
             p90 = round(quantile(change, 0.9), 2)), by = boro])
cat("Correlation of the change with the 2018-19 ratio:", round(cor(pp[, change], pp[, ratio_before]), 2), "\n")
cat("Precincts with the smallest and largest drop:\n")
print(pp[order(change)][c(1:5, (.N - 4):.N), .(precinct, boro, ratio_before = round(ratio_before, 2), ratio_after = round(ratio_after, 2), change = round(change, 2))])

# Benchmark: DMV crash cases 2021-2024 (police and motorist reports) ----
cat("\n== NYPD crashes against DMV crash cases, 2021-2024\n")
dmv <- fread("output/explore/dmv/dmv_cases_nyc.csv")
dmv[, boro := c(BRONX = "Bronx", KINGS = "Brooklyn", `NEW YORK` = "Manhattan", QUEENS = "Queens", RICHMOND = "Staten Island")[county_name]]
dmv[, pdo := accident_descriptor == "Property Damage Accident"]
d <- dmv[, .(dmv_pdo_police = sum(n[pdo & police_report == "Y"]), dmv_pdo_motorist = sum(n[pdo & police_report == "N"]),
             dmv_inj_police = sum(n[!pdo & police_report == "Y"]), dmv_inj_motorist = sum(n[!pdo & police_report == "N"])), by = .(boro, year)]
n <- cr[year %in% 2021:2024 & !is.na(boro), .(nypd_pdo = sum(!injury), nypd_inj = sum(injury)), by = .(boro, year)]
d <- merge(d, n, by = c("boro", "year"))
fwrite(d, file.path(out, "nypd_vs_dmv.csv"))
print(d[, .(nypd_pdo = sum(nypd_pdo), dmv_pdo_police = sum(dmv_pdo_police), dmv_pdo_motorist = sum(dmv_pdo_motorist),
            nypd_inj = sum(nypd_inj), dmv_inj_police = sum(dmv_inj_police), dmv_inj_motorist = sum(dmv_inj_motorist)), by = year])
cat("\nShare of DMV PDO cases filed only by motorists, by borough (2021-2024):\n")
print(d[, .(motorist_share_pdo = round(sum(dmv_pdo_motorist) / sum(dmv_pdo_police + dmv_pdo_motorist), 3),
            motorist_share_injury = round(sum(dmv_inj_motorist) / sum(dmv_inj_police + dmv_inj_motorist), 3),
            nypd_pdo_per_dmv_police_pdo = round(sum(nypd_pdo) / sum(dmv_pdo_police), 2)), by = boro])

# Missing PDO reports: pre-policy ratio times injury crashes ----
cat("\n== PDO crashes implied by the 2018-19 ratio (2016-2025, city; Staten Island uses 2016-18)\n")
base <- cr[!is.na(boro) & ((boro != "Staten Island" & year %in% 2018:2019) | (boro == "Staten Island" & year %in% 2016:2018)),
           .(r0 = sum(!injury) / sum(injury)), by = boro]
mis <- cr[year %in% 2016:2025 & !is.na(boro), .(pdo = sum(!injury), inj = sum(injury)), by = .(boro, year)][base, on = "boro"]
print(mis[, .(observed_pdo = sum(pdo), implied_pdo = round(sum(r0 * inj)), missing_share = round(1 - sum(pdo) / sum(r0 * inj), 2)), by = year][order(year)])
sink()
