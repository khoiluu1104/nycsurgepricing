# 00_setup.R — packages, paths and constants shared by every script.
# Run scripts from the project root (opening NYC_Surge_Project.Rproj does this).

pkgs <- c("DBI", "duckdb", "data.table", "fixest", "ggplot2", "rvest")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

stopifnot("Run from the project root" = file.exists("NYC_Surge_Project.Rproj"))

DIR_DERIVED <- "data/derived"
DIR_EVENTS  <- "data/events"
DIR_FIG     <- "output/figures"
DIR_TAB     <- "output/tables"

# NYC TLC high-volume FHV (Uber/Lyft) monthly files, read remotely (no download)
tlc_url <- function(ym) sprintf(
  "https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_%s.parquet", ym)

# TLC taxi zone containing each venue: point-in-polygon on the TLC zone shapefile
# (code/00b_venue_zones.R -> data/events/venue_zones.csv)
VENUE_ZONE <- c(
  "Madison Square Garden" = 186L,  # Penn Station/Madison Sq West
  "Barclays Center"       = 181L,  # Park Slope (the zone's edge runs along Flatbush/Atlantic)
  "Yankee Stadium"        = 247L,  # West Concourse
  "Citi Field"            = 93L    # Flushing Meadows-Corona Park
)

# Spillover zones: other zones within 800 m of the venue. Crowds walk into them before
# booking, so they are left out of the control group (and can be treated in robustness checks).
VENUE_SPILLOVER <- list(
  "Madison Square Garden" = c(48L, 68L, 90L, 100L, 164L, 234L, 246L),
  "Barclays Center"       = c(25L, 49L, 97L, 106L, 189L),
  "Yankee Stadium"        = c(42L, 69L, 119L),
  "Citi Field"            = c(57L, 70L, 92L, 173L, 253L)
)
MSG_NEIGHBOURS <- VENUE_SPILLOVER[["Madison Square Garden"]]   # used by the pilot script

BIN_MIN <- 15  # panel time resolution in minutes

# Timestamps are kept as naive NYC local clock time, stored as "UTC" so DST never shifts them
as_local <- function(x) as.POSIXct(x, tz = "UTC")
