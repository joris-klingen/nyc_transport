# Extend the crash vehicle type lookup to every vehicle type code in the crash data
#
# Run from the repo root: Rscript scripts/31_vehicle_lookup.R [--write]
# crashes/reference/NYC_vehicle_lookup_table.csv maps the free-text VEHICLE TYPE CODE 1-5 of the
# crash table to classes (Car, SUV, Taxi, Van, Truck, Bus, Motorcycle, Scooter, Bike, Other, Unknown). The
# hand-made table of 2020-01 covered 106 spellings; newer data add e-bikes ("E-Bike", 12k
# vehicles), e-scooters, and in 2026 NYPD's four-letter codes (BICY, EBIK, ESST, MOPD, ...).
# This script keeps every hand-made row and classifies each code not in the table by the rules
# below, in the spirit of the hand-made choices: e-bikes are Bike (as "E-Bik"); mopeds and motor
# scooters are Motorcycle (as "SCOOT", "Moped"). E-scooters, standing scooters and similar devices
# (hoverboards, one-wheels) are their own class Scooter (decided 2026-10-18: they ride in bike lanes);
# this changes the hand-made row "E-Sco" (Source "hand, changed 20261018"). Plain "SCOOTER" stays
# Motorcycle: before e-scooters it meant motor scooters.
# Codes that match no rule are Other, so that every vehicle still counts; unknown codes Unknown.
# The Source column says hand (2020 table) or rule (this script, with its date).
# Without --write it prints the classification for review; with --write it saves the new table
# and keeps the old one as NYC_vehicle_lookup_table.superseded_YYYYMMDD.csv.
# A code is never dropped once seen: snapshots spell the same vehicles differently (the 2026-10-10
# snapshot has NYPD's four-letter codes BICY, EBIK, ESST; the 2026-11-04 one, from NYPD's new
# system, writes "Bicyclist", "E-Bike (must have pedals)", "E-Scooter (standing)"), and projects
# pin older snapshots. Until 2026-11-05 the rule rows came from the newest snapshot alone, so the
# refresh of 2026-11-04 silently unclassified 1,785 crashes of the 2026-10-10 snapshot (888 bike
# crashes of 2026) in nyc_res_bikelanes.

library(data.table)
source("R/nyc_transport.R")

f <- file.path(nyc_data_root(), "reference", "NYC_vehicle_lookup_table.csv")
lk <- fread(f, encoding = "UTF-8")
if (!"Source" %in% names(lk)) lk[, Source := "hand"]
seen <- lk[!Source %like% "^hand", VehicleTypeRaw]   # codes classified by rule in earlier runs
for (s in list.files(dirname(f), "^NYC_vehicle_lookup_table\\.superseded_[0-9]{8}\\.csv$", full.names = TRUE))
  seen <- union(seen, fread(s, encoding = "UTF-8")[, VehicleTypeRaw])   # and in the superseded tables
lk <- lk[Source %like% "^hand"]   # rules are re-derived each run
lk[VehicleTypeRaw == "E-Sco", `:=`(VehicleType = "Scooter", Source = "hand, changed 20261018")]

# all codes in the newest crash snapshot, plus every code classified before (N = 0 when it no
# longer occurs) ----
cr <- crashes_read(select = paste("VEHICLE TYPE CODE", 1:5))
codes <- melt(cr[, lapply(.SD, as.character)], measure.vars = names(cr), value.name = "raw")[!is.na(raw) & raw != "", .N, raw]
codes <- rbind(codes, data.table(raw = setdiff(seen, codes[, raw]), N = 0L))
# codes that read back as missing ("NA") would match every empty vehicle slot in a merge: leave them out
new <- codes[!raw %in% lk[, VehicleTypeRaw] & !raw %in% c("NA", "N/A", "na", "n/a")]

