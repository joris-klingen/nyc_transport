# streets/ — street network history

Curated history of the NYC street network 2012 to now: what each street segment looked like at each
date (bike lanes, travel lanes, and later bus lanes, parking, traffic rules, Citi Bike stations, ...),
with the evidence for each date. Used by `nyc_res_bikelanes` (treatment timing) and the gender &
cycling work. Part of the `nyc_transport` repo; was the separate repo `nyc_streets` until
2026-10-23 (merged with its history) and `nyc_bikelane_history` before 2026-10-14.

Raw data (LION releases, DOT bike routes, snapshots of the current-state layout sets) is downloaded
and read by the repo root (`R/nyc_transport.R`, `scripts/`); `streets/` adds what needs judgment: dating rules, manual review, and
evidence. Published layout data is often current state only, and its dates are imprecise: DOT's
bike lane install dates are often 1 January or the 1st of the month, are revised between releases,
and before 2025 did not record what a segment was *before* an upgrade. LION's lane counts were
recounted in 2024.

The outputs go to `data/derived/streets/` (found with `nyc_streets_data_root()`).
All scripts in `streets/` run from `streets/`: `cd streets; Rscript spine/01_lion_segments.R`.

## Simulated data

To develop code without the data, every output has a profile (`profiles/<source>.csv`,
`<source>_values.csv`, `index.csv`; same format as the repo-level profiles) and a simulator in `sim/`:

```r
source("sim/sim.R")              # from streets/; uses the repo's R/simulate.R
keys <- sim_key_segments(2000, boro = 1)
sp   <- sim_street_spells(keys)
panel <- streets_panel("2018-01-01", "2019-12-01", spells = sp, keys = keys)   # production code
w    <- sim_bikelane_windows(segment_ids = keys[, key_id])
```

The simulators keep the structure that code depends on: the key (every key segment has a
current version, some older versions and retired segments), spells that do not overlap and start
when LION has the attribute, bike lane windows that chain from 1899-01-01 to 2099-09-09, lane
panels over the real LION releases. `streets_panel()` and `streets_state()` take `spells =` and
`keys =`, so the panel logic runs unchanged on simulated spells. `profiles/build_profiles.R`
rebuilds the profiles.

## Layout

```
R/streets.R                      readers: streets_state(), streets_panel(), streets_spells_read(), streets_attributes(),
                                 key_segments_read(), segment_key_read(), segment_key_map(), segment_key_attach(),
                                 segment_versions_read(), bikelane_windows_keyed_read()
build/
  01_street_spells.R             all layers as spells on the key segments
                                 -> derived/streets/spells/street_spells.parquet, key_segments.parquet
spine/                           LION SegmentID across the 57 quarterly releases (12a-26c) -> segment key
  01_lion_segments.R             attributes of every LION record per release (no geometry)
                                 -> derived/streets/spine/lion_segment_releases.parquet
  02_segment_versions.R          one row per SegmentID x distinct geometry, first/last release
                                 -> derived/streets/spine/segment_versions.gpkg
  03_segment_key.R               links between versions (overlap, same id redrawn, LegacyID) chained to 26c
                                 -> derived/streets/spine/segment_links.parquet, segment_key.parquet
  checks_segment_key.R           unlinked versions, agreement with LegacyID, coverage of traffic counts / bike routes
layers/                          one folder per street attribute
  bike_lanes/
    manual/
      streetview_dot2020.csv       manual Street View checks on the DOT 2020 release (2,609 segments, all boroughs);
                                   before-upgrade type in tf_bef_mod / ft_bef_mod (class code I/II/III), blank = unchanged
      streetview_initial_2019.csv  first pass on the 2019 release (superseded by dot2020)
      rules.csv                    coding rules used during the checks
      lookup_bikelane_types.xlsx   facility text -> class (I protected, II conventional, III shared)
      exported_at.txt              time of the last export from the Google Sheet
      decisions.md                 dated coding decisions (buffered = protected, park drives, ...)
      streetview_review_answers.csv  answers from the review page (37 projects, 2026-10)
      review_export/               raw JSON export of the review page answers
      03_park_drive_dates.R        -> park_drive_dates.csv: Central Park drives car-free dates (2015-06 north of 72nd St, 2018-06 rest)
      04_build_overrides.R         -> protection_overrides.csv: segment-level protection dates from the review
                                   and park-drive dates (294 segments); applied in scripts/03_time_windows.R
      segmentid_crosswalk_lion16d.csv  DOT segments whose windows are copied to LION 16d SegmentIDs (18)
      aerial_capture_dates_manhattan.csv  flight dates of the Manhattan orthophotos
    scripts/
      01_export_manual_sheet.R     export the Google Sheet "Manual Streetview NYC Bikelanes" to manual/
      02_import_review_answers.py  review page export -> manual/streetview_review_answers.csv
      03_time_windows.R            build the segment x time-window facilities (Protected / Standard / Sharrows), all
                                   boroughs, from the DOT 2026 version history with the manual checks before 2020
                                   -> derived/streets/bike_lanes/bike_lanes_time_windows.RDS
                                   (the earlier DOT 2020 build: bike_lanes_time_windows_dot2020.RDS,
                                   bikelane_windows_read("dot2020"))
      04_key_windows.R             the windows on the segment key (tf/ft swapped where the key segment runs the
                                   other way) -> bike_lanes_windows_keyed.parquet, bikelane_windows_keyed_read()
    checks/                        quality checks from 2026-10 (DOT releases, pipeline vs DOT history, upgrade bug;
                                   06: the DOT 2026 build against the DOT 2020 build on the segment key)
  travel_lanes/                  travel-lane panel from 57 quarterly LION releases (citywide, Manhattan monthly);
                                 see its README
evidence/                        material used to date changes, shared by the layers
  pilot_aerial/                  blind test of dating lanes from orthophotos (30 segments); see its README
  aerial_labelling/              aerial labels for 124 Manhattan protected-lane projects, review list and the
                                 review page (review_app/); see its README
  dot_projects/                  DOT presentation catalogue, matched to the review projects, with timing
                                 sentences from the PDFs; see its README
```

