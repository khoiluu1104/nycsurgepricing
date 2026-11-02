# lib_event_panel.R — builds the zone x 15-min event panel used by 05 and 06.
# Sourced, not run on its own. Requires code/00_setup.R to be sourced first.
#
# build_event_panel(test = FALSE) returns list(p, ev, ring):
#   p    : one row per zone x 15-min bin, clock slots 12:00-01:45 only (all game ends fall 14:00-23:00,
#          so every +/- 2 h window is inside). Columns: outcomes, FE keys, role (venue/ring/control),
#          rel / relR (event time for venue / ring zones, -999 = same day outside window, -1000 = none),
#          gend (the game end the bin is timed against; NA for controls), post_game, other_game, weather.
#   ev   : games_2024.csv with end as POSIXct
#   ring : ring zones (centroid 0.8-3 km from a venue) and their venue
# Memory: ~4.2M rows, ~0.8 GB in R for the full year. Joins are in place (no copies).

WIN    <- c(-8L, 8L)      # event window: 2 hours before to 2 hours after game end (15-min bins)
NEAR   <- 12 * 60         # bins within 12 h of a game end but outside the window get rel = -999
RING_M <- 3000            # ring zones: centroid within 3 km of the venue
HOURS  <- c(12:23, 0:1)   # clock hours loaded

mem <- function(step) { g <- gc(); message(sprintf("[%s] R memory in use: %.0f MB", step, sum(g[, 2]))) }

build_event_panel <- function(test = FALSE) {
  library(sf)
  months <- if (test) "2024-03" else "2024-*"
  period <- if (test) c("2024-03-01 00:00:00", "2024-03-31 23:45:00") else c("2024-01-01 00:00:00", "2024-12-31 23:45:00")

  # ---- Zones: venue, spillover, ring, controls ----
  zl <- unique(fread(file.path(DIR_EVENTS, "taxi_zone_lookup.csv")), by = "LocationID")
  unzip(file.path(DIR_EVENTS, "taxi_zones.zip"), exdir = tempdir())
  shp <- st_read(file.path(tempdir(), "taxi_zones", "taxi_zones.shp"), quiet = TRUE)
  cen <- suppressWarnings(st_centroid(shp))
  vpts <- st_transform(st_as_sf(data.frame(
    venue = names(VENUE_ZONE),
    lat = c(40.7505, 40.6826, 40.8296, 40.7571), lon = c(-73.9934, -73.9754, -73.9262, -73.8458)),
    coords = c("lon", "lat"), crs = 4326), st_crs(shp))
  dist_m <- st_distance(cen, vpts) / 3.28084                   # EPSG:2263 is in feet
  dist_m <- matrix(as.numeric(dist_m), nrow = nrow(shp), dimnames = list(shp$LocationID, names(VENUE_ZONE)))

  near_zones <- unique(c(VENUE_ZONE, unlist(VENUE_SPILLOVER)))
  ring <- rbindlist(lapply(names(VENUE_ZONE), function(v) {
    ids <- as.integer(rownames(dist_m))[dist_m[, v] <= RING_M]
    data.table(zone = setdiff(ids, near_zones), venue = v)
  }))
  ring <- ring[, .SD[1], by = zone]                             # a zone near two venues: keep the first
  ring <- merge(ring, zl, by.x = "zone", by.y = "LocationID")

  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  vol <- as.data.table(dbGetQuery(con, sprintf(
    "SELECT zone, sum(n_trips) / 35136.0 AS per_bin FROM read_parquet('%s/panel_2024-*.parquet') GROUP BY 1",
    DIR_DERIVED)))
  ctrl <- setdiff(vol[per_bin >= 5, zone], c(near_zones, ring$zone))
  keep <- c(VENUE_ZONE, ring$zone, ctrl)
  message(sprintf("4 venue zones, %d ring zones, %d control zones", nrow(ring), length(ctrl)))

  # ---- Panel, evening slots only, empty bins filled ----
  p <- as.data.table(dbGetQuery(con, sprintf("
    SELECT zone, bin, n_trips, n_dropoffs, surge_idx, med_fare_per_mile, med_pay_per_mile,
           med_wait, p90_wait, med_speed_mph
    FROM read_parquet('%s/panel_%s.parquet')
    WHERE zone IN (%s) AND bin >= TIMESTAMP '%s' AND bin <= TIMESTAMP '%s'
      AND hour(bin) IN (%s)",
    DIR_DERIVED, months, paste(keep, collapse = ","), period[1], period[2], paste(HOURS, collapse = ","))))
  p[, bin := as_local(bin)]
  all_bins <- seq(as_local(period[1]), as_local(period[2]), by = BIN_MIN * 60)
  all_bins <- all_bins[hour(all_bins) %in% HOURS]
  p <- p[CJ(zone = keep, bin = all_bins), on = .(zone, bin)]
  p[is.na(n_trips), n_trips := 0L][is.na(n_dropoffs), n_dropoffs := 0L]
  p[, `:=`(date = as.Date(bin), dow = wday(bin), qod = hour(bin) * 4L + minute(bin) %/% 15L)]
  p[zl, on = .(zone = LocationID), borough := i.Borough]
  message(sprintf("panel: %s rows", format(nrow(p), big.mark = ",")))

  # ---- Event time: nearest game end at the zone's venue ----
  ev <- fread(file.path(DIR_EVENTS, "games_2024.csv"))
  ev[, `:=`(end = as_local(end), start = as_local(start), length_min = as.numeric(length_min))]
  zone_venue <- rbind(data.table(zone = unname(VENUE_ZONE), venue = names(VENUE_ZONE), role = "venue"),
                      ring[, .(zone, venue, role = "ring")])
  p[zone_venue, on = .(zone), `:=`(venue = i.venue, role = i.role)]
  p[is.na(role), role := "control"]

  tr <- p[role != "control", .(zone, bin, venue)]
  tr <- ev[, .(venue, end, gend = end)][tr, on = .(venue, end = bin), roll = "nearest"]
  setnames(tr, "end", "bin")
  tr[, mins := as.numeric(difftime(bin, gend, units = "mins"))]
  tr[, k := as.integer(floor(mins / BIN_MIN))]
  tr[, rel_t := fifelse(k >= WIN[1] & k <= WIN[2], k, fifelse(abs(mins) <= NEAR, -999L, -1000L))]
  tr[rel_t == -1000L, gend := NA]
  p[, `:=`(rel_t = -1000L, gend = as_local(NA))]
  p[tr, on = .(zone, bin), `:=`(rel_t = i.rel_t, gend = i.gend)]
  rm(tr)
  p[, rel  := fifelse(role == "venue", rel_t, -1000L)]
  p[, relR := fifelse(role == "ring",  rel_t, -1000L)]
  p[, rel_t := NULL]

  # ---- Outcomes, weather, IV dummies ----
  p[, `:=`(log_trips = log1p(n_trips), log_drop = log1p(n_dropoffs),
           log_fpm = log(med_fare_per_mile), log_pay_pm = log(med_pay_per_mile))]
  w <- fread(file.path(DIR_EVENTS, "weather_2024_hourly.csv"))
  w[, hour := as_local(hour)]
  p[, hour := as_local(trunc(bin, "hours"))]
  p[w, on = .(hour), `:=`(temp_c = i.temp_c, rainy = i.rainy, snowy = i.snowy)]
  p[, temp_bin := cut(temp_c, c(-Inf, 0, 10, 20, 25, 30, Inf))]
  p[, c("hour", "temp_c") := NULL]
  p[, post_game  := as.integer(rel >= 0 & rel <= 3)]               # first hour after game end
  p[, other_game := as.integer(rel != -1000 & !(rel >= 0 & rel <= 3))]
  mem("panel built")
  list(p = p, ev = ev, ring = ring)
}

