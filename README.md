# nyc_transport

Shared NYC transport data for the `nyc_res_*` research projects, in two parts:

- **Raw data and readers** (repo root): download and access code for TLC taxi and ride-hail trips,
  NYPD motor vehicle collisions, LION streets, address points, DOT bike routes, traffic and bicycle
  counts, Citi Bike trips, street layout snapshots, EPA air pollution monitors, congestion relief
  zone entries, and boundary layers (boroughs, community districts, NTAs, census tracts and blocks,
  precincts, taxi zones).
- **Street network history** ([`streets/`](streets/README.md)): what each street segment looked
  like at each date (segment key across LION releases, bike lanes, travel lanes, …), with the
  manual review and evidence behind the dates. Was the separate `nyc_streets` repo until 2026-10-23
  (merged with its history; this repo was `nyc_traffic`).

The data lives outside the repo, in one store: `nyc_transport_data/` (raw data under `raw/`, the
street network history under `derived/streets/`).

## Setup

Copy `config.example` to `config.local` (not tracked) and set `NYC_TRANSPORT_DATA` to the root of
the data store. An `NYC_TRANSPORT_DATA` environment variable takes precedence. In R, one file loads every reader,
including the street network history:

```r
source(Find(file.exists, c("../nyc_transport_repo/R/nyc_transport.R", "../nyc_transport/R/nyc_transport.R")))
# needs data.table, arrow, sf
```

Locally the repo is `nyc_transport_repo` and the data `nyc_transport_data`, next to the research
projects (`nyc_res_*_repo`); the `Find()` above tries both the local name and the plain GitHub name,
so a fresh clone works too. Scripts at the repo root run from the repo root; scripts in `streets/`
run from `streets/`.

## Simulated data (no data store)

To write and test code without the data (in a cloud session, for example), every source has a
profile and a simulator:

```r
source("sim/sim.R")              # from the repo root; ../nyc_transport_repo/sim/sim.R from a project
sim_list()                       # the simulators
cr  <- sim_crashes(5000, from = "2018-01-01", to = "2019-12-31")
per <- sim_crash_persons(cr)     # persons and vehicles linked to the simulated crashes
tt  <- sim_taxi_yellow(10000, month = "2019-06")
lion <- sim_lion()               # a connected Manhattan-like street grid
```

- `profiles/<source>.csv`: one row per column of what the reader returns (or of the raw file
  where there is no reader): kind (integer, numeric, character, Date, POSIXct, ITime, logical),
  class, NA share, distinct values, quantiles (min, 0.1%, 1%, 5%, 10%, 25%, median, 75%, 90%, 95%,
  99%, 99.9%, max), mean, sd, text lengths and an example. `<source>_values.csv`: the most common
  values of discrete columns with their shares, and grid cells of coordinate pairs.
  `index.csv`: one row per source with the reader, files, rows, sample, geometry and notes.
  Reference tables kept whole: `taxi_zone_lookup_full.csv`, `lion_releases_full.csv`,
  `bike_ped_sensors_full.csv`, station and count-location lists, TLC columns and types by year
  (`taxi_*_schema_by_year.csv`), hour-of-week shares of trips and counts.
- `sim/sim_<source>.R`: what the real data are (file, reader, grain, columns, quirks), what the
  simulation keeps and what it does not, and `sim_<source>()` returning a table with the reader's
  columns and types. Columns are drawn from their own distributions; the scripts restore the
  relations that matter (dropoff after pickup, totals that add up, persons and vehicles linked to
  crashes, Citi Bike trips between real stations, count time series with the real daily
  pattern). The data are made up: for code, never for results.
- `profiles/build_profiles.R` rebuilds the profiles from the store (about 20 minutes; `Rscript
  profiles/build_profiles.R crashes lion` for some sources).

The street network history has the same in `streets/` (`streets/profiles/`, `streets/sim/sim.R`).

## Sources

