# 05_full_event_study.R — MAIN RESULTS: all of 2024, all four venues (310 games).
#
# Same design as the pilot (03), scaled up:
#   treated units : the four venue zones (MSG 186, Barclays 181, Yankee Stadium 247, Citi Field 93)
#   controls      : busy zones (>= 5 trips per 15-min bin on average) that are NOT a venue zone,
#                   a spillover zone (< 800 m) or a ring zone (below)
#   fixed effects : zone x weekday x 15-min slot, and date; SEs clustered by date
#
# New here:
#   * event time from the NEAREST game end at the same venue (handles games ending near midnight)
#   * RELOCATION CHECK: "ring" zones whose centroid is 0.8-3 km from a venue. If drivers drive
#     TO the venue after a game, these zones may LOSE cars: trips fall and waits rise there.
#     Ring zones are kept out of the control group in the main spec so they cannot contaminate it.
#   * IV per venue, and robustness columns (borough x date FE; weather controls)
#
# MEMORY (the laptop has 8 GB; the first version crashed it):
#   * only clock slots 12:00-01:45 are loaded. All 2024 game ends fall 14:00-23:00, so every
#     event window (+/- 2 h) lies inside; slots outside never contain a game bin and would only
#     help estimate the date FE. This cuts the panel from ~7.7M to ~4.5M rows.
#   * joins are done in place (no merge copies), subsamples use feols(subset=) (no copies),
#     models are fit with lean = TRUE, and big objects are freed with gc() between steps.
#   * the panel build lives in code/lib_event_panel.R (shared with 06)
#   * Test first:  Rscript code/05_full_event_study.R test   (March only, outputs to tempdir)
#
# Outputs: output/figures/es_all_venues.png, output/figures/es_relocation.png
#          output/tables/es_all_venues.csv, es_relocation.csv, iv_main.tex, iv_by_venue.csv,
#          summary_stats.csv

source("code/00_setup.R")
source("code/lib_event_panel.R")

TEST <- "test" %in% commandArgs(trailingOnly = TRUE)
if (TEST) { DIR_TAB <- DIR_FIG <- tempdir(); message("TEST MODE: March 2024 only, outputs -> ", tempdir()) }

# ---- 1-4. Zones, panel, event time, outcomes (code/lib_event_panel.R) --------------------
b <- build_event_panel(TEST)
p <- b$p; ev <- b$ev; ring <- b$ring; rm(b)
if (!TEST) fwrite(ring, file.path(DIR_TAB, "ring_zones.csv"))

# ---- 4b. Summary statistics for the Data section (small: venue zones only) -------------
# venue zones, first hour after a game end vs. the same clock slots on non-game nights
post_qod <- p[post_game == 1, unique(qod)]
ss <- p[role == "venue" & (post_game == 1 | (rel == -1000 & qod %in% post_qod))]
ss[, period := fifelse(post_game == 1, "Hour after game end", "Same slots, no game")]
stats <- ss[, .(bins = .N, trips = mean(n_trips), surge_idx = mean(surge_idx, na.rm = TRUE),
                fare_per_mile = mean(med_fare_per_mile, na.rm = TRUE),
                pay_per_mile = mean(med_pay_per_mile, na.rm = TRUE),
                med_wait = mean(med_wait, na.rm = TRUE), p90_wait = mean(p90_wait, na.rm = TRUE),
                speed_mph = mean(med_speed_mph, na.rm = TRUE)),
            by = .(venue, period)][order(venue, period)]
fwrite(stats, file.path(DIR_TAB, "summary_stats.csv"))
print(stats, digits = 3)
rm(ss)
p[, c("n_dropoffs", "med_fare_per_mile", "med_pay_per_mile") := NULL]   # logs kept
mem("outcomes built")

outcomes <- OUTCOMES

is_main <- p$role != "ring"
is_ring <- p$role != "venue"

