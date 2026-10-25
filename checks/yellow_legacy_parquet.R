# Parquet copy of the legacy yellow CSVs against the CSVs ----
# Rows per month: data lines of the CSV (counted from the bytes, not through fread; blank lines and
# the header left out) against the parquet copy, and the TLC parquet file of the same month for
# reference. Values: for one month the sums of the money, distance and coordinate columns.
#
# Rscript checks/yellow_legacy_parquet.R   (from the repo root)

suppressMessages(library(data.table))
source("R/nyc_transport.R")

# lines that hold data: newlines, minus empty lines (a newline followed by \r or \n), minus the header
csv_rows <- function(f, chunk = 2^26) {
  con <- file(f, "rb"); on.exit(close(con))
  n_nl <- 0; n_blank <- 0; prev <- as.raw(0); last <- as.raw(10)
  repeat {
    b <- readBin(con, "raw", chunk)
    if (!length(b)) break
    nl <- b == as.raw(10)
    n_nl <- n_nl + sum(nl)
    nxt <- c(b[-1], as.raw(0))
    n_blank <- n_blank + sum(nl[-length(b)] & (nxt[-length(b)] == as.raw(10) | nxt[-length(b)] == as.raw(13)))
    # a newline at the end of the previous chunk followed by an empty line here
    if (prev == as.raw(10) && (b[1] == as.raw(10) || b[1] == as.raw(13))) n_blank <- n_blank + 1
    prev <- b[length(b)]; last <- prev
  }
  n_nl - n_blank - 1 + (last != as.raw(10))
}

# file() reads .csv.gz transparently
src <- list.files(file.path(tlc_data_dir(), "yellow_csv_legacy"), "^yellow_tripdata_\\d{4}-\\d{2}\\.csv(\\.gz)?$", full.names = TRUE)
pq_of <- function(f) file.path(tlc_legacy_dir(), sub("\\.csv(\\.gz)?$", ".parquet", basename(f)))
res <- rbindlist(lapply(src, function(f) {
  ym <- substr(basename(f), 17, 23)
  pq <- pq_of(f)
  tlc <- file.path(tlc_data_dir(), "yellow", basename(pq))
  data.table(month = ym, csv = csv_rows(f),
             parquet = if (file.exists(pq)) arrow::ParquetFileReader$create(pq)$num_rows else NA_real_,
             tlc_parquet = if (file.exists(tlc)) arrow::ParquetFileReader$create(tlc)$num_rows else NA_real_)
}))
res[, `:=`(same = csv == parquet, tlc_minus_csv = tlc_parquet - csv)]
print(res, nrows = 100)
cat("months:", nrow(res), " parquet rows equal to the CSV:", res[, sum(same, na.rm = TRUE)], "\n")

# Values of one month ----
f <- sample(src, 1)
hdr <- trimws(names(fread(f, nrows = 0, blank.lines.skip = TRUE)))
x <- fread(f, header = TRUE, blank.lines.skip = TRUE, showProgress = FALSE,
           select = which(hdr %in% c("fare_amount", "tip_amount", "total_amount", "trip_distance", "pickup_longitude", "dropoff_latitude")))
setnames(x, trimws(names(x)))
y <- as.data.table(arrow::read_parquet(pq_of(f), col_select = names(x)))
cat("\n", basename(f), ": column sums equal:\n")
print(sapply(names(x), function(v) isTRUE(all.equal(sum(as.numeric(x[[v]]), na.rm = TRUE), sum(y[[v]], na.rm = TRUE)))))
