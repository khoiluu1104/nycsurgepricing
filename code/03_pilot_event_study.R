# 03_pilot_event_study.R — PILOT: does a game ending at Madison Square Garden
# move prices, trips and wait times in the MSG zone? (one month, one venue)
#
# Comparison: MSG zone on game nights vs (a) the same zone, same weekday, same
# 15-min slot on non-game nights [zone^dow^qod FE], net of (b) anything that hit
# all of Manhattan that day [date FE, identified from the control zones].

source("code/00_setup.R")

PILOT_MONTH <- "2024-03"
MSG <- VENUE_ZONE[["Madison Square Garden"]]
WIN <- c(-8L, 8L)   # event window in 15-min bins: 2 hours before to 2 hours after the game ends

# ---- 1. Panel: MSG zone + Manhattan control zones, with empty bins filled ------
zones <- unique(fread(file.path(DIR_EVENTS, "taxi_zone_lookup.csv")), by = "LocationID")  # from 00b_venue_zones.R
con <- dbConnect(duckdb::duckdb())
p <- as.data.table(dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet('%s/panel_%s.parquet')", DIR_DERIVED, PILOT_MONTH)))
dbDisconnect(con, shutdown = TRUE)
p[, bin := as_local(bin)]

manhattan <- zones[Borough == "Manhattan", LocationID]
busy <- p[, .(m = sum(n_trips) / uniqueN(p$bin)), by = zone][m >= 10, zone]   # >= 10 trips per bin on average
ctrl <- setdiff(intersect(manhattan, busy), c(MSG, MSG_NEIGHBOURS))
keep <- c(MSG, ctrl)
message(sprintf("MSG zone + %d Manhattan control zones", length(ctrl)))

grid <- CJ(zone = keep, bin = sort(unique(p$bin)))
p <- p[grid, on = .(zone, bin)]
p[is.na(n_trips), n_trips := 0L]

p[, `:=`(date = as.Date(bin), dow = wday(bin),
         qod  = hour(bin) * 4L + minute(bin) %/% 15L)]   # 15-min slot of the day, 0..95

# ---- 2. Event time: 15-min bins relative to the nearest game end, same day ---------
ev <- fread(file.path(DIR_EVENTS, "games_2024.csv"))
ev <- ev[zone == MSG & !is.na(end)]
ev[, `:=`(end = as_local(end), date = as.Date(date))]

msg_bins <- p[zone == MSG, .(bin, date)]
m <- ev[msg_bins, on = .(date), allow.cartesian = TRUE, nomatch = NULL]
m[, k := floor(as.numeric(difftime(bin, end, units = "mins")) / BIN_MIN)]
m <- m[, .SD[which.min(abs(k))], by = bin]          # nearest game if there are two that day

p[, rel := -1000L]                                    # -1000 = no game: the reference group
p[m, on = .(bin), rel := fifelse(zone == MSG,
                                 fifelse(i.k >= WIN[1] & i.k <= WIN[2], as.integer(i.k), -999L),
                                 -1000L)]
# -999 = game day but outside the window (e.g. the afternoon before): gets its own dummy, not plotted

# ---- 3. Outcomes ---------------------------------------------------------------
p[, `:=`(log_trips   = log1p(n_trips),
         log_fpm     = log(med_fare_per_mile),
         log_pay_pm  = log(med_pay_per_mile))]
outcomes <- c(log_trips  = "Trips (log)",
              surge_idx  = "Implied surge index (log points)",
              log_fpm    = "Fare per mile (log)",
              log_pay_pm = "Driver pay per mile (log)",
              med_wait   = "Median wait (min)",
              p90_wait   = "90th pct wait (min)",
              med_speed_mph = "Median speed (mph)")

# ---- 4. Event study -------------------------------------------------------------
es <- feols(.[names(outcomes)] ~ i(rel, ref = -1000) | zone^dow^qod + date,
            data = p, cluster = ~date)

coefs <- rbindlist(lapply(seq_along(outcomes), function(j) {
  ct <- as.data.table(coeftable(es[[j]]), keep.rownames = "term")
  ct[, rel := as.integer(sub("rel::", "", term))]
  ct[rel >= WIN[1] & rel <= WIN[2],
     .(outcome = outcomes[[j]], minutes = rel * BIN_MIN,
       est = Estimate, lo = Estimate - 1.96 * `Std. Error`, hi = Estimate + 1.96 * `Std. Error`)]
}))
coefs[, outcome := factor(outcome, levels = outcomes)]
fwrite(coefs, file.path(DIR_TAB, "pilot_msg_event_study.csv"))

g <- ggplot(coefs, aes(minutes, est)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.2) +
  geom_line() + geom_point(size = 1) +
  facet_wrap(~outcome, scales = "free_y", ncol = 2) +
  labs(x = "Minutes relative to game end (request time, 15-min bins)",
       y = "Difference vs. non-game nights (95% CI)",
       title = sprintf("Pilot: Madison Square Garden zone, %s (%d games)",
                       PILOT_MONTH, ev[format(date, "%Y-%m") == PILOT_MONTH, .N]),
       subtitle = "Fixed effects: zone x weekday x 15-min slot, and date; SEs clustered by date") +
  theme_minimal(base_size = 11)
ggsave(file.path(DIR_FIG, "pilot_msg_event_study.png"), g, width = 9, height = 10, dpi = 150)

# ---- 5. Pilot IV / 2SLS: game ending as the instrument for price ------------------------
# post_game = first hour after the game ends; other_game = remaining game-day bins (controlled for)
p[, post_game  := as.integer(rel >= 0 & rel <= 3)]
p[, other_game := as.integer(rel != -1000 & !(rel >= 0 & rel <= 3))]

iv <- feols(log_trips ~ other_game | zone^dow^qod + date | log_fpm ~ post_game,
            data = p, cluster = ~date)
fs <- feols(log_fpm   ~ post_game + other_game | zone^dow^qod + date, data = p, cluster = ~date)
rf <- feols(log_trips ~ post_game + other_game | zone^dow^qod + date, data = p, cluster = ~date)
# same IV with the implied surge index (fare net of trip length/duration) as the price
iv_s <- feols(log_trips ~ other_game | zone^dow^qod + date | surge_idx ~ post_game,
              data = p, cluster = ~date)
fs_s <- feols(surge_idx ~ post_game + other_game | zone^dow^qod + date, data = p, cluster = ~date)

hdr <- c("FS: fare/mile", "Reduced form", "2SLS: fare/mile", "FS: surge index", "2SLS: surge index")
etable(fs, rf, iv, fs_s, iv_s, headers = hdr,
       fitstat = ~ n + ivf, file = file.path(DIR_TAB, "pilot_msg_iv.tex"), replace = TRUE)
print(etable(fs, rf, iv, fs_s, iv_s, headers = hdr, fitstat = ~ n + ivf))
cat(sprintf("\nWald check: reduced form / first stage = %.3f / %.3f = %.2f\n",
            coef(rf)["post_game"], coef(fs)["post_game"],
            coef(rf)["post_game"] / coef(fs)["post_game"]))
