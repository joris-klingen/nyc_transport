# Is a Citi Bike pseudo-cyclist one person? ----
# Checks of citibike_panel() sets against what the trips can tell:
#   - label purity (2018-2019): birth year x gender of members, not used to form the sets here
#     (use_label = FALSE, as from 2020 on), against the same route and hour in the same month;
#   - purity by cutoffs and by route traffic (traffic doubled from 2019 to 2024);
#   - speed: share of speed variance within a route-month that the set explains, against random sets;
#   - member mix (2024): sets mixing members and casual riders, against random draws;
#   - return legs: sets on the reverse route riding on the same dates, and their label agreement.
# Run from the repo root: Rscript explore/22_panel_identity.R

suppressMessages({library(data.table); library(fixest); library(DBI)})
source("R/nyc_transport.R")
out_dir <- "output/explore/panel_identity"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
set.seed(20261112)

# Purity helpers ----
# pairwise agreement: share of pairs of labelled trips in a set that share the label
purity <- function(x, by = "cyclist_set") {
  l <- x[!is.na(label), .N, by = c(by, "label")]
  s <- l[, .(n_lab = sum(N), same_pairs = sum(N * (N - 1)), modal = max(N) / sum(N)), by = by]
  s[n_lab >= 2]
}
summ <- function(x, name) {
  p <- purity(x)
  s <- attr(x, "sets")
  data.table(spec = name, sets = nrow(s), trips = nrow(x), sets_lab = nrow(p),
             pair_agree = round(p[, sum(same_pairs) / sum(n_lab * (n_lab - 1))], 3),
             set_pure90 = round(p[, mean(modal >= 0.9)], 3), modal_trip = round(p[, weighted.mean(modal, n_lab)], 3))
}

# Baselines: label agreement among all member trips of the same route x month (x hour) ----
con <- dbConnect(duckdb::duckdb(shared_home = FALSE))
f19 <- gsub("\\\\", "/", citibike_keyed_files(2018:2019))
base <- as.data.table(dbGetQuery(con, sprintf("
  WITH t AS (SELECT start_station_id, end_station_id, year(date) * 100 + month(date) AS ym, dep_s // 3600 AS h, label
             FROM read_parquet([%s]) WHERE member AND label IS NOT NULL),
  rm AS (SELECT start_station_id, end_station_id, ym, label, count(*) AS c FROM t GROUP BY ALL),
  rmh AS (SELECT start_station_id, end_station_id, ym, h, label, count(*) AS c FROM t GROUP BY ALL)
  SELECT 'route x month' AS baseline, sum(c * (c - 1)) AS same, (SELECT sum(n * (n - 1)) FROM
           (SELECT sum(c) AS n FROM rm GROUP BY start_station_id, end_station_id, ym)) AS all_pairs FROM rm
  UNION ALL
  SELECT 'route x month x hour', sum(c * (c - 1)), (SELECT sum(n * (n - 1)) FROM
           (SELECT sum(c) AS n FROM rmh GROUP BY start_station_id, end_station_id, ym, h)) FROM rmh",
  paste0("'", f19, "'", collapse = ", "))))
base[, agree := round(same / all_pairs, 3)]
lab_1969 <- dbGetQuery(con, sprintf("SELECT avg(CAST(label // 10 = 1969 AS DOUBLE)) AS s FROM read_parquet([%s]) WHERE label IS NOT NULL",
                                    paste0("'", f19, "'", collapse = ", ")))[["s"]]
dbDisconnect(con, shutdown = TRUE)
cat("\nLabel agreement among all member trips (2018-2019):\n"); print(base)
cat(sprintf("Share of labelled trips with birth year 1969 (the sign-up default): %.3f\n", lab_1969))

# Purity by cutoffs, 2019, sets formed without the label ----
specs <- list(
  "default (month, 60 min, 4+, p<.05)" = list(),
  "min_trips 6"        = list(min_trips = 6),
  "min_trips 8"        = list(min_trips = 8),
  "p_max .01"          = list(p_max = 0.01),
  "sd_max 10 min"      = list(sd_max = 10),
  "bin 30 min"         = list(bin_min = 30),
  "bin 120 min"        = list(bin_min = 120),
  "week, 3+"           = list(period = "week", min_trips = 3),
  "year, 8+"           = list(period = "year", min_trips = 8),
  "pooled month (2018-2019)" = list(period = "pooled_month", years = 2018:2019),
  "weekdays only"      = list(weekdays_only = TRUE),
  "no thin filter"     = list(thin = FALSE)
)
res <- rbindlist(lapply(names(specs), function(nm) {
  a <- modifyList(list(years = 2019, use_label = FALSE, bikes = "classic"), specs[[nm]])
  x <- do.call(citibike_panel, a)
  if (nm == "default (month, 60 min, 4+, p<.05)") x19 <<- x
  summ(x, nm)
}))
cat("\nPurity of sets formed without the label, 2019 members:\n"); print(res)
fwrite(res, file.path(out_dir, "purity_by_spec.csv"))

