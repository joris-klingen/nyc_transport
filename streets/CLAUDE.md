# streets/ — agent signpost

**Where you are.** The street network history part of the `nyc_transport` repo (see
[`../CLAUDE.md`](../CLAUDE.md)). It builds what each street segment looked like at each date (segment
key, spells, bike-lane and travel-lane panels) from raw LION and DOT releases, with manual review and
evidence. Outputs go to `data/derived/streets/`.

**Run scripts from `streets/`**, not the repo root: `Rscript spine/01_lion_segments.R`. Inside it,
`source("R/streets.R")` loads these readers (and the raw-data readers in `../R/nyc_transport.R`).

**Not to be confused with** `data/raw/street_layout/`, the *raw* current-state street
layout as published. This folder produces the *dated history*.

**Read this first.** [`README.md`](README.md): segment key, street spells, bike-lane classification,
the review page, layout. Catalog of outputs: [`../nyc_data_catalog.md`](../nyc_data_catalog.md).

**Rules.** Outputs in `derived/streets/` are rebuildable; working files stay here (`out/`). The CSVs in
`layers/bike_lanes/manual/` are the source of truth for manual checks. Work without the store via
`sim/` + `profiles/`; re-run `profiles/build_profiles.R` after rebuilding outputs.
