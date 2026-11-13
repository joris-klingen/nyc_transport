# TODO

*Last updated 2026-10-14. Roughly in order of payoff for the bike lane paper (`nyc_bikelanes`, plan in `notes/paper_plan_v2.md`).*

## Profiles and simulated data

- [x] Profiles of the outputs in `profiles/` and simulators in `sim/` (2026-10-16); `streets_panel()` and `streets_state()` take `spells =` / `keys =`.
- [x] Outputs moved from `nyc_traffic_data/derived/streets/` to their own store `nyc_streets_data/` (2026-10-16).
- [ ] Re-run `profiles/build_profiles.R` after rebuilding the outputs.

## Segment key (`spine/`)

- [x] **Segment key built** (2026-10-14): 57 LION releases, versions, links and crosswalk to 26c; see README.
- [x] **Layer outputs keyed** (2026-10-14): `bike_lanes_windows_keyed.parquet` (19,886 key segments; 111 retired source ids dropped), `lion_lanes_panel_keyed.parquet` and `manhattan_lanes_monthly_keyed.parquet`, next to the unkeyed files (the paper pipeline still reads those).
- [ ] **Merged sources that disagree**: 29-40 of the 165 key segments with several bike lane sources differ in facility at a given date; 3,561 key segment-months in the Manhattan lane panel differ in lanes. Check whether `main_source` is the right pick there.
- [ ] **Move `nyc_bikelanes` to the keyed outputs** when the paper pipeline is next rebuilt (zone assignment and street panel on key_id).
- [x] **Spell schema** built (2026-10-14): `build/01_street_spells.R`, `streets_state()`, `streets_panel()`.
- [x] **Panel inspected** (2026-10-14, `build/checks_street_panel.R`, figures in `build/out/inspect/`). Network length grows smoothly; Manhattan bike lane maps and the lane-change map (1 Av, 2 Av, Columbus, Amsterdam, park drives) look right; on one-way streets 1% of bike lanes run against traffic only (direction swap works); Manhattan facilities agree with DOT 2026 on 87.8% of segments.
- [x] **Bike lanes outside Manhattan stop in 2020** (fixed 2026-10-14 by the DOT 2026 rebuild; was:) (the windows use the DOT 2020 release plus 2025 updates): citywide, about 5,000 key segments with a facility in DOT 2026 are not in the spells (Bronx 1,527, Queens 1,543, Brooklyn 999, Staten Island 389, Manhattan 481), and upgrades after 2020 are missing (Bronx 318 Standard -> Protected). Fixed by the DOT 2026 version-history item below; do this before any citywide use.
- [ ] **Buffered lanes**: 118 Manhattan segments are Protected in the spells and Standard in DOT 2026 because buffered counts as protected here (decision 2026-10-10); keep in mind when comparing with DOT figures.
- [ ] **Next layers on the spells**: bus lanes (`year1` install years), speed limits and slow zones, speed humps (install dates), parking signs (`order_completed_on_date`), Citi Bike stations (first/last trip), all from the snapshots in data/streets.
- [ ] **Street spells before the key network**: spells exist only for segments in 26c; streets removed since 2012 (2,711 retired versions) drop out of panels. Add them as their own key ids if a study needs them.
- [ ] **evidence_id** in the spells: link verified bike lane dates to the review project (proj_id) and DOT presentation.
- [ ] **Unlinked versions near the network**: 216 retired versions lie 30-100 ft and 153 lie 100-500 ft from a segment of the next release (realignments beyond the 10 ft buffer?). Check a sample on a map before relying on them.
- [ ] **LION before 12a**: 3% of the traffic count ids are in no release since 2012; the DCP archive has older releases if the counts before 2012 are needed.
- [ ] **Faster raw LION reads**: `lion_read()` / `lion_gdb()` in R/nyc_transport.R read the zip through /vsizip, which takes minutes for the 2012-2016 releases; unzipping to a local temp folder takes seconds.

## Protection dates

