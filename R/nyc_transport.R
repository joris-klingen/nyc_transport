# Readers for the shared NYC transport data store (nyc_transport_data); the one file to source.
# Also loads the street network history readers (streets/R/streets.R) at the end.
#
# source(Find(file.exists, c("../nyc_transport_repo/R/nyc_transport.R", "../nyc_transport/R/nyc_transport.R")))
# ds <- tlc_open("fhvhv", years = 2019:2020)      # lazy arrow dataset
# f  <- nyc_latest("crashes")                     # newest crash snapshot
#
# TLC column names differ between types (e.g. tpep_/lpep_ prefixes, trip_distance
# vs trip_miles) and across years within a type; harmonize after selecting.

# locate this file among (possibly nested) source() calls to find config.R next to it
local({
  ofiles <- unlist(lapply(sys.frames(), function(f) if (is.character(f$ofile)) f$ofile))
  this <- tail(ofiles[grepl("nyc_transport\\.R$", ofiles)], 1)
  source(file.path(if (length(this)) dirname(this) else "R", "config.R"), local = FALSE)
})

# TLC trips ----
tlc_files <- function(type, years = NULL) {
  f <- list.files(file.path(tlc_data_dir(), type),
                  pattern = paste0("^", type, "_tripdata_\\d{4}-\\d{2}\\.parquet$"),
                  full.names = TRUE)
  if (!is.null(years)) f <- f[as.integer(substr(basename(f), nchar(type) + 11, nchar(type) + 14)) %in% years]
  f
}

tlc_open <- function(type, years = NULL) {
  f <- tlc_files(type, years)
  if (length(f) == 0) stop("no files for ", type, " in ", tlc_data_dir())
  # unify_schemas: column types drift across years (e.g. int vs double)
  arrow::open_dataset(f, unify_schemas = TRUE)
}

# Dated snapshots ----
nyc_snapshots <- c(
  setNames(lapply(seq_len(nrow(nyc_opendata)), function(i)
    nyc_opendata[i, c(dir, nyc_snapshot_pattern(prefix, ext))]), nyc_opendata[, name]),
  list(
    taxi_zones        = c("taxi/zones",        "^taxi_zones_(\\d{8})\\.zip$"),
    taxi_zone_lookup  = c("taxi/zones",        "^taxi_zone_lookup_(\\d{8})\\.csv$"),
    citibike_stations = c("citibike/stations", "^station_information_(\\d{8})\\.json$"),
    # MTA congestion relief zone entries (data.ny.gov t2rz-wjj6), 10-minute blocks from 2025-01-05
    crz_entries       = c("congestion_pricing", "^MTA_Congestion_Relief_Zone_Vehicle_Entries__Beginning_2025_(\\d{8})\\.csv$"),
    # 2020 census population (P1_001N) per block group, from the Census API
    bg_population     = c("boundaries/census_block_groups_2020", "^nyc_bg_population_2020_(\\d{8})\\.json$")
  )
)

# all snapshots of a dataset, oldest first, named by snapshot date
nyc_snapshot_files <- function(name) {
  s <- nyc_snapshots[[name]]
  f <- list.files(file.path(nyc_data_root(), "raw", s[1]), pattern = s[2])
  d <- sub(s[2], "\\1", f)
  setNames(file.path(nyc_data_root(), "raw", s[1], f), d)[order(d)]
}

# newest snapshot, or the newest one on or before `as_of` (YYYYMMDD), for reproducibility
nyc_latest <- function(name, as_of = NULL) {
  f <- nyc_snapshot_files(name)
  if (!is.null(as_of)) f <- f[names(f) <= as_of]
  if (length(f) == 0) stop("no snapshot of ", name, " in ", nyc_data_root())
  unname(f[length(f)])
}

# Crashes ----
crashes_parquet_dir <- function() file.path(nyc_data_root(), "derived", "crashes_parquet")

# Read a crash snapshot with harmonized columns: snake_case names, squished text, numeric
# coordinates (some 2026 snapshots write "40,717175" and pad text fields), coordinates at 0/0 or
# outside NYC as NA, crash_date as IDate. `select` takes the original column names. Uses the
# parquet copy from scripts/30_crashes_parquet.R when there is one (much faster).
crashes_read <- function(file = nyc_latest("crashes"), select = NULL, use_parquet = TRUE) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  snake <- function(x) gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(x)))
  pq <- file.path(crashes_parquet_dir(), sub("\\.csv$", ".parquet", basename(file)))
  if (use_parquet && file.exists(pq) && file.mtime(pq) > file.mtime(file)) {
    # col_select is evaluated by tidyselect, so pass the names with all_of()
    cols <- snake(select)
    cr <- data.table::as.data.table(if (is.null(select)) arrow::read_parquet(pq)
                                    else arrow::read_parquet(pq, col_select = tidyselect::all_of(cols)))
    return(cr[])
  }
  chr <- intersect(c("LATITUDE", "LONGITUDE", "ZIP CODE"), if (is.null(select)) c("LATITUDE", "LONGITUDE", "ZIP CODE") else select)
  cr <- data.table::fread(file, select = select, colClasses = list(character = chr), na.strings = "")
  data.table::setnames(cr, snake(names(cr)))
  for (v in names(cr)[vapply(cr, is.character, logical(1))])
    data.table::set(cr, j = v, value = gsub(" {2,}", " ", trimws(cr[[v]])))
  for (v in intersect(c("latitude", "longitude"), names(cr)))
    data.table::set(cr, j = v, value = as.numeric(sub(",", ".", cr[[v]], fixed = TRUE)))
  if (all(c("latitude", "longitude") %in% names(cr)))
    cr[!nyc_in_bbox(longitude, latitude), `:=`(latitude = NA_real_, longitude = NA_real_)]
  if ("crash_date" %in% names(cr)) cr[, crash_date := data.table::as.IDate(crash_date, format = "%m/%d/%Y")]
  cr[]
}

