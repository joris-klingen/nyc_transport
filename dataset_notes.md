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