# Purity by set size, regularity and route traffic (default sets, 2019) ----
p <- purity(x19)
s19 <- attr(x19, "sets")
p <- merge(p, s19[, .(cyclist_set, n, sd_min, start_station_id, end_station_id, period, bin)], by = "cyclist_set")
# route-hour-month traffic: member trips on the route in the same month and hour bin
con <- dbConnect(duckdb::duckdb(shared_home = FALSE))
traffic <- function(yr) as.data.table(dbGetQuery(con, sprintf("
  SELECT start_station_id, end_station_id, CAST(year(date) * 100 + month(date) AS VARCHAR) AS period,
         CAST(dep_s // 3600 AS INTEGER) AS bin, count(*) AS traffic
  FROM read_parquet('%s') WHERE member GROUP BY ALL", gsub("\\\\", "/", citibike_keyed_files(yr)))))
tr19 <- traffic(2019)
p <- merge(p, tr19, by = c("start_station_id", "end_station_id", "period", "bin"), all.x = TRUE)
p[, traffic_b := cut(traffic, c(0, 8, 15, 30, 60, Inf), right = TRUE)]
cat("\nPurity by trips on the route in that month and hour (all members), 2019:\n")
print(p[, .(sets = .N, pair_agree = round(sum(same_pairs) / sum(n_lab * (n_lab - 1)), 3), pure90 = round(mean(modal >= 0.9), 3)),
        by = traffic_b][order(traffic_b)])
cat("\nPurity by set size:\n")
print(p[, .(sets = .N, pair_agree = round(sum(same_pairs) / sum(n_lab * (n_lab - 1)), 3), pure90 = round(mean(modal >= 0.9), 3)),
        by = .(n_b = cut(n, c(3, 4, 5, 7, 10, Inf)))][order(n_b)])
cat("\nPurity by departure sd (minutes):\n")
print(p[, .(sets = .N, pair_agree = round(sum(same_pairs) / sum(n_lab * (n_lab - 1)), 3), pure90 = round(mean(modal >= 0.9), 3)),
        by = .(sd_b = cut(sd_min, c(0, 5, 10, 15, 20)))][order(sd_b)])

# Traffic in 2024: where do 2024 sets sit on the 2019 purity curve? ----
s24 <- citibike_panel(years = 2024, bikes = "any", trips = FALSE)
tr24 <- traffic(2024)
dbDisconnect(con, shutdown = TRUE)
s24 <- merge(s24, tr24, by = c("start_station_id", "end_station_id", "period", "bin"), all.x = TRUE)
pur_b <- p[, .(agree_b = sum(same_pairs) / sum(n_lab * (n_lab - 1))), by = traffic_b]
s24[, traffic_b := cut(traffic, c(0, 8, 15, 30, 60, Inf), right = TRUE)]
cat("\nSets by route-hour-month traffic, 2019 vs 2024 (default cutoffs):\n")
tb <- merge(p[, .(sets19 = .N), by = traffic_b], s24[, .(sets24 = .N), by = traffic_b], by = "traffic_b", all = TRUE)
tb <- merge(tb, pur_b, by = "traffic_b")
tb[, `:=`(share19 = round(sets19 / sum(sets19), 3), share24 = round(sets24 / sum(sets24), 3), agree_b = round(agree_b, 3))]
print(tb)
cat(sprintf("Implied 2024 agreement (2019 curve, 2024 traffic mix): %.3f vs 2019 %.3f\n",
            tb[, sum(agree_b * share24)], tb[, sum(agree_b * share19)]))

# Speed: does the set explain speed within a route-month? Real vs random sets ----
x19[, rm := .GRP, by = .(start_station_id, end_station_id, period)]
x19[, rand_set := sample(cyclist_set), by = rm]
cat("\nWithin route-month R2 of speed on set id, routes with 2+ sets in the month (2019):\n")
x19m <- x19[, if (uniqueN(cyclist_set) >= 2) .SD, by = rm]
sp <- data.table(sets = c("real", "random within route-month"),
                 r2 = c(fitstat(feols(speed_kmh ~ 1 | rm + cyclist_set, x19m), "r2")[[1]] - fitstat(feols(speed_kmh ~ 1 | rm, x19m), "r2")[[1]],
                        fitstat(feols(speed_kmh ~ 1 | rm + rand_set, x19m), "r2")[[1]] - fitstat(feols(speed_kmh ~ 1 | rm, x19m), "r2")[[1]]))
print(sp)
cat(sprintf("Routes x months with 2+ sets: %d; trips %d\n", uniqueN(x19m[, rm]), nrow(x19m)))
# speed sd within set vs between sets on the route-month
cat(sprintf("Mean within-set sd of speed %.2f km/h; within route-month (random sets) %.2f\n",
            x19m[, sd(speed_kmh), by = cyclist_set][, mean(V1, na.rm = TRUE)],
            x19m[, sd(speed_kmh), by = rand_set][, mean(V1, na.rm = TRUE)]))

# Member mix, 2024: real sets vs random draws of the same size on the same route-hour ----
x24a <- citibike_panel(years = 2024, bikes = "any", members_only = FALSE)
mix <- x24a[, .(n = .N, m = sum(member)), by = cyclist_set]
mix[, mixed := m > 0 & m < n]
# expected under random draws: member share of all trips on the route-hour-month
con <- dbConnect(duckdb::duckdb(shared_home = FALSE))
ms <- as.data.table(dbGetQuery(con, sprintf("
  SELECT start_station_id, end_station_id, CAST(year(date) * 100 + month(date) AS VARCHAR) AS period,
         CAST(dep_s // 3600 AS INTEGER) AS bin, avg(CAST(member AS DOUBLE)) AS pm
  FROM read_parquet('%s') GROUP BY ALL", gsub("\\\\", "/", citibike_keyed_files(2024)))))
dbDisconnect(con, shutdown = TRUE)
mix <- merge(mix, merge(attr(x24a, "sets")[, .(cyclist_set, start_station_id, end_station_id, period, bin)], ms,
                        by = c("start_station_id", "end_station_id", "period", "bin")), by = "cyclist_set")
mix[, p_mixed_random := 1 - pm^n - (1 - pm)^n]
cat(sprintf("\n2024, members and casual riders: %d sets; %.1f%% casual-only, %.1f%% mixed (random draws: %.1f%%)\n",
            nrow(mix), 100 * mix[, mean(m == 0)], 100 * mix[, mean(mixed)], 100 * mix[, mean(p_mixed_random)]))

# Return legs: a set on the reverse route riding on the same dates ----
link_sets <- function(x, ids = c("start_station_id", "end_station_id")) {
  d <- unique(x[, .(cyclist_set, o = get(ids[1]), d = get(ids[2]), period = attr(x, "sets")[cyclist_set, period],
                    bin = attr(x, "sets")[cyclist_set, bin], date)])
  n <- d[, .(n_dates = .N), by = cyclist_set]
  j <- d[d, on = .(o = d, d = o, period, date), nomatch = 0, allow.cartesian = TRUE,
         .(out = i.cyclist_set, ret = x.cyclist_set, out_bin = i.bin, ret_bin = x.bin)]
  j <- j[ret_bin > out_bin, .(shared = .N), by = .(out, ret)]
  j <- merge(merge(j, n[, .(out = cyclist_set, n_out = n_dates)], by = "out"), n[, .(ret = cyclist_set, n_ret = n_dates)], by = "ret")
  j[, share := shared / pmin(n_out, n_ret)]
  # one partner per set: the return leg with the most shared dates, and vice versa
  setorder(j, -shared, -share)
  j <- j[!duplicated(out)][!duplicated(ret)]
  j[]
}
lk <- link_sets(x19)
cat(sprintf("\n2019 sets: %d; with a reverse-route set sharing 1+ dates: %d out-legs\n", nrow(s19), nrow(lk)))
print(lk[, .N, by = .(shared_b = cut(shared, c(0, 1, 2, 3, 5, 10, 31)))][order(shared_b)])
# label agreement of the linked legs (modal labels), by dates shared
ml <- x19[!is.na(label), .N, by = .(cyclist_set, label)][order(-N)][!duplicated(cyclist_set), .(cyclist_set, label)]
lk <- merge(merge(lk, ml[, .(out = cyclist_set, lab_out = label)], by = "out"), ml[, .(ret = cyclist_set, lab_ret = label)], by = "ret")
cat("\nModal label of out and return leg the same, by dates shared:\n")
print(lk[, .(links = .N, same_label = round(mean(lab_out == lab_ret), 3)), by = .(shared_b = cut(shared, c(0, 1, 2, 3, 5, 31)))][order(shared_b)])
# baseline: random reverse-route set in the same month
rr <- merge(s19[, .(out = cyclist_set, o = start_station_id, d = end_station_id, period)],
            s19[, .(ret = cyclist_set, o = end_station_id, d = start_station_id, period)], by = c("o", "d", "period"),
            allow.cartesian = TRUE)
rr <- merge(merge(rr, ml[, .(out = cyclist_set, lab_out = label)], by = "out"), ml[, .(ret = cyclist_set, lab_ret = label)], by = "ret")
cat(sprintf("Baseline, any reverse-route set of the month: same label %.3f (%d pairs)\n", rr[, mean(lab_out == lab_ret)], nrow(rr)))
fwrite(lk, file.path(out_dir, "links_2019.csv"))
