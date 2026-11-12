# Download quarterly LION releases (DCP BYTES of the Big Apple archive) into data/raw/street_layout/lion
#
# Usage (from repo root):  Rscript scripts/11_download_lion_releases.R [first] [last]
#   first, last  release labels, default 17a and the newest published (probed up to 29d)
#
# Files are saved as nyclion_<release>.zip. Releases 12a-16d were downloaded earlier as
# nyc_lion<release>.zip (older DCP naming); existing files are skipped. A release that is not
# published returns HTTP 404 and is skipped.

source("R/config.R")

# the archive uses nyclion_<release>.zip for recent releases and nyc_lion<release>.zip for older ones
url_base <- c("https://s-media.nyc.gov/agencies/dcp/assets/files/zip/data-tools/bytes/lion/nyclion_%s.zip",
              "https://s-media.nyc.gov/agencies/dcp/assets/files/zip/data-tools/bytes/lion/nyc_lion%s.zip")
out_dir <- file.path(nyc_data_root(), "raw", "street_layout", "lion")
options(timeout = 3600)

args <- commandArgs(trailingOnly = TRUE)
releases <- as.vector(outer(letters[1:4], 12:29, function(q, y) paste0(y, q)))
releases <- releases[order(as.integer(substr(releases, 1, 2)), substr(releases, 3, 3))]
first <- if (length(args) >= 1) args[1] else "17a"
last <- if (length(args) >= 2) args[2] else "29d"
releases <- releases[match(first, releases):match(last, releases)]

# Download ----
for (r in releases) {
  dest <- file.path(out_dir, sprintf("nyclion_%s.zip", r))
  old <- file.path(out_dir, sprintf("nyc_lion%s.zip", r))
  if (file.exists(dest) || file.exists(old)) next
  part <- paste0(dest, ".part")
  ok <- FALSE
  for (u in url_base) {
    ok <- tryCatch(download.file(sprintf(u, r), part, mode = "wb", quiet = TRUE) == 0,
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (ok) break
  }
  # a complete zip lists its contents; a truncated one does not
  if (ok) ok <- file.size(part) > 1e6 && !inherits(tryCatch(unzip(part, list = TRUE), error = function(e) e), "error")
  if (ok) {
    file.rename(part, dest)
    message(r, ": ", round(file.size(dest) / 1e6), " MB")
  } else {
    unlink(part)
    message(r, ": not published")
  }
}

have <- list.files(out_dir, pattern = "^nyc_?lion_?\\d\\d[a-d]\\.zip$")
message(length(have), " quarterly releases on disk: ", paste(sort(sub("nyc_?lion_?(\\d\\d[a-d])\\.zip", "\\1", have)), collapse = " "))
