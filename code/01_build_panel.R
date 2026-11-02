# 01_build_panel.R — stream a month of Uber/Lyft trips from the TLC and collapse
# them to a zone x 15-minute panel. Only the small panel is saved to disk
# (~35 MB per month), never the raw trips (~500 MB per month).
#
# Usage (from the project root):  Rscript code/01_build_panel.R 2024-01 2024-02 ...
# With no arguments it builds the pilot month, 2024-03.
#
# Price measure: IMPLIED SURGE INDEX
#   Fare per mile changes when the MIX of trips changes (e.g. more short trips after a game),
#   not only when surge changes. So for each month and company we fit a "rate card"
#       log(fare) = b0 + b1 log(miles) + b2 log(minutes) + b3 airport/out-of-city drop-off
#   on all clean trips, and define each trip's implied surge as its residual (log points):
#   how much more it cost than a typical trip of the same length and duration.
#   The panel stores the median and mean residual per zone x bin.
#   Pass 1 computes the regression from sums in DuckDB (X'X, X'y), then R solves it.

source("code/00_setup.R")

AIRPORT_OR_OUT <- c(1L, 132L, 138L, 264L, 265L)  # Newark, JFK, LaGuardia, unknown/outside NYC

CLEAN <- "base_passenger_fare BETWEEN 2.5 AND 500 AND trip_miles BETWEEN 0.2 AND 60
          AND trip_time BETWEEN 60 AND 10800"

