# 02b_weather.R — hourly NYC weather for 2024, a control for the DML step and robustness checks.
# Source: Open-Meteo Historical Weather API (ERA5 reanalysis), grid point nearest Central Park.
#         https://open-meteo.com/en/docs/historical-weather-api   (no key needed)
# Note: reanalysis is gridded, not a station reading. For a station series, NOAA Local
#       Climatological Data for Central Park (WBAN 94728) is the alternative.
# Output: data/events/weather_2024_hourly.csv  (local NYC clock time, naive)

source("code/00_setup.R")

url <- paste0("https://archive-api.open-meteo.com/v1/archive?latitude=40.7812&longitude=-73.9665",
              "&start_date=2024-01-01&end_date=2024-12-31",
              "&hourly=temperature_2m,precipitation,rain,snowfall,wind_speed_10m",
              "&timezone=America%2FNew_York")
w <- jsonlite::fromJSON(url)$hourly
w <- as.data.table(w)
setnames(w, c("time", "temp_c", "precip_mm", "rain_mm", "snow_cm", "wind_kmh"))
w[, hour := as_local(strptime(time, "%Y-%m-%dT%H:%M", tz = "UTC"))][, time := NULL]
w[, `:=`(rainy = as.integer(precip_mm >= 0.5), snowy = as.integer(snow_cm > 0))]
setcolorder(w, "hour")
fwrite(w, file.path(DIR_EVENTS, "weather_2024_hourly.csv"), dateTimeAs = "write.csv")
message(sprintf("%d hourly rows; %d rainy hours, %d snowy hours", nrow(w), sum(w$rainy), sum(w$snowy)))
