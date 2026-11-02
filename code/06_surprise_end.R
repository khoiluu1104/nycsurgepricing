# 06_surprise_end.R — Is the supply response pre-positioning or a live response to surge?
#
# Idea: drivers can plan for when a game is EXPECTED to end (start + a typical game length),
# but not for overtime, extra innings, rain delays or a fast blowout. Split games by the
# surprise in their length and re-run the event study and IV for each group.
#   * expected length = median length in the game's league (MLB / NBA / NHL)
#   * surprise        = actual length - expected length
#   * groups          : Ended early (<= -15 min), On time (within 15 min), Ran late (>= +15 min)
# Reading: if drivers mostly pre-position for the expected end, a late end catches fewer of them
# in place: surge should rise MORE and waits get LONGER at the actual end of late games, and the
# 2SLS ratio should be SMALLER there. Similar estimates across groups = little pre-positioning.
# Caveats: fans leave early in long/lopsided games (smaller post-game crowd); MLB length includes
# rain delays (weather), so the IV also reports a weather-controlled version.
#
# Also: event study split by league, to see where the pre-game rise in trips comes from.
#
# Outputs: output/figures/es_surprise.png, es_by_league.png
#          output/tables/games_surprise.csv, es_surprise.csv, es_by_league.csv, iv_by_surprise.csv
# Test first: Rscript code/06_surprise_end.R test   (March only, outputs to tempdir)

source("code/00_setup.R")
source("code/lib_event_panel.R")

TEST <- "test" %in% commandArgs(trailingOnly = TRUE)
if (TEST) { DIR_TAB <- DIR_FIG <- tempdir(); message("TEST MODE: March 2024 only, outputs -> ", tempdir()) }

b <- build_event_panel(TEST)
p <- b$p; ev <- b$ev; rm(b)

# ---- 1. Surprise in game length ----------------------------------------------------------
GRP <- c("Ended early", "On time", "Ran late")
ev[, exp_len := median(length_min), by = league]
ev[, surprise := length_min - exp_len]
ev[, grp := fcase(surprise <= -15, GRP[1], surprise >= 15, GRP[3], default = GRP[2])]
gs <- ev[, .(games = .N, mean_surprise_min = mean(surprise), min = min(surprise), max = max(surprise)),
         by = .(grp, league)][order(grp, league)]
fwrite(gs, file.path(DIR_TAB, "games_surprise.csv"))
print(gs, digits = 3)

p[ev, on = .(venue, gend = end), `:=`(grp = i.grp, league = i.league)]
is_main <- p$role != "ring"

es_out <- OUTCOMES[c("log_trips", "surge_idx", "med_wait", "p90_wait", "log_drop")]

# ---- 2. Event study by surprise group -----------------------------------------------------
p[, relG := fifelse(rel == -1000L, "none", paste0(grp, "_", rel))]
es_s <- run_es(p, "relG", "relG::", NULL, is_main, outcomes = es_out, ref = "none")
fwrite(es_s, file.path(DIR_TAB, "es_surprise.csv"))
plot_es(es_s, "Games that ended early, on time, or late (vs. league median length)",
        "es_surprise.png", outcomes = es_out)
p[, relG := NULL]; mem("surprise event study done")

# ---- 3. Event study by league --------------------------------------------------------------
p[, relL := fifelse(rel == -1000L, "none", paste0(league, "_", rel))]
es_l <- run_es(p, "relL", "relL::", NULL, is_main, outcomes = es_out, ref = "none")
fwrite(es_l, file.path(DIR_TAB, "es_by_league.csv"))
plot_es(es_l, "Game end by league (MLB: Yankees, Mets; NBA: Knicks, Nets; NHL: Rangers)",
        "es_by_league.png", outcomes = es_out)
p[, relL := NULL]; mem("league event study done")

# ---- 4. IV by surprise group -----------------------------------------------------------------
# For group g: post_g = first hour after a group-g game; every other game bin gets other_g.
# Early/late games are mostly MLB, so the split is also run on MLB games only (same league).
iv_s <- rbindlist(lapply(c("All leagues", "MLB only"), function(smp) rbindlist(lapply(GRP, function(g) {
  lg <- if (smp == "MLB only") "MLB" else c("MLB", "NBA", "NHL")
  p[, post_g  := as.integer(post_game == 1L & grp %chin% g & league %chin% lg)]
  p[, other_g := as.integer(rel != -1000L & post_g == 0L)]
  if (!any(p$post_g[is_main] == 1L)) return(NULL)
  f  <- feols(surge_idx ~ post_g + other_g | zone^dow^qod + date, p, subset = is_main, cluster = ~date, lean = TRUE)
  r  <- feols(log_trips ~ post_g + other_g | zone^dow^qod + date, p, subset = is_main, cluster = ~date, lean = TRUE)
  w  <- feols(med_wait  ~ post_g + other_g | zone^dow^qod + date, p, subset = is_main, cluster = ~date, lean = TRUE)
  i  <- feols(log_trips ~ other_g | zone^dow^qod + date | surge_idx ~ post_g, p, subset = is_main, cluster = ~date, lean = TRUE)
  iw <- feols(log_trips ~ other_g + rainy + snowy + i(temp_bin) | zone^dow^qod + date | surge_idx ~ post_g,
              p, subset = is_main, cluster = ~date, lean = TRUE)
  out <- data.table(sample = smp, group = g, games = ev[grp == g & league %chin% lg, .N],
                    fs = coef(f)["post_g"], fs_se = se(f)["post_g"],
                    rf = coef(r)["post_g"], rf_se = se(r)["post_g"],
                    wait = coef(w)["post_g"], wait_se = se(w)["post_g"],
                    beta = coef(i)["fit_surge_idx"], beta_se = se(i)["fit_surge_idx"],
                    beta_weather = coef(iw)["fit_surge_idx"], beta_weather_se = se(iw)["fit_surge_idx"],
                    F = fitstat(i, "ivf")[[1]]$stat)
  rm(f, r, w, i, iw); gc()
  out
}))))
p[, c("post_g", "other_g") := NULL]
fwrite(iv_s, file.path(DIR_TAB, "iv_by_surprise.csv"))
print(iv_s, digits = 3)
mem("done")
