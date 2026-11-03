# Dataset notes

Hand-written knowledge per dataset that the profiles cannot see: what one row is, coverage, how to
join, and the breaks and gaps to know before using it. `scripts/50_build_catalog.R` merges these
into `nyc_data_catalog.md`, next to the reader call and the columns from the profiles.

Format: one `## <source>` block per dataset, or a block with a short title and a `Sources:` line
listing the datasets it covers; then the fields `Coverage:`, `One row:`, `Keys:`, `Issues:` (a list
of `- ` lines) and `See:`. Source names are those in `profiles/index.csv` and
`streets/profiles/index.csv`. Write facts with the date
they were checked; update a note when a check changes it.

## taxi_yellow
Coverage: 2012-01 to the latest month TLC published (2026-08 on 2026-10-25), monthly parquet as TLC republished them.
One row: one yellow taxi trip (TPEP); pickup and dropoff as TLC taxi zones, times in NYC clock time stored without a time zone.
Keys: `PULocationID`, `DOLocationID` -> `taxi_zones_read()` `LocationID` (one numbering for all years).
Issues:
- 2012-2016 hold other trips than the legacy CSVs: 2012-01, -02, -04, -05, 2013-04 and 2013-08 lack 0.4-2.0M trips each (up to 13%), 2014-08..12 have 10-98k more, 2015-2016 about 0.05% fewer (`checks/yellow_legacy_parquet.R`, 2026-10-25). Use `tlc_legacy_open()` for counts in those years.
- The missing 2012-2013 trips are spread over every day (2013-04: 14 whole or part days) and keep the borough and Manhattan-zone shares within sampling noise, so zone counts are scaled down, not shifted (month fixed effects absorb it). They are mostly VTS trips: in 2012 the parquet lacks 15-25% of VendorID 2 against 1-5% of VendorID 1, so vendor shares (and pooled tip rates, as the vendors' tip screens differ) are off in those months (`checks/yellow_parquet_gaps.R`).
- From 2026-06 `request_source` names the ride-hail licence that dispatched the trip (HV0003 Uber ~25% of trips, HV0005 Lyft from 2026-08); app-dispatched trips are longer and dearer, so averages shift (audit 2026-10-24, `explore/notes/idea_dispatch.md`).
- Outer-borough pickups jump in 2024-03 and again in 2025-02..05.
- Missing days: 2013-08-11, 2022-09-18, 2023-09-21..24.
- `airport_fee` is `Airport_fee` from 2023-02; `cbd_congestion_fee` from 2025-01; column types drift across years (see the schema by year in profiles/).
- 2020-04..06 are COVID lows (about 15% of normal), not data errors.
See: README "Sources"; `checks/store.R`.

## taxi_yellow_legacy
Coverage: 2012-01 to 2016-06 (54 months, 732M trips).
One row: one yellow taxi trip from the legacy CSVs, with pickup and dropoff coordinates; same columns, names and codes as `taxi_yellow` (VendorID 1/2, payment_type 1-5), timestamps in NYC clock time stored as UTC.
Keys: pickup/dropoff lon/lat (EPSG 4326); point-in-polygon with `taxi_zones_read()` gives TLC's zone for 99.9-100% of trips.
Issues:
- Rows equal the CSVs in every month (`checks/yellow_legacy_parquet.R`); TLC's own parquet files of these months differ (see taxi_yellow).
- About 2% of pickups sit at 0,0 or outside NYC: filter with `nyc_in_bbox()`.
- `RatecodeID` as published (0, 7, 210, ... kept; TLC's parquet files code these 99). `improvement_surcharge` is NA before 2015 (the charge started then).
- 2016-01..06 coordinates are single precision (about 1 ft).
See: `scripts/02_yellow_legacy_parquet.R`.

## taxi_yellow_csv_legacy
Coverage: 2012-01 to 2016-06, the CSVs as TLC published them (no longer online, 403 since at least 2026-10-24); gzipped in place (byte-identical once unzipped).
One row: one yellow taxi trip with coordinates.
Keys: as taxi_yellow_legacy.
Issues:
- Read the parquet copy (`tlc_legacy_open()`) instead; the CSVs are the archive of record.
- 2012-2014 headers use `vendor_id`, `pickup_datetime`, `rate_code`, `surcharge` and text codes (CMT/VTS, CRD/CSH/NOC/DIS/UNK), followed by a blank line (`blank.lines.skip = TRUE`); 2014 headers have spaces after the commas; 2015-2016 use the TLC names and numeric codes.
See: `_meta/yellow_csv_legacy_md5.csv`.

## taxi_foil
Coverage: 2012-01 to 2013-12 (24 months, 351,724,083 trips): the yellow trips of the two Freedom of Information Law releases that carry driver ids. 2013 (173,179,759 trips) as released under Chris Whong's request (chriswhong.com/open-data/foil_nyc_taxi, archived at archive.org/details/nycTaxiTripData2013); 2012 (178,544,324 trips) from Donovan and Work (2016, Illinois Data Bank, doi:10.13012/J8PN93H8, CC0), whose release also holds 2010, 2011 and 2013 (`raw/taxi/foil_2010_2013/`; 2013 is the same trips relabelled and is not converted, 2010-2011 convert with `scripts/07_foil_donovan_parquet.R <year>` when needed).
One row: one yellow taxi trip, the `taxi_yellow_legacy` columns (same names, codes and coordinates; clock time stored as UTC) plus `medallion` and `hack_license` (the cab and the driver: in 2013 the 32-character MD5 hashes of the medallion and hack licence number as published, in 2012 ten-digit pseudonyms `2012000001`.. drawn by Donovan and Work anew each year) and `trip_time_in_secs` (the meter's trip time).
Keys: `hack_license` (driver), `medallion` (cab), pickup/dropoff lon/lat as taxi_yellow_legacy. An id never links across years (different releases, pseudonyms redrawn each year). 2012: 13,731 medallions and 40,383 drivers over the year, 13,360-13,450 and 30,800-32,300 in a month; 2013: 14,144 and 43,191, 13,400-13,560 and 32,000-33,500.
Issues:
- Same extract as the legacy CSVs: every month of both years has exactly the `taxi_yellow_legacy` row count, and 2012-01 and 2013-01 have identical fare, tip, distance and passenger sums and payment and vendor counts (`_meta/foil_2013_parquet_log.csv`, `_meta/foil_donovan_parquet_log.csv`).
- The 2013 hashes are reversible (the MD5 of a 7-character medallion or 6-digit licence number; Pandurangan 2014, Douriez et al. 2016): use them as opaque ids only, never reverse them, publish aggregates only. The 2012 pseudonyms are not hashes, but Donovan and Work do not claim the data are anonymous; same rule.
- Trip and fare files (`trip_data_M.csv`, `trip_fare_M.csv`) list the same trips in the same order and were joined by position after checking medallion, hack_license, vendor_id and pickup_datetime on every row (0 unmatched in every month). Headers have spaces after the commas (2013: the fare files and the December trip file; 2012: all files).
- `improvement_surcharge` is NA (the charge started in 2015); `RatecodeID` as published.
- 2012-06 to 2012-12, CMT (`VendorID` 1) only: `trip_distance` differs from `taxi_yellow_legacy` on nine trips in ten, by up to 0.4 miles either way (monthly sums 0.2% higher), while pickup and dropoff times, fares, tips and row counts are identical; VTS and all of 2013 agree to the cent and the hundredth of a mile. Which file holds the meter's distance is unknown. Match to the legacy file on vendor, pickup and dropoff second, fare and tip, not on distance (as `nyc_res_tips` scripts/data_management/016 does).
- Raw archives: `raw/taxi/foil_2013/trip_data.7z` (3.8 GiB, 12 CSVs of 2.1-2.6 GB) and `trip_fare.7z` (1.6 GiB, 12 CSVs of 1.4-1.8 GB), md5 in `_meta/foil_2013_md5.csv`, bsdtar (Windows `tar.exe`) streams a member in seconds. `raw/taxi/foil_2010_2013/FOIL2012.zip` (7.08 GiB, downloaded by hand on 2026-11-02 because the Illinois Data Bank refuses non-browser downloads; md5 in `_meta/foil_2010_2013_md5.csv`) holds `FOIL2012/trip_data_M.zip` and `trip_fare_M.zip`, one CSV each (1.8 and 1.1 GB for January); its offsets wrapped at 4 GB without Zip64 records, so bsdtar reports a damaged archive and Python's zipfile fails on the early members: `scripts/zipfix.py` corrects the offsets and extracts a member with a CRC check (about a minute per month end to end).
See: `scripts/04_download_foil_2013.sh`, `scripts/06_foil_2013_parquet.R`, `scripts/07_foil_donovan_parquet.R`, `scripts/zipfix.py`; used by `nyc_res_tips` for within-driver estimates.

## taxi_green
Coverage: 2014-01 to the latest month (green taxis started 2013-08; 2013-08..12 are not published as parquet).
One row: one street-hail livery (boro taxi) trip.
Keys: `PULocationID`, `DOLocationID` -> taxi zones.
Issues:
- Volume falls from 1.6M trips a month (2015-06) to 0.5M (2019-06) and under 100k from 2020 (44k in 2026-06): few trips per zone in recent years.
See: README "Sources".

## taxi_fhvhv
Coverage: 2019-02 (the first month TLC published high-volume for-hire trips) to the latest month.
One row: one Uber, Lyft, Via or Juno trip (`hvfhs_license_num` HV0003 Uber, HV0005 Lyft, HV0004 Via, HV0002 Juno).
Keys: `PULocationID`, `DOLocationID` -> taxi zones.
Issues:
- `trip_miles`, not `trip_distance`; `cbd_congestion_fee` from 2025-01.
- Ride-hail trips before 2019-02 are only in the non-high-volume FHV files, which are not in the store (README source table).
See: README "Sources".

## taxi_zones
Coverage: the TLC zone file of 2026-10 (`taxi_zones_read()`); an older file with `taxi_zones_read(as_of = "20250923")`.
One row: one taxi zone (263 polygons); ids 264/265 are unknown and have no polygon.
Keys: `LocationID`.
Issues:
- One numbering for all trip years (2012 on): checked against the legacy coordinates (`checks/taxi_zones.R`, 2026-10-25).
- The 2025-09 file has the same polygons but numbers 57 as 56 and 104/105 as 103; nyc_res_bikelanes reads it (negligible for Manhattan).
See: issue #1 (closed).

## crashes
Coverage: 2012-07-01 to 2026-06-11 (snapshot 2026-10-10; NYPD stopped publishing after 2026-06-15, so newer snapshots add nothing yet).
One row: one police-reported motor vehicle crash (MV-104AN).
Keys: `collision_id` -> crash_persons, crash_vehicles; lon/lat; `crashes_relocate()` adds LION `segment_id` and `node_id`.
Issues:
- Property-damage-only crashes are under-reported from 2019: NYPD stopped attending them (Staten Island pilot from 2019-03-18, citywide from 2020-04-06), and about two thirds were missing by 2024. Injury and fatal crashes are not affected. Never compare totals or PDO counts across 2019-2020; use injury crashes (`explore/notes/crash_reporting.md`).
- Coordinate coverage jumps in 2017 and in 2024-11 (house-number crashes geocoded to address points from then); reported borough is blank for about a third of crashes in 2016-2023 (use the coordinates).
- `crash_time` is text H:MM; coordinates at 0,0 or outside NYC are NA after `crashes_read()`.
See: README "Crash locations"; `explore/notes/crash_reporting.md`.

## crash_persons
Coverage: 2012-07 on, but only injured and killed persons before 2016; every person involved from 2016.
One row: one person in a crash (driver, passenger, pedestrian, cyclist).
Keys: `COLLISION_ID` -> crashes `collision_id`; `VEHICLE_ID` -> crash_vehicles.
Issues:
- The 2016 change in who is recorded makes person counts (and uninjured shares) incomparable across 2016.
See: README "Sources".

## crash_vehicles
Coverage: 2012-07 on.
One row: one vehicle in a crash.
Keys: `COLLISION_ID` -> crashes; vehicle type codes -> `reference/NYC_vehicle_lookup_table.csv` (3,148 codes, classes incl. Bike, E-bike, Scooter).
Issues:
- Vehicle type coding changes in 2016; e-bikes appear from 2020 and NYPD's four-letter codes from 2026. Re-run `scripts/31_vehicle_lookup.R --write` after each new snapshot.
See: TODO "Crash vehicle types".

## Citi Bike trips
Sources: citibike_trips_2013_2019, citibike_trips_2020_on
Coverage: 2013-06 to the latest month, one parquet per month (`citibike_read("YYYY-MM")`, `citibike_open()` for all months).
One row: one Citi Bike trip in NYC (Jersey City excluded).
Keys: start/end station id (text) and lon/lat.
Issues:
- Rider demographics (`birth_year`, `gender`) only to 2019-12: the 2020-01..2021-01 originals with them are gone (only 2020-02 and -03 on the Wayback Machine).
- The 2018 archive holds April twice; the parquet keeps one copy (fixed 2026-10-24; outputs built before then counted April 2018 twice).
- Months are by file as Citi Bike publishes them: a trip starting late on the last day of a month can sit in the next month's file.
- E-bike trips from 2020 carry GPS coordinates of the dock, which vary slightly per trip: use the median per station.
See: README "Citi Bike".

## citibike_stations
Coverage: GBFS snapshots from 2026-10-14 (one per run of the snapshot script); 2019 snapshots.
One row: one station at the snapshot date.
Keys: `station_id`, lon/lat.
Issues:
- Before 2026, station locations come only from the trips (first and last trip per station).
See: `scripts/21_snapshot_citibike_stations.R`.

## traffic_counts
Coverage: 2000 to the latest snapshot, 15-minute automated traffic recorder (ATR) counts.
One row: one count location, direction and 15 minutes.
Keys: LION `SegmentID` (85% in the current LION, the rest in older releases: use `nyc_lion_for_date()`); x, y in EPSG 2263.
Issues:
- Not a panel: 89% of segments are counted in only one year (short campaigns of a week or two). Use as cross-sections or for within-location changes only.
See: README "Sources".

## Bicycle and pedestrian counters
Sources: bike_ped_counts, bike_ped_sensors
Coverage: DOT automated counters, 2012-08-31 to the snapshot (2026-10-11), 15 minutes (21.4M rows, 41 sensors with counts, checked 2026-10-13).
One row: one sensor, flow (direction) and 15 minutes; time in NYC local time.
Keys: sensor id; `segment_id` = nearest LION centerline.
Issues:
- `counter_id` is empty for 10% of rows, mostly two sensors whose device dates do not cover their data (Comprehensive Brooklyn Bridge Counter 2013-12..2022-03, 1st Avenue - 26th St N 2013-09..2018-04).
- Off-street sensors snap to a far centerline: Concrete Plant Park (165 ft), High Bridge (136 ft), Hunts Point Ave (89 ft); one sensor (Manhattan Bridge Interference Calibration 2018) has no coordinates.
- Level shifts at device swaps; delete-and-modify duplicates are dropped by the reader.
See: TODO "Bicycle and pedestrian counts".

## Air pollution
Sources: air_pollution_hourly, air_pollution_daily
Coverage: 2012 to the latest EPA release (revised about twice a year), NYC-area monitors (box around the five boroughs; `nyc` flags the city itself).
One row: one monitor (site, parameter, POC) and hour or day.
Keys: `site_id` (state-county-site), lon/lat (NAD83 or WGS84 per record, `datum`).
Issues:
- Ten parameters (ozone, NO2, NO/NOx/NOy, CO, SO2, PM2.5 FRM/FEM and non-FRM, PM10, wind, temperature); hourly PM10 has no monitor near NYC (0 rows).
- PM2.5 filter samplers (88101, one sample every three days) appear only in the daily files.
- The latest year is provisional until EPA's next revision.
See: README "Sources"; `scripts/41_air_pollution_nyc.R`.

## crz_entries
Coverage: 2025-01-05 (start of congestion pricing) to the snapshot (2026-10-17 in the 2026-10-25 snapshot).
One row: one 10-minute block, vehicle class and detection group (crossing into the congestion relief zone).
Keys: `Detection Group`, `Detection Region`; time as text MM/DD/YYYY HH:MM:SS AM.
Issues:
- Entries, not unique vehicles or revenue (no exemptions or repeat entries).
- Published on data.ny.gov as t6yz-b64h since 2026 (t2rz-wjj6 before).
See: README "Sources".

## lion
Coverage: 57 quarterly releases 2012a-2026c (12d and 22d not archived) plus the current snapshot.
One row: one LION record (street segment on a layer); `lion_read()` keeps street centerlines.
Keys: `SegmentID` (bike routes, traffic counts, relocated crashes), `NodeIDFrom`/`NodeIDTo` (intersections), `StreetCode`.
Issues:
- Segments are split, merged and redrawn between releases: use the release in force at a date (`nyc_lion_for_date()`) or the segment key in derived/streets.
- `RW_TYPE` is stored with a leading space; curved segments need linearizing; 15b is kept as a damaged download (`nyc_lion15b.corrupt_20200630.zip`).
See: README "LION"; streets/README.md.

## bike_routes
Coverage: DOT bike route snapshots 2025-10 and 2026-10; archives of 2017-2020 releases.
One row: one segment version (status Current/Retired, bikeid/prevbikeid).
Keys: `segmentid` = LION `SegmentID` (99%).
Issues:
- 13 empty geometries (dropped by the reader). For dated lane history use `bikelane_windows_read()`.
See: streets/README.md.

## address_points
Coverage: current snapshot.
One row: one building address point.
Keys: `b5sc` street code + house number.
See: README "Crash locations".

## Boundaries
Sources: boundaries_blocks, boundaries_boroughs, boundaries_community_districts, boundaries_ntas,
boundaries_precincts, boundaries_tracts, tract_nta, census_block_groups, bg_population
Coverage: 2020 census geographies; current administrative areas.
One row: one area.
Keys: `borocode`, `boro_cd`, `nta2020`, `geoid`/`boroct2020`, `bctcb2020`, `precinct`; block groups by `GEOID`.
Issues:
- 4 census blocks have invalid geometry (repaired by the reader). Block-group population JSON has the names in its first row.
See: README "Joining sources".

## Street layout snapshots
Sources: parking_signs, parking_meters, meter_blockfaces, meter_rate_zones, bus_lanes, speed_limits,
arterial_slow_zones, neighborhood_slow_zones, truck_routes, street_network_changes, speed_humps,
srts, lpi_signals, barnes_dance, open_streets, ped_plazas, ped_space_added, bike_parking,
bike_shelters, pavement_ratings, street_closures
Coverage: current state as published, snapshots from 2026-10-14 (SRTS and street closures also 2020-02).
One row: one sign, meter, segment, location or request, as published.
Keys: mostly LION `segmentid`, or street + from/to street; signs and meters as points.
Issues:
- Published as current state only: history exists only from the first snapshot, except fields with install dates (speed humps, LPI signals, bike racks, bus lane `year1`, signs `order_completed_on_date`) and street_network_changes (one-way conversions).
See: README "Sources" (street layout row).

## Historical count files
Sources: counts_bicycle_counters_20200204, counts_bicycle_counts_20200204,
counts_nycdcp_manhattan_bike_counts_off_street, counts_nycdcp_manhattan_bike_counts_on_street_weekday,
counts_traffic_volume_counts_2011_2012, counts_traffic_volume_counts_2012_2013,
counts_traffic_volume_counts_2014_2018, counts_vehicle_classification_counts_2011_2012,
counts_vehicle_classification_counts_2012_2013, counts_vehicle_classification_counts_2014_2018
Coverage: historical files, no longer updated.
One row: as published (counts per location and hour or day).
Issues:
- The 2020 bicycle counter file has 10 of 66 counters at 0,0. Superseded by bike_ped_counts and traffic_counts for current work.

## Bike lane history
Sources: bikelane_windows, bikelane_windows_dot2020, bikelane_windows_keyed, bike_lane_updates
Coverage: bike lane history of all boroughs from the DOT 2026 version history (the dot2020 build: DOT 2020 release plus Manhattan 2025 updates).
One row: one LION segment and time window with the facility per direction (Protected, Standard, Sharrows; NA no lane).
Keys: `SegmentID` (keyed: `key_id`).
See: streets/README.md "Bike-lane classification".

## Segment key
Sources: segment_key, segment_versions, segment_links, key_segments, lion_segment_releases
Coverage: LION releases 12a-26c.
One row: see the profile note; the key maps every SegmentID and geometry version to key segments (`key_id` = SegmentID in 26c).
Keys: `key_id`, `SegmentID`.
See: streets/README.md "Segment key".

## Street spells and lane panels
Sources: street_spells, streets_panel_manhattan, lion_lanes_panel, lion_lanes_panel_keyed,
manhattan_lanes_monthly, manhattan_lanes_monthly_keyed
Coverage: 2012 on (LION releases), Manhattan monthly lane panels dated with the bike lane changes.
One row: see the profile note.
Keys: `key_id` or `SegmentID`, and month or release.
See: streets/README.md "Street spells".
