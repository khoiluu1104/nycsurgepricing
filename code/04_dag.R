# 04_dag.R — causal diagram (DAG) for the IV design, plus a table of the variables
# that threaten it. Outputs:
#   output/figures/dag.png
#   output/tables/dag_variables.csv
#
# Read the DAG this way:
#   - Solid black: the path we want. Game ends -> rider demand -> surge price -> drivers -> trips.
#     beta = the effect of price on rides supplied (price -> drivers -> trips).
#   - Grey: confounders of price and trips. They are why OLS fails, and are handled by IV + fixed effects.
#   - Dashed red: paths from the game to trips that skip price. Each one breaks the exclusion restriction.

source("code/00_setup.R")

# ---- nodes -------------------------------------------------------------------
# Main path on y = 0; confounder above; each threat sits right under what it acts on,
# fed from the game by one "bus" line along the bottom, so no arrow crosses a box.
nodes <- data.table(
  id   = c("Z", "D", "P", "S", "Q", "U", "A", "B", "T", "M"),
  x    = c(0,   2.3, 4.6, 7.2, 10.2, 5.9, 6.2, 8.2, 10.2, 4.6),
  y    = c(0,   0,   0,   0,   0,    1.9, -1.7, -1.7, -1.7, -1.7),
  hw   = c(0.62, 0.6, 0.58, 0.68, 0.7, 0.85, 0.85, 1.0, 0.5, 0.6),   # half-widths, for arrow ends
  label = c("Game ends\n(instrument Z)",
            "Rider demand",
            "Surge price\n(treatment P)",
            "Drivers on road\n(supply)",
            "Completed trips\n(outcome Q)",
            "Weather, hour, day,\ncitywide shocks (U)",
            "Driver anticipation /\nplatform bonuses",
            "Drivers lingering after\npre-game drop-offs",
            "Traffic\ncongestion",
            "Trip mix\n(shorter trips)"),
  type = c("instrument", "main", "treatment", "main", "outcome",
           "confounder", "threat", "threat", "threat", "threat")
)

# ---- edges -------------------------------------------------------------------
N  <- function(k) nodes[id == k]
HH <- 0.33                                     # half-height of a two-line box
right_of <- function(k) c(N(k)$x + N(k)$hw, N(k)$y)
left_of  <- function(k) c(N(k)$x - N(k)$hw, N(k)$y)
seg <- function(a, b, kind) data.table(x = a[1], y = a[2], xend = b[1], yend = b[2], kind = kind)

edges <- rbind(
  # main path
  seg(right_of("Z"), left_of("D"), "main"),
  seg(right_of("D"), left_of("P"), "main"),
  seg(right_of("P"), left_of("S"), "main"),
  seg(right_of("S"), left_of("Q"), "main"),
  # confounder U -> demand, price, supply
  seg(c(N("U")$x - 0.5, N("U")$y - HH), c(N("D")$x + 0.2, HH - 0.08), "confounder"),
  seg(c(N("U")$x - 0.2, N("U")$y - HH), c(N("P")$x + 0.25, HH), "confounder"),
  seg(c(N("U")$x + 0.4, N("U")$y - HH), c(N("S")$x - 0.2, HH), "confounder"),
  # threats -> what they act on (straight up, or a short diagonal)
  seg(c(N("M")$x, N("M")$y + HH), c(N("P")$x, -HH), "threat"),
  seg(c(N("A")$x + 0.3, N("A")$y + HH), c(N("S")$x - 0.3, -HH), "threat"),
  seg(c(N("B")$x - 0.4, N("B")$y + HH), c(N("S")$x + 0.3, -HH), "threat"),
  seg(c(N("T")$x, N("T")$y + HH), c(N("Q")$x, -HH), "threat")
)
# the "bus": game -> down -> along the bottom -> up into each threat
BUS_Y <- -2.75
bus <- data.table(x = c(N("Z")$x, N("Z")$x, N("T")$x), y = c(-HH, BUS_Y, BUS_Y))
bus_taps <- data.table(x = c(N("M")$x, N("A")$x, N("B")$x, N("T")$x), y = BUS_Y,
                       xend = c(N("M")$x, N("A")$x, N("B")$x, N("T")$x), yend = N("M")$y - HH)

pal <- c(instrument = "#2E7D32", treatment = "#1565C0", outcome = "#1565C0",
         main = "grey20", confounder = "grey45", threat = "#C62828")
arr <- function(s = 0.16) arrow(length = unit(s, "cm"), type = "closed")