OUTCOMES <- c(log_trips  = "Trips (log)",
              surge_idx  = "Implied surge index (log points)",
              log_pay_pm = "Driver pay per mile (log)",
              med_wait   = "Median wait (min)",
              p90_wait   = "90th pct wait (min)",
              med_speed_mph = "Median speed (mph)",
              log_drop   = "Drop-offs (log)")

# Event study, one outcome at a time (lean models, memory freed in between).
# rhs_var is an integer event-time column (ref -1000) or a character "<group>_<k>" column (ref "none").
run_es <- function(p, rhs_var, prefix, label, keep_rows, outcomes = OUTCOMES, ref = -1000) {
  ref_txt <- if (is.character(ref)) sprintf('"%s"', ref) else ref
  rbindlist(lapply(names(outcomes), function(y) {
    m <- feols(as.formula(sprintf("%s ~ i(%s, ref = %s) | zone^dow^qod + date", y, rhs_var, ref_txt)),
               data = p, subset = keep_rows, cluster = ~date, lean = TRUE)
    ct <- as.data.table(coeftable(m), keep.rownames = "term")[startsWith(term, prefix)]
    rm(m); gc()
    lvl <- sub(prefix, "", ct$term, fixed = TRUE)
    # grouped event time is coded "<group>_<k>" (e.g. "Ran late_-2"); plain event time is "<k>"
    grp <- if (is.character(ref)) sub("_-?[0-9]+$", "", lvl) else label
    ct[, `:=`(sample = grp, rel = as.integer(sub(".*_", "", lvl)))]
    ct[rel >= WIN[1] & rel <= WIN[2],
       .(sample, outcome = outcomes[[y]], minutes = rel * BIN_MIN, est = Estimate,
         se = `Std. Error`, lo = Estimate - 1.96 * `Std. Error`, hi = Estimate + 1.96 * `Std. Error`)]
  }))
}

plot_es <- function(d, title, file, outcomes = OUTCOMES,
                    subtitle = "FE: zone x weekday x 15-min slot, and date; SEs clustered by date") {
  d[, outcome := factor(outcome, levels = outcomes)]
  g <- ggplot(d, aes(minutes, est, colour = sample, fill = sample)) +
    geom_hline(yintercept = 0, colour = "grey50") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey30") +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, colour = NA) +
    geom_line() + geom_point(size = 0.8) +
    facet_wrap(~outcome, scales = "free_y", ncol = 2) +
    labs(x = "Minutes relative to game end (request time, 15-min bins)",
         y = "Difference vs. non-game nights (95% CI)", title = title, subtitle = subtitle,
         colour = NULL, fill = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
  ggsave(file.path(DIR_FIG, file), g, width = 9, height = 2.6 * ceiling(length(unique(d$outcome)) / 2) + 1, dpi = 150)
}