# Address points ----
borough_codes <- c("1" = "MANHATTAN", "2" = "BRONX", "3" = "BROOKLYN", "4" = "QUEENS", "5" = "STATEN ISLAND")

# Canonical street name, applied to both crash addresses and address points
# ("WEST 86 STREET", "W 86TH ST" and "W  86 ST" all become "W 86 ST")
nyc_street_norm <- function(x) {
  abbr <- c(STREET = "ST", AVENUE = "AVE", AV = "AVE", BOULEVARD = "BLVD", ROAD = "RD", PLACE = "PL",
            DRIVE = "DR", PARKWAY = "PKWY", EXPRESSWAY = "EXPY", EXPWY = "EXPY", LANE = "LN", COURT = "CT",
            TERRACE = "TER", TERR = "TER", SQUARE = "SQ", HIGHWAY = "HWY", TURNPIKE = "TPKE", CONCOURSE = "CONC",
            PLAZA = "PLZ", CRESCENT = "CRES", SAINT = "ST", FORT = "FT", MOUNT = "MT", BEACH = "BCH",
            WEST = "W", EAST = "E", NORTH = "N", SOUTH = "S")
  x <- gsub("[^A-Z0-9 ]", " ", toupper(x))
  x <- gsub("\\b([0-9]+)(ST|ND|RD|TH)\\b", "\\1", x, perl = TRUE)
  w <- strsplit(trimws(gsub(" +", " ", x)), " ", fixed = TRUE)
  vapply(w, function(t) { i <- t %in% names(abbr); t[i] <- abbr[t[i]]; paste(t, collapse = " ") }, character(1))
}

# Matching key: canonical name without spaces, so "MC DONALD AVE" meets "MCDONALD AVE"
nyc_street_key <- function(x) gsub(" ", "", nyc_street_norm(x), fixed = TRUE)

# House number as a number; Queens hyphenated numbers "137-70" become 137070, letter suffixes dropped
nyc_house_num <- function(x) {
  x <- sub("^([0-9]+(-[0-9]+)?).*", "\\1", trimws(x))
  pre <- suppressWarnings(as.numeric(sub("-.*", "", x)))
  suf <- suppressWarnings(as.numeric(ifelse(grepl("-", x), sub(".*-", "", x), NA)))
  ifelse(is.na(suf), pre, pre * 1000 + suf)
}

# DCP/OTI address points: one point per building address, with hn_lo..hn_hi for range addresses.
# b5sc is the borough + 5-digit street code, shared by all names of a street (8 AVE and
# FREDERICK DOUGLASS BLVD are both 110810)
address_points_read <- function(file = nyc_latest("address_points")) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  ap <- data.table::fread(file, select = c("the_geom", "House Number", "House Number Range", "Borough Code",
                                           "Full Street Name", "B7SC_ACTUAL"),
                          colClasses = "character", na.strings = "")
  data.table::setnames(ap, c("geom", "hn", "hn_range", "boro_code", "street", "b7sc"))
  ap[, `:=`(longitude = as.numeric(sub("POINT \\(([-0-9.]+) .*", "\\1", geom)),
            latitude  = as.numeric(sub("POINT \\([-0-9.]+ ([-0-9.]+)\\)", "\\1", geom)),
            borough   = unname(borough_codes[boro_code]),
            b5sc      = substr(b7sc, 1, 6),
            hn_lo     = nyc_house_num(hn))]
  ap[, hn_hi := data.table::fifelse(is.na(hn_range), hn_lo, pmax(hn_lo, nyc_house_num(hn_range), na.rm = TRUE))]
  ap <- ap[!is.na(hn_lo) & !is.na(longitude) & !is.na(b5sc)]
  ap[, parity := hn_lo %% 2]
  ap[, .(borough, b5sc, street, hn_lo, hn_hi, parity, longitude, latitude)]
}

# Street name -> street code dictionary (borough, key, b5sc) from the address point names, LION
# street names and LION alternate names, so a crash on "WEST 110 STREET" finds the address
# points filed under CATHEDRAL PKWY. Without sf or a LION snapshot only address point names are used.
nyc_street_codes <- function(ap = address_points_read(), lion_file = tryCatch(nyc_latest("lion"), error = function(e) NULL)) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  d <- list(unique(ap[, .(borough, street, b5sc)]))
  if (!is.null(lion_file) && requireNamespace("sf", quietly = TRUE)) {
    gdb <- paste0("/vsizip/", lion_file, "/lion/lion.gdb")
    tab <- function(...) { x <- sf::st_read(gdb, quiet = TRUE, ...); data.table::as.data.table(if (inherits(x, "sf")) sf::st_drop_geometry(x) else x) }
    ln <- unique(tab(query = "SELECT Street, LBoro, StreetCode, Join_ID FROM lion"))
    ln <- ln[grepl("^[1-5][0-9]{5}$", StreetCode)]
    ln[, borough := unname(borough_codes[as.character(LBoro)])]
    d <- c(d, list(unique(ln[, .(borough, street = Street, b5sc = StreetCode)])))
    # alternate names (renamed streets: STONE AVE is MOTHER GASTON BLVD). Join_ID groups segments
    # of several streets, so an alternate name is only used when it is not the name of another
    # street in the borough and its segments all belong to one street.
    al <- unique(tab(layer = "altnames")[, .(Street, Join_ID)])
    al <- unique(ln[, .(Join_ID, borough, b5sc = StreetCode)])[al, on = "Join_ID", nomatch = 0L]
    al[, key := nyc_street_key(Street)]
    al <- unique(al[, .(borough, key, b5sc)])
  }
  d <- unique(data.table::rbindlist(d, use.names = TRUE))
  d[, key := nyc_street_key(street)]
  d <- unique(d[, .(borough, key, b5sc)])
  if (exists("al", inherits = FALSE)) {
    al <- al[!d, on = .(borough, key)]
    al <- al[, if (data.table::uniqueN(b5sc) == 1L) .SD, .(borough, key)]
    d <- rbind(d, al)
  }
  d
}

