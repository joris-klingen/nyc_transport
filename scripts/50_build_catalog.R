# Build the NYC data catalog ----
#
# Merges the two profile indexes (profiles/index.csv for the raw and derived sources,
# streets/profiles/index.csv for the street network history in derived/streets) and the
# hand-written dataset_notes.md into one catalog that lists every dataset in nyc_transport_data:
# the exact call to read it, coverage, what one row is, keys, known issues and its columns (from the
# column profiles). Writes nyc_data_catalog.csv (machine-readable, one row per dataset) and
# nyc_data_catalog.md (the manual every README and CLAUDE.md points to). File paths are relative to
# the store root.
#
# Run from the repo root:  Rscript scripts/50_build_catalog.R
# Re-run after rebuilding either set of profiles or editing dataset_notes.md.

library(data.table)

# Read the two indexes ----
main_index    <- "profiles/index.csv"
streets_index <- "streets/profiles/index.csv"
if (!file.exists(main_index) || !file.exists(streets_index))
  stop("run from the nyc_transport repo root: ", normalizePath("."))

read_index <- function(path, section) {
  dt <- fread(path)
  dt[, `:=`(section = section, profile_dir = dirname(path))]
  dt[]
}

cat_dt <- rbindlist(list(
  read_index(main_index,    "raw and derived"),
  read_index(streets_index, "street network history (derived/streets)")
), use.names = TRUE, fill = TRUE)

# Hand-written notes ----
# "## name" starts a block for source `name`, or for the sources on its "Sources:" line (a group
# title); "Field: value" lines; "- " lines belong to Issues
read_notes <- function(path = "dataset_notes.md") {
  l <- readLines(path, encoding = "UTF-8")
  out <- list(); cur <- NULL; field <- NULL
  add <- function(src, f, v) for (s in src) out[[s]][[f]] <<- c(out[[s]][[f]], v)
  for (x in l) {
    if (grepl("^## ", x)) {
      cur <- trimws(sub("^## ", "", x)); field <- NULL
    } else if (!is.null(cur) && grepl("^Sources:", x)) {
      cur <- character(); field <- "Sources"
      cur <- c(cur, trimws(gsub("`", "", strsplit(sub("^Sources:", "", x), ",")[[1]])))
    } else if (identical(field, "Sources") && grepl("^[a-z]", x)) {
      # the list wraps onto the next lines
      cur <- c(cur, trimws(gsub("`", "", strsplit(x, ",")[[1]])))
    } else if (!is.null(cur) && grepl("^(Coverage|One row|Keys|Issues|See):", x)) {
      field <- sub(":.*", "", x)
      v <- trimws(sub("^[^:]*:", "", x))
      if (nzchar(v)) add(cur, field, v)
    } else if (!is.null(cur) && identical(field, "Issues") && grepl("^- ", x)) {
      add(cur, "Issues", sub("^- ", "", x))
    }
  }
  out
}
notes <- read_notes()
unknown <- setdiff(names(notes), cat_dt[, source])
if (length(unknown)) warning("dataset_notes.md names sources without a profile: ", paste(unknown, collapse = ", "))
note <- function(s, f) notes[[s]][[f]]
cat_dt[, coverage := vapply(source, function(s) paste(note(s, "Coverage"), collapse = " "), character(1))]
cat_dt[, one_row  := vapply(source, function(s) paste(note(s, "One row"), collapse = " "), character(1))]
cat_dt[, keys     := vapply(source, function(s) paste(note(s, "Keys"), collapse = " "), character(1))]
cat_dt[, issues   := vapply(source, function(s) paste(note(s, "Issues"), collapse = " | "), character(1))]
cat(sum(cat_dt[, coverage != ""]), "of", nrow(cat_dt), "datasets have notes\n")

keep <- c("section", "source", "reader", "files", "rows_total", "geometry", "crs", "coverage", "one_row", "keys", "issues", "notes")
setorder(cat_dt, section, source)

# Machine-readable catalog ----
fwrite(cat_dt[, ..keep], "nyc_data_catalog.csv")

# Markdown catalog ----
md_escape <- function(x) gsub("|", "\\|", as.character(x), fixed = TRUE)
fmt_rows  <- function(x) ifelse(is.na(x) | x == "", "", format(as.numeric(x), big.mark = ",", scientific = FALSE, trim = TRUE))
anchor    <- function(s) paste0("#", gsub("[^a-z0-9_-]", "", tolower(s)))
short     <- function(x, n = 70) ifelse(nchar(x) > n, paste0(substr(x, 1, n - 3), "..."), x)

