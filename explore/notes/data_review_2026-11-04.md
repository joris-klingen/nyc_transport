# Review of the NYC data repo, the store and the projects (2026-11-04)

Second look at `nyc_transport_repo` and `data/` after the 2026-10-24 audit
(`crash_reporting.md`, `idea_*.md`): how the five research projects read the store, where the
store lags the portals, what is undocumented, and which open datasets the literature uses that we
do not hold. Facts checked on 2026-11-04 unless dated otherwise. The candidate datasets are kept
as a living list in `dataset_candidates.md`.

## 1. What works

- One repo, one store, one entry point. `nyc_res_bikelanes`, `nyc_res_cc`, `nyc_res_tips` and
  `nyc_res_cctips` all source `R/nyc_transport.R` through the same `Find(file.exists, ...)` line;
  `nyc_res_effort` carries a frozen copy (`R/shared_readers.R`, commit a0dddbe, 2026-10-27) so its
  replication package needs no second repository. The catalog, profiles and simulators make the
  store legible without the data.
- No project writes into the store. A grep of every project script for writes or downloads under
  `nyc_data_root()`, `tlc_data_dir()`, `citibike_dir()` or `streets_dir()` finds none. The one
  script that would (`nyc_res_cc/scripts/data_import/109_import_speed_cameras.R`, see 3d) is a
  stub that never ran.
- Snapshots are pinned where the analysis is final: bikelanes pins crashes, persons, taxi zones,
  traffic counts and `bikelane_version`; cc pins crashes, CRZ entries and `taxi_last_month`;
  tips imports by year list and no longer reads crashes (the crash IV was retired); cctips reads
  tips' `data/intermediate` read-only; effort pins its months and sample seed.

| Project | Reads from the store | Own inputs outside the store |
|---|---|---|
| bikelanes | yellow + FHVHV trips, crashes + persons + vehicle lookup, LION 16d, ATR counts, DCP counts, Citi Bike trips, bike-lane windows, Manhattan lane panel, CRZ entries (one welfare check) | study-area and zone definitions in `references/` |
| cc | yellow/green/FHVHV 2021 to 2026-03, crashes, block groups + population, CRZ entries | own copy of the taxi zone shapefile, Cook et al. figures (`data/external`) |
| tips | yellow 2012 on, legacy yellow with coordinates, FOIL 2012-2013 driver ids, FHVHV, taxi zones, LION for the within-road filter | none |
| cctips | taxi zones; everything else via tips' intermediates | none |
| effort | Citi Bike trips 2021 on, station status archive (`raw/citibike/stock_panel`), GBFS station list, boroughs, block groups, LION releases, segment versions | ASOS Central Park weather (Iowa Mesonet), USGS 3DEP 10 m DEM tiles (`C:/data/usgs_dem`, outside Dropbox), station elevations (Open-Topo-Data / EPQS API), ACS B19013 income, e-bike price history |

## 2. The store lags the portals

Checked against the portals' metadata on 2026-11-04. One command refreshes everything below
(`Rscript scripts/00_update.R`, 30-90 minutes); the last run was 2026-10-26 and added only a
station snapshot.

Done on 2026-11-04 (run `20261104_1713`, 105 minutes with `--profiles`): every row below is now in
the store as the "On the portal" column says; crashes, persons and vehicles `20261104` are complete
to 2026-10-31. Vehicles and CRZ entries were reset mid-download and re-run alone; profiles, catalog
and `checks/store.R` rebuilt afterwards. Moving the bikelanes crash pin to 20261104 was tried the same
evening and reverted: the snapshot is in a new NYPD format (hashed ids; `off_street_name` and
`cross_street_name` swapped, so `crashes_relocate()` moves nothing; cyclists recoded from 2025; see
`dataset_notes.md`), and the re-run moved 396 of 1,649 paper values. Restoring the pin showed a second
problem: the refresh had rebuilt the vehicle lookup from the new snapshot alone, dropping the four-letter
codes of the old one (1,785 crashes unclassified); `31_vehicle_lookup.R` keeps every code since 2026-11-05.
The re-run that verifies the fix was stopped on 2026-11-05 after 17 of 37 scripts (all reproduced the
paper's outputs; the bikelanes output folders were restored from a copy taken before the re-pin; the
remaining scripts are its todo item 21). The reader change comes first (`TODO.md`).