### Segment key

LION SegmentIDs are stable: per release 0.1-0.7% are retired and 0.2-2% added, and ids are not
reused for other streets. Over 2012-2026, 196,722 ids have 228,389 geometry versions (27,275 ids
redrawn at least once). `spine/03_segment_key.R` links each version that ends to its successors in
the next release (line overlap within 10 ft, at least half of either line; else the same id with a
redrawn line, or a later segment naming it as LegacyID) and chains the links to 26c: 94.3% of ended
versions get a successor; the 2,711 that do not are mostly removed or rebuilt highways, ramps,
bridges, paths and driveways. `share` is the share of a version's length that continues as each
26c segment (a split spreads it, a street cut back keeps less than 1). With the key, 96.3% of the
DOT traffic count SegmentIDs and 99.5% of the DOT 2020 bike route ids reach a current segment (85%
and 95% match current LION directly). Spells for every layer are meant to be keyed on it.

```r
source("../nyc_transport_repo/R/nyc_transport.R")   # from a project; loads these readers too
segment_key_map(c(32886, 28), date = "2016-06-01")   # 1 Av segment 32886 is now three segments
```

### Street spells

`build/01_street_spells.R` puts every layer in one long table on the key segments: `key_id`,
`attribute`, `side` (both / tf / ft, relative to the key segment), `value`, `valid_from`, `valid_to`
(NA = still valid), `date_precision` (day / month / year / release / verified / undated / open),
`source`, `priority`, `source_id`, `key_cover`. `streets_attributes()` lists the attributes:

| attribute | from | source |
|---|---|---|
| `in_lion` | 2012-05 | segment key: the street exists in LION |
| `bike_lane` (tf, ft) | DOT install dates | `layers/bike_lanes` (Protected / Standard / Sharrows / none; NA = not in the DOT bike route data) |
| `travel_lanes` | 2012-07 Manhattan, 2016-02 elsewhere | dated Manhattan panel (priority), LION per release |
| `parking_lanes`, `total_lanes`, `street_width`, `traffic_dir` | 2016 (traffic_dir 2012) | LION per release |

`streets_state(date)` gives one row per key segment on a date (`geometry = TRUE` for sf lines),
`streets_panel(from, to, by)` a key segment x date panel; both filter by `boro` or `key_ids`, drop
segments not yet in LION, and resolve overlapping sources by priority, then key_cover. Manhattan
monthly 2012-2026 (2.6M rows) takes about 5 s.

```r
source("../nyc_transport_repo/R/nyc_transport.R")   # from a project; loads these readers too
s <- streets_state("2019-06-01", boro = 1, geometry = TRUE)
p <- streets_panel("2012-07-01", "2026-07-01", "month", attributes = c("bike_lane", "travel_lanes"), boro = 1)
```

New layers (bus lanes, parking, speed limits, ...) are added as a block in `build/01_street_spells.R`
on the key, with their attribute in `streets_attributes()`.

All scripts run from `streets/`. Outputs that other projects read go to
`derived/streets/<layer>/`; working files stay in the repo (`out/`).

### Review page

Street View date checks are entered on a private review page:
https://claude.ai/artifact/LNgqgjc1jKrH4Yf35vjX9i (share as Contributor so reviewers can save answers).
It shows per project the claimed dates, the aerial sheets, the matched DOT presentations and Street View links.
It is built by `evidence/aerial_labelling/review_app/build.py`, and the answers flow into `layers/bike_lanes/manual/` via
`layers/bike_lanes/scripts/02_import_review_answers.py` and `layers/bike_lanes/manual/04_build_overrides.R`.

The Google Sheet is the entry form; the CSVs in `layers/bike_lanes/manual/` are the source of truth for analysis.
After editing the sheet, re-export and commit so git records every change:

```bash
Rscript layers/bike_lanes/scripts/01_export_manual_sheet.R
```

The output is read in other projects (e.g. `nyc_res_bikelanes`) with `bikelane_windows_read()` from
`R/nyc_transport.R`. All bike lane classification and dating happens in `streets/`:

```bash
Rscript layers/bike_lanes/scripts/03_time_windows.R
```

Raw DOT releases live in the shared data store: `Dropbox/1_research/nyc_transport/data/raw/street_layout/bike_routes/`
(downloaded by `scripts/10_download_opendata.R` at the repo root).

## Classification

Class I (protected) includes buffered lanes (confirmed 2026-10-10); curbside lanes are class II.
Note: `rules.csv` from the original checks codes buffered as II; the lookup table, which the
pipeline uses, codes it as I.

## Roadmap

Open work is listed in [TODO.md](TODO.md).