build_month <- function(ym) {
  out      <- file.path(DIR_DERIVED, sprintf("panel_%s.parquet", ym))
  coef_out <- file.path(DIR_DERIVED, sprintf("surge_coefs_%s.csv", ym))
  if (file.exists(out)) { message(ym, ": already built, skipping"); return(invisible(out)) }

  start <- as.Date(paste0(ym, "-01"))
  end   <- seq(start, by = "month", length.out = 2)[2]
  t0 <- Sys.time()

  # Download the month ONCE (one HTTP request), process it locally, then delete it.
  # Reading remotely with many range requests got this machine rate-limited (HTTP 403)
  # by the TLC's CloudFront server. The file is ~500 MB and lives only in the temp folder.
  url <- tempfile(fileext = ".parquet")
  on.exit(unlink(url), add = TRUE)
  rc <- system2("curl", c("-sfL", "--retry", "3", "--retry-delay", "60", "-o", shQuote(url),
                          shQuote(tlc_url(ym))))
  if (rc != 0 || !file.exists(url)) stop("download failed (curl exit ", rc, ")")

  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # ---- pass 1: rate-card regression per company, from sums ---------------------------
  xs  <- c("1", "ln(trip_miles)", "ln(trip_time / 60.0)",
           sprintf("CASE WHEN DOLocationID IN (%s) THEN 1.0 ELSE 0.0 END", paste(AIRPORT_OR_OUT, collapse = ",")))
  nx  <- length(xs)
  prods <- c(unlist(lapply(1:nx, function(i) lapply(i:nx, function(j)
                sprintf("sum((%s) * (%s)) AS xx_%d_%d", xs[i], xs[j], i, j)))),
             sprintf("sum((%s) * ln(base_passenger_fare)) AS xy_%d", xs, seq_len(nx)))
  mom <- dbGetQuery(con, sprintf("
    SELECT hvfhs_license_num AS company, %s
    FROM read_parquet('%s')
    WHERE request_datetime >= DATE '%s' AND request_datetime < DATE '%s' AND %s
    GROUP BY 1", paste(prods, collapse = ",\n "), url, start, end, CLEAN))

  coefs <- rbindlist(lapply(seq_len(nrow(mom)), function(k) {
    XX <- matrix(0, nx, nx); Xy <- numeric(nx)
    for (i in 1:nx) { Xy[i] <- mom[[sprintf("xy_%d", i)]][k]
      for (j in i:nx) XX[i, j] <- XX[j, i] <- mom[[sprintf("xx_%d_%d", i, j)]][k] }
    b <- solve(XX, Xy)
    data.table(company = mom$company[k], n = XX[1, 1], b0 = b[1], b_lnmiles = b[2],
               b_lnminutes = b[3], b_airport_out = b[4])
  }))
  fwrite(coefs, coef_out)

  # the fitted rate card, as a SQL CASE over companies
  fit <- paste0("CASE hvfhs_license_num ", paste(sprintf(
    "WHEN '%s' THEN %.10f + %.10f * (%s) + %.10f * (%s) + %.10f * (%s)",
    coefs$company, coefs$b0, coefs$b_lnmiles, xs[2], coefs$b_lnminutes, xs[3],
    coefs$b_airport_out, xs[4]), collapse = " "), " END")

  # ---- pass 2: pickups by request time; pass 3: drop-offs by drop-off time ---------------
  # Trips are binned by REQUEST time in the PICKUP zone: when and where demand appears.
  # Drop-offs (by drop-off time in the drop-off zone) measure cars brought INTO a zone,
  # e.g. fans dropped before a game: the 'lingering drivers' threat in the DAG.
  sql <- sprintf("
    COPY (
      WITH t AS (
        SELECT PULocationID                                         AS zone,
               time_bucket(INTERVAL '%1$d minutes', request_datetime) AS bin,
               base_passenger_fare                                  AS fare,
               trip_miles, trip_time, driver_pay, hvfhs_license_num,
               date_diff('second', request_datetime, on_scene_datetime) / 60.0 AS wait_min,
               CASE WHEN %5$s THEN ln(base_passenger_fare) - (%6$s) END AS surge_resid
        FROM read_parquet('%2$s')
        WHERE request_datetime >= DATE '%3$s' AND request_datetime < DATE '%4$s'
          AND base_passenger_fare > 0 AND trip_miles > 0 AND trip_time > 0
      ),
      pu AS (
        SELECT zone, bin,
          count(*)                                                                AS n_trips,
          median(surge_resid)                                                     AS surge_idx,
          avg(surge_resid)                                                        AS surge_idx_mean,
          median(fare)                                                            AS med_fare,
          median(fare / trip_miles)       FILTER (WHERE trip_miles >= 0.5)        AS med_fare_per_mile,
          median(driver_pay / trip_miles) FILTER (WHERE trip_miles >= 0.5)        AS med_pay_per_mile,
          median(driver_pay / fare)                                               AS med_pay_share,
          median(trip_miles)                                                      AS med_miles,
          median(wait_min)                FILTER (WHERE wait_min BETWEEN 0 AND 60) AS med_wait,
          quantile_cont(wait_min, 0.9)    FILTER (WHERE wait_min BETWEEN 0 AND 60) AS p90_wait,
          count(wait_min)                 FILTER (WHERE wait_min BETWEEN 0 AND 60) AS n_wait,
          median(trip_miles / (trip_time / 3600.0))                               AS med_speed_mph,
          avg(CASE WHEN hvfhs_license_num = 'HV0003' THEN 1.0 ELSE 0.0 END)       AS share_uber
        FROM t GROUP BY zone, bin
      ),
      dropoffs AS (
        SELECT DOLocationID AS zone,
               time_bucket(INTERVAL '%1$d minutes', dropoff_datetime) AS bin,
               count(*) AS n_dropoffs
        FROM read_parquet('%2$s')
        WHERE dropoff_datetime >= DATE '%3$s' AND dropoff_datetime < DATE '%4$s'
        GROUP BY 1, 2
      )
      SELECT coalesce(pu.zone, d.zone) AS zone, coalesce(pu.bin, d.bin) AS bin,
             coalesce(pu.n_trips, 0) AS n_trips, coalesce(d.n_dropoffs, 0) AS n_dropoffs,
             pu.* EXCLUDE (zone, bin, n_trips)
      FROM pu FULL OUTER JOIN dropoffs d ON pu.zone = d.zone AND pu.bin = d.bin
    ) TO '%7$s' (FORMAT PARQUET);",
    BIN_MIN, url, start, end, gsub("\n", " ", CLEAN), fit, out)
  dbExecute(con, sql)

  message(sprintf("%s: done in %.1f min -> %s  (rate card: %s)", ym,
                  as.numeric(difftime(Sys.time(), t0, units = "mins")), out,
                  paste(sprintf("%s b_miles=%.2f b_min=%.2f", coefs$company, coefs$b_lnmiles,
                                coefs$b_lnminutes), collapse = "; ")))
  invisible(out)
}

# Remote reads occasionally fail with transient HTTP errors: retry, and never leave a
# half-written panel file behind.
build_with_retry <- function(ym, tries = 4) {
  for (k in seq_len(tries)) {
    ok <- tryCatch({ build_month(ym); TRUE }, error = function(e) {
      unlink(file.path(DIR_DERIVED, sprintf("panel_%s.parquet", ym)))
      message(sprintf("%s: attempt %d failed (%s)", ym, k, conditionMessage(e))); FALSE })
    if (ok) return(invisible(TRUE))
    Sys.sleep(20 * k)
  }
  message(ym, ": FAILED after ", tries, " attempts"); invisible(FALSE)
}

months <- commandArgs(trailingOnly = TRUE)
if (!length(months)) months <- "2024-03"
for (m in months) { build_with_retry(m); Sys.sleep(15) }   # pause between months: be polite to the server