| Source | In the store | On the portal | Note |
|---|---|---|---|
| Crashes, persons, vehicles | snapshot 2026-10-10, last crash 2026-06-11, June only a third full (2,322 crashes) | rows updated 2026-11-03, complete to 2026-10-31 (June 7,451, July to October 6,900-7,400 a month) | NYPD resumed publishing. The "stopped publishing" lines in `dataset_notes.md`, `NYC_DATA.md` and the catalog are out of date; after the refresh re-run `31_vehicle_lookup.R --write`, move the bikelanes crash pin (its todo items 7 and 20) |
| TLC yellow, green, FHVHV | to 2026-08 | 2026-09 published (2026-10 not yet) | tips wants the latest months before submission |
| CRZ entries | snapshot 2026-10-25 (to 2026-10-17) | rows updated 2026-10-29 | |
| Bicycle and pedestrian counts | 2026-10-11 | rows updated 2026-11-03 | |
| Citi Bike trips | to 2026-09 | 2026-10 not yet on S3 | |
| ATR counts, bike routes, LION | 2026-10 | last changed 2026-03, 2026-07, 2026-11-02 (LION view only) | nothing to do |

Still open from `TODO.md`: schedule the refresh (monthly, after TLC publishes) and an offline copy
of the 471 irreplaceable files (37.7 GB; Dropbox is the only second copy).

## 3. Undocumented and loose ends

**a. The station status archive is invisible to the repo.** `raw/citibike/stock_panel/`
(11 yearly parquets, 21 GB, Kaggle `rosenthal/citi-bike-stations`, CC BY 4.0: every station every
2 minutes 2016-2026, e-bikes from 2019-08) is the input to the effort paper's main sample, but it
appears nowhere in the transport repo: not in the README layout, `dataset_notes.md`, the catalog,
`profiles/index.csv`, `checks/store.R`, `_meta/` (no manifest; the download was by hand with a
Kaggle token) or the readers. Only `nyc_res_effort/scripts/data_management/050_station_status.R`
and its `REPLICATION.md` describe it (schema, the legacy `station_id` in 2022-23, report lag of
about 10 minutes in 2022, gaps 2023-07-19/20, 2024-07-24..26, 2025-10-20). To add: a README line
and a `dataset_notes.md` block, a reader (`citibike_status_files(year)`), a profile and
simulator, a presence check in `checks/store.R`, and a manifest with sizes and md5 in `_meta/`.

**b. Shared-purpose inputs that live in one project.** The effort paper built four inputs that
every other project could use, all outside the store: hourly weather (ASOS KNYC 2021-2026, 3 MB,
`nyc_res_effort/data/raw`), the two USGS 3DEP tiles (660 MB, `C:/data/usgs_dem`, no Dropbox copy)
and their NYC clip (`data/derived/dem/nyc_dem10.tif`, 119 MB), station elevations from the
Open-Topo-Data and EPQS APIs, and ACS block-group income (B19013, 18 MB). Weather is the obvious
one: rain is the standard control in the tipping literature and the demand shifter for cycling,
and the store has only EPA monitor temperature and wind. Proposal: `raw/weather/asos/` (KNYC,
KLGA, KJFK from 2012, one download script), `raw/elevation/usgs_3dep/` with the clip in
`derived/`, `raw/boundaries/acs/` (B19013, B08301 commute mode, by tract and block group), each
with a reader and a catalog entry. The effort repo keeps its own copies (frozen for replication),
so this is additive.

**c. The DMV benchmark is not in the store.** The crash-reporting diagnosis pulled the NYS DMV
crash cases (data.ny.gov `e8ky-4vqe`) into `output/explore/dmv/`. The dataset is a rolling
three-year window, so the years we compared (2021-2024) will disappear from the portal; take dated
snapshots now (`raw/crashes_dmv/`, via `nyc_opendata` with `domain = "data.ny.gov"`) and add the
individual and vehicle files. This is the one input the crash-reporting idea cannot do without.