# LION street centerlines (generic and both-roadbed layers, not the separate roadbeds of divided
# streets) with their street code and SegmentID, in NY State Plane feet (EPSG 2263)
nyc_street_lines <- function(lion_file = nyc_latest("lion")) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  # type = 5 linearizes the curved segments, which GEOS cannot handle
  ln <- sf::st_read(lion_gdb(lion_file), quiet = TRUE, type = 5, query =
    "SELECT SegmentID, StreetCode FROM lion WHERE FeatureTyp IN ('0','6','A','C') AND RB_Layer IN ('G','B')")
  ln <- sf::st_zm(ln[grepl("^[1-5][0-9]{5}$", ln[["StreetCode"]]), ])
  names(ln)[names(ln) == "StreetCode"] <- "b5sc"
  ln$segment_id <- as.integer(ln$SegmentID)
  ln[, c("b5sc", "segment_id")]
}

# Orthogonal projection of points onto the nearest centerline of their own street (b5sc).
# Returns longitude/latitude of the snapped points, snap_ft and the LION segment_id snapped to;
# NA where the street has no line.
nyc_snap_to_street <- function(lon, lat, b5sc, lines = nyc_street_lines()) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  pts <- sf::st_transform(sf::st_as_sf(data.frame(lon, lat), coords = c("lon", "lat"), crs = 4326), 2263)
  xy <- matrix(NA_real_, length(lon), 2)
  seg <- rep(NA_integer_, length(lon))
  by_street <- split(seq_along(lon), b5sc)
  by_street <- by_street[names(by_street) %in% lines[["b5sc"]]]
  line_idx <- split(seq_len(nrow(lines)), lines[["b5sc"]])
  for (s in names(by_street)) {
    i <- by_street[[s]]
    l <- sf::st_geometry(lines)[line_idx[[s]]]
    p <- sf::st_geometry(pts)[i]
    k <- sf::st_nearest_feature(p, l)
    seg[i] <- lines[["segment_id"]][line_idx[[s]][k]]
    np <- sf::st_nearest_points(p, l[k], pairwise = TRUE)
    # each connector runs from the point to its foot on the line
    xy[i, ] <- sf::st_coordinates(np)[c(FALSE, TRUE), 1:2, drop = FALSE]
  }
  snap_ft <- sqrt(rowSums((xy - sf::st_coordinates(pts))^2))
  ok <- !is.na(xy[, 1])
  ll <- matrix(NA_real_, length(lon), 2)
  if (any(ok)) ll[ok, ] <- sf::st_coordinates(sf::st_transform(sf::st_as_sf(data.frame(x = xy[ok, 1], y = xy[ok, 2]), coords = c("x", "y"), crs = 2263), 4326))
  list(longitude = ll[, 1], latitude = ll[, 2], snap_ft = snap_ft, segment_id = seg)
}

# LION intersection nodes with the street codes of the segments that meet there, and node
# coordinates (longitude, latitude)
nyc_street_nodes <- function(lion_file = nyc_latest("lion")) {
  stopifnot(requireNamespace("sf", quietly = TRUE), requireNamespace("data.table", quietly = TRUE))
  gdb <- lion_gdb(lion_file)
  seg <- data.table::as.data.table(sf::st_drop_geometry(sf::st_read(gdb, quiet = TRUE, query =
    "SELECT NodeIDFrom, NodeIDTo, LBoro, StreetCode FROM lion WHERE FeatureTyp IN ('0','6','A','C')")))
  seg <- seg[grepl("^[1-5][0-9]{5}$", StreetCode)]
  ns <- unique(data.table::rbindlist(list(seg[, .(node = as.integer(NodeIDFrom), b5sc = StreetCode)],
                                          seg[, .(node = as.integer(NodeIDTo), b5sc = StreetCode)])))
  nd <- sf::st_transform(sf::st_read(gdb, layer = "node", quiet = TRUE), 4326)
  xy <- sf::st_coordinates(nd)
  nd <- data.table::data.table(node = nd[["NODEID"]], longitude = xy[, 1], latitude = xy[, 2])
  nd[ns, on = "node", nomatch = 0L]
}

# Coordinates for intersection crashes (on_street_name and cross_street_name, no address) from the
# LION node where both streets meet. Streets are matched by street code, as in crashes_relocate().
# All candidate nodes must lie within `max_spread_ft` of each other (divided roads have several
# nodes per intersection); the node nearest their centroid is used. Otherwise the crash is left
# out: the two names meet at more than one place (often a crash without a borough).
# Returns collision_id, node (LION NODEID), longitude, latitude, n_nodes.
crashes_intersection_nodes <- function(cr, streets = nyc_street_codes(), nodes = nyc_street_nodes(), max_spread_ft = 500) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  a <- cr[is.na(off_street_name) & !is.na(on_street_name) & !is.na(cross_street_name),
          .(collision_id, borough, k1 = nyc_street_key(on_street_name), k2 = nyc_street_key(cross_street_name))]
  codes <- function(k) {
    x <- streets[a, on = c(key = k), nomatch = 0L, allow.cartesian = TRUE, .(collision_id, cb = i.borough, sb = x.borough, b5sc)]
    unique(x[is.na(cb) | cb == sb, .(collision_id, b5sc)])
  }
  n1 <- unique(nodes[codes("k1"), on = "b5sc", nomatch = 0L, allow.cartesian = TRUE, .(collision_id, node, longitude, latitude)])
  n2 <- unique(nodes[codes("k2"), on = "b5sc", nomatch = 0L, allow.cartesian = TRUE, .(collision_id, node)])
  cand <- unique(n1[n2, on = .(collision_id, node), nomatch = 0L])
  cand[, `:=`(cx = mean(longitude), cy = mean(latitude)), collision_id]
  cand[, d_ft := sqrt(((longitude - cx) * 276500)^2 + ((latitude - cy) * 364000)^2)]
  ok <- cand[, .(spread = 2 * max(d_ft)), collision_id][spread <= max_spread_ft, collision_id]
  cand <- cand[collision_id %in% ok]
  data.table::setorder(cand, collision_id, d_ft)
  cand[, .(node = node[1], longitude = longitude[1], latitude = latitude[1], n_nodes = .N), collision_id]
}

