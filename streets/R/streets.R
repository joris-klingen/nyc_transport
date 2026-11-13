# Readers for the street network history built in streets/ (outputs in data/derived/streets/)
#
# Loaded automatically by R/nyc_transport.R; from streets/ scripts: source("R/streets.R")
# k <- segment_key_map(c(32886, 9000277), date = "2014-06-01")

local({
  ofiles <- unlist(lapply(sys.frames(), function(f) if (is.character(f$ofile)) f$ofile))
  this <- tail(ofiles[grepl("(^|[/\\\\])streets\\.R$", ofiles)], 1)
  streets <- if (length(this)) dirname(dirname(this)) else "."
  # streets/ sits inside nyc_db; the raw-data readers are in its R/ one level up
  if (!exists("nyc_data_root")) source(file.path(streets, "..", "R", "nyc_transport.R"), local = FALSE)
})

streets_dir <- function(...) file.path(nyc_streets_data_root(), ...)

# Segment key (spine/03_segment_key.R): every LION SegmentID x geometry version since 12a with the
# SegmentIDs of the last release it continues as. share = share of the version's length that maps to
# key_id; key_status current (still in the last release), continued (replaced, split, merged or
# redrawn), retired (removed, key_id NA).
segment_key_read <- function() data.table::setDT(arrow::read_parquet(streets_dir("spine", "segment_key.parquet")))[]

# Map SegmentIDs to the key. date: the version in use on that date (the release in force then);
# without a date the latest version of each id.
segment_key_map <- function(segment_id, date = NULL, key = segment_key_read()) {
  ids <- data.table::data.table(segment_id = as.integer(segment_id))
  k <- key[ids, on = "segment_id", nomatch = 0]
  if (!is.null(date)) k <- k[first_date <= as.Date(date)]
  if (nrow(k)) k <- k[k[, .I[version == max(version)], by = segment_id][, V1]]   # ids in no release (before 12a) drop out
  k[, .(segment_id, version, key_id, share, key_status)][]
}

# Attach the key to a table of SegmentIDs: one row per input row and key segment (a split segment
# gives several rows, a retired one key_id NA). release_col: LION release of each row ("16a"), to
# use the version in force then; without it the latest version of each id. Adds key_id, share (of
# the source segment's length), key_cover (of the key segment's length), reversed (key segment drawn
# the other way: from-to and to-from attributes swap) and key_status.
segment_key_attach <- function(dt, id_col = "SegmentID", release_col = NULL, key = segment_key_read()) {
  dt <- data.table::copy(data.table::as.data.table(dt))
  dt[, `.seg` := as.integer(get(id_col))]
  k <- key[, .(`.seg` = segment_id, version, first_release, last_release, first_date, key_id, share, key_cover, reversed, key_status)]
  if (is.null(release_col)) {
    k <- k[k[, .I[version == max(version)], by = `.seg`][, V1]]
    out <- merge(dt, k[, !c("version", "first_release", "last_release", "first_date")], by = ".seg", all.x = TRUE, allow.cartesian = TRUE)
  } else {
    rels <- unique(key[, .(release = c(first_release, last_release), date = c(first_date, last_date))])[order(date)]
    rels <- unique(rels, by = "release")[, ri := .I]
    k[rels, first_ri := i.ri, on = .(first_release = release)][rels, last_ri := i.ri, on = .(last_release = release)]
    dt[rels, `.ri` := i.ri, on = setNames("release", release_col)]
    out <- k[, !c("version", "first_release", "last_release", "first_date")][
      dt, on = .(`.seg`, first_ri <= `.ri`, last_ri >= `.ri`), allow.cartesian = TRUE]
    out[, c("first_ri", "last_ri") := NULL]   # the non-equi join keeps dt's .ri under these names
  }
  out[, `.seg` := NULL][]
}

# Bike lane time windows on the key (layers/bike_lanes/scripts/04_key_windows.R): key_id x source
# SegmentID x time_window, tf/ft facilities in the key segment's direction, share, key_cover and
# main_source (filter on it for one set of windows per key segment)
bikelane_windows_keyed_read <- function() data.table::setDT(arrow::read_parquet(streets_dir("bike_lanes", "bike_lanes_windows_keyed.parquet")))[]

# Segment versions (spine/02_segment_versions.R) as sf in EPSG 2263; date: the network in use then
segment_versions_read <- function(date = NULL) {
  v <- sf::st_read(streets_dir("spine", "segment_versions.gpkg"), quiet = TRUE)
  if (is.null(date)) return(v)
  r <- lion_releases()
  rel <- r[["release"]][max(1, findInterval(as.numeric(as.Date(date)), as.numeric(r[["release_date"]])))]
  ri <- match(c(v$first_release, v$last_release, rel), r[["release"]])
  n <- nrow(v)
  v[ri[seq_len(n)] <= ri[2 * n + 1] & ri[n + seq_len(n)] >= ri[2 * n + 1], ]
}

# Street spells (build/01_street_spells.R) ----
# Every layer as spells on the key segments: key_id, attribute, side, value, valid_from, valid_to
# (NA = still valid), date_precision, source, priority, source_id, key_cover.