# ---- 5. Event study: venue zones (main) -------------------------------------------------
es_c <- run_es(p, "rel", "rel::", "Venue zones", is_main)
fwrite(es_c, file.path(DIR_TAB, "es_all_venues.csv"))
plot_es(copy(es_c), sprintf("Game end at four NYC venues, 2024 (%d games)", nrow(ev)), "es_all_venues.png")
mem("event study done")

# ---- 6. Relocation check: ring zones 0.8-3 km away -----------------------------------------
es_rc <- run_es(p, "relR", "relR::", "Ring zones (0.8-3 km)", is_ring)
fwrite(es_rc, file.path(DIR_TAB, "es_relocation.csv"))
plot_es(rbind(es_c, es_rc), "Relocation check: venue zones vs. surrounding ring zones",
        "es_relocation.png")
mem("relocation done")

# ---- 7. IV / 2SLS ----------------------------------------------------------------------------
fs   <- feols(surge_idx ~ post_game + other_game | zone^dow^qod + date, p, subset = is_main, cluster = ~date, lean = TRUE)
rf   <- feols(log_trips ~ post_game + other_game | zone^dow^qod + date, p, subset = is_main, cluster = ~date, lean = TRUE)
iv   <- feols(log_trips ~ other_game | zone^dow^qod + date | surge_idx ~ post_game, p, subset = is_main, cluster = ~date, lean = TRUE)
iv_f <- feols(log_trips ~ other_game | zone^dow^qod + date | log_fpm ~ post_game, p, subset = is_main, cluster = ~date, lean = TRUE)
iv_b <- feols(log_trips ~ other_game | zone^dow^qod + borough^date | surge_idx ~ post_game,
              p, subset = is_main, cluster = ~date, lean = TRUE)
iv_w <- feols(log_trips ~ other_game + rainy + snowy + i(temp_bin) | zone^dow^qod + date |
                surge_idx ~ post_game, p, subset = is_main, cluster = ~date, lean = TRUE)

hdr <- c("First stage", "Reduced form", "2SLS", "2SLS: fare/mile", "2SLS: boro x date FE",
         "2SLS: + weather")
etable(fs, rf, iv, iv_f, iv_b, iv_w, headers = hdr, keep = c("post_game", "surge_idx", "log_fpm"),
       fitstat = ~ n + ivf, file = file.path(DIR_TAB, "iv_main.tex"), replace = TRUE)
print(etable(fs, rf, iv, iv_f, iv_b, iv_w, headers = hdr,
             keep = c("post_game", "surge_idx", "log_fpm"), fitstat = ~ n + ivf))
rm(fs, rf, iv, iv_f, iv_b, iv_w); mem("IV done")

# by venue: one venue zone at a time against the same controls
by_v <- rbindlist(lapply(names(VENUE_ZONE), function(v) {
  sub_v <- p$role == "control" | p$zone == VENUE_ZONE[[v]]
  if (!any(p$post_game[sub_v] == 1)) return(NULL)                   # no games in sample (test mode)
  f <-feols(surge_idx ~ post_game + other_game | zone^dow^qod + date, p, subset = sub_v, cluster = ~date, lean = TRUE)
  r <- feols(log_trips ~ post_game + other_game | zone^dow^qod + date, p, subset = sub_v, cluster = ~date, lean = TRUE)
  i <- feols(log_trips ~ other_game | zone^dow^qod + date | surge_idx ~ post_game, p, subset = sub_v, cluster = ~date, lean = TRUE)
  out <- data.table(venue = v, games = ev[venue == v, .N],
             fs = coef(f)["post_game"], fs_se = se(f)["post_game"],
             rf = coef(r)["post_game"], rf_se = se(r)["post_game"],
             beta = coef(i)["fit_surge_idx"], beta_se = se(i)["fit_surge_idx"],
             F = fitstat(i, "ivf")[[1]]$stat)
  rm(f, r, i); gc()
  out
}))
fwrite(by_v, file.path(DIR_TAB, "iv_by_venue.csv"))
print(by_v, digits = 3)
mem("done")