# Relocate crashes geocoded from a house number (off_street_name) to the address point of that
# building. LION interpolation pulls these toward the low-number end of blocks with padded
# address ranges; address points are the building itself. Takes crashes_read() output and adds
#   longitude_ap, latitude_ap  relocated coordinates (original ones for all other crashes)
#   loc_method                 "address point", "nearest address point" (same street and side,
#                              house number within `max_hn_gap`), "intersection node", or "original"
#   snap_ft                    distance from the building to its street centerline
#   moved_ft                   distance between original and relocated point
#   segment_id                 LION SegmentID the crash was snapped to (relocated crashes)
#   node_id                    LION NODEID of intersection crashes: the node filled in, or the node
#                              within 10 ft of the original point (~96% of intersection crashes)
# With snap = TRUE (default) the building point is projected orthogonally onto the nearest LION
# centerline of the same street, so crashes sit on the street beside the building. Buildings on
# a street without a centerline, or farther than `max_snap_ft` from it (large complexes, streets
# whose LION line lies elsewhere), keep the address point (snap_ft NA).
# Without a borough, the borough of the candidate closest to the original point is used. When
# the crash has an original point, candidates beyond `max_move_ft` are discarded: the original
# geocode is on the right street, so a far candidate means the name matched a different street
# (two "37 AVE" in Queens, an alternate name shared by several streets).
# With fill_intersections = TRUE (default) intersection crashes without coordinates get the LION
# node where the two streets meet (crashes_intersection_nodes()). Tested on crashes that have
# coordinates: with a borough the node is within 150 ft for 99%, without one for 83%.
crashes_relocate <- function(cr, ap = address_points_read(), streets = nyc_street_codes(ap),
                             max_hn_gap = 10, max_move_ft = 1000,
                             snap = TRUE, max_snap_ft = 500, lines = if (snap) nyc_street_lines() else NULL,
                             fill_intersections = TRUE, nodes = if (fill_intersections) nyc_street_nodes() else NULL) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  a <- cr[!is.na(off_street_name) & grepl("^[0-9]", off_street_name),
          .(collision_id, borough, lon0 = longitude, lat0 = latitude,
            hn = nyc_house_num(sub(" .*", "", off_street_name)), key = nyc_street_key(sub("^[^ ]+ ", "", off_street_name)))]
  a <- a[!is.na(hn)]
  a[, `:=`(parity = hn %% 2, hn_from = hn - max_hn_gap, hn_to = hn + max_hn_gap)]

  # street codes the name can refer to (in the crash's borough when it has one)
  sc <- streets[a, on = "key", nomatch = 0L, allow.cartesian = TRUE,
                .(collision_id, crash_boro = i.borough, ap_boro = x.borough, b5sc, lon0, lat0, hn, parity, hn_from, hn_to)]
  sc <- unique(sc[is.na(crash_boro) | crash_boro == ap_boro])

  # address points on those streets and the same side within the house number window
  cand <- ap[sc, on = .(b5sc, parity, hn_hi >= hn_from, hn_lo <= hn_to), nomatch = 0L, allow.cartesian = TRUE,
             .(collision_id, crash_boro, ap_boro, b5sc, lon0, lat0, hn = i.hn, hn_lo = x.hn_lo, hn_hi = x.hn_hi,
               longitude = x.longitude, latitude = x.latitude)]
  cand[, gap := pmax(hn_lo - hn, hn - hn_hi, 0)]
  # feet, equirectangular at NYC's latitude
  cand[, moved_ft := sqrt(((longitude - lon0) * 276500)^2 + ((latitude - lat0) * 364000)^2)]
  cand <- cand[is.na(moved_ft) | moved_ft <= max_move_ft]
  cand[is.na(crash_boro) & !is.na(moved_ft), crash_boro := ap_boro[which.min(moved_ft)], collision_id]
  # no borough and no original point: only accept when all candidates are in one borough
  amb <- cand[is.na(crash_boro), .(n = data.table::uniqueN(ap_boro)), collision_id][n > 1, collision_id]
  cand <- cand[(is.na(crash_boro) | crash_boro == ap_boro) & !collision_id %in% amb]
  data.table::setorder(cand, collision_id, gap, moved_ft, na.last = TRUE)
  best <- cand[, .SD[1], collision_id]

  best[, `:=`(snap_ft = NA_real_, segment_id = NA_integer_)]
  if (snap && nrow(best)) {
    s <- nyc_snap_to_street(best[, longitude], best[, latitude], best[, b5sc], lines)
    ok <- !is.na(s$longitude) & s$snap_ft <= max_snap_ft
    best[ok, `:=`(longitude = s$longitude[ok], latitude = s$latitude[ok], snap_ft = s$snap_ft[ok], segment_id = s$segment_id[ok])]
    best[, moved_ft := sqrt(((longitude - lon0) * 276500)^2 + ((latitude - lat0) * 364000)^2)]
  }

  out <- data.table::copy(cr)
  out[, `:=`(longitude_ap = longitude, latitude_ap = latitude, loc_method = "original", snap_ft = NA_real_, moved_ft = NA_real_,
             segment_id = NA_integer_, node_id = NA_integer_)]
  out[best, on = "collision_id", `:=`(longitude_ap = i.longitude, latitude_ap = i.latitude, snap_ft = i.snap_ft, moved_ft = i.moved_ft,
                                      segment_id = i.segment_id,
                                      loc_method = data.table::fifelse(i.gap == 0, "address point", "nearest address point"))]
  if (fill_intersections) {
    g <- crashes_intersection_nodes(out[is.na(longitude)], streets, nodes)
    out[g, on = "collision_id", `:=`(longitude_ap = i.longitude, latitude_ap = i.latitude, node_id = i.node, loc_method = "intersection node")]
    # intersection crashes with coordinates: the node they sit on
    it <- out[is.na(off_street_name) & !is.na(cross_street_name) & !is.na(longitude), .(collision_id, longitude, latitude)]
    if (nrow(it) && requireNamespace("sf", quietly = TRUE)) {
      nd <- unique(nodes[, .(node, longitude, latitude)], by = "node")
      to_sf <- function(d) sf::st_transform(sf::st_as_sf(as.data.frame(d), coords = c("longitude", "latitude"), crs = 4326), nyc_crs)
      p <- to_sf(it); q <- to_sf(nd)
      k <- sf::st_nearest_feature(p, q)
      d <- sqrt(rowSums((sf::st_coordinates(p) - sf::st_coordinates(q)[k, , drop = FALSE])^2))
      it[, `:=`(node = nd[["node"]][k], d = d)]
      out[it[d <= 10], on = "collision_id", node_id := i.node]
    }
  }
  out[]
}

