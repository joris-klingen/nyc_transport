# nyc_transport — agent signpost

**What this is.** The one shared NYC repo under every `nyc_res_*` project. It downloads and reads
all raw NYC data, and builds the street network history, into one store: `data/`.

- Repo root: download scripts (`scripts/`), readers (`R/`), profiles + simulators (`profiles/`,
  `sim/`), store checks (`checks/`). Run from the repo root.
- [`streets/`](streets/README.md): the curated street network history (segment key, spells, bike-lane
  and travel-lane panels, manual review, evidence). Writes `derived/streets/` in the store. Run its
  scripts from `streets/`.

**Read this first.** [`README.md`](README.md) (sources, joins, CRS, crash geocoding, LION, data layout)
and [`streets/README.md`](streets/README.md) (segment key, spells, bike-lane classification).

**Find a dataset and how to read it.** [`nyc_data_catalog.md`](nyc_data_catalog.md): every dataset in
the store with the exact reader call, coverage, keys, known issues (breaks, gaps) and columns. Read its
known issues before counting anything. Generated from the profiles and the hand-written
[`dataset_notes.md`](dataset_notes.md): edit the notes, then `Rscript scripts/50_build_catalog.R`.

**Big picture.** [`../NYC_DATA.md`](../NYC_DATA.md).

**To use the readers** (one file loads all of them, street history included):
```r
source(Find(file.exists, c("../nyc_transport_repo/R/nyc_transport.R", "../nyc_transport/R/nyc_transport.R")))
```

**Rules.** Everything under `raw/` in the store is as published and never edited (Citi Bike trips and
EPA AQS files are stored as parquet, converted on download); snapshots keep their
download date; computed outputs go to `derived/`. Work without the store via `sim/` + `profiles/`
(and `streets/sim/`). The store is local only (not on GitHub). Store root: `NYC_TRANSPORT_DATA` in
`config.local`.

**R style.** data.table, `dt[, col]` bracket syntax, `# Section ----` headers. Never run R inline
(`Rscript -e`); write a script file and run it with `Rscript`.

## The data store is inside this repo

Since 2026-11-12 the store is `data/` in this folder (it was the separate folder `nyc_transport_data`). It is
ignored by git and holds `raw/`, `derived/`, `reference/`, `docs/`, `_meta/`, `_archive/`; its own
signpost is `data/README.md`. The readers find it there by default; the environment variable or
`config.local` only override the place.

**Never run `git clean -x` (or `-X`) here, and never delete or move anything under `data/`.** Git
does not know these files, so nothing brings them back. Everything under `data/raw/` is as published;
part of it cannot be downloaded again.