| Source | Coverage | Location / join key | CRS | Read with | Known issues |
|---|---|---|---|---|---|
| Yellow taxi | 2012-01 to latest month | `PULocationID`, `DOLocationID` (taxi zones) | - | `tlc_open("yellow")` | `airport_fee` is `Airport_fee` from 2023-02; `cbd_congestion_fee` from 2025-01, `request_source` from 2026-06; column types drift across years. 2012-2016 hold other trips than the legacy CSVs (`checks/yellow_legacy_parquet.R`): 2012-01, -02, -04, -05, 2013-04 and 2013-08 lack 0.4-2.0M trips each (up to 13%), 2014-08..12 have 10-98k more, 2015-2016 about 0.05% fewer; use `tlc_legacy_open()` for trip counts in those years |
| Green taxi | 2014-01 to latest | zone ids | - | `tlc_open("green")` | 2013-08..12 not published as parquet |
| FHVHV (Uber, Lyft, ...) | 2019-02 to latest | zone ids | - | `tlc_open("fhvhv")` | `trip_miles`, not `trip_distance`; `cbd_congestion_fee` from 2025-01 |
| FHV (other for-hire bases) | not in the store | zone ids | - | - | black car, livery and limousine trips; before 2019-02 also Uber and Lyft (the FHVHV files start then), so ride-hail trips 2015-2019-01 exist only here. No fares or distances; zones often missing before 2017. Download with `01_download_tlc.R` (type `fhv`) if needed |
| Yellow legacy CSV | 2012-01 to 2016-06 | pickup/dropoff lon/lat | 4326 | `tlc_legacy_open()` (parquet copy), `fread` | the same trips as the yellow parquet files of those months, plus coordinates; ~2.4% of pickups at 0,0 or outside NYC: filter with `nyc_in_bbox()` |
| Crashes | 2012-07 to latest | lon/lat; `crashes_relocate()` adds LION `segment_id`, `node_id` | 4326 | `crashes_read()`, `crashes_relocate()` | see [Crash locations](#crash-locations) |
| Crash persons, vehicles | 2012 to latest | `collision_id` | - | `fread(nyc_latest("persons"))` | |
| LION | 57 quarterly releases 2012a-2026c (12d, 22d not archived) + current snapshot | `SegmentID`, `NODEID`, `StreetCode` | 2263 | `lion_read()`, `nyc_lion_for_date()` | see [LION](#lion) |
| Address points | current | building point; `b5sc` street code | 4326 | `address_points_read()` | |
| DOT bike routes | snapshots 2025-10, 2026-10; archives 2017-2020 | `segmentid` = LION `SegmentID` (99%) | 4326 | `bike_routes_read()` | 13 empty geometries (dropped by the reader) |
| Automated traffic counts | 2000 to latest, 15 min | `SegmentID` (85% in current LION, rest in older releases) | 2263 (`WktGeom`) | `traffic_counts_read()` | |
| Bicycle/pedestrian counts | DOT counters | sensor `id` | 4326 | `fread(nyc_latest("bike_ped_counts"))` | 10 of 66 counters in the 2020 version sit at 0,0 |
| Citi Bike | 2013-06 to latest month | station lon/lat | 4326 | `citibike_read("2016-07")`, `citibike_open()` | rider demographics only to 2019-12 (see below); monthly parquet |
| Street layout (parking signs and meters, bus lanes, speed limits, slow zones, truck routes, speed humps and SRTS, LPI and Barnes dance signals, open streets, plazas, bike parking, pavement ratings, construction closures) | current state, dated snapshots from 2026-10-14 (SRTS, closures also 2020-02) | mostly LION `segmentid` or street + from/to street; signs and meters as points | 4326 | `nyc_latest("bus_lanes")` etc., names in `nyc_opendata` (`R/config.R`) | published as current state only: history exists only from the first snapshot, except fields with install dates (speed humps, LPI, bike racks, bus lane `year1`, signs `order_completed_on_date`) and `street_network_changes` (one-way conversions) |
| Citi Bike stations | GBFS snapshots from 2026-10-14; 2019 snapshots | station lon/lat | 4326 | `jsonlite::fromJSON(nyc_latest("citibike_stations"))` | before 2026: first and last trip per station in the trip data |
| Air pollution (EPA AQS) | 2012 to latest release (revised twice a year), hourly and daily | monitor `site_id` (state-county-site), lon/lat | 4326 (NAD83 or WGS84 per record, `datum`) | `air_pollution_read("42602", "hourly")` | national files kept as parquet (one per published zip); the NYC-area extract (box around the five boroughs, `nyc` flags them) is in `derived/air_pollution/`; PM2.5 filter samplers (`88101`, 1-in-3 days) appear only in the daily files |
| Boundaries | 2020 census geographies, current admin areas | polygons | 4326 on disk | `boundaries_read("tracts")` | 4 census blocks have invalid geometry (repaired by the reader) |
| Taxi zones | current; one numbering for all trip years (2012 on) | `LocationID` | 2263 | `taxi_zones_read()` | zones 264/265 are "unknown", no polygon. The point-in-polygon of the legacy pickup coordinates gives TLC's `PULocationID` for 99.9-100% of trips 2012-2016, the rest within about 1 ft of a boundary (`checks/taxi_zones.R`). The 2025-09 file has the same polygons but numbers 57 as 56 and 104/105 as 103 |
| Census block groups 2020 | TIGER/Line 2020, New York State; population per block group (Census API) | `GEOID` | 4269 | `census_block_groups_read()`, `nyc_latest("bg_population")` | population JSON has the names in its first row |
| Congestion relief zone entries (MTA) | 2025-01-05 to snapshot | detection group (crossing), 10-minute block | - | `fread(nyc_latest("crz_entries"))` | times as text MM/DD/YYYY HH:MM:SS AM |

Coverage is checked by `checks/store.R`.

## Joining sources

- **CRS.** Join and measure in NY State Plane Long Island feet, `nyc_crs` (EPSG 2263). All
  `*_read()` helpers that return sf use it; `nyc_points_sf(dt, "longitude", "latitude")` turns any
  lon/lat table into points in it (dropping rows without coordinates in NYC).
- **Streets.** LION `SegmentID` links LION, bike routes, traffic counts and relocated crashes;
  LION `NODEID` links intersection crashes. LION changes over time: use the release in force at
  the date (`nyc_lion_for_date()`), especially for older count stations.
- **Street names.** Match by street code (`b5sc`, borough + 5 digits), not by name:
  `nyc_street_codes()` maps normalized names, alternate and former names to codes.
- **Areas.** `sf::st_join(points, boundaries_read("ntas"))`; trips join to `taxi_zones_read()` by
  `LocationID`. Boundary keys: `borocode`, `boro_cd`, `nta2020`, `geoid`/`boroct2020` (tracts),
  `bctcb2020` (blocks), `precinct`. Tracts also carry `nta2020` and `cdta2020`.

```r
library(data.table); library(sf)
source("../nyc_transport_repo/R/nyc_transport.R")

cr  <- crashes_relocate(crashes_read())                   # best location per crash
pts <- nyc_points_sf(cr, "longitude_ap", "latitude_ap")   # sf points, EPSG 2263
pts <- st_join(pts, boundaries_read("ntas")["nta2020"])   # crashes by neighborhood

lion <- lion_read(nyc_lion_for_date("2019-06-01"), boro = 1)   # Manhattan streets in mid-2019
tc   <- traffic_counts_read()
tc   <- merge(tc, st_drop_geometry(lion)[, c("SegmentID", "Number_Travel_Lanes")], by = "SegmentID")

trips <- tlc_open("yellow", 2024) |> dplyr::count(PULocationID) |> dplyr::collect()
zones <- merge(taxi_zones_read(), trips, by.x = "LocationID", by.y = "PULocationID")
```

## Crash locations

`crashes_read()` harmonizes the snapshots: snake_case names, squished text, numeric coordinates
(the 2026-02 to 2026-05 snapshots write `40,717175` and pad text fields), coordinates at 0,0 or
outside NYC as NA, `crash_date` as IDate. It reads a parquet copy when
`scripts/30_crashes_parquet.R` has made one.

`crashes_relocate()` returns the best available location in `longitude_ap`, `latitude_ap`, with
`loc_method` saying where it comes from:

- `address point`, `nearest address point`: crashes reported at a house number (`off_street_name`,
  about 18% of crashes). Until October 2024 these were geocoded by interpolating along LION's
  address range; where LION pads a block's range to xx98 they pile toward the low-number end of the
  block, and about 10% land on another block. From November 2024 the published coordinates are
  already the building's address point. They are moved to the building's address point (about 95%
  match), projected orthogonally onto the LION centerline of the same street (`snap_ft`, median
  about 50 ft, `segment_id` of that centerline); median total move about 50 ft.
- `intersection node`: intersection crashes without coordinates (about 10% of them) get the LION
  node where the two streets meet, when that is unambiguous. Against crashes with coordinates:
  median error 2 ft with a borough, 99% within 150 ft (83% without a borough).
- `original`: everything else, including street-only crashes (mostly highways, placed along the
  highway; on surface streets at a node of the named street).

`node_id` is set for intersection crashes (the node filled in, or the one within 10 ft of the
original point). Coordinates are missing for 11.0% of crashes in the data and 6.1% after
`crashes_relocate()`.

## LION

`lion_read(file, boro, what = "centerline")` handles what reading LION by hand gets wrong: the
geodatabase sits at `lion/lion.gdb` inside the zip (`lion.gdb` in 2015b), curved segments must be
linearized (`type = 5`) for GEOS, `RW_TYPE` is stored with a leading space (`" 1"`), and
`what = "centerline"` keeps the street features (`FeatureTyp` 0, 6, A, C; not rail, shoreline or
boundaries) on the generic and both-roadbed layers (`RB_Layer` G, B), so a divided street is one line. `RW_TYPE` 1 is
a street, 2 a highway, 3 a bridge, 4 a tunnel, 9 a ramp. `lion_releases()` lists the quarterly
releases with their dates (a in February, b May, c August, d November).

## Citi Bike

`citibike_read("2016-07")` returns one month in one schema: `started_at`, `ended_at`,
`start/end_station_id`, `_name`, `_lat`, `_lng`, `member`, plus `bikeid`, `birth_year`, `gender`
up to 2019-12 and `ride_id`, `rideable_type` from 2020. Citi Bike published the old format with
rider demographics until 2021-01, but its 2024 repackaging converted all of 2020 to the new
format; the original 2020-01 to 2021-01 files are not in the store. The 2013 archive holds each
month twice (whole and split), and the 2018 archive holds April twice; the conversion uses one copy.

The store keeps one parquet per month in this schema (`raw/citibike/trips/citibike_tripdata_YYYY-MM.parquet`),
converted from the published zips by `scripts/20_download_citibike.R`, which deletes the zips afterwards
(they stay on S3). `citibike_open()` opens all months as one arrow dataset for queries across months.
Months are by file, as Citi Bike publishes them: a trip starting late on the last day of a month can sit
in the next month's file.

## Data layout

```
nyc_transport_data/           top level is by KIND: raw / derived / reference / docs, and _meta / _archive
  raw/                      every raw source, as published; never edited. Exception: Citi Bike trips and the
                            EPA AQS files are stored as parquet (converted on download; the zips can be
                            downloaded again)
    taxi/
      yellow/              yellow_tripdata_YYYY-MM.parquet   2012-01 onward
      green/               green_tripdata_YYYY-MM.parquet    2014-01 onward
      fhvhv/               fhvhv_tripdata_YYYY-MM.parquet    2019-02 onward
      yellow_csv_legacy/   yellow_tripdata_YYYY-MM.csv.gz    2012-01 to 2016-06, with pickup/dropoff
                                                             coordinates; no longer published this way, keep.
                                                             Gzipped 2026-10-25 (123 GB to 26 GB), byte-identical
                                                             once unzipped (md5 in _meta/yellow_csv_legacy_md5.csv);
                                                             fread() reads them directly
      zones/               taxi_zones_YYYYMMDD.zip (shapefile), taxi_zone_lookup_YYYYMMDD.csv;
                           taxi_zones_20250923.zip is the 2025 version used by nyc_res_bikelanes (same
                           polygons, but ids 56 and 103 duplicated where the trips use 57, 104, 105)
    crashes/               Motor_Vehicle_Collisions_-_{Crashes,Person,Vehicles}_YYYYMMDD.csv (dated snapshots)
                           NYPD_Motor_Vehicle_Collisions_YYYYMMDD.csv (pre-2020 version of the crash table)
    street_layout/         raw current-state street layout (renamed from streets/ 2026-10-23)
      lion/                quarterly releases nyc_lion12a.zip ... nyc_lion16d.zip, nyclion_17a.zip ...
                           nyclion_26c.zip; current snapshot nyclion_YYYYMMDD.zip;
                           nyc_lion15b.corrupt_20200630.zip (a damaged download, kept). Read the zips
                           directly with lion_gdb() / lion_read(); the extracted copies of 12a-15a, 16d
                           and 19d that used to sit here were deleted 2026-10-14
      address_points/      AddressPoint_YYYYMMDD.csv (one point per building address)
      bike_routes/         New York City Bike Routes_YYYYMMDD.geojson; DOT archive zips
                           Archived_nyc_bike_routes_2019.zip, _2020.zip (shapefile, csv, metadata; read
                           with /vsizip/), nyc-bike-routes.zip (2017 release), 20190110__NYCDOT_BICYCLE_NETWORK.zip
                           (the 2019 release as first published); nyc_bike_routes_2017.csv (despite the
                           name the 2019 release, 16,672 rows) and nyc_bike_routes_2017_v2020.csv (the
                           2020 release, 18,730 rows), used by the gender paper
      bus_lanes/           Bus_Lanes_Local_Streets_YYYYMMDD.geojson
      parking/             Parking_Regulation_Locations_and_Signs, Parking_Meters_Locations_and_Status (csv);
                           Parking_Meters_ParkNYC_Block_Faces, Parking_Meters_Citywide_Rate_Zones (geojson)
      traffic_rules/       VZV_Speed_Limits, VZV_Arterial_Slow_Zones, VZV_Neighborhood_Slow_Zones,
                           New_York_City_Truck_Routes (geojson); Street_Network_Changes_Historical.csv;
                           dot_VZV_Speed_Limits.zip and _20200626.csv (2020-06)
      calming/             VZV_Speed_Humps.geojson; Speed_Reducer_Tracking_System__SRTS_.csv (from 2020-02)
      signals/             VZV_Leading_Pedestrian_Interval_Signals, Exclusive_Pedestrian_Signal_Locations (csv)
      public_space/        Open_Streets_Locations, NYC_DOT_Pedestrian_Plazas (geojson); Pedestrian_Space_Added.csv
      bike_parking/        Bicycle_Parking, Bicycle_Parking_Shelters (csv)
      pavement/            Street_Pavement_Ratings.csv (geometry as WKT)
      closures/            Street_Closures_due_to_construction_activities_by_Block.csv (from 2020-02)
      other/               NYC_streets_shape.zip and NYC_Streets.csv (street centerline export, 2020-01)
    boundaries/            borough_boundaries, community_districts, nta_2020, census_tracts_2020,
                           census_blocks_2020, police_precincts (_YYYYMMDD.geojson);
                           census_tract_2020_to_nta_cdta_YYYYMMDD.csv
      census_block_groups_2020/ tl_2020_36_bg.* (TIGER/Line block groups, New York State) and
                           nyc_bg_population_2020_YYYYMMDD.json (P1_001N per block group); from nyc_res_cc
    congestion_pricing/    MTA_Congestion_Relief_Zone_Vehicle_Entries__Beginning_2025_YYYYMMDD.csv (data.ny.gov
                           t6yz-b64h, was t2rz-wjj6 until 2026; 10_download_opendata.R)
    traffic_counts/
      automated/           Automated_Traffic_Volume_Counts_YYYYMMDD.csv (DOT ATR counts)
      legacy/              DOT volume and vehicle classification counts 2011-2018, Midtown 2018
      bicycle/             Bicycle_and_Pedestrian_Counts(_Sensors)_YYYYMMDD.csv (DOT counters),
                           Bicycle_Count(er)s_20200204.csv (historical version), DCP Manhattan and
                           East River bridge counts
    citibike/
      trips/               citibike_tripdata_YYYY-MM.parquet, 2013-06 onward, one schema (citibike_read());
                           converted from the published YYYY-citibike-tripdata.zip (2013-2023) and
                           YYYYMM-citibike-tripdata.zip (2024 onward); rider demographics to 2019-12
      trips_monthly_original/ YYYYMM-citibike-tripdata(.csv).zip, 2014-01 to 2019-12: original monthly releases,
                           before Citi Bike repackaged them into yearly zips in 2024. Keep: original record
                           for the gender paper.
      stations/            station_information_YYYYMMDD.json (GBFS, from 2026-10-14);
                           citibikestationsNYC_YYYYMMDD_HHMM.json (2019)
    air_pollution/
      epa_aqs/
        hourly/            hourly_<param>_YYYY.parquet, national, 2012 onward: 44201 ozone, 42602 NO2, NONOxNOy,
                           42101 CO, 42401 SO2, 88101 PM2.5 FRM/FEM, 88502 PM2.5 non-FRM, 81102 PM10, WIND, TEMP
        daily/             daily_<param>_YYYY.parquet, same parameters (daily means, AQI)
        sites/             aqs_sites_YYYYMMDD.parquet, aqs_monitors_YYYYMMDD.parquet (site and monitor lists)
                           (each parquet is one published zip, columns as published, codes as text)
  derived/                  made from the raw data, can be rebuilt:
    crashes_parquet/       parquet copies of the crash snapshots (scripts/30_crashes_parquet.R)
    taxi_yellow_legacy/    yellow_tripdata_YYYY-MM.parquet: the legacy yellow CSVs in one schema (TLC parquet
                           names and codes, sorted by pickup; scripts/02_yellow_legacy_parquet.R, tlc_legacy_open())
    air_pollution/         {hourly,daily}_<param>.parquet: NYC-area monitors (scripts/41_air_pollution_nyc.R)
    streets/               street network history built in streets/ (see streets/README.md):
      spine/               segment key across the 57 LION releases (lion_segment_releases, segment_versions,
                           segment_links, segment_key)
      spells/              street_spells, key_segments
      bike_lanes/          bike lane time windows (dot2026, dot2020), keyed windows, 2025 DOT updates
      travel_lanes/        LION lane panel, Manhattan monthly lane panel (and keyed versions)
  reference/                lookup tables (hand/rule, not raw and not rebuilt from raw alone):
    NYC_vehicle_lookup_table.csv   vehicle type code -> class (Car, SUV, Taxi, Van, Truck, Bus,
                           Motorcycle, Scooter, Bike, Other, Unknown) for every code in the data; hand
                           (2020) or rule (scripts/31_vehicle_lookup.R); 2020 table as *.superseded_20261016.csv
  docs/                     non-data material:
    dot_presentations/     DOT project presentations and street design checklists (PDF), downloaded by
                           streets/evidence/dot_projects/03_fetch_extract.py
  _meta/                    download logs and manifests (one place):
                           opendata_download_log.csv, taxi_manifest.csv, taxi_download_log.csv,
                           citibike_manifest.csv, epa_aqs_manifest.csv (epa manifest: Last-Modified and
                           size per published zip; revised files kept as *.superseded_YYYYMMDD.parquet;
                           citibike manifest: size and months per published zip)
  _archive/                 superseded legacy from earlier project generations (5_NYC_bikelanes_raw/)
```

The street network history built in `streets/` (segment key, spells, bike lane windows, travel lane
panels) is in `derived/streets/` (a separate store, `nyc_streets_data`, from 2026-10-16 to
2026-10-23). `nyc_streets_data_root()` returns that folder; `bikelane_windows_read()` and the
readers in `streets/R/streets.R` read from it.

Everything under `raw/` is raw data as published, and never edited. Each file is kept once:
read zips directly (`/vsizip/`) instead of keeping unzipped copies (removed 2026-10-14). Snapshots of updating
datasets carry their download date. Files the
publisher replaced are kept as `*.superseded_YYYYMMDD.*`, damaged downloads as
`*.corrupt_YYYYMMDD.*`. Anything computed from the raw data goes to `derived/`.

## Scripts

Run from the repo root.

| Script | Purpose |
|---|---|
| `scripts/01_download_tlc.R` | New TLC months (and re-check the most recent ones), taxi zones; writes `_meta/taxi_manifest.csv` |
| `scripts/10_download_opendata.R` | New dated snapshots of the NYC Open Data sets listed in `nyc_opendata` (`R/config.R`: crashes, LION, bike routes, street layout sets, counts, boundaries, ...) when they were updated; a download identical to the latest snapshot is dropped; logs to `opendata_download_log.csv` |
| `scripts/21_snapshot_citibike_stations.R` | Citi Bike station list (GBFS) when it changed |
| `scripts/11_download_lion_releases.R` | Quarterly LION releases from the DCP archive |
| `scripts/20_download_citibike.R` | Citi Bike trip zips that are new or republished, converted to one parquet per month (zips deleted); writes `_meta/citibike_manifest.csv` |
| `scripts/40_download_epa_aqs.R` | EPA AQS hourly and daily files from 2012 that are new or revised, site and monitor lists, converted to parquet (zips deleted); writes `_meta/epa_aqs_manifest.csv` |
| `scripts/41_air_pollution_nyc.R` | NYC-area monitor extract per parameter in `derived/air_pollution/` |
| `scripts/30_crashes_parquet.R` | Parquet copies of the crash snapshots in `derived/crashes_parquet/` |
| `scripts/31_vehicle_lookup.R` | Classify vehicle type codes not yet in `reference/NYC_vehicle_lookup_table.csv` (review without `--write`); re-run after a new crash snapshot. E-bikes are Bike as in the 2020 hand-made table; e-scooters and standing scooters Scooter (since 2026-10-18); mopeds and motor scooters Motorcycle |

```bash
Rscript scripts/01_download_tlc.R yellow,green,fhvhv 3
Rscript scripts/10_download_opendata.R
Rscript scripts/20_download_citibike.R
Rscript scripts/21_snapshot_citibike_stations.R
Rscript scripts/30_crashes_parquet.R
Rscript scripts/40_download_epa_aqs.R
Rscript scripts/41_air_pollution_nyc.R
```

## Checks

| Script | Checks |
|---|---|
| `checks/store.R` | every dataset present and its age, failed downloads, TLC missing months and trip-count drops, zone ids, Citi Bike months, traffic count years, boundary feature counts and geometry validity |
| `checks/crash_geocoding.R <borough>` | position of house-number crashes along their block, original vs relocated (padded LION ranges: 25% of Brooklyn segments, 64% of Queens) |
| `checks/crash_locations.R` | missing crash coordinates, placement of intersection and street-only crashes, accuracy of the intersection nodes |

Each project keeps its own cleaning filters and spatial aggregation.
