# DOT project records

Cross-checks for the review projects from NYC DOT's own documentation.

| Script | Output |
|---|---|
| `01_catalogue.py` | `dot_project_catalogue.csv`: every presentation linked from DOT's project archive (`projects-2007.shtml` ... `projects-2025.shtml`, `current-projects.shtml`): 1,550 presentations of 851 projects, with the month presented |
| `02_match_review.py` | `review_matches.csv`: presentations naming a review project's street (with aliases), not in another borough, presented 4 years before to 2 years after the claimed date; `relevance` = street in the project title (2) + bike project (1) |
| `03_fetch_extract.py` | PDFs to `data/docs/dot_presentations/` (not in git); `presentation_timing.csv`: sentences combining an implementation word with a date |
| `04_review_evidence.py` | `review_evidence.json`: per review project, up to 8 presentations with their timing sentences, plus the 2014 report rows; embedded in the review page |

`dot_2014_report_install_years.csv`: install years of 12 Manhattan protected-lane corridors from NYC DOT (2014), *Protected Bicycle Lanes in NYC*, p. 5.

Matching is by street name, so crosstown projects that only touch an avenue also appear; the reviewer judges relevance. Planned dates in early presentations are often missed; post-implementation decks are the better evidence.
