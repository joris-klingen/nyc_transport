# Open datasets we do not hold (living list)

Started 2026-11-04 with the review in `data_review_2026-11-04.md`. One row per source: what it is,
where, coverage, the location key it joins on, size, which project or idea wants it, and what to do.
Ids are NYC Open Data (`data.cityofnewyork.us/d/<id>`) unless marked NY (`data.ny.gov/d/<id>`).
Coverage and update dates were read from the portals' metadata on 2026-11-04; "unverified" marks
what was not checked. Add to this list when a paper, a review or an idea names a source; strike a
row when the source is in the store and the catalog.

How the literature uses data (222 abstracts in `../../literature/`, checked 2026-11-04): the
competing NYC papers run on the sources the store already holds (TLC trips, NYPD crashes, Citi Bike,
LION, DOT counts), plus controls we lack (weather beyond temperature, elevation, ACS demographics,
land use) and proprietary speeds and platform data (Google Maps segment speeds in Cook et al. 2025,
Uber and Lyft internal data, Strava Metro). No cited paper uses DOT link speeds, bus speeds, parking
or camera tickets, 311 or signal data; those are additions the literature has not exploited.

## Tier 1: small, cheap, wanted now

| Source | Where | Coverage, cadence | Location key | Size | For | Action |
|---|---|---|---|---|---|---|
| NYS DMV crash cases, vehicles, individuals, violations | NY `e8ky-4vqe`, `xe9x-a24f`, `ir4y-sesj`, `abfj-y7uq` ("Four Year Window") | 2021-2024, annual (updated 2026-01-22); rolling window, older years drop off; ITSMR TSSR unreachable on 2026-11-04 | county, municipality, DOT reference marker (no coordinates) | 1.5M cases | crash-reporting idea (the police vs motorist benchmark, see `crash_reporting.md`); bikelanes and cc across the 2019-2020 PDO break | add to `nyc_opendata` with `domain = "data.ny.gov"`, dir `crashes_dmv`; snapshot now and after each annual update |
| Hourly weather, ASOS | Iowa Environmental Mesonet, network NY_ASOS (`cgi-bin/request/asos.py`); stations NYC (Central Park), LGA, JFK | from the 1940s, live; 1-minute data from 2000 | station | a few MB a station-decade | tips (rain is the standard control: Farber 2015, Lee and Sohn 2020), effort (heat), bikelanes (cycling demand), cc | `raw/weather/asos/`, one script from 2012 for the three stations; reader `weather_read(station, freq)`; the effort project's `030_weather.R` is the template |
| Elevation | USGS 3DEP 1/3 arc-second tiles n41w074, n41w075 (already on `C:/data/usgs_dem`, 660 MB, no Dropbox copy); NYC 1 ft DEM `dpc8-z3jc` (2010 lidar, 3.3 GB zipped); NYS 2017 topobathymetric lidar (`elevation.its.ny.gov`, 1 ft and 1 m services) | static | raster | 0.7-3 GB | effort (grade is in every e-bike study cited), bikelanes (detour cost) | `raw/elevation/usgs_3dep/` with the tiles, the NYC clip in `derived/elevation/`; segment grade as a street layer (`streets/`) |
| ACS 5-year tables | Census API / table-based summary files: B19013 income, B08301 commute mode (bicycle share), B25044 vehicles, B01003 population, by tract and block group; latest 2020-2024 (released 2026-01-29) | annual | GEOID | small | bikelanes (equity heterogeneity as in Moran et al. 2026), effort (welfare by income, already built locally), tips | `raw/boundaries/acs/`; the effort project's `012_acs_income.R` is the template (keyless summary files) |
| LEHD LODES 8.4 | `lehd.ces.census.gov/data/lodes/LODES8/` | 2002-2023 | 2020 census block | small | trip generation controls | with the ACS tables |
| DOT street improvement projects (Vision Zero View) | intersections `shr7-eqdc`, corridors `if4c-w48d` (maps `79sh-heg3`, `wqhs-q6wd`) | 2009-2026 (`sip_year`, `end_date`), monthly | point / multiline | 430 + 1,021 rows | bikelanes and `streets/` (dated redesigns citywide; the manual dating covers 37 projects) | add to `nyc_opendata` (snapshots) |
| Other Vision Zero layers with dates | turn traffic calming `hz4p-9f7s` (`completion`), bike priority areas `ii5c-g6sq`, priority corridors `36nr-7fbp`, intersections `2nj7-jxah`, zones `n4hs-fahn`, Safe Streets for Seniors `bsuh-ywiw`, enhanced crossings `bssx-36gg`; signal and all-way-stop study requests `w76s-c5u4` (77k rows, `signalinstalldate` 1997-2026, no coordinates) | monthly | geometry; street + cross street | small | streets layers, bikelanes | add to `nyc_opendata`; the store already has LPI, Barnes dance, speed humps, SRTS, slow zones, speed limits |
| TLC industry indicators | `v6kb-cqej` (2019-01 to 2026-09, monthly, by licence class: trips, farebox, unique drivers and vehicles, hours per vehicle per day); the longer `data_reports_monthly.csv` on nyc.gov/tlc (start date unverified) | monthly | industry | tiny | dispatch idea (utilisation per cab), tips (driver counts by year) | add to `nyc_opendata`; keep the csv as a dated snapshot |
| TLC vehicle and driver lists | medallion vehicles `rhe8-mgbb`, medallion drivers `jb3k-j3gp`, FHV vehicles `8wbx-tsch`, FHV drivers `xjfq-wh2d`, FHV base aggregate report `2v9c-2k7f`; medallion transfer prices (nyc.gov/tlc, monthly PDF 2012-2014 then xlsx to 2026-09) | daily snapshots, no history | plate, licence | small | dispatch idea (fleet size, medallion values) | snapshot monthly from now (history is lost otherwise) |
| Yellow taxi 2009-2011 | TLC CloudFront parquet (yellow from 2009-01) | 36 months | taxi zone (TLC's republished files) | about 3 GB | tips (with the FOIL 2010-2011 zips already in the store, a four-year driver panel: Donovan and Work 2016, Farber 2015, Mosquera 2024) | set `tlc_start["yellow"]` to 2009-01; convert `foil_2010_2013/FOIL2010.zip`, `FOIL2011.zip` with `07_foil_donovan_parquet.R` |
| Citi Bike operating reports and prices | citibikenyc.com/system-data/operating-reports (monthly PDF 2013-06 to 2026-09, 2026-05 missing); citibikenyc.com/pricechange | monthly | system | small | effort (members, rebalancing; the price history as a tracked input file, effort todo) | `docs/citibike_reports/`; the price steps to `inputs/price_changes.csv` in the effort repo |

## Tier 2: congestion pricing outcomes and speeds (cc, cctips, future cc work)

| Source | Where | Coverage, cadence | Location key | Size | For | Action |
|---|---|---|---|---|---|---|
| MTA bus speeds | route by month `cudb-vcni` (NY, 2015 to 2026-09); route segment `58t6-89vi` (2023-2024) and `kufs-yh3x` (2025 on); CBD bus speeds `r6db-kkzj` (2023 on) | monthly, updated 2026-10-23 | route, direction, timepoint stop with lat/lon | 0.1M + 22M + 0.7M rows | cc (the bus outcome Cook et al. and the MTA use), cctips | add to `nyc_opendata` (`domain = "data.ny.gov"`) |
| MTA CBD indicators | taxi and FHV speeds in the CBD `6p29-6xqn` (2019-10 to 2025-08), CBD trips `d3qp-nhf8` (2019-05 on), taxi and FHV miles `2iid-6be2`, VMT in the CBD `jbxx-kxff` (2024 on), regional transit ridership `sv2g-g4mz` (2021 on), CBD taxi zones `yfdc-w5jh`, geofence `srxy-5nxn` | monthly | zone, CBD flag | small | cc (a cross-check of the trip-file estimates against the MTA's own series) | add to `nyc_opendata` |
| MTA ridership | subway hourly `wujg-7c2s` (2020-2024, static) and `5wq4-mkjj` (2025 on, 47M rows); bus hourly `kv7t-n8in` (2020-09 to 2024-12, 362M rows) and `gxb3-akrn` (2025 on, 171M rows, route only); daily ridership and traffic `sayj-mze2` (2020-03 on, replaces `vxuj-8kew`); turnstile archives per year 2014-2022 (`i55r-43gk` ... `k7j9-jnct`) | weekly / daily | station complex with lat/lon; bus route | large for bus hourly | cc and cctips (mode shift), dispatch idea | subway hourly and daily first; bus hourly only with a SoQL filter; convert to parquet (re-downloadable, queried a lot) |
| MTA bridges and tunnels crossings | hourly `ebfx-2m7v` (2019 on, 13.8M rows, vehicle class, payment); the deprecated `qzve-kjga` (2010 to 2025-04, 2.4M rows) | weekly | facility, direction | medium | cc (volumes entering Manhattan) | download `qzve-kjga` before it disappears; `ebfx-2m7v` as snapshots |
| Port Authority crossings | PDFs `panynj.gov/.../traffic-e-zpass-usage-YYYY.pdf` (2011-2025, monthly eastbound by crossing); NY `5uvq-7ebw` is stale at 2015; PA crashes by facility `n4ys-au5c` (2000 on) | annual PDF | crossing | tiny | cc | `docs/panynj/`, a small table extracted by hand |
| DOT link speeds | Traffic Speeds NBE `i4gi-tjb9` (TRANSCOM links, 2017-07 on, 104M rows, several updates a minute; highways and arterials); EZ-Pass reader local-street speeds (Midtown in Motion), yearly `s7y8-dkgd` (2021) ... `6a2s-2t65` (2026), live `ume6-8kxp` | continuous | link id, polyline | 10+ GB as CSV | cc, tips (a speed measure independent of the taxis), taxi-bike idea (sub-zone speeds), crash-reporting idea (clearance) | only when a project needs it: filter on download (SoQL by date), parquet |
| ATR counts, static version | `btm5-ppia` (2012-2021) | static | LION `segmentid` | | nothing new (the store has `7ym2-wayt`) | none |

## Tier 3: enforcement, curb and nuisance (bikelanes mechanism, cc, dispatch idea)

| Source | Where | Coverage, cadence | Location key | Size | For | Action |
|---|---|---|---|---|---|---|
| Bus lane camera violations (ACE) | NY `kh8p-hcbm` | 2019-10 to 2026-10, monthly | violation lat/lon, bus stop, route | 7.2M rows | cc (bus lane enforcement), bikelanes (double parking) | add to `nyc_opendata` |
| Parking violations issued, by fiscal year | FY2014 `jt7v-77mi` ... FY2027 `pvqr-7yc4` (one id per year; FY2023 id not retrieved) | about 10M tickets a year, monthly | street name, house number, cross street, street codes, precinct | 130M rows in all | bikelanes (tickets in bike lanes as a blocked-lane measure; check the violation code list in the DOF dictionary), cc (curb use), speed cameras (code 36 school-zone speed tickets are the only public trace of camera sites; DOT does not publish locations) | download by year with a code filter; Manhattan first |
| Open parking and camera violations | `nc67-uf89` | 2016-05 on, 85M rows, weekly | precinct and county only | large | enforcement totals | lower priority than the fiscal-year files (no street) |
| Moving violation summonses | `bme5-7ty4` (2018-2025, 5.6M rows, lat/lon, violation code, vehicle category), `57p3-pdcj` (year to date); precinct monthly `f6an-2v46` (to 2024-10) | historic + quarterly | lat/lon, precinct | medium | crash-reporting idea (does enforcement change when police stop attending crashes), cc | add to `nyc_opendata` |
| 311 service requests | `erm2-nwe9` (now 2020 on), `76ig-c548` (2010-2019, 22.6M rows, static) | daily | lat/lon, address, cross streets, BBL | very large | blocked bike lane, illegal parking, traffic signal and street condition complaints | SoQL by complaint type only |
| Street construction permits | `tqtj-sjs8` (2022 on; issue dates back to 1999 in the data), `c9sj-fmsg` (2013-2021) | daily | on, from and to street, WKT geometry (no SegmentID) | 4M rows | bikelanes and cc (traffic shocks), taxi-bike idea | add to `nyc_opendata`; `ipu4-2q9a` is DOB permits, not DOT |

## Tier 4: context and controls

| Source | Where | Coverage, cadence | Location key | Size | For | Action |
|---|---|---|---|---|---|---|
| PLUTO / MapPLUTO | `64uk-42ks` (26v2, 2026-08-24), MapPLUTO and its archive to 2002 on nyc.gov/planning (archive page unverified) | three times a year | BBL, tract, block | 0.9M lots | land use and density controls (Moran et al. 2026, Wang and Akar 2019) | one snapshot a year in `raw/land_use/` |
| Citywide Mobility Survey | 2017 `dd6w-hnq9`; 2018 `jpcp-ic7c` (unverified); 2019 household `a5rk-jemi`, trip `w9dc-u4ik`, day `x5ra-hhdw`, vehicle `jxs5-ygaz`; 2022 person `7qdz-u9hr`, household `dt3g-khpi`, trip `x5mc-2gmi`, day `5njs-bq3c`, vehicle `qyry-gwrj`; 2024 person `i2im-iqtt`, household `5mb3-padx`, trip `wgnh-qwsg`, day `naav-ygga`, vehicle `qhkz-4dqm`; zones `sx7h-iavd` | biennial (no 2023) | survey zone | small | effort and bikelanes (mode choice, attitudes, cyclist demographics) | add to `nyc_opendata` as `surveys/` |
| NYCCAS air pollution | rasters `q68s-8qxv` (annual 2008-2019, 300 m: NO2, PM2.5, BC, NO, summer O3, winter SO2); neighbourhood table `c3uy-2p5r` (2005-2024) | annual | raster / UHF42, community district | small | pollution context beyond the EPA monitors | add if a pollution project returns |
| Non-high-volume FHV trips 2015-2019 | TLC CloudFront (`fhv_tripdata`, still published, to 2026-08) | monthly | zone (often missing before 2017); no fares | tens of GB | dispatch idea (ride-hail before 2019-02), cc | `01_download_tlc.R` type `fhv`, 2015-01 to 2019-01 only |
| Other cities | Chicago taxi trips (City of Chicago portal; Conlisk 2020), Capital Bikeshare and Bluebikes trip feeds (Weschke 2026 design), London TfL (already used in `ozone_cycling`) | | | | second-city checks for tips and effort | out of the NYC store's scope; note only |

## Not available or not open

- Speed camera and red light camera sites: DOT does not publish them (discovery API finds nothing); infer from DOF tickets, violation codes 36 (school-zone speed), 5 (bus lane camera), 7 (red light). The `nyc_res_cc` stub `109_import_speed_cameras.R` cannot be filled as written.
- Link speeds from NPMRDS, INRIX, HERE: licence only (IEEE NTDAS subscription or a RITIS data-sharing agreement); Google Maps speeds as in Cook et al. 2025: proprietary.
- Uber Movement (2016-2020): retired 2023, no mirror found on Dataverse, Zenodo, Kaggle or GitHub.
- Strava Metro (cyclist flows by street and gender; Battiston et al. 2023, Garber et al. 2023): licence.
- Uber and Lyft platform data (arrival estimates, telematics, driver earnings): proprietary.
- CRZ revenue, exemptions, crossing credits: not published as data (MTA board PDFs only).
- Signal locations and timing: no point layer; the signal study requests `w76s-c5u4` carry install dates by street pair.
- DMV crash years before 2021: off the portal; ITSMR's TSSR site was unreachable on 2026-11-04.
- Subway hourly ridership before 2020: turnstile files only (2014-2022 per-year archives on data.ny.gov; 2010-2013 not found); bus hourly has no stop.
- Citi Bike 2020-01 to 2021-01 originals with rider demographics: gone (see `TODO.md`).
- Retired ids to avoid: `vxuj-8kew` (daily ridership, now `sayj-mze2`), `qzve-kjga` (bridges and tunnels, now `ebfx-2m7v`), `t2rz-wjj6` (CRZ entries, now `t6yz-b64h`), `web.mta.info/developers/turnstile.html` (redirects to `wujg-7c2s`).

## Already in the store, mentioned for completeness

Automated traffic counts `7ym2-wayt` (LION `segmentid`), LPI signals `xc4v-ntf4` and Barnes dance
`8kuj-2n3u` (install dates), speed humps `jknp-skuy`, SRTS, slow zones, speed limits, bus lanes,
CRZ entries `t6yz-b64h`, the Kaggle station status archive (`raw/citibike/stock_panel`, to be
documented), FOIL 2010-2013 zips (2012-2013 converted).