# The attributes in the spells: type, sides, source, and what the value means
streets_attributes <- function() data.table::data.table(
  attribute = c("in_lion", "bike_lane", "travel_lanes", "parking_lanes", "total_lanes", "street_width", "traffic_dir"),
  type      = c("flag", "character", "numeric", "numeric", "numeric", "numeric", "character"),
  sides     = c("both", "tf, ft", "both", "both", "both", "both", "both"),
  from      = c("2012-05", "DOT install dates", "2016-02 (LION), 2012-07 (Manhattan)", "2016-02", "2016-02", "2016-11", "2012-05"),
  meaning   = c("the key segment exists in LION (a source version covers it)",
                "Protected / Standard / Sharrows / none, per direction of the key segment",
                "moving lanes; Manhattan: dated with bike lane changes and reviews, elsewhere LION per release",
                "parking lanes (LION)", "total lanes (LION)", "minimum street width in ft (LION)",
                "LION TrafDir relative to the key segment: W with, A against, T two-way, P pedestrian"))

streets_spells_read <- function(attributes = NULL) {
  sp <- data.table::setDT(arrow::read_parquet(streets_dir("spells", "street_spells.parquet")))
  if (!is.null(attributes)) sp <- sp[attribute %in% attributes]
  sp[, `:=`(valid_from = data.table::as.IDate(valid_from), valid_to = data.table::as.IDate(valid_to))]
  sp[]
}

# Key segments with borough, street, street code, roadway type (1 street, 2 highway, 3 bridge, ...)
key_segments_read <- function() data.table::setDT(arrow::read_parquet(streets_dir("spells", "key_segments.parquet")))[]

# Street state on a grid of dates: one row per key segment and date (wide = TRUE: one column per
# attribute, bike_lane as bike_lane_tf / bike_lane_ft), or long rows key_id, date, attribute, side,
# value, date_precision, source. Where sources overlap the lower priority wins, then the larger
# key_cover. in_lion_only drops key segments not in LION on a date (streets that did not exist yet).
# sources: keep only these sources (e.g. "lion" for the undated LION values; in_lion always kept).
# spells, keys: tables to use instead of the stored spells and key segments (e.g. simulated ones,
# sim_street_spells() and sim_key_segments() in sim/).
streets_panel <- function(from, to = from, by = "month", attributes = NULL, boro = NULL, key_ids = NULL,
                          wide = TRUE, in_lion_only = TRUE, sources = NULL, spells = NULL, keys = NULL) {
  dates <- data.table::as.IDate(seq(as.Date(from), as.Date(to), by = by))
  attrs <- unique(c(attributes, if (in_lion_only) "in_lion"))
  sp <- if (is.null(spells)) streets_spells_read(if (is.null(attributes)) NULL else attrs)
        else if (is.null(attributes)) data.table::copy(spells) else spells[attribute %in% attrs]
  if (!is.null(sources)) sp <- sp[source %in% sources | attribute == "in_lion"]
  if (!is.null(boro)) { b <- boro; key_ids <- c(key_ids, (if (is.null(keys)) key_segments_read() else keys)[boro %in% b, key_id]) }
  if (!is.null(key_ids)) sp <- sp[key_id %in% key_ids]
  vt <- sp[, data.table::fifelse(is.na(valid_to), data.table::as.IDate("2100-01-01"), valid_to)]
  i1 <- findInterval(as.integer(sp[, valid_from]) - 1L, as.integer(dates)) + 1L   # first grid date on or after valid_from
  i2 <- findInterval(as.integer(vt) - 1L, as.integer(dates))                      # last grid date before valid_to
  n <- pmax(i2 - i1 + 1L, 0L)
  x <- sp[rep(seq_len(nrow(sp)), n)]
  x[, date := dates[rep(i1, n) + sequence(n) - 1L]]
  data.table::setorder(x, key_id, date, attribute, side, priority, -key_cover)
  x <- x[!duplicated(x[, .(key_id, date, attribute, side)])]
  if (in_lion_only) {
    x <- x[x[attribute == "in_lion", .(key_id, date)], on = .(key_id, date), nomatch = 0]
    if (!is.null(attributes) && !"in_lion" %in% attributes) x <- x[attribute != "in_lion"]
  }
  if (!wide) return(x[, .(key_id, date, attribute, side, value, date_precision, source)][])
  x[, col := data.table::fifelse(side == "both", attribute, paste(attribute, side, sep = "_"))]
  w <- data.table::dcast(x, key_id + date ~ col, value.var = "value")
  num <- intersect(names(w), streets_attributes()[type == "numeric", attribute])
  for (v in num) data.table::set(w, j = v, value = as.numeric(w[[v]]))
  if ("in_lion" %in% names(w)) w[, in_lion := !is.na(in_lion)]
  w[]
}

# Street state on one date; geometry = TRUE returns sf with the key segments' lines (EPSG 2263)
streets_state <- function(date, attributes = NULL, boro = NULL, key_ids = NULL, wide = TRUE, geometry = FALSE,
                          spells = NULL, keys = NULL) {
  x <- streets_panel(date, date, attributes = attributes, boro = boro, key_ids = key_ids, wide = wide,
                     spells = spells, keys = keys)
  if (!geometry) return(x)
  v <- segment_versions_read()
  v <- v[v$last_release == max(segment_key_read()[, last_release]), c("segment_id")]
  names(v)[1] <- "key_id"
  merge(v, x, by = "key_id")
}
