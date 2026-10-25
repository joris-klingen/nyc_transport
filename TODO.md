# To do

State on 2026-10-11: repo renamed to `nyc_traffic` (GitHub `joris-klingen/nyc_traffic`), data store
renamed to `Dropbox/1_research/nyc_traffic_data` with the flat layout, all three repos pushed
(`nyc_traffic` 3982288, `nyc_bikelane_history` 96717c8, `nyc_res_bikelanes` a2cd41f).

State on 2026-10-23: `nyc_traffic` and `nyc_streets` merged into one repo, `nyc_transport` (streets
in `streets/`, history kept), and the two stores into one, `nyc_transport_data` (street history in
`derived/streets/`). Store root `NYC_TRANSPORT_DATA`. GitHub: nyc_traffic renamed to nyc_transport,
nyc_streets archived (both 2026-10-23).

## After the rename

- [x] Folder rename verified 2026-10-13 (`nyc_data_root()` and 176 yellow months; `NYC_DATA` unset).
- [x] `nyc_res_bikelanes/scripts/000_project_init.R` and `nyc_bikelane_history/checks/01_dot_release_quality.R`
      run against the new paths.
- [x] `checks/store.R` run on the new layout 2026-10-13: only flags the real COVID drops (2020-04 to
      2020-06); the IDate warning is fixed. 85% of traffic count SegmentIDs are in current LION.

## Bicycle and pedestrian counts

- [x] Readers tested on the full file 2026-10-13 (17 min, 21.4M rows, 41 sensors with counts):
  - every count has a sensor name; no unparsed times
  - no duplicate sensor-flow-time keys once deleted rows are dropped: the duplicates of the sample
    were 216 deleted + modified pairs, not daylight saving
  - local time confirmed: 02:00 missing on spring-forward Sundays, fall-back Sundays have a single
    01:00 hour, weekday morning peak at 8 in summer
- [ ] `counter_id` is empty for 10% of rows, mostly two sensors whose device dates do not cover their
      data: Comprehensive Brooklyn Bridge Counter (2013-12 to 2022-03, 543k rows) and 1st Avenue -
      26th St N - Interference testing (2013-09 to 2018-04, 321k rows).
- [ ] Off-street sensors snap to a far LION centerline: Concrete Plant Park (165 ft), High Bridge
      (136 ft), Hunts Point Ave (89 ft). Set `segment_id` to NA beyond some distance, or flag
      off-street paths. One sensor has no coordinates (Manhattan Bridge Interference Calibration 2018).
- [ ] Add the counts to the README source table and `checks/store.R` (sensors still reporting,
      gaps per sensor, level shifts at device swaps).

## Smaller items

- [x] `lanes/01_lion_panel.R` re-run through `nyc_data_root()` 2026-10-13; output identical.
- [x] `nyc_res_bikelanes/notes/*.md` point to the current repos and data store (2026-10-16; a
      header line in each note says the paths were updated).
- [ ] Optionally drop the `NYC_DATA` fallback in `R/config.R` once nothing uses it.
- [ ] Citi Bike: the original 2020-01 to 2021-01 releases with rider demographics are not in the
      store (the 2024 repackaging converted 2020 to the new format). Check whether they can still be
      found anywhere if the gender work needs them.
- [x] `output/` and `migration_logs/` deleted 2026-10-13.

## Yellow legacy CSVs (raw/taxi/yellow_csv_legacy)

The 54 CSVs (2012-01 to 2016-06, 123 GB) are the only copy of yellow trips with pickup and dropoff
coordinates; TLC no longer serves them (403, checked 2026-10-24), so they stay in the store. Do both
after the tips import (`nyc_res_tips/scripts/data_management/011_import_yellow_legacy.R`) has finished.

- [ ] Parquet copy for fast queries: `derived/taxi_yellow_legacy/yellow_tripdata_YYYY-MM.parquet`.
  - One schema for all months: the TLC parquet names (`VendorID`, `tpep_pickup_datetime`, `RatecodeID`,
    `extra`, ...) plus `pickup_longitude`, `pickup_latitude`, `dropoff_longitude`, `dropoff_latitude`
    (2012-2014 write `vendor_id`, `pickup_datetime`, `rate_code`, `surcharge`; 2015-2016 the new names).
  - Sorted by pickup time, row groups of about 250,000 trips (as the Citi Bike months).
  - A reader `tlc_legacy_open()`, a check that row counts match the CSVs, and a line in the README
    and the catalog. Expected size 15-25 GB, a few hours to build.
- [ ] Gzip the CSVs in place for storage (`yellow_tripdata_YYYY-MM.csv.gz`, about 25-30 GB instead of
      123 GB). The files stay byte-for-byte as published once unzipped; `fread()` reads `.csv.gz`.
      Check the md5 of each unzipped file against the CSV before deleting the CSV, and update the
      readers and scripts that list `*.csv` (the tips import, `checks/store.R`).

## Profiles and simulated data

- [x] Profiles of every source in `profiles/` and simulators in `sim/` (2026-10-16); see the README.
- [ ] Re-run `profiles/build_profiles.R` after refreshing the store (new snapshots, new months), so
      that the profiles and reference tables follow the data.
- [ ] Optional: `sim_store(dir)` writing a fake data store in the real file formats (parquet months,
      crash CSV, ...), so that the readers and project pipelines run unchanged on simulated data.

## Crash vehicle types

- [x] `crashes/reference/NYC_vehicle_lookup_table.csv` extended to all 3,148 codes (2026-10-16,
      `scripts/31_vehicle_lookup.R`): e-bikes (12k vehicles, from 2020) and NYPD's 2026 four-letter
      codes were unclassified, so bike crashes were undercounted by 13-33% a year from 2020.
- [ ] Re-run `scripts/31_vehicle_lookup.R --write` after each new crash snapshot (new codes).
- [x] E-scooters and standing scooters are their own class Scooter (decided 2026-10-18; 9,326 vehicles),
      instead of Motorcycle as in the 2020 table: they ride in bike lanes.
