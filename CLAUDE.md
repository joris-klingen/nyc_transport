# nyc_transport — agent signpost

**What this is.** The one shared NYC repo under every `nyc_res_*` project. It downloads and reads
all raw NYC data, and builds the street network history, into one store: `../nyc_transport_data/`.

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