**d. The speed camera stub.** `nyc_res_cc/.../109_import_speed_cameras.R` has
`CAMERA_URL <- 'TBD'`, would create `raw/street_layout/speed_cameras/` from a project (against
the store rule) and was never run; the dataset it wants was never located. Either add the
source to `nyc_opendata` (see `dataset_candidates.md`, enforcement) or delete the stub.

**e. Stale text.** `nyc_res_cc/README.md` still gives store paths without `raw/`
(`taxi/{yellow,...}`, `crashes/`, `congestion_pricing/`) and the retired CRZ id `t2rz-wjj6`; the
code is right (commit f7e64b7). `NYC_DATA.md`, `dataset_notes.md` and the catalog say the crash
feed stopped in June 2026 (see 2).

**f. Files in the store without a catalog entry.** `traffic_counts/bicycle/NYCDOT_Bicycle_Counts_2017-_East_River_Bridges.zip`,
`traffic_counts/legacy/Midtown_Counts_Total_Volume_-_12H_-_2018...xlsx`,
`street_layout/other/NYC_Streets.csv` (2020-01) and `traffic_rules/dot_VZV_Speed_Limits_20200626`
are listed in the README layout only. The East River bridge counts are the one that matters (cycling
exposure for the bike lane paper, and the only long bicycle series besides the DOT counters).

**g. Branches.** `nyc_res_bikelanes` is on `sim-appendix`, 10 commits ahead of `main` and not on
GitHub (the todo says "merge after review"); `nyc_res_cc` `main` is one commit behind
`wip_polish_cooc` (the citation fix of 2026-10-28); `nyc_res_effort` `price-steps` and
`paper-rewrite` are fully merged into `master` and can go; `nyc_res_tips` has 14 uncommitted files
from the table work of 2026-11-04; the transport repo carries the untracked `explore/14-20` ozone
scripts and three idea notes on purpose.

**h. The literature library lags the bibs.** `literature/` was built on 2026-10-28 from the bibs.
Since then the tips introduction was rewritten (2026-11-03) and its bib has 15 academic keys with no
abstract: `akturk2022logistics`, `almas2020cutthroat`, `almas2026fairness`, `anderson2008failures`,
`andre2025shallow`, `cappelen2007pluralism`, `cappelen2013luck`, `charness2007intention`,
`conlisk2021crises`, `fuller1987measurement`, `gauriot2019fooled`, `jenter2015turnover`,
`kausel2019outcome`, `mosquera2024stuck`, `taylor1994waiting` (the rest are data references). cctips
lacks `mohsin2026faster` (verified real on 2026-10-28). The bikelanes and cc files skip 110 and 128
keys by design (legacy entries of the shared bibs). Four bikelanes references are still marked
"check" in `notes/literature_update.md` (Dai 2025, Goodman 2014, Strauss, Bhatia and Wier).

**i. Layers waiting in the store.** `streets/TODO.md` lists the next layers for the street spells
(bus lane `year1`, speed limits and slow zones, speed hump install dates, parking sign order dates,
Citi Bike station first and last trip). The inputs are all in `raw/street_layout/`; nothing is
missing, only the build.

## 4. Datasets we do not hold

See `dataset_candidates.md` for the full list with ids, coverage and the project each serves.
Summary of the check (literature files in `literature/`, the submission strategy of 2026-11-02, the
idea notes, and the portals on 2026-11-04):

- **The literature does not expose a hole in the base.** The competing NYC papers (Cook et al. 2025,
  Zhang et al. 2026, Moran et al. 2026, the tipping papers) run on the sources the store holds. What
  they add and we lack are controls: weather beyond temperature (rain, snow, humidity, sunlight:
  Devaraj and Patel 2017, Lee and Sohn 2020, Farber 2015), elevation (every e-bike and route-choice
  paper cited), ACS demographics by tract or block group (Moran et al., Berke et al. 2024) and land
  use. Their speed measures are proprietary (Google Maps segment speeds, Uber and Lyft data, Strava
  Metro), which we cannot replace, but open substitutes exist that none of them used: DOT link
  speeds (`i4gi-tjb9`, 2017 on), EZ-Pass reader speeds on local streets (2021 on) and MTA bus speeds
  (2015 on, segment level from 2023).
