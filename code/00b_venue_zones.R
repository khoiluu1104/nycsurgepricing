# 00b_venue_zones.R — which TLC taxi zone contains each venue, and which zones are
# within 800 m (spillover). Results are copied into VENUE_ZONE / VENUE_SPILLOVER in 00_setup.R.
# Output: data/events/venue_zones.csv

source("code/00_setup.R")
library(sf)

# cached copy of the TLC zone shapefile (downloaded once; the server rate-limits repeat requests)
zip <- file.path(DIR_EVENTS, "taxi_zones.zip")
if (!file.exists(zip)) download.file("https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.zip", zip, mode = "wb")
unzip(zip, exdir = tempdir())
z <- st_read(file.path(tempdir(), "taxi_zones", "taxi_zones.shp"), quiet = TRUE)

# zone lookup table (LocationID, Borough, Zone), saved locally for the other scripts
fwrite(data.table(LocationID = z$LocationID, Borough = z$borough, Zone = z$zone)[order(LocationID)],
       file.path(DIR_EVENTS, "taxi_zone_lookup.csv"))

venues <- data.frame(
  venue = c("Madison Square Garden", "Barclays Center", "Yankee Stadium", "Citi Field"),
  lat   = c(40.7505, 40.6826, 40.8296, 40.7571),
  lon   = c(-73.9934, -73.9754, -73.9262, -73.8458))
pts <- st_transform(st_as_sf(venues, coords = c("lon", "lat"), crs = 4326), st_crs(z))

home <- st_join(pts, z[, c("LocationID", "zone", "borough")])
near <- st_is_within_distance(pts, z, dist = 800 * 3.28084)   # shapefile CRS (EPSG:2263) is in feet

out <- rbindlist(lapply(seq_len(nrow(venues)), function(i) {
  ids <- z$LocationID[near[[i]]]
  data.table(venue = venues$venue[i], zone = ids, zone_name = z$zone[near[[i]]],
             role = fifelse(ids == home$LocationID[i], "venue", "spillover (<800 m)"))
}))
setorder(out, venue, -role, zone)
fwrite(out, file.path(DIR_EVENTS, "venue_zones.csv"))
print(out)