# Spatial conventions ----
# Joins and distances in NY State Plane Long Island, US feet (EPSG 2263): the CRS of LION and
# the traffic counts. Lon/lat sources (crashes, Citi Bike, address points, bike routes,
# boundaries) are converted with nyc_points_sf() or sf::st_transform(x, nyc_crs).
nyc_crs <- 2263

nyc_in_bbox <- function(lon, lat) !is.na(lon) & !is.na(lat) & lon > -74.27 & lon < -73.68 & lat > 40.49 & lat < 40.92

# sf points in nyc_crs from a table with lon/lat columns; rows without coordinates or outside
# NYC are dropped (with a message)
nyc_points_sf <- function(dt, lon = "longitude", lat = "latitude", crs = nyc_crs) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  ok <- nyc_in_bbox(dt[[lon]], dt[[lat]])
  if (any(!ok)) message("nyc_points_sf: dropped ", sum(!ok), " of ", length(ok), " rows without coordinates in NYC")
  sf::st_transform(sf::st_as_sf(as.data.frame(dt)[ok, , drop = FALSE], coords = c(lon, lat), crs = 4326), crs)
}

# LION ----
# path of the file geodatabase inside a LION zip (lion/lion.gdb, or lion.gdb in 2015b)
lion_gdb <- function(zip = nyc_latest("lion")) {
  n <- utils::unzip(zip, list = TRUE)$Name
  paste0("/vsizip/", zip, "/", sub("(\\.gdb)/.*", "\\1", n[grepl("\\.gdb/", n)][1]))
}

# Quarterly LION releases on disk with their release date (newest file date inside the zip)
lion_releases <- function() {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  dir <- file.path(nyc_data_root(), "raw", "street_layout", "lion")
  f <- list.files(dir, pattern = "^(nyc_lion|nyclion_)[0-9]{2}[a-d]\\.zip$", full.names = TRUE)
  r <- data.table::data.table(release = sub("^(nyc_lion|nyclion_)([0-9]{2}[a-d])\\.zip$", "\\2", basename(f)), file = f)
  r[, release_date := as.Date(vapply(file, function(z) format(max(utils::unzip(z, list = TRUE)$Date)), character(1)))]
  r[order(release_date)]
}

# The LION release in force on a date (the last one released on or before it)
nyc_lion_for_date <- function(date, releases = lion_releases()) {
  date <- as.Date(date)
  i <- findInterval(as.numeric(date), as.numeric(releases[["release_date"]]))
  if (any(i == 0)) warning("dates before the first release (", releases[["release"]][1], ") get that release")
  releases[["file"]][pmax(i, 1)]
}

# LION segments as sf in nyc_crs. what = "centerline": street features (FeatureTyp 0, 6, A, C) on
# the generic and both-roadbed layers (one line per street, the usual choice); "all": every
# feature. RW_TYPE is trimmed (stored as " 1"), SegmentID and LBoro become integers, curved
# segments are linearized. Columns missing in older releases are skipped.
lion_read <- function(file = nyc_latest("lion"), boro = NULL, what = c("centerline", "all"),
                      columns = c("SegmentID", "Street", "StreetCode", "LBoro", "FeatureTyp", "RB_Layer", "RW_TYPE",
                                  "TrafDir", "NodeIDFrom", "NodeIDTo", "Number_Travel_Lanes", "StreetWidth_Min",
                                  "BikeLane", "POSTED_SPEED", "LLo_Hyphen", "LHi_Hyphen", "RLo_Hyphen", "RHi_Hyphen")) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  what <- match.arg(what)
  gdb <- lion_gdb(file)
  have <- names(sf::st_read(gdb, quiet = TRUE, query = "SELECT * FROM lion WHERE 1 = 0"))
  where <- c(if (what == "centerline") "FeatureTyp IN ('0','6','A','C') AND RB_Layer IN ('G','B')",
             if (!is.null(boro)) sprintf("LBoro IN (%s)", paste(as.integer(boro), collapse = ",")))
  q <- paste("SELECT", paste(intersect(columns, have), collapse = ", "), "FROM lion",
             if (length(where)) paste("WHERE", paste(where, collapse = " AND ")))
  ln <- sf::st_zm(sf::st_read(gdb, quiet = TRUE, type = 5, query = q))
  if ("RW_TYPE" %in% names(ln)) ln$RW_TYPE <- trimws(ln$RW_TYPE)
  for (v in intersect(c("SegmentID", "LBoro"), names(ln))) ln[[v]] <- as.integer(ln[[v]])
  sf::st_transform(ln, nyc_crs)
}