g <- ggplot() +
  geom_segment(data = edges[kind == "main"], aes(x, y, xend = xend, yend = yend),
               linewidth = 0.9, colour = "grey15", arrow = arr(0.2)) +
  geom_segment(data = edges[kind == "confounder"], aes(x, y, xend = xend, yend = yend),
               linewidth = 0.6, colour = "grey55", arrow = arr()) +
  geom_segment(data = edges[kind == "threat"], aes(x, y, xend = xend, yend = yend),
               linewidth = 0.65, colour = pal[["threat"]], linetype = "dashed", arrow = arr()) +
  geom_path(data = bus, aes(x, y), linewidth = 0.65, colour = pal[["threat"]], linetype = "dashed") +
  geom_segment(data = bus_taps, aes(x, y, xend = xend, yend = yend),
               linewidth = 0.65, colour = pal[["threat"]], linetype = "dashed", arrow = arr()) +
  annotate("text", x = 0.12, y = BUS_Y + 0.22, hjust = 0, size = 3, colour = pal[["threat"]],
           label = "the game also causes...") +
  geom_label(data = nodes, aes(x, y, label = label, colour = type),
             size = 3.1, label.size = 0.5, label.padding = unit(0.25, "lines"),
             fill = "white", lineheight = 0.95) +
  annotate("text", x = (N("P")$x + N("S")$x) / 2, y = 0.22, label = "beta", parse = TRUE,
           size = 5.5, colour = "grey15") +
  scale_colour_manual(values = pal, guide = "none") +
  coord_cartesian(xlim = c(-0.7, 11.0), ylim = c(-3.0, 2.4)) +
  labs(title = "Causal diagram: game endings as an instrument for surge price",
       subtitle = paste("Black: the path we want (beta = price -> rides supplied).",
                        "Grey: confounders handled by IV + fixed effects.",
                        "Red dashed: game -> trips paths that skip price (exclusion threats).",
                        sep = "\n")) +
  theme_void(base_size = 11) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(colour = "grey30", lineheight = 1.1),
        plot.margin = margin(12, 12, 12, 12),
        plot.background = element_rect(fill = "white", colour = NA))

ggsave(file.path(DIR_FIG, "dag.png"), g, width = 10, height = 6.2, dpi = 160)

# ---- variable table ---------------------------------------------------------------
vars <- data.table(
  variable = c(
    "Weather (rain, snow, cold)",
    "Hour of day, day of week",
    "Citywide shocks (holidays, subway outages, parades)",
    "Concerts / other events at MSG on non-game nights",
    "Driver anticipation of known game end times",
    "Platform driver bonuses for events (quests, boosts)",
    "Drivers lingering after pre-game drop-offs",
    "Post-game traffic congestion",
    "Trip mix after games (shorter trips, other destinations)",
    "Riders who give up without booking",
    "Spillover to neighbouring zones",
    "Wait time / arrival timestamp (as a control)",
    "Trip speed (as a control)"),
  role = c(
    "Confounder of price and trips",
    "Confounder of price and trips",
    "Confounder of price and trips",
    "Contaminates the comparison group",
    "Exclusion threat (Z -> supply, skipping price)",
    "Exclusion threat (Z -> supply, skipping price)",
    "Exclusion threat (Z -> supply, skipping price)",
    "Exclusion threat (Z -> trips, skipping price)",
    "Measurement error in price (Z -> measured price)",
    "Selection: demand not observed",
    "SUTVA violation: treatment leaks to control zones",
    "Bad control: caused by both demand and supply (collider)",
    "Bad control: post-treatment mediator"),
  observed = c("Add NOAA hourly data", "Yes", "Partly (dates)", "Add MSG calendar",
               "No (test via pre-trends)", "No", "Partly (pre-game drop-offs by zone)",
               "Yes (median speed)", "Yes (miles, minutes, destination)", "No",
               "Yes (zone IDs)", "Yes", "Yes"),
  handled_by = c(
    "Date FE absorbs citywide weather; add hourly weather in DML",
    "Zone x weekday x 15-min-slot fixed effects",
    "Date fixed effects (identified from control zones)",
    "Drop or flag concert nights; robustness check",
    "Test trips at -30/-15 min; use games with surprise end times (overtime, blowouts)",
    "Cannot observe; discuss as a limitation; driver pay per mile partly captures it",
    "Control for pre-game drop-offs into the zone; robustness check",
    "Speed as an outcome (pilot: no significant change)",
    "Implied-surge index: log fare residual after miles, minutes, destination, company",
    "State as a limitation; demand elasticity taken from literature",
    "Exclude neighbours from controls (done); robustness check with neighbours treated",
    "Do NOT control for it; use only as an outcome",
    "Do NOT control for it; use only as an outcome / exclusion check")
)
fwrite(vars, file.path(DIR_TAB, "dag_variables.csv"))
message("Wrote ", file.path(DIR_FIG, "dag.png"), " and ", file.path(DIR_TAB, "dag_variables.csv"))
