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

## Backup and updates

- [x] Irreplaceable files listed and md5-checked (`checks/irreplaceable.R`, 471 files, 37.7 GB,
      2026-10-26); all in sync with Dropbox. See the README, Backup.
- [x] One refresh command, `scripts/00_update.R` (2026-10-26).
- [ ] Offline copy of the irreplaceable files on an external disk (Dropbox is the only other copy).
- [ ] Schedule `scripts/00_update.R` (monthly, after TLC publishes) or run it by hand.

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
- [x] `NYC_DATA` and `NYC_TRAFFIC_DATA` fallbacks dropped 2026-10-25 (no environment variable,
      `.Renviron` or config file used them).
- [x] Citi Bike: the original 2020-01 to 2021-01 releases with rider demographics are not in the
      store (the 2024 repackaging converted 2020 to the new format). Checked 2026-10-25: S3 no longer
      has them; the Wayback Machine has only `202002-` and `202003-citibike-tripdata.csv.zip`
      (web.archive.org/cdx, captures 2020-12 and 2022-06). Not downloaded; for more months look for
      copies others posted (Kaggle) if the gender work needs 2020.
- [x] Congestion relief zone entries downloaded by `10_download_opendata.R` (2026-10-25): the MTA
      republished them on data.ny.gov as `t6yz-b64h` (`t2rz-wjj6` is gone); `nyc_opendata` has a
      `domain` column for the state portal.
- [x] `10_download_opendata.R` wrote new snapshots to `<root>/<dir>` instead of `<root>/raw/<dir>`
      since the store moved to `raw/` (2026-10-23); fixed 2026-10-25 (no snapshot was downloaded in
      between). Same fix for the legacy count files in `profiles/build_profiles.R` and their reader
      calls in `profiles/index.csv`.
- [x] `output/` and `migration_logs/` deleted 2026-10-13.

## Yellow legacy CSVs (raw/taxi/yellow_csv_legacy)

The 54 CSVs (2012-01 to 2016-06, 123 GB) are the only copy of yellow trips with pickup and dropoff
coordinates; TLC no longer serves them (403, checked 2026-10-24), so they stay in the store. Do both
after the tips import (`nyc_res_tips/scripts/data_management/011_import_yellow_legacy.R`) has finished.

- [x] Parquet copy built 2026-10-25 (`scripts/02_yellow_legacy_parquet.R`, 19 GB, `tlc_legacy_open()`);
      rows equal the CSV in all 54 months (`checks/yellow_legacy_parquet.R`). Found on the way: TLC's
      own yellow parquet files of 2012-2016 hold other trips (6 months lack 0.4-2.0M trips; see
      the README). Plan as written:
- Parquet copy for fast queries: `derived/taxi_yellow_legacy/yellow_tripdata_YYYY-MM.parquet`.
  - One schema for all months: the TLC parquet names (`VendorID`, `tpep_pickup_datetime`, `RatecodeID`,
    `extra`, ...) plus `pickup_longitude`, `pickup_latitude`, `dropoff_longitude`, `dropoff_latitude`
    (2012-2014 write `vendor_id`, `pickup_datetime`, `rate_code`, `surcharge`; 2015-2016 the new names).
  - Sorted by pickup time, row groups of about 250,000 trips (as the Citi Bike months).
  - A reader `tlc_legacy_open()`, a check that row counts match the CSVs, and a line in the README
    and the catalog. Expected size 15-25 GB, a few hours to build.
- [x] Gzipped 2026-10-25 (`scripts/03_gzip_yellow_legacy.sh`): 123 GB to 26 GB, all 54 md5-checked
      (`_meta/yellow_csv_legacy_md5.csv`); readers, checks, profiles and the tips import take `.csv.gz`.
      Plan as written:
- Gzip the CSVs in place for storage (`yellow_tripdata_YYYY-MM.csv.gz`, about 25-30 GB instead of
      123 GB). The files stay byte-for-byte as published once unzipped; `fread()` reads `.csv.gz`.
      Check the md5 of each unzipped file against the CSV before deleting the CSV, and update the
      readers and scripts that list `*.csv` (the tips import, `checks/store.R`).

## Taxi zones and trip types

- [x] Zone numbering (issue #1), 2026-10-25: one numbering for all trip years. The point-in-polygon of
      the legacy pickup coordinates reproduces TLC's `PULocationID` with the 2026-10 file for
      99.9-100% of trips (2012-07, 2014-01, 2016-01; the rest within 1.2 ft of the boundary,
      `checks/taxi_zones.R`); the 2025-09 file has the same polygons but ids 56 and 103 duplicated
      where the trips use 57, 104 and 105. `taxi_zones_read(as_of)` reads an older file if needed.
- [x] Non-high-volume FHV (issue #2): not in the store; documented in the README source table
      (the only record of Uber and Lyft trips before 2019-02). Download with `01_download_tlc.R` if a
      project needs ride-hail volumes 2015-2019.

## Profiles and simulated data

- [x] Profiles of every source in `profiles/` and simulators in `sim/` (2026-10-16); see the README.
- [ ] Re-run `profiles/build_profiles.R` after refreshing the store (new snapshots, new months), so
      that the profiles and reference tables follow the data (`scripts/00_update.R --profiles`).

## Crash vehicle types

- [x] `crashes/reference/NYC_vehicle_lookup_table.csv` extended to all 3,148 codes (2026-10-16,
      `scripts/31_vehicle_lookup.R`): e-bikes (12k vehicles, from 2020) and NYPD's 2026 four-letter
      codes were unclassified, so bike crashes were undercounted by 13-33% a year from 2020.
- [x] Re-run `scripts/31_vehicle_lookup.R --write` after each new crash snapshot (new codes):
      `scripts/00_update.R` does this since 2026-10-26.
- [x] E-scooters and standing scooters are their own class Scooter (decided 2026-10-18; 9,326 vehicles),
      instead of Motorcycle as in the 2020 table: they ride in bike lanes.