# rules, in order: the first that matches wins ----
rules <- list(
  Unknown    = "^(unk|unkno|unknown|un/.|n/a|na|none|unspec|\\?+|0|-+|\\.)$|^unk|unknown",
  # specific spellings that the broader rules below would misplace (the 0 is dropped afterwards)
  SUV0       = "^pick ?-?up with",
  Van0       = "motor ?home|motorized home|ford trans|transit",
  Truck0     = "^trac$",
  # e-scooters and similar devices; then motorised two-wheelers before bikes, so that "Dirt Bike",
  # "Minibike", "Motorbike" stay motorised (gas scooters are motor scooters)
  Scooter    = "^e-? ?sco|^esst$|standing s|stand up|electric s|^elec sc|e-scoot|e scoot|kick ?scoot|segway|unicycle|one wheel|onewheel|hoverboard|e-skate|electric skate|motorized skate",
  Motorcycle = "motorcy|^moto|moped|mopd|scoot|minibike|mini bike|minicycle|dirt ?bike|pocket bike|motor ?bike|vespa|^mc$|^mcy",
  Bike       = "^bicy|bicycle|^bike|^e-? ?bik|^ebik|electric bi|e-bicyc|pedal|citi ?bike|^cyc|bicyc",
  Taxi       = "taxi|yellow cab|^cab$|green cab",
  Bus        = "bus|^mta b|^schoo|school",
  Ambulance  = "ambu|^amb$|^amb |^ems|fdny am|ambul",
  Truck      = "truck|^trk|tract|trail|^trl|dump|garb|sanit|^tow|wreck|fire|ladder|engine|tank|^mack|freig|flat|box ?t|refg|refrig|concrete|mixer|cement|semi|wheeler|usps|posta|postal|delv|deliv|beverage|crane|^util|utili|sweep|plow|fork|bucket|cherry|boom|^comm|commercial|lunch|food|pallet|hopper|rack|carry|armored|stake|tanker|^large|^lg|^heavy|^hvy|^mail|^ups|^fedex|^dhl|^pallet",
  Van        = "van|camper|sprinter|^rv$|motor ?home|motorized home",
  SUV        = "suv|pick ?-?up|^pick|jeep|station|sport util|^subn|suburban|^util v",
  Car        = "sedan|^pas|passen|coupe|conv|^car$|^cars$|hatch|limo|^lincoln|town car|^4 ?dr|^2 ?dr|^4dsd|^2dsd|^auto|^veh|vehicle|^honda|^toyota|^nissan|^ford|^chev|^hyund|^bmw|^merc|^lexus|^acura|^kia|^audi|^vw|^volks|^subaru|^mazda|^dodge|^tesla"
)
classify <- function(x) {
  y <- tolower(trimws(x))
  out <- rep(NA_character_, length(y))
  for (k in names(rules)) out[is.na(out) & grepl(rules[[k]], y, perl = TRUE)] <- k
  out[is.na(out)] <- "Other"
  out[out == "Ambulance"] <- "Van"   # as in the hand-made table
  out <- sub("0$", "", out)
  out
}
new[, VehicleType := classify(raw)]
new[, Source := paste("rule", format(Sys.Date(), "%Y%m%d"))]

# review ----
cat("codes in the data:", nrow(codes), "; in the hand-made table:", codes[raw %in% lk[, VehicleTypeRaw], .N],
    "; new:", nrow(new), "covering", sum(new[, N]), "vehicles\n")
print(new[, .(codes = .N, vehicles = sum(N)), VehicleType][order(-vehicles)])
for (k in unique(new[, VehicleType])) {
  cat("\n", k, ": ", paste(new[VehicleType == k][order(-N)][1:min(.N, 25), sprintf("%s (%d)", raw, N)], collapse = ", "), "\n", sep = "")
}

# write ----
if ("--write" %in% commandArgs(trailingOnly = TRUE)) {
  old <- sub("\\.csv$", paste0(".superseded_", format(Sys.Date(), "%Y%m%d"), ".csv"), f)
  if (!file.exists(old)) file.copy(f, old)
  out <- rbind(lk[, .(VehicleTypeRaw, VehicleType, Source)], new[order(-N), .(VehicleTypeRaw = raw, VehicleType, Source)])
  fwrite(out, f)
  cat("\nwrote", nrow(out), "rows to", f, "; previous table kept as", basename(old), "\n")
}