- [x] **Re-run the paper pipeline with the overrides** (2026-10-13). `101 → 303` re-run; old vs new treatment and TWFE in `nyc_bikelanes/scripts/checks/303_compare_treatment_overrides.R` (output in `output/checks/`). 80 of 120 zone-directions change in at least one month; estimates move little.
- [ ] **Remaining disagreements outside the review.** After the upgrade-bug fix, 69 study-period segments still differ from the DOT 2026 history by more than a year, and 133 are protected in only one source. The 37 reviewed projects cover part of this; list what is left (`layers/bike_lanes/checks/02_pipeline_vs_dot_history.R` on the new windows) and decide whether a second review round is needed.
- [ ] **27 segments moved earlier with the bug fix** (2016 → 1978), where the manual sheet codes the pre-upgrade type as protected. Check them against Street View or the aerial sheets.
- [x] **Overlapping time windows fixed** (2026-10-13, `layers/bike_lanes/scripts/03_time_windows.R`, which now stops if any remain). Not the 2025 retired records: (1) install dates before 1899 (old bridges) gave backwards first windows, now dropped; (2) 20 records with segment id 0 in the 2020 release, dropped; (3) two segments with two 2025 update records, chained (11 Av 33609: Sharrows 2022-02, Protected 2023-09); (4) crosswalk targets deduplicated, the copy replacing the target's own windows (36563: Protected from 2018-12 instead of DOT Standard from 2018-12-24). Study-period facilities change only for 33609 and 36563 (and segment 0).
- [x] **Re-run `nyc_bikelanes` 101 → 303** (2026-10-14, with the DOT 2026 windows, which include the overlap fix).
- [x] **Windows rebuilt from the DOT 2026 version history** (2026-10-14, `layers/bike_lanes/scripts/03_time_windows.R`): all boroughs, 28,426 versions on 24,778 segments, 364 lanes removed for good; manual checks replace the DOT history before 2019-12-20 (they differ from DOT 2026 at that date on 282 of 2,472 segments); 195 segments of the 2020 release that DOT 2026 dropped (rebuilt bridges, Brooklyn Bridge promenade) keep their 2020 facility up to then. Protected street-km citywide 509 (2020) -> 728 (2026-07). Against DOT 2026 the remaining differences are coding rules (buffered = I; Sidewalk / Unpaved in class I coded II; Signed Route and Wide Parking Lane no facility).
- [x] **`nyc_bikelanes` moved to the DOT 2026 windows** (2026-10-14; pinned as `bikelane_version` in its 000_project_init.R, 101 -> 303 re-run: 45 of 120 zone-directions change in some month, first protected month moves for 8, TWFE estimates move little, see its `scripts/checks/303_compare_treatment_overrides.R`). `bikelane_windows_read()` now returns them; `bikelane_windows_read("dot2020")` gives the windows the paper was built on. On the segment key (`checks/06_dot2026_vs_dot2020_windows.R`), 17.7% of Manhattan segment-months with a facility differ: segments updated in 2025 lost their earlier history in the old build (26k months), buffered lanes now described as such (Standard -> Protected, 23k), lanes the old build missed (E 61/62 St, Terrace Dr). First protected month: same for 3,034 key segments, moved for 106, only in the new build 423, only in the old 46.
- [ ] **Sidewalk and Unpaved in DOT class I** (746 key segments Standard here, Protected in DOT 2026; Staten Island greenways): check whether these should count as protected.
- [ ] **Date precision flag** per segment: exact day / month only (1st of month) / year only (1 January) / verified (Street View or aerial). Needed for the robustness check that drops or shifts imprecise dates.
- [ ] **3 Av (M029):** reviewed as first seen 2026-04, with nothing visible up to 2024-09. Record the window (after 2024-09, by 2026-04) rather than a point date.

## Travel-lane panel (`layers/travel_lanes/`)

- [ ] **Apply the park-drive car-free dates to the lane panel.** West/East Drive go from 2 to 1 lane; date these at 2015-06 (north of 72nd St) and 2018-06 (rest), as in `layers/bike_lanes/manual/park_drive_dates.csv`.
- [ ] **Resolve the lane review list** (`layers/travel_lanes/out/lane_review.csv`: 869 segments on 89 streets; largest 1 Av, 2 Av, Columbus Av, 9 Av, Amsterdam Av).
  1. Use the DOT deck statements ("remove one travel lane …", `evidence/dot_projects/presentation_timing.csv` and the full PDFs) to confirm lane removals and their dates.
  2. Add a lane-count question to the review page for what remains; aerial photos show the lane markings.
- [ ] **447 segments with a protected lane from 2012-07 to 2016-02.** LION's first lane count (2016) may already be post-project; take the pre-project count from DOT decks ("Before: four moving lanes") or the aerial photos.
- [ ] **Aggregate the monthly lane panel to zone-directions** for the paper's mechanism analysis (lanes removed vs kept).

## DOT records (`evidence/dot_projects/`)

- [ ] **3 presentation PDFs return 404** (L Train CB6 decks 2018, Kent Ave). Look for them in the Wayback Machine.
- [ ] **Reduce noise in the matching:** crosstown projects that only touch an avenue are matched to it. Match on cross-street ranges as well as the street name.
- [ ] **Extend beyond the 37 review projects** if a second review round happens.

## Aerial imagery

- [ ] **Capture dates for other boroughs** (NYC OTI metadata lists per-borough dates for 2004–2014) if the work goes citywide.
- [ ] **Classifier** (parked 2026-10-11): PyTorch CPU is installed in `C:/code/nyc_aerial_venv`. Worth building only for citywide coverage. Design notes are in `evidence/aerial_labelling/README.md` and `evidence/pilot_aerial/README.md`: an obscured class; flight dates; labels by facility type; the 124 labelled projects plus the pilot as test set.
- [ ] **Unpainted parking-protected lanes are a blind spot** of the aerial reading (Columbus Av, M087). A classifier needs labelled examples of them.