# Boundaries ----
# Borough, community district, NTA, census tract/block and precinct polygons as sf in nyc_crs
boundaries_read <- function(name = c("boroughs", "community_districts", "ntas", "tracts", "blocks", "precincts"), as_of = NULL) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  x <- sf::st_transform(sf::st_read(nyc_latest(match.arg(name), as_of), quiet = TRUE), nyc_crs)
  # a few census blocks have self-intersections
  if (!all(sf::st_is_valid(x))) x <- sf::st_make_valid(x)
  x
}

# 2020 census block groups of New York State (TIGER/Line tl_2020_36_bg) as published (NAD83,
# EPSG 4269), with GEOID, STATEFP, COUNTYFP, TRACTCE, BLKGRPCE, ALAND, ... NYC: COUNTYFP 005, 047,
# 061, 081, 085. Population per block group: nyc_latest("bg_population") (Census API JSON).
census_block_groups_read <- function() {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  sf::st_read(file.path(nyc_data_root(), "raw", "boundaries", "census_block_groups_2020", "tl_2020_36_bg.shp"), quiet = TRUE)
}

# TLC taxi zones (LocationID, borough, zone, service_zone) as sf in nyc_crs; the location in all
# TLC parquet trips (PULocationID, DOLocationID). Zones 264/265 are unknown and have no polygon.
taxi_zones_read <- function() {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  z <- nyc_latest("taxi_zones")
  shp <- grep("\\.shp$", utils::unzip(z, list = TRUE)$Name, value = TRUE)[1]
  zones <- sf::st_read(paste0("/vsizip/", z, "/", shp), quiet = TRUE)
  lk <- data.table::fread(nyc_latest("taxi_zone_lookup"))
  zones <- merge(zones[, c("LocationID", "geometry")], lk, by = "LocationID", all.x = TRUE)
  sf::st_transform(zones, nyc_crs)
}

# Citi Bike ----
citibike_dir <- function() file.path(nyc_data_root(), "raw", "citibike", "trips")

# One parquet per month (citibike_tripdata_YYYY-MM.parquet), converted from the published zips by
# scripts/20_download_citibike.R; zips not yet converted are listed too
citibike_files <- function(type = c("parquet", "zip")) {
  type <- match.arg(type)
  list.files(citibike_dir(), full.names = TRUE,
             pattern = if (type == "parquet") "^citibike_tripdata_\\d{4}-\\d{2}\\.parquet$" else "citibike-tripdata\\.zip$")
}

# All months as one arrow dataset, for queries across months (filter, then collect)
citibike_open <- function() {
  f <- citibike_files()
  if (length(f) == 0) stop("no Citi Bike parquet files in ", citibike_dir())
  arrow::open_dataset(f, unify_schemas = TRUE)
}

# Trips of one month ("2016-07") in one schema across the format change:
#   started_at, ended_at (POSIXct, NYC time), start/end_station_id, _name, _lat, _lng,
#   member (TRUE for members/subscribers), rideable_type and ride_id (from 2020),
#   bikeid, birth_year, gender (to 2019-12: the 2024 repackaging converted 2020 to the new format).
# Reads the month's parquet; falls back on the published zip when the month is not converted.
citibike_read <- function(ym, nrows = Inf) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  pq <- file.path(citibike_dir(), sprintf("citibike_tripdata_%s.parquet", substr(ym, 1, 7)))
  if (file.exists(pq)) {
    x <- data.table::as.data.table(arrow::read_parquet(pq))
    if (is.finite(nrows)) x <- x[seq_len(min(nrows, .N))]
    for (v in c("started_at", "ended_at")) attr(x[[v]], "tzone") <- "America/New_York"
    return(x[])
  }
  yyyymm <- gsub("-", "", ym)
  f <- citibike_files("zip")
  outer <- f[basename(f) == paste0(yyyymm, "-citibike-tripdata.zip")]
  if (!length(outer)) outer <- f[basename(f) == paste0(substr(yyyymm, 1, 4), "-citibike-tripdata.zip")]
  if (!length(outer)) stop("no Citi Bike parquet or archive for ", ym)
  citibike_read_zip(outer, ym, nrows)
}