- **Two cheap extensions of what we have.** TLC publishes yellow trips from 2009-01 (the store
  starts 2012-01), and the FOIL 2010-2011 zips are already in the store: together a four-year
  driver panel for the tips paper. The DMV crash cases are a rolling four-year window on
  data.ny.gov; the years the crash-reporting diagnosis used (2021-2024) will roll off.
- **Datasets the portals hold that no cited paper uses**, which fit the open questions: DOT's dated
  street improvement projects and turn-calming layers (`shr7-eqdc`, `if4c-w48d`, `hz4p-9f7s`; the
  citywide version of the manual bike-lane dating), geocoded bus lane camera tickets (`kh8p-hcbm`,
  7M, 2019 on), parking tickets with street and house number by fiscal year (blocked bike lanes;
  also the only trace of speed camera sites, which DOT does not publish), record-level moving
  violation summonses with coordinates (2018 on), MTA CBD indicators and ridership series, and TLC's
  industry indicators (trips, farebox, unique drivers and vehicles per day, 2019 on) for the
  dispatch idea.
- **Not obtainable**: speed camera locations, Uber Movement (retired, no mirror), NPMRDS or INRIX
  (licence), Strava Metro, CRZ revenue and exemptions, signal timing, DMV years before 2021, Citi
  Bike 2020 originals with demographics.

Ordered by payoff per hour: DMV snapshots and ASOS weather (an afternoon, used by three projects and
one idea), the Vision Zero project layers and TLC indicators (rows in `nyc_opendata`), elevation and
ACS (move what the effort project built), yellow 2009-2011; then the MTA bus speed and ridership
series when the congestion pricing paper is next revised.

## 5. What the ideas need

- **Crash reporting policy** (`idea_crash_reporting.md`): DMV case snapshots (3c), the TLC speed
  panel (in hand), and the live crash feed now that it runs again. Nothing else to buy.
- **Ride-hail apps dispatching taxis** (`idea_dispatch.md`): TLC's aggregate monthly indicators
  (trips, unique vehicles and drivers, farebox per day by industry) turn zone-hour counts into
  utilisation per cab, which the trip files cannot give; medallion and FHV licence lists date the
  fleet. Both are on the TLC site and NYC Open Data (candidates list, TLC block).
- **Taxi-bike substitution** (`explore/taxi_bike`, shelved 2026-10-28): the zone-hour-date speed
  panel and the crash-to-zone join are reusable; an instrument finer than the taxi zone would need
  DOT link speeds (candidates list, speed block).
- **Effort follow-ups**: the station status archive is in the store (3a); the price history should
  become a tracked input file (effort todo); the DEM clip belongs in the store (3b).
- **Bike lanes**: DOT's dated street-improvement projects (candidates list, Vision Zero block) would
  extend the manual dating citywide; parking violations in bike lanes measure blocked lanes; the East
  River bridge counts (3f) and the DOT counters give exposure.
- **Congestion pricing**: bus speeds, subway and bus ridership, bridge and tunnel crossings and DOT
  link speeds are the outcomes the competing evaluations use (candidates list, speed and transit
  blocks); the store has only the CRZ entries and the trip files.
- **Tips**: hourly rain (3b) for the standard weather control; the 2025 months for the full sample
  are in the store; `request_source` from 2026-06 lets app-dispatched yellow trips be split out.

## 6. Actions, in order

1. Done 2026-11-04: store refreshed, profiles and catalog rebuilt, the "stopped publishing" lines
   replaced. `crashes_read()` adapted to the new format on 2026-11-05. Still open: move the
   bikelanes crash pin once the cyclist recoding is understood (its todo items 7 and 20 say what
   was found).
2. Document the station status archive (3a).
3. Snapshot the DMV crash cases before the window rolls (3c).
4. Weather, elevation and ACS into the store with readers (3b), reusing the effort scripts.
5. Decide the speed camera stub (3d); fix the cc README paths (3e).
6. Offline copy of the irreplaceable files; schedule the monthly refresh.
7. Push `sim-appendix`, fast-forward cc `main`, delete the merged effort branches (3g).
8. Refresh `literature/tips.md` and `cctips.md` (3h).
9. Download the top candidates in `dataset_candidates.md`.