# columns of a dataset from its column profile: a table, or only the names when there are many
column_lines <- function(src, dir, rows_profiled, sample) {
  f <- file.path(dir, paste0(src, ".csv"))
  if (!file.exists(f)) return(character())
  p <- fread(f, colClasses = "character")
  if (!"column" %in% names(p)) return(character())
  # .cell:lon:lat rows are the profiler's own grid cells, not columns of the data
  p <- p[!startsWith(column, ".")]
  head_line <- sprintf("**Columns** (%d; profiled on %s):", nrow(p),
                       if (!is.na(sample) && nzchar(sample)) sample else paste(fmt_rows(rows_profiled), "rows"))
  if (nrow(p) > 40) return(c(head_line, "", paste0("`", p[, column], "`", collapse = " "), ""))
  # profiles of all-text or spatial data lack some columns
  pc <- function(v) if (v %in% names(p)) { x <- p[[v]]; x[is.na(x)] <- ""; x } else rep("", nrow(p))
  na <- suppressWarnings(as.numeric(pc("na_share")))
  rng <- ifelse(nzchar(pc("min")) & nzchar(pc("max")), paste(pc("min"), "to", pc("max")),
                ifelse(nzchar(pc("example")), paste0("e.g. ", pc("example")), ""))
  nd <- suppressWarnings(as.numeric(pc("n_distinct")))
  c(head_line, "",
    "| column | type | NA | distinct | range / example |",
    "|---|---|---|---|---|",
    sprintf("| `%s` | %s | %s | %s | %s |", md_escape(p[, column]), pc("class"),
            ifelse(is.na(na) | na == 0, "", ifelse(na < 0.001, "<0.1%", paste0(round(100 * na, 1), "%"))), fmt_rows(nd), md_escape(short(rng))),
    "")
}

lines <- c(
  "# NYC data catalog",
  "",
  paste0("_Generated by `nyc_transport_repo/scripts/50_build_catalog.R` on ", Sys.Date(),
         " from the profiles and `dataset_notes.md`. Do not edit by hand: edit `dataset_notes.md`",
         " (coverage, keys, known issues) or rebuild the profiles, then re-run._"),
  "",
  "Every dataset in `nyc_transport_data/`: how to read it, what one row is, coverage, keys, the",
  "breaks and gaps to know before using it, and its columns. Paths are relative to the store root.",
  "One source() loads every reader, including the street network history:",
  "",
  "```r",
  "source(Find(file.exists, c(\"../nyc_transport_repo/R/nyc_transport.R\", \"../nyc_transport/R/nyc_transport.R\")))",
  "```",
  "",
  "Read **Known issues** before using a dataset for counts or trends: several sources have breaks",
  "that look like real changes (crash reporting from 2019, yellow taxi trips 2012-2016 and from 2026-06,",
  "crash persons before 2016). Columns come from a random sample (see each dataset), so ranges and",
  "NA shares are approximate.",
  "",
  "## Overview",
  ""
)
for (sec in unique(cat_dt[, section])) {
  d <- cat_dt[section == sec]
  lines <- c(lines, paste0("### ", sec, " (", nrow(d), " datasets)"), "",
             "| source | read with | rows | coverage |", "|---|---|---|---|",
             sprintf("| [`%s`](%s) | `%s` | %s | %s |", d[, source], anchor(d[, source]), md_escape(d[, reader]),
                     fmt_rows(d[, rows_total]), md_escape(short(d[, coverage], 90))), "")
}

lines <- c(lines, "## Datasets", "")
for (i in seq_len(nrow(cat_dt))) {
  d <- cat_dt[i]; s <- d[, source]
  field <- function(label, v) if (length(v) && any(nzchar(v))) c(paste0("**", label, "**: ", paste(v, collapse = " ")), "") else character()
  iss <- note(s, "Issues")
  lines <- c(lines,
    paste0("### ", s), "",
    paste0("`", d[, reader], "`  "),
    paste0("Files: `", d[, files], "`  "),
    paste0("Rows: ", fmt_rows(d[, rows_total]),
           if (!is.na(d[, geometry]) && nzchar(d[, geometry])) paste0("; geometry ", d[, geometry], if (!is.na(d[, crs]) && nzchar(as.character(d[, crs]))) paste0(", EPSG ", d[, crs])), ""),
    "",
    field("Coverage", note(s, "Coverage")),
    field("One row", note(s, "One row")),
    field("Keys", note(s, "Keys")),
    if (length(iss)) c("**Known issues**:", "", paste0("- ", iss), "") else character(),
    if (!is.na(d[, notes]) && nzchar(d[, notes])) c(paste0("Profile note: ", d[, notes]), "") else character(),
    column_lines(s, d[, profile_dir], d[, rows_profiled], d[, sample]),
    field("See", note(s, "See")))
}

writeLines(lines, "nyc_data_catalog.md", useBytes = TRUE)

cat("wrote nyc_data_catalog.csv and nyc_data_catalog.md:",
    nrow(cat_dt), "datasets in", length(unique(cat_dt[, section])), "sections,", length(lines), "lines\n")