# One month from a published zip. Handles the three archive layouts: month folders in yearly zips
# (to 2019), monthly zips inside yearly zips (2020-2023), monthly zips split into several CSVs (2024 on).
citibike_read_zip <- function(outer, ym, nrows = Inf) {
  yyyymm <- gsub("-", "", ym)
  tmp <- tempfile("citibike"); dir.create(tmp); on.exit(unlink(tmp, recursive = TRUE))
  # the 2013 archive has each month twice: whole (201309-...csv) and split (201309-..._1.csv, _2)
  one_copy <- function(csv) if (any(grepl("_[0-9]+\\.csv$", csv))) csv[grepl("_[0-9]+\\.csv$", csv)] else csv
  n <- utils::unzip(outer, list = TRUE)$Name
  n <- n[!grepl("__MACOSX|/\\.", n) & grepl(yyyymm, basename(n))]
  # the 2018 archive holds April twice (top level and 4_April/): one copy per file name
  n <- n[!duplicated(basename(n))]
  inner_zip <- n[grepl("\\.zip$", n)]
  if (length(inner_zip)) {
    utils::unzip(outer, files = inner_zip, exdir = tmp, junkpaths = TRUE)
    z <- file.path(tmp, basename(inner_zip))
    n <- utils::unzip(z, list = TRUE)$Name
    n <- one_copy(n[!grepl("__MACOSX|/\\.", n) & grepl("\\.csv$", n)])
    utils::unzip(z, files = n, exdir = tmp, junkpaths = TRUE)
  } else {
    n <- one_copy(n[grepl("\\.csv$", n)])
    utils::unzip(outer, files = n, exdir = tmp, junkpaths = TRUE)
  }
  parts <- lapply(file.path(tmp, basename(n)), data.table::fread, nrows = nrows, colClasses = "character")
  x <- data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
  data.table::setnames(x, gsub("[^a-z0-9]+", "_", tolower(names(x))))
  # 2016-10 to 2017-03 write the old columns with spaces ("Start Time", "User Type", "Bike ID")
  data.table::setnames(x, c("start_time", "stop_time", "user_type", "bike_id", "trip_duration"),
                       c("starttime", "stoptime", "usertype", "bikeid", "tripduration"), skip_absent = TRUE)
  if ("starttime" %in% names(x)) {
    data.table::setnames(x, c("starttime", "stoptime", "start_station_latitude", "start_station_longitude",
                              "end_station_latitude", "end_station_longitude", "birth_year"),
                         c("started_at", "ended_at", "start_lat", "start_lng", "end_lat", "end_lng", "birth_year"), skip_absent = TRUE)
    x[, member := usertype == "Subscriber"]
  } else {
    x[, member := member_casual == "member"]
  }
  # the format is picked from the first value and applied to all, so that a time in the
  # spring-forward gap becomes NA instead of failing the whole parse (tryFormats needs every value to parse)
  fmt <- c("%Y-%m-%d %H:%M:%OS", "%m/%d/%Y %H:%M:%OS", "%m/%d/%Y %H:%M")
  for (v in c("started_at", "ended_at")) {
    first <- x[[v]][!is.na(x[[v]])][1]
    f <- fmt[!is.na(vapply(fmt, function(ff) as.numeric(as.POSIXct(first, format = ff, tz = "UTC")), numeric(1)))][1]
    data.table::set(x, j = v, value = as.POSIXct(x[[v]], format = f, tz = "America/New_York"))
  }
  for (v in c("start_lat", "start_lng", "end_lat", "end_lng")) data.table::set(x, j = v, value = as.numeric(x[[v]]))
  # some old csv parts write station ids as "116.0" next to "116" in others (2013-06)
  for (v in intersect(c("start_station_id", "end_station_id", "birth_year", "bikeid"), names(x)))
    data.table::set(x, j = v, value = sub("^([0-9]+)\\.0$", "\\1", x[[v]]))
  keep <- c("started_at", "ended_at", "start_station_id", "start_station_name", "start_lat", "start_lng",
            "end_station_id", "end_station_name", "end_lat", "end_lng", "member", "rideable_type", "ride_id",
            "bikeid", "birth_year", "gender")
  x[, intersect(keep, names(x)), with = FALSE]
}

# Counts ----
# DOT automated traffic counts (ATR): one row per 15 minutes and direction, with time as POSIXct,
# the LION SegmentID and x, y in nyc_crs (from WktGeom)
traffic_counts_read <- function(file = nyc_latest("traffic_counts")) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  tc <- data.table::fread(file)
  # explicit format: without it as.POSIXct() falls back to the date alone as soon as one time is in
  # the spring-forward gap (02:00-02:59), which made every time midnight; those times are NA now
  tc[, time := as.POSIXct(sprintf("%d-%02d-%02d %02d:%02d", Yr, M, D, HH, MM), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]
  xy <- unique(tc[, .(WktGeom)])
  xy[, `:=`(x = as.numeric(sub("POINT \\(([0-9.]+) .*", "\\1", WktGeom)), y = as.numeric(sub("POINT \\([0-9.]+ ([0-9.]+)\\)", "\\1", WktGeom)))]
  tc <- xy[tc, on = "WktGeom"]
  tc[, SegmentID := as.integer(SegmentID)]
  tc[]
}

# DOT bicycle and pedestrian counters, one row per sensor: name, lon/lat, x/y in nyc_crs, first and
# last data, travel modes, number of devices, and the nearest LION centerline segment_id with its
# distance (bridge paths can sit some way from a centerline). The source table has one row per
# device: a sensor gets a new device row when its counter is replaced.
bike_count_sensors <- function(file = nyc_latest("bike_ped_sensors")) {
  stopifnot(requireNamespace("data.table", quietly = TRUE), requireNamespace("sf", quietly = TRUE))
  s <- data.table::fread(file)
  fmt <- "%m/%d/%Y %I:%M:%S %p"
  first <- function(v) v[!is.na(v)][1]
  out <- s[, .(name = name[1], longitude = first(lon), latitude = first(lat),
               first_data = data.table::as.IDate(min(as.POSIXct(firstData, format = fmt, tz = "America/New_York"), na.rm = TRUE)),
               last_data = data.table::as.IDate(max(as.POSIXct(lastData, format = fmt, tz = "America/New_York"), na.rm = TRUE)),
               travel_modes = travelModes[1], devices = data.table::uniqueN(counters_id[!is.na(counters_id)])), .(sensor_id = id)]
  out[, `:=`(x = NA_real_, y = NA_real_, segment_id = NA_integer_, segment_ft = NA_real_)]
  ok <- out[, which(nyc_in_bbox(longitude, latitude))]
  p <- sf::st_transform(sf::st_as_sf(as.data.frame(out[ok]), coords = c("longitude", "latitude"), crs = 4326), nyc_crs)
  xy <- sf::st_coordinates(p)
  lines <- nyc_street_lines()
  k <- sf::st_nearest_feature(p, lines)
  out[ok, `:=`(x = xy[, 1], y = xy[, 2], segment_id = lines[["segment_id"]][k],
               segment_ft = as.numeric(sf::st_distance(p, lines[k, ], by_element = TRUE)))]
  out[]
}

