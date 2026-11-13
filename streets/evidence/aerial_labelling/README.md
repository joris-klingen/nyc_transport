# Direct aerial labelling of Manhattan protected-lane projects (2026-10-11)

Goal: check the claimed protection dates of the projects that drive the nyc_bikelanes treatment against orthophotos, and produce a short list for Street View checking.

## Steps

1. `01_projects.R`: define the projects.
   - Universe: north–south segments in the study zones that become protected between 2010-01 and 2025-08, according to the fixed pipeline or the DOT 2026 history.
   - Segments with the same street and claimed month that are contiguous (gaps under 300 m) form one project. This gives 1,206 segments in **124 projects**.
   - Outputs: `out/projects.csv` (location only), `out/project_claims.csv` (dates) and `out/project_segments.csv`.
2. `../pilot_aerial/02_fetch_images.py out/projects.csv out/sheets`: one contact sheet per project, with 2008–2024 photos (two-year intervals) of a 70 m square at the middle segment. The tile cache lives in `%LOCALAPPDATA%/nyc_aerial_cache`, outside Dropbox.
3. `out/labels.csv`: blind labels by Claude for each project and image year.
   - P = protected or buffered, C = conventional, N = no lane, ? = unreadable.
   - A trailing `?` means low confidence.
4. `02_compare.R`: compare the labels with the claims. Writes `out/comparison.csv`.
   - The aerial evidence is a window: protection appeared after the last firm N/C image and by the first firm P image.
   - Images are taken to be flown on 1 May. The NYS services describe them as "Spring <year>".
5. `03_review_list.R`: categorise the conflicts. Writes `out/review_list.csv`.

## Results

| Pipeline claim vs photos | Projects |
|---|---|
| Consistent | 50 |
| No protection seen (claim after the last readable image, or not visible) | 24 |
| Conflict: photo shows no lane after the claimed date | 15 |
| Conflict: protection visible before the claimed date | 16 |
| No claim / undecidable | 19 |

The review list (`out/review_list.csv`, 36 projects) has three groups:

- **19 "claim too early"** (157 segments). Examples: Avenue of the Americas, Columbus Av, Amsterdam Av, Hudson St, 11 Av, Lafayette St, Dyckman St.
- **9 "claim too late"** (101 segments). Examples: Central Park West, 1 Av, 8 Av, 2 Av, Varick St. Typically a buffered lane is visible before the date of the protected upgrade.
  - This depends on whether buffered counts as protected. It does in our lookup.
- **8 park drives** (35 segments). Painted bike lanes are visible in every year. The claimed dates (2012, 2018, 2019) are the car-free or auto-limited changes, which DOT codes as protected.
  - This is a **definition choice**, not a dating error, and it decides whether the Central Park drives switch treatment inside the panel.

## Caveat: this is a list to check, not a list of errors

The pilot showed my aerial reading errs late, never early. But at least one high-priority "claim too early" case looks like a problem with the method:
- M087 Columbus Av has a documented 2010 protected lane (77th–96th St).
- Its sheet shows a narrow street, so the 70 m frame may not cover the avenue's carriageway, or I misread it.

Only Street View-confirmed dates go into the manual overrides (`layers/bike_lanes/manual/`). The aerial labels are evidence, not ground truth.

## Outcome (2026-10-12)

- `04_review_material.R` and `05_review_sheets.py` redrew the sheets of the review projects with the segment lines marked. `06_checklist_html.py` built a local checklist, which the review page below replaced.
- All review projects (37) were checked in Street View time travel on the review page.
  - 21 got a reviewed date.
  - 4 keep the buffered-lane date (buffered counts as protected).
  - 2 were always protected and 2 never.
  - The 8 park drives follow the decision to date them at the car-free date (`layers/bike_lanes/manual/park_drive_dates.csv`).
- M087 Columbus Av was reviewed as protected from 2011-06. Its unpainted parking-protected lane is invisible in the photos, so this aerial flag was a false alarm.
- The answers are in `layers/bike_lanes/manual/streetview_review_answers.csv`. `layers/bike_lanes/manual/04_build_overrides.R` turns them into `layers/bike_lanes/manual/protection_overrides.csv` (294 segments). The decisions are recorded in `layers/bike_lanes/manual/decisions.md`.

## Review page

Published at https://claude.ai/artifact/LNgqgjc1jKrH4Yf35vjX9i (private; share with reviewers as Contributor so they can save answers).
Built by `review_app/build.py` from `out/review_checklist.csv` and `out/review_sheets/`. Answers are stored in the artifact database, collection `reviews`, one document per project (`protected_from` YYYY-MM or "none", `before_type`, `note`, `by`, `saved_at`). Claude exports them with the ArtifactData tool to `layers/bike_lanes/manual/review_export/`, and `layers/bike_lanes/scripts/02_import_review_answers.py` writes `layers/bike_lanes/manual/streetview_review_answers.csv`.
