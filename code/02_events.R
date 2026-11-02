# 02_events.R — home games at the four NYC venues, with start AND end times.
#
# Sources
#   NBA, NHL: basketball-reference.com / hockey-reference.com schedule pages
#             (start time ET, attendance, game length "LOG"). Rate-limited, so we pause between pages.
#   MLB:      MLB Stats API (statsapi.mlb.com): schedule + each game's boxscore
#             (first pitch, game length "T", delay, attendance).
# Each season's raw scrape is cached in data/events/raw_*.csv, so re-runs do not re-scrape.
#
# Output: data/events/games_all.csv   (every game, all seasons scraped)
#         data/events/games_2024.csv  (games that END in calendar 2024: the analysis sample)
#
# Usage: Rscript code/02_events.R

source("code/00_setup.R")
library(jsonlite)

UA <- "Mozilla/5.0 (academic research; ECO1400 term paper)"
get_page <- function(url) { Sys.sleep(4); read_html(httr::GET(url, httr::user_agent(UA))) }
cached <- function(file, f) {
  path <- file.path(DIR_EVENTS, file)
  if (file.exists(path)) return(fread(path))
  d <- f(); fwrite(d, path); d
}

# "2:34" -> 154 minutes
log_to_min <- function(x) {
  p <- strsplit(gsub("[^0-9:]", "", x), ":", fixed = TRUE)
  vapply(p, function(v) if (length(v) == 2) as.numeric(v[1]) * 60 + as.numeric(v[2]) else NA_real_, 0)
}
num <- function(x) as.numeric(gsub("[^0-9.]", "", x))

# ---- NBA: one page per month -------------------------------------------------
nba_season <- function(season_end_year,
                       months = c("october", "november", "december", "january", "february",
                                  "march", "april", "may", "june")) {
  rbindlist(lapply(months, function(m) {
    url <- sprintf("https://www.basketball-reference.com/leagues/NBA_%d_games-%s.html",
                   season_end_year, m)
    tabs <- tryCatch(html_table(get_page(url)), error = function(e) list())
    if (!length(tabs)) return(NULL)
    d <- as.data.table(tabs[[1]], .name_repair = "unique")
    d <- d[Date != "Date" & Date != "Playoffs"]
    data.table(league = "NBA",
               date   = as.character(as.Date(d$Date, format = "%a, %b %d, %Y")),
               start_txt = d[["Start (ET)"]],
               home = d[["Home/Neutral"]], away = d[["Visitor/Neutral"]],
               attendance = num(d[["Attend."]]), length_min = log_to_min(d$LOG),
               arena = d$Arena)
  }), fill = TRUE)
}

# ---- NHL: one page per season (regular season + playoffs tables) --------------
nhl_season <- function(season_end_year) {
  url  <- sprintf("https://www.hockey-reference.com/leagues/NHL_%d_games.html", season_end_year)
  tabs <- html_table(get_page(url))
  rbindlist(lapply(tabs, function(t) {
    d <- as.data.table(t, .name_repair = "unique")
    if (!"Home" %in% names(d)) return(NULL)
    d <- d[Date != "Date"]
    data.table(league = "NHL", date = as.character(as.Date(d$Date)), start_txt = d$Time,
               home = d$Home, away = d$Visitor,
               attendance = num(d$Att.), length_min = log_to_min(d$LOG), arena = NA_character_)
  }), fill = TRUE)
}

# ---- MLB: Stats API schedule + boxscore per home game ------------------------------
mlb_season <- function(team_id, season) {
  s <- fromJSON(sprintf(paste0("https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=%d",
                               "&season=%d&gameType=R,F,D,L,W"), team_id, season),
                simplifyVector = FALSE)
  games <- unlist(lapply(s$dates, `[[`, "games"), recursive = FALSE)
  games <- Filter(function(g) g$teams$home$team$id == team_id &&
                    g$status$detailedState %in% c("Final", "Completed Early"), games)
  rbindlist(lapply(games, function(g) {
    Sys.sleep(0.3)
    b <- fromJSON(sprintf("https://statsapi.mlb.com/api/v1/game/%d/boxscore", g$gamePk),
                  simplifyVector = FALSE)
    info <- setNames(vapply(b$info, function(i) if (is.null(i$value)) NA_character_ else i$value, ""),
                     vapply(b$info, function(i) i$label, ""))
    data.table(league = "MLB", date = g$officialDate,
               start_txt = sub("\\.$", "", info["First pitch"]),
               home = g$teams$home$team$name, away = g$teams$away$team$name,
               attendance = num(info["Att"]),
               length_min = log_to_min(sub(" .*", "", info["T"])) +
                 fifelse(is.na(info["Delay"]), 0, log_to_min(sub(" .*", "", info["Delay"]))),
               arena = g$venue$name)
  }), fill = TRUE)
}

# "7:30p" (NBA), "7:30 PM" (NHL, MLB) -> POSIXct, as naive local time
parse_start <- function(date, txt) {
  txt <- toupper(gsub("\\s+", "", txt))
  txt <- sub("([AP])$", "\\1M", txt)
  as_local(strptime(paste(date, txt), "%Y-%m-%d %I:%M%p", tz = "UTC"))
}

HOME_VENUE <- c("New York Knicks"  = "Madison Square Garden",
                "New York Rangers" = "Madison Square Garden",
                "Brooklyn Nets"    = "Barclays Center",
                "New York Yankees" = "Yankee Stadium",
                "New York Mets"    = "Citi Field")

raw <- rbind(
  cached("raw_nba_2023-24.csv", function() nba_season(2024)),
  cached("raw_nba_2024-25.csv", function() nba_season(2025)),
  cached("raw_nhl_2023-24.csv", function() nhl_season(2024)),
  cached("raw_nhl_2024-25.csv", function() nhl_season(2025)),
  cached("raw_mlb_nyy_2024.csv", function() mlb_season(147L, 2024L)),
  cached("raw_mlb_nym_2024.csv", function() mlb_season(121L, 2024L)),
  fill = TRUE)

g <- raw[home %in% names(HOME_VENUE)]
# drop neutral-site "home" games (e.g. NBA games abroad); MLB/NBA pages name the venue
g <- g[is.na(arena) | arena == "" |
         grepl("Madison Square Garden|Barclays|Yankee Stadium|Citi Field", arena)]
g[, venue := HOME_VENUE[home]]
g[, zone  := VENUE_ZONE[venue]]
g[, start := parse_start(date, start_txt)]
g[, end   := start + length_min * 60]
g <- g[!is.na(start)]
setorder(g, start)
g <- unique(g, by = c("venue", "start"))
g <- g[, .(league, home, away, venue, zone, date = as.Date(date), start, end, length_min, attendance)]

fwrite(g, file.path(DIR_EVENTS, "games_all.csv"), dateTimeAs = "write.csv")
g24 <- g[format(end, "%Y") == "2024"]
fwrite(g24, file.path(DIR_EVENTS, "games_2024.csv"), dateTimeAs = "write.csv")

message(sprintf("%d games in all; %d end in 2024 -> data/events/games_2024.csv", nrow(g), nrow(g24)))
print(g24[, .(games = .N, missing_end = sum(is.na(end)),
              median_length = median(length_min, na.rm = TRUE)), by = .(venue, home)])
# Same-venue overlaps (two events less than 4 hours apart) need care in the event-time coding
ov <- g24[order(venue, start)][, gap_h := as.numeric(difftime(start, shift(end), units = "hours")), by = venue][gap_h < 4]
message(sprintf("%d games start within 4 hours of the previous game at the same venue", nrow(ov)))