# DOT bicycle and pedestrian counts: one row per sensor, flow (direction) and 15 minutes.
#   time        start of the interval, NYC local time. The source says EST, but the data follow
#               daylight saving: the 02:00 hour is missing on spring-forward days, and fall-back
#               days have a single 01:00 hour (the repeated hour is not in the data).
#   counter_id  the device mounted at that time (counters are replaced now and then; check
#               for a level shift at a swap)
# Rows DOT marked "deleted" are dropped unless keep_deleted = TRUE; status "modified" means DOT
# corrected the raw count (216 sensor-flow-times have both a deleted and a modified row; after
# dropping deleted rows the key sensor_id x flow_id x time is unique). Reading the full file takes
# ~17 minutes and ~2 GB (21.4M rows); filter with `modes` or read once and save to parquet. Sensor name and location come from bike_count_sensors(). `modes`
# keeps only some travel modes ("bike", "pedestrian", "scooter").
bike_counts_read <- function(file = nyc_latest("bike_ped_counts"), sensors_file = nyc_latest("bike_ped_sensors"),
                             modes = NULL, keep_deleted = FALSE) {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  x <- data.table::fread(file, colClasses = list(character = c("timestamp", "flowName")))
  data.table::setnames(x, c("travelMode", "flowID", "flowName"), c("travel_mode", "flow_id", "flow_name"))
  if (!keep_deleted) x <- x[status != "deleted"]
  if (!is.null(modes)) x <- x[travel_mode %in% modes]
  x[, time := as.POSIXct(timestamp, format = "%m/%d/%Y %I:%M:%S %p", tz = "America/New_York")]
  x[, c("timestamp", "granularity") := NULL]
  # device in place at the time of the count
  dev <- data.table::fread(sensors_file)[!is.na(counters_id)]
  fmt <- "%m/%d/%Y %I:%M:%S %p"
  dev <- dev[, .(sensor_id = id, counter_id = counters_id,
                 from = as.POSIXct(counters_installationDate, format = fmt, tz = "America/New_York"),
                 to = as.POSIXct(counters_detachmentDate, format = fmt, tz = "America/New_York"))]
  dev[is.na(to), to := as.POSIXct("2100-01-01", tz = "America/New_York")]
  x[, counter_id := NA_integer_]
  x[dev, on = .(sensor_id, time >= from, time < to), counter_id := i.counter_id]
  s <- bike_count_sensors(sensors_file)
  x <- s[, .(sensor_id, name, longitude, latitude, x, y, segment_id)][x, on = "sensor_id"]
  data.table::setcolorder(x, c("sensor_id", "name", "travel_mode", "direction", "flow_id", "flow_name", "time", "counts", "status", "counter_id"))
  x[]
}

# Bike lane history built by streets/layers/bike_lanes/scripts/03_time_windows.R: one row per
# SegmentID x time_window with date_from, date_to and tf_facilit / ft_facilit (Protected, Standard,
# Sharrows; NA = no lane in that direction). version "dot2026": all boroughs from the DOT 2026 version
# history (since 2026-10-14); "dot2020": the earlier build from the DOT 2020 release plus the
# Manhattan 2025 updates (no changes after 2020 outside Manhattan)
bikelane_windows_read <- function(version = c("dot2026", "dot2020")) {
  version <- match.arg(version)
  f <- file.path(nyc_streets_data_root(), "bike_lanes",
                 if (version == "dot2026") "bike_lanes_time_windows.RDS" else "bike_lanes_time_windows_dot2020.RDS")
  if (!file.exists(f)) stop(f, " not found: run layers/bike_lanes/scripts/03_time_windows.R in streets/")
  readRDS(f)
}

# DOT bike routes as sf in nyc_crs, with segmentid as an integer LION SegmentID
bike_routes_read <- function(file = nyc_latest("bike_routes")) {
  stopifnot(requireNamespace("sf", quietly = TRUE))
  br <- sf::st_read(file, quiet = TRUE)
  br <- br[!sf::st_is_empty(br), ]
  br$segmentid <- as.integer(br$segmentid)
  sf::st_transform(br, nyc_crs)
}


# Air pollution ----
# EPA AQS monitor data for the NYC area (scripts/40_download_epa_aqs.R, scripts/41_air_pollution_nyc.R).
# param: "44201" ozone, "42602" NO2, "NONOxNOy", "42101" CO, "42401" SO2, "88101" PM2.5 FRM/FEM,
# "88502" PM2.5 non-FRM, "81102" PM10, "WIND", "TEMP". freq "hourly" (sample_measurement per
# local hour) or "daily" (arithmetic_mean, aqi, by pollutant standard). nyc_only keeps the five boroughs.
air_pollution_read <- function(param, freq = c("hourly", "daily"), years = NULL, nyc_only = FALSE) {
  freq <- match.arg(freq)
  f <- file.path(nyc_data_root(), "derived", "air_pollution", paste0(freq, "_", param, ".parquet"))
  if (!file.exists(f)) stop(f, " not found: run scripts/41_air_pollution_nyc.R")
  ds <- arrow::open_dataset(f)
  if (nyc_only) ds <- dplyr::filter(ds, nyc)
  x <- data.table::setDT(dplyr::collect(ds))
  if (!is.null(years)) x <- x[data.table::year(date_local) %in% years]
  x[]
}

# Street network history readers ----
# streets_state(), streets_panel(), segment_key_read(), ... from streets/R/streets.R, so one
# source() of this file gives every reader. Skipped when streets.R is the file being sourced.
local({
  ofiles <- unlist(lapply(sys.frames(), function(f) if (is.character(f$ofile)) f$ofile))
  this <- tail(ofiles[grepl("nyc_transport\\.R$", ofiles)], 1)
  f <- file.path(if (length(this)) dirname(this) else "R", "..", "streets", "R", "streets.R")
  if (!any(grepl("(^|[/\\\\])streets\\.R$", ofiles)) && file.exists(f)) source(f, local = FALSE)
})
