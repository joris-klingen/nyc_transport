# To do

State on 2026-10-11: repo renamed to `nyc_traffic` (GitHub `joris-klingen/nyc_traffic`), data store
renamed to `Dropbox/1_research/nyc_traffic_data` with the flat layout, all three repos pushed
(`nyc_traffic` 3982288, `nyc_bikelane_history` 96717c8, `nyc_res_bikelanes` a2cd41f).

State on 2026-10-23: `nyc_traffic` and `nyc_streets` merged into one repo, `nyc_transport` (streets
in `streets/`, history kept), and the two stores into one, `data/` (street history in
`derived/streets/`). Store root `NYC_TRANSPORT_DATA`. GitHub: nyc_traffic renamed to nyc_transport,
nyc_streets archived (both 2026-10-23).

## Review of 2026-11-04

Findings and actions in `explore/notes/data_review_2026-11-04.md`; open datasets we do not hold, with
ids and the project each serves, in `explore/notes/dataset_candidates.md` (a living list: add to it
when a paper or review names a source).

- [x] Store refreshed 2026-11-04 (`00_update.R --profiles`, run `20261104_1713`, 105 min): crashes,
      persons and vehicles to 2026-10-31 (NYPD had paused from mid-June to late October; the
      2026-10-10 snapshot ends 2026-06-11), TLC 2026-09, CRZ entries, bike counts, boundaries, eight
      street layout sets. Vehicles and CRZ entries were reset mid-download and re-run with
      `10_download_opendata.R vehicles,crz_entries`; profiles, catalog and `checks/store.R` rebuilt
      afterwards. The "stopped publishing" lines are gone from `dataset_notes.md`, `../NYC_DATA.md`
      and the explore notes. The crash tables came back in a new format (next item); the projects
      keep the `20261010` pin. The refresh also rebuilt the vehicle lookup from the new snapshot
      alone and dropped 136 codes of the old one (fixed 2026-11-05, see Crash vehicle types). The
      bikelanes re-run that verifies the fix was stopped on 2026-11-05 after 17 of 37 scripts,
      all reproducing the paper's outputs; the rest is item 21 in
      `../../papers_active/nyc_res_bikelanes/notes/todo.md`.
- [x] Crashes in NYPD's new format (snapshot 2026-11-04; `dataset_notes.md`, crashes): since
      2026-11-05 `crashes_read()` swaps `off_street_name` and `cross_street_name` back for snapshots
      from 2026-11 (the parquet copy of 20261104 rebuilt with it) and reads their hashed
      `collision_id` as character. `crashes_relocate()` on 2019 crashes: 46,531 address points,
      2,080 nearest, 4,662 intersection nodes with 20261104 (4,661 with 20261010, one crash fewer;
      none before the swap). `checks/store.R` flags a newest snapshot whose `off_street_name` does
      not start with a house number (95% in both snapshots, 26% for `cross_street_name`). Moving
      the bikelanes pin to 20261104 was tried on 2026-11-04 and reverted (without the swap 396 of
      1,649 paper values moved, BCR 0.99 to 0.90); try again after the cyclist item below.
- [ ] Cyclist recoding in the new format: in 2025, 975 of 6,515 Bicyclist persons became Other
      Motorized and `number_of_cyclist_injured` fell by 753 (11%); 2024 and earlier unchanged. Find
      which riders moved (vehicle ids are not shared across snapshots; 1,018 Standing Scooter
      vehicles appear) and decide how the bikelanes cyclist outcomes treat 2025 before the pin moves.
- [ ] Document `raw/citibike/stock_panel/` (21 GB Kaggle station status archive, used by nyc_res_effort):
      README, `dataset_notes.md`, a reader, a profile, `checks/store.R`, a manifest in `_meta/`.
- [ ] Snapshot the NYS DMV crash cases (data.ny.gov `e8ky-4vqe`, rolling three-year window) into
      `raw/crashes_dmv/` before 2021-2022 roll off.
- [ ] Weather (ASOS), elevation (USGS 3DEP) and ACS tables into the store with readers; the effort
      project's scripts 030, 011 and 012 are the templates.
- [ ] Settle `nyc_res_cc/scripts/data_import/109_import_speed_cameras.R` (stub, source never found).

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
      `scripts/00_update.R` does this since 2026-10-26. Since 2026-11-05 the table keeps every code
      of every snapshot (union with the superseded tables): the 2026-11-04 rebuild had taken the
      codes of the newest snapshot only, which spells the 2026 codes out ("Bicyclist" for BICY), so
      1,785 crashes of the pinned 2026-10-10 snapshot lost their class in nyc_res_bikelanes (888
      bike crashes of 2026; cyclist risk, rerouting and welfare values moved, the area estimates not).
      Verified 2026-11-05: with the repaired table the first 17 scripts of the bikelanes chain
      (import to 267) reproduce the paper's outputs file for file; the remaining 20 are its todo
      item 21.
- [x] E-scooters and standing scooters are their own class Scooter (decided 2026-10-18; 9,326 vehicles),
      instead of Motorcycle as in the 2020 table: they ride in bike lanes.
