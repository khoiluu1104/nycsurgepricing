from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.formatting.rule import CellIsRule, FormulaRule
from openpyxl.utils import get_column_letter
import sys

OUT = sys.argv[1]
F = "Arial"
H_FILL = PatternFill("solid", fgColor="1F3864")
SUB_FILL = PatternFill("solid", fgColor="D9E1F2")
INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
thin = Side(style="thin", color="BFBFBF")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)
WRAP = Alignment(wrap_text=True, vertical="top")

def font(**k):
    return Font(name=F, **{"size": 10, **k})

QUESTIONS = [
    ("Q1", "Supply response to price", "Does it estimate or model how ride supply (drivers, hours, completed rides) responds to price / surge? This is our parameter beta."),
    ("Q2", "Event demand shocks", "Does it use or study sports games, concerts or other scheduled events as demand shocks?"),
    ("Q3", "Wait times / rationing", "Does it measure wait times, unfilled requests or other non-price rationing?"),
    ("Q4", "Welfare of surge / dynamic pricing", "Does it quantify rider/driver/total surplus under surge vs. fixed prices?"),
    ("Q5", "NYC or public trip data", "Does it use NYC data or public trip records like ours (TLC)?"),
    ("Q6", "Our methods", "Does it supply or apply our methods: event study, IV/2SLS, quantile regression, DML?"),
]

# ---------------------------------------------------------------------------
# (strand, short, full citation, year, venue type, journal?, doi/url,
#  question, data, method, finding, [Q1..Q6], how we use it, gap, in previous map?, verification)
P = [
 # ---- 1. Surge pricing & supply response -------------------------------------------
 ("Surge pricing & supply response", "Hall, Kendrick & Nosko (2015)",
  "Hall, J., C. Kendrick and C. Nosko (2015). \"The Effects of Uber's Surge Pricing: A Case Study.\" Uber / University of Chicago working paper.",
  2015, "Case study (not peer-reviewed)", "No", "https://leeds-faculty.colorado.edu/leachj/BCOR1015/Readings%20not%20linked%20to%20Library%20Page/Effects_of_uber's_surge_pricing%20CASE.pdf",
  "What happens to completion rates and ETAs when surge works vs. when it fails?",
  "Uber internal data, NYC: a sold-out Ariana Grande concert at Madison Square Garden (2015) and a 26-minute surge outage on New Year's Eve 2014-15.",
  "Descriptive case comparison of two events.",
  "At the MSG concert, about twice as many drivers met about twice as many requests and completion stayed near 100%. During the outage, only about 25% of requests were completed and ETAs rose sharply.",
  [2, 2, 2, 1, 1, 0],
  "Intro + lit review: the closest precedent. Our design is the systematic, public-data version of their MSG example.",
  "Two events, Uber-internal data, authors employed by Uber, no causal estimate of supply elasticity. We use about 300 games and public data, and estimate beta with IV.",
  "No", "Full 8-page paper read 2026-11-01; local copy: literature/Hall_Kendrick_Nosko_2015_Uber_surge_case_study.pdf. Concert date: March 21, 2015"),
 ("Surge pricing & supply response", "Chen & Sheldon (2016)",
  "Chen, M. K. and M. Sheldon (2016). \"Dynamic Pricing in a Labor Market: Surge Pricing and Flexible Work on the Uber Platform.\" Proceedings of the 2016 ACM Conference on Economics and Computation (EC '16).",
  2016, "Conference proceedings", "No", "https://doi.org/10.1145/2940716.2940798",
  "Does surge pull more drivers onto the road, or only reallocate existing ones?",
  "Uber internal driver panel (not public).",
  "Uses discontinuities in the surge algorithm; driver session decisions around surge.",
  "Drivers extend sessions and supply rises during surges: a real labour-supply response.",
  [2, 0, 0, 0, 0, 1],
  "Lit review: prior estimate of the supply response; compare the sign and size of our beta.",
  "Proprietary data, so not replicable. We estimate the supply response from public data using an external demand shock.",
  "Yes", "From previous map (DOI listed there)"),
 ("Surge pricing & supply response", "Castillo (2025)",
  "Castillo, J. C. (2025). \"Who Benefits from Surge Pricing?\" Econometrica 93(6): 1811-1854.",
  2025, "Journal", "Yes", "https://doi.org/10.3982/ECTA19106",
  "How does surge vs. uniform pricing redistribute welfare among riders, drivers and the platform?",
  "Uber Houston trip and pricing data (academic agreement, not public).",
  "Structural spatial-equilibrium model; supply response partly identified from rounding in the surge algorithm; counterfactual uniform pricing.",
  "Surge raises total welfare relative to uniform pricing, mainly through better matching (shorter waits).",
  [2, 0, 2, 2, 0, 1],
  "Lit review + welfare section: the benchmark. Compare our welfare conclusion with theirs.",
  "Full structural model on private data. We give a reduced-form, public-data estimate of the key supply parameter.",
  "Yes", "From previous map; consistent with search 2026-11-01"),
 ("Surge pricing & supply response", "Cohen et al. (2016)",
  "Cohen, P., R. Hahn, J. Hall, S. Levitt and R. Metcalfe (2016). \"Using Big Data to Estimate Consumer Surplus: The Case of Uber.\" NBER Working Paper 22627.",
  2016, "Working paper", "No", "https://doi.org/10.3386/w22627",
  "How much consumer surplus does UberX generate?",
  "About 50 million UberX sessions in 4 US cities, 2015 (Uber internal).",
  "Regression discontinuity at surge-multiplier rounding thresholds gives the demand elasticity.",
  "Large consumer surplus (about $1.60 per $1 spent); demand is fairly inelastic.",
  [0, 0, 0, 2, 0, 2],
  "Welfare section: source of the DEMAND elasticity we borrow; vary it in sensitivity checks.",
  "Demand side only. We estimate the SUPPLY side, which their study does not.",
  "Yes", "From previous map"),
 ("Surge pricing & supply response", "Castillo, Knoepfle & Weyl (2017)",
  "Castillo, J. C., D. Knoepfle and E. G. Weyl (2017). \"Surge Pricing Solves the Wild Goose Chase.\" Proceedings of the 2017 ACM Conference on Economics and Computation (EC '17).",
  2017, "Conference proceedings", "No", "https://doi.org/10.1145/3033274.3085098",
  "Why is surge needed for matching efficiency in spatial markets?",
  "Theory and simulation.",
  "Matching model with and without surge.",
  "Without surge, drivers are sent on long pickups (a 'wild goose chase'); waits balloon and throughput falls.",
  [1, 0, 2, 2, 0, 0],
  "Model section: explains why waits matter for welfare, and why rising waits after games mean partial rationing.",
  "No empirical test. Our wait-time quantile results are a test of its prediction.",
  "Yes", "From previous map"),
 ("Surge pricing & supply response", "Hall, Horton & Knoepfle (2023)",
  "Hall, J. V., J. J. Horton and D. T. Knoepfle (2023). \"Ride-Sharing Markets Re-Equilibrate.\" NBER Working Paper 30883.",
  2023, "Working paper", "No", "https://www.nber.org/papers/w30883",
  "How do driver earnings and hours respond to Uber-initiated base fare changes?",
  "Uber internal city-level fare changes (not public).",
  "Event study around fare changes across cities.",
  "Higher fares raise hourly earnings at first; drivers then add hours, utilisation falls, and hourly earnings return to baseline within about 2 months. Riders get shorter waits.",
  [2, 0, 1, 1, 0, 1],
  "Lit review: the long-run supply response. Contrast with our minutes-scale short-run response.",
  "Long-run, persistent fare changes. We study short-run surge responses within an hour of a demand shock.",
  "No", "Verified 2026-11-01 (NBER page)"),
 ("Surge pricing & supply response", "Miao et al. (2023)",
  "Miao, W., Y. Deng, W. Wang, Y. Liu and C. S. Tang (2023). \"The Effects of Surge Pricing on Driver Behavior in the Ride-Sharing Market: Evidence from a Quasi-Experiment.\" Journal of Operations Management 69(5): 794-822.",
  2023, "Journal", "Yes", "https://doi.org/10.1002/joom.1223",
  "How does introducing surge pricing change drivers' revenue and working behaviour?",
  "Chinese ride-hailing platform data (not public); surge introduced in two cities at different times.",
  "Difference-in-differences with causal forest (ML heterogeneity).",
  "Weekly driver revenue rose about 14%, but daily revenue fell from competition. Part-time drivers gained; full-time drivers lost.",
  [2, 0, 0, 1, 0, 2],
  "Lit review: quasi-experimental evidence on supply response; methods parallel to our DML robustness check.",
  "Studies the introduction of surge (extensive margin), in China. We study minute-level responses to demand shocks in NYC.",
  "No", "Verified 2026-11-01 (UCL Discovery, Wiley)"),
 ("Surge pricing & supply response", "Cachon, Daniels & Lobel (2017)",
  "Cachon, G. P., K. M. Daniels and R. Lobel (2017). \"The Role of Surge Pricing on a Service Platform with Self-Scheduling Capacity.\" Manufacturing & Service Operations Management 19(3): 368-384.",
  2017, "Journal", "Yes", "https://doi.org/10.1287/msom.2017.0618",
  "When does surge pricing benefit platform, drivers and riders when drivers choose when to work?",
  "Theory.",
  "Stylised model comparing fixed and surge contracts.",
  "Surge is near-optimal for the platform, and all parties can gain because more drivers work at peaks.",
  [2, 0, 0, 2, 0, 0],
  "Model section: theory that a positive supply response is what makes surge welfare-improving.",
  "Theory only. We measure the supply response it assumes.",
  "No", "Verified 2026-11-01 (INFORMS)"),
 ("Surge pricing & supply response", "Garg & Nazerzadeh (2022)",
  "Garg, N. and H. Nazerzadeh (2022). \"Driver Surge Pricing.\" Management Science 68(5): 3219-3235.",
  2022, "Journal", "Yes", "https://doi.org/10.1287/mnsc.2021.4058",
  "How should driver-side surge pay be designed so drivers do not game it?",
  "Theory plus numerical analysis on ride-hailing data.",
  "Mechanism design.",
  "Multiplicative surge is not incentive compatible over time; additive surge performs better.",
  [1, 0, 0, 1, 0, 0],
  "Background: why driver pay may not move one-for-one with rider fares (our driver-pay outcome).",
  "Design question, not empirical supply response.",
  "No", "Verified 2026-11-01 (EconPapers)"),
 ("Surge pricing & supply response", "Chen, Mislove & Wilson (2015)",
  "Chen, L., A. Mislove and C. Wilson (2015). \"Peeking Beneath the Hood of Uber.\" Proceedings of the 2015 ACM Internet Measurement Conference (IMC).",
  2015, "Conference proceedings", "No", "https://mislove.org/publications/Uber-IMC.pdf",
  "How does Uber's surge algorithm behave in practice?",
  "43 emulated Uber app clients in midtown Manhattan and San Francisco (public-facing app data).",
  "Measurement study.",
  "Surge in Manhattan about 14% of the time; short-lived, set by 16 small Manhattan surge areas; weak evidence that surge draws drivers in.",
  [1, 0, 1, 0, 1, 0],
  "Data section: why fare per mile is a noisy surge proxy, and why surge varies within small areas.",
  "Measures surge but not the supply response. We link price changes to trips and waits.",
  "No", "Verified 2026-11-01 (paper, slides)"),
 ("Event demand shocks & traffic", "Jiao (2018)",
  "Jiao, J. (2018). \"Investigating Uber Price Surges during a Special Event in Austin, TX.\" Research in Transportation Business & Management 29: 101-107.",
  2018, "Journal", "Yes", "https://doi.org/10.1016/j.rtbm.2018.02.008",
  "How does Uber surge behave during a special event?",
  "Uber Developer API price estimates, July 4 2015 weekend, Austin.",
  "Descriptive spatio-temporal analysis.",
  "Most requests had no surge (median multiplier 1), with spikes around the event.",
  [1, 2, 0, 0, 1, 0],
  "Lit review: prior event-surge evidence (price side only).",
  "One event, price only, no supply or wait outcomes, no causal design.",
  "No", "Verified 2026-11-01 (Semantic Scholar, PubMed). verify volume/pages"),
 # ---- 2. Driver labour supply --------------------------------------------------------
 ("Driver labour supply", "Farber (2015)",
  "Farber, H. S. (2015). \"Why You Can't Find a Taxi in the Rain and Other Labor Supply Lessons from Cab Drivers.\" Quarterly Journal of Economics 130(4): 1975-2026.",
  2015, "Journal", "Yes", "https://www.nber.org/papers/w20604",
  "Do NYC taxi drivers work more when earnings opportunities are high (neoclassical) or stop at an income target?",
  "All NYC yellow-taxi trip records 2009-2013 (public TLC data).",
  "Labour supply regressions on hourly earnings opportunities.",
  "Hours rise with earnings opportunities, anticipated or not: a positive supply elasticity. Weak support for income targeting.",
  [2, 0, 0, 0, 2, 1],
  "Lit review: the classic public-NYC-data labour supply estimate; prior that beta > 0.",
  "Taxi drivers with fixed meters; no price variation from surge. We study app drivers facing dynamic prices.",
  "No", "Verified 2026-11-01 (NBER, QJE listing)"),
 ("Driver labour supply", "Camerer et al. (1997)",
  "Camerer, C., L. Babcock, G. Loewenstein and R. Thaler (1997). \"Labor Supply of New York City Cabdrivers: One Day at a Time.\" Quarterly Journal of Economics 112(2): 407-441.",
  1997, "Journal", "Yes", "",
  "Do cab drivers target daily income?",
  "NYC taxi trip sheets.",
  "Daily hours on daily wage (with IV).",
  "Negative wage elasticity, consistent with income targeting.",
  [2, 0, 0, 0, 2, 1],
  "Lit review: the opposing hypothesis; income targeting would make beta small or negative.",
  "Old data, taxi market. Cite with Farber (2015) as the debate.",
  "No", "Standard reference, not re-checked online. Verify pages"),
 ("Driver labour supply", "Chen, Chevalier, Rossi & Oehlsen (2019)",
  "Chen, M. K., J. A. Chevalier, P. E. Rossi and E. Oehlsen (2019). \"The Value of Flexible Work: Evidence from Uber Drivers.\" Journal of Political Economy 127(6).",
  2019, "Journal", "Yes", "",
  "How much do Uber drivers value schedule flexibility?",
  "Uber driver hourly data (not public).",
  "Structural labour-supply model.",
  "Drivers' reservation wages vary a lot hour to hour; flexibility is worth a large share of earnings.",
  [1, 0, 0, 1, 0, 0],
  "Background: why app supply can respond within hours (flexible entry and exit).",
  "Values flexibility; does not use demand shocks.",
  "No", "Not re-checked online. Verify pages"),
 ("Driver labour supply", "Angrist, Caldwell & Hall (2021)",
  "Angrist, J. D., S. Caldwell and J. V. Hall (2021). \"Uber versus Taxi: A Driver's Eye View.\" American Economic Journal: Applied Economics 13(3): 272-308.",
  2021, "Journal", "Yes", "https://doi.org/10.1257/app.20190655",
  "How do Uber drivers respond to taxi-style lease contracts?",
  "Field experiment with Boston Uber drivers.",
  "Randomised experiment; labour supply model.",
  "Drivers' labour supply responds to the net wage; estimates the value of Uber's flexible contract.",
  [1, 0, 0, 0, 0, 1],
  "Background: experimental evidence that driver supply is wage-elastic.",
  "Contract experiment, not price shocks.",
  "No", "Verified 2026-11-01 (AEA)"),
 # ---- 3. NYC markets / welfare with public data --------------------------------------
 ("NYC markets & welfare", "Rosaia (2025)",
  "Rosaia, N. (2025). \"Competing Platforms and Transport Equilibrium.\" Econometrica 93(6): 2235-2271.",
  2025, "Journal", "Yes", "https://doi.org/10.3982/ECTA21773",
  "How do competing ride-hail platforms set prices, and what are the welfare effects of competition and policy?",
  "Detailed data from Uber and Lyft in New York City.",
  "Structural spatial equilibrium with competing platforms.",
  "Welfare and policy counterfactuals for NYC ride-hail (check the paper for the headline numbers).",
  [1, 0, 1, 2, 2, 0],
  "Lit review: the state-of-the-art NYC ride-hail model; our reduced-form beta complements it.",
  "Structural and city-wide. We focus on short-run event-driven supply responses.",
  "No", "Verified 2026-11-01 (Econometric Society). verify headline findings"),
 ("NYC markets & welfare", "Buchholz (2022)",
  "Buchholz, N. (2022). \"Spatial Equilibrium, Search Frictions, and Dynamic Efficiency in the Taxi Industry.\" Review of Economic Studies 89(2): 556-591.",
  2022, "Journal", "Yes", "https://doi.org/10.1093/restud/rdab050",
  "How much welfare do search frictions cost in the NYC taxi market, and can pricing help?",
  "NYC yellow medallion trip data (public TLC).",
  "Dynamic spatial search game, estimated structurally.",
  "Weekday welfare about $5.7m/day; about 53k customers a day fail to find a cab; tariff changes could improve allocation.",
  [1, 0, 1, 2, 2, 0],
  "Welfare section: unserved demand and pricing as an allocation tool, in NYC with public data.",
  "Taxis with regulated fares. We study app markets with surge.",
  "No", "Verified 2026-11-01 (Princeton, REStud listing)"),
 ("NYC markets & welfare", "Frechette, Lizzeri & Salz (2019)",
  "Frechette, G. R., A. Lizzeri and T. Salz (2019). \"Frictions in a Competitive, Regulated Market: Evidence from Taxis.\" American Economic Review 109(8).",
  2019, "Journal", "Yes", "",
  "How large are matching frictions and entry regulation costs in NYC taxis?",
  "NYC yellow-cab trip data (public TLC).",
  "Dynamic equilibrium model of taxi supply and matching.",
  "Matching frictions and medallion limits create large inefficiencies; thinner markets worsen search.",
  [1, 0, 1, 2, 2, 0],
  "Lit review: frictions explain why waits can rise even when prices adjust.",
  "Regulated taxi supply; no dynamic pricing.",
  "No", "Working paper verified 2026-11-01; verify AER pages"),
 ("NYC markets & welfare", "Lam, Liu & Hui (2021)",
  "Lam, C. T., M. Liu and X. Hui (2021). \"The Geography of Ridesharing: A Case Study on New York City.\" Information Economics and Policy 57: 100941.",
  2021, "Journal", "Yes", "https://doi.org/10.1016/j.infoecopol.2021.100941",
  "How do ridesharing surplus and availability vary across NYC neighbourhoods?",
  "NYC Uber/Lyft/taxi data.",
  "Discrete-choice demand model.",
  "Riders 5-15 miles from Midtown gain about 60% more surplus; over half of the gains come from shorter waits.",
  [0, 0, 2, 2, 2, 0],
  "Welfare section: shows wait time is a large part of rider surplus in NYC, so our wait results matter for welfare.",
  "Cross-sectional demand. We study supply responses to time-varying shocks.",
  "No", "Verified 2026-11-01 (RePEc)"),
 ("NYC markets & welfare", "Williams (2022)",
  "Williams, K. R. (2022). \"The Welfare Effects of Dynamic Pricing: Evidence from Airline Markets.\" Econometrica 90(2): 831-858.",
  2022, "Journal", "Yes", "https://doi.org/10.3982/ECTA16180",
  "Does dynamic pricing raise or lower welfare in airline markets?",
  "Airline fares and seat maps.",
  "Structural demand and dynamic pricing model.",
  "Dynamic pricing improves allocation of scarce seats; welfare effects are mixed across consumer types.",
  [0, 0, 0, 2, 0, 0],
  "Background: welfare of dynamic pricing in another market (one sentence in the lit review).",
  "Different market. Optional citation.",
  "Yes", "From previous map"),
 # ---- 4. Event demand shocks & traffic (exclusion threats) ----------------------------------
 ("Event demand shocks & traffic", "Hwang, Humphreys & Pyun (2025)",
  "Hwang, H., B. R. Humphreys and H. Pyun (2025). \"Game Day Traffic and Sports: Evidence from Yankee Stadium in the Bronx.\" Journal of Sports Economics 26(3): 219-239.",
  2025, "Journal", "Yes", "https://econpapers.repec.org/RePEc:sae:jospec:v:26:y:2025:i:3:p:219-239",
  "Do Yankees home games slow down travel in NYC?",
  "About 280,000 NYC taxi trips on weekday evenings, Mar-Sep 2019 (public TLC data).",
  "Game-day vs. non-game-day comparison of trip travel times.",
  "Travel times 1.3% longer on game days; 6.3% longer for trips through the stadium area; 17% longer before the game; about $2m/year in lost time.",
  [0, 2, 1, 0, 2, 1],
  "Threats section: direct evidence on the traffic exclusion threat; also the CLOSEST data neighbour (public TLC data + NYC games).",
  "Studies travel times only. We study prices, ride supply and wait times after game END, at four venues, with Uber/Lyft data.",
  "No", "Verified 2026-11-01 (EconPapers). NEW: read in full"),
 ("Event demand shocks & traffic", "Humphreys & Pyun (2018)",
  "Humphreys, B. R. and H. Pyun (2018). \"Professional Sporting Events and Traffic: Evidence from U.S. Cities.\" Journal of Regional Science 58(5): 869-886.",
  2018, "Journal", "Yes", "https://ideas.repec.org/a/bla/jregsc/v58y2018i5p869-886.html",
  "Do MLB games increase traffic and congestion?",
  "25 US metro areas with MLB teams, 1990-2014.",
  "IV estimates of attendance effects on vehicle-miles travelled.",
  "MLB attendance raises daily VMT about 6.9% and congestion about 2%.",
  [0, 2, 0, 0, 0, 2],
  "Threats section: games cause congestion, a path that skips price; justifies the speed check.",
  "City-level traffic, not ride-hail markets.",
  "No", "Verified 2026-11-01 (RePEc)"),
 ("Event demand shocks & traffic", "Garces & Gil (2024)",
  "Garces, D. and S. Gil (2024). \"Surge Routing: Event-informed Multiagent Reinforcement Learning for Autonomous Rideshare.\" Proceedings of AAMAS 2024.",
  2024, "Conference proceedings", "No", "https://arxiv.org/abs/2307.02637",
  "Can a fleet use event information to anticipate demand spikes?",
  "NYC rideshare data 2022 plus 2,000+ events at 300 Manhattan venues.",
  "Demand prediction + multi-agent RL routing.",
  "Event-informed routing cuts wait per request by 25-75%.",
  [0, 2, 1, 0, 2, 0],
  "Threats section: event demand is predictable, so drivers/platforms can pre-position (anticipation threat).",
  "Engineering; no prices or causal supply response.",
  "No", "Verified 2026-11-01 (arXiv abstract)"),
 # ---- 5. Methods ------------------------------------------------------------------
 ("Methods", "Freyaldenhoven, Hansen & Shapiro (2019)",
  "Freyaldenhoven, S., C. Hansen and J. M. Shapiro (2019). \"Pre-event Trends in the Panel Event-Study Design.\" American Economic Review 109(9): 3307-3338.",
  2019, "Journal", "Yes", "https://doi.org/10.1257/aer.20180609",
  "How to identify effects in event studies when confounds cause pre-trends?",
  "Methods.",
  "2SLS using covariates related to the policy only through the confound.",
  "Valid inference is possible even with pre-trends, if a suitable covariate exists.",
  [0, 1, 0, 0, 0, 2],
  "Methods + threats: our trips rise 30 minutes before game end; this paper frames how to handle pre-trends.",
  "Methods reference.",
  "No", "Verified 2026-11-01 (AEA)"),
 ("Methods", "Chernozhukov et al. (2018)",
  "Chernozhukov, V., D. Chetverikov, M. Demirer, E. Duflo, C. Hansen, W. Newey and J. Robins (2018). \"Double/Debiased Machine Learning for Treatment and Structural Parameters.\" Econometrics Journal 21(1): C1-C68.",
  2018, "Journal", "Yes", "https://doi.org/10.1111/ectj.12097",
  "How to estimate causal parameters with ML-chosen controls?",
  "Methods.",
  "Orthogonal scores + cross-fitting; includes partially linear IV.",
  "Root-n consistent estimates with flexible nuisance functions.",
  [0, 0, 0, 0, 0, 2],
  "Methods: DML robustness check of beta (ECO1400 Lecture 4).",
  "Methods reference.",
  "No", "Verified 2026-11-01 (EconPapers)"),
 ("Methods", "Koenker & Bassett (1978)",
  "Koenker, R. and G. Bassett (1978). \"Regression Quantiles.\" Econometrica 46(1): 33-50.",
  1978, "Journal", "Yes", "https://doi.org/10.2307/1913643",
  "Estimating conditional quantiles.",
  "Methods.",
  "Quantile regression.",
  "Foundational quantile regression estimator.",
  [0, 0, 0, 0, 0, 2],
  "Methods: quantile regression on wait times (ECO1400 Lecture 5).",
  "Methods reference.",
  "No", "Standard reference, not re-checked online"),
 ("Methods", "Stock & Yogo (2005)",
  "Stock, J. H. and M. Yogo (2005). \"Testing for Weak Instruments in Linear IV Regression.\" In D. W. K. Andrews and J. H. Stock (eds.), Identification and Inference for Econometric Models. Cambridge University Press.",
  2005, "Book chapter", "No", "",
  "When is an instrument too weak?",
  "Methods.",
  "Critical values for first-stage F.",
  "Rule of thumb: first-stage F above about 10.",
  [0, 0, 0, 0, 0, 2],
  "Methods: justifies the first-stage F check (pilot F = 27.6).",
  "Methods reference.",
  "No", "Standard reference, not re-checked online"),
 # ---- 6. Policy / grey literature -------------------------------------------------------
 ("Policy & grey literature", "NY Attorney General-Uber agreement (2014)",
  "New York State Office of the Attorney General and Uber Technologies (2014). Agreement to cap surge pricing during abnormal market disruptions, July 8, 2014. As reported in TechCrunch, \"Uber Caps Surge Pricing During Emergencies Nationwide,\" July 8, 2014.",
  2014, "Policy / press", "No", "https://techcrunch.com/2014/07/08/uber-caps-surge-pricing-during-emergencies",
  "Policy: limit surge during emergencies under NY price-gouging law.",
  "n/a",
  "n/a",
  "Surge capped near the normal range of the previous 60 days during declared emergencies; Uber said it would apply a similar cap nationwide.",
  [1, 0, 0, 0, 1, 0],
  "Extension: emergency days as partial no-surge periods. Confirm the agreement is still in force.",
  "Not a study. Provides a possible second source of price variation.",
  "No", "Verified 2026-11-01 (press coverage)"),
 ("Policy & grey literature", "NYC TLC FHV Congestion Study (2019)",
  "New York City Taxi and Limousine Commission (2019). \"FHV Congestion Study Report.\" June 2019.",
  2019, "Government report", "No", "https://www.nyc.gov/assets/tlc/downloads/pdf/fhv_congestion_study_report.pdf",
  "How do Uber/Lyft vehicles contribute to Manhattan congestion?",
  "TLC trip records.",
  "Descriptive.",
  "Platforms oversupply vehicles to keep waits low; drivers spend over 40% of work time empty and cruising.",
  [1, 0, 1, 0, 2, 0],
  "Data/context: idle capacity exists, so short-run supply can respond quickly.",
  "Descriptive policy report.",
  "No", "Found 2026-11-01 (search result); not opened"),
]

EXCLUDED = [
 ("McAfee & te Velde (2006)", "Airline dynamic pricing", "Airline revenue management; no ride-hail supply, events or waits."),
 ("Hortacsu, Oery & Williams (2022)", "Airline dynamic pricing", "Airline price competition; off-question."),
 ("Chen & Jeziorski (2023)", "Airline dynamic pricing", "Airline markets; working paper."),
 ("Calvano et al. (2020)", "Algorithmic collusion", "Pricing algorithms and collusion; not about supply response."),
 ("Assad et al. (2024)", "Algorithmic collusion", "German gasoline; off-question."),
 ("Musolff (2026)", "Algorithmic collusion", "E-commerce repricing; off-question."),
 ("Fish, Gonczarowski & Shorrer (2024)", "Algorithmic collusion", "LLM collusion simulation; off-question."),
 ("Dube & Misra (2023)", "Personalised pricing", "Price discrimination across consumers, not across time."),
 ("Chang, Winston & Yan (2022)", "Ride-hail price discrimination", "Relevant to the earlier Chicago fairness topic, not to supply response."),
 ("Pandey & Caliskan (2021)", "Ride-hail price discrimination", "Chicago fare disparities; earlier Chicago topic."),
 ("Media reports on battery-level pricing", "Ride-hail price discrimination", "Anecdotal, not peer-reviewed."),
]
KEPT_NOTE = "Kept from the previous map: Cohen et al. (2016), Chen & Sheldon (2016), Castillo (2025), Castillo, Knoepfle & Weyl (2017), Williams (2022)."

SEARCHES = [
 ("ride-hailing surge pricing driver supply response sporting events concerts demand shock empirical", "Found Miao et al. (2023), Castillo JMP; no study of event-driven supply response"),
 ("NYC TLC high volume FHV trip records Uber Lyft economics paper wait times", "Only GitHub projects + TLC reports; no peer-reviewed wait-time paper"),
 ("Hall Horton Knoepfle ride-sharing markets re-equilibrate", "NBER w30883 (2023)"),
 ("Humphreys Pyun sporting events traffic", "JRS 2018; led to Hwang, Humphreys & Pyun (2025) Yankee Stadium paper"),
 ("Farber taxi in the rain", "QJE 2015 confirmed"),
 ("Rosaia competing platforms transport equilibrium", "Econometrica 2025 confirmed"),
 ("Pyun Humphreys Yankee Stadium taxi", "JSE 2025 26(3) confirmed; closest data neighbour"),
 ("Chen Mislove Wilson peeking beneath the hood of Uber", "IMC 2015 confirmed"),
 ("Uber 2014 NY Attorney General surge cap", "July 8 2014 agreement confirmed"),
 ("Freyaldenhoven Hansen Shapiro pre-event trends", "AER 2019 confirmed"),
 ("ride-hailing demand stadium event surge pricing study", "Jiao (2018) Austin; no multi-stadium study found"),
 ("Miao surge pricing driver behavior quasi-experiment", "JOM 2023 confirmed"),
 ("Uber Lyft Madison Square Garden event demand NYC FHV", "Hall-Kendrick-Nosko MSG case study; Garces & Gil (2024); no public-data MSG study found"),
 ("Cachon Daniels Lobel surge pricing self-scheduling", "MSOM 2017 confirmed"),
 ("Buchholz taxi; Frechette Lizzeri Salz", "REStud 2022 confirmed; FLS AER pages not confirmed"),
 ("Angrist Caldwell Hall Uber versus taxi", "AEJ Applied 2021 confirmed"),
 ("Garg Nazerzadeh driver surge pricing", "Management Science 2022 confirmed"),
 ("Geography of ridesharing NYC", "Lam, Liu & Hui, IEP 2021 confirmed"),
 ("Chernozhukov DML", "Econometrics Journal 2018 confirmed"),
]

wb = Workbook()

# ===== Sheet 1: README =====
ws = wb.active
ws.title = "README"
ws.sheet_view.showGridLines = False
rows = [
 ("NYC Surge Pricing: Systematic Literature Review", "title"),
 ("ECO1400 term paper. Built 2026-11-01. Sources checked by web search on that date (see Search Log).", "note"),
 ("", None),
 ("Research question", "h"),
 ("When demand for rides suddenly jumps (a game ends at a NYC arena), how strongly does Uber/Lyft ride supply respond to the higher surge price, and how much is rationed by waiting instead?", "body"),
 ("", None),
 ("How each paper is scored (Literature Matrix, columns M-R)", "h"),
]
for q, name, desc in QUESTIONS:
    rows.append((f"{q}  {name}: {desc}", "body"))
rows += [
 ("Score 2 = central to the paper; 1 = touches it; 0 = not addressed.", "body"),
 ("", None),
 ("Computed columns (formulas, do not type over)", "h"),
 ("Total = sum of Q1-Q6.  Tier: Methods papers are 'Method'; otherwise Core (6+), Supporting (4-5), Background (0-3).", "body"),
 ("'Counts toward requirement' = peer-reviewed journal AND year 2015 or later (guidelines: at least 3, ideally 5+, recent journal articles).", "body"),
 ("", None),
 ("How to use", "h"),
 ("Yellow cells are inputs: edit scores (0/1/2), journal flag or year and the formulas update. Add a paper by copying the last row down.", "body"),
 ("Filter the Tier column to 'Core' for the papers the lit review must discuss; the 'How we use it' column says where in the paper.", "body"),
 ("'Verification' says what was confirmed online. Anything marked 'verify' must be checked before it goes in the reference list.", "body"),
 ("", None),
 ("Bottom line", "h"),
 ("No study found estimates the short-run supply response to surge using scheduled events and PUBLIC trip data. The closest are Hall, Kendrick & Nosko (2015) (one MSG concert, Uber data) and Hwang, Humphreys & Pyun (2025) (Yankee Stadium games, TLC taxi data, travel times only).", "body"),
 ("That combination is the paper's original component.", "body"),
]
for i, (text, kind) in enumerate(rows, start=1):
    c = ws.cell(row=i, column=1, value=text)
    if kind == "title":
        c.font = font(size=14, bold=True, color="1F3864")
    elif kind == "h":
        c.font = font(size=11, bold=True, color="1F3864")
    elif kind == "note":
        c.font = font(italic=True, color="595959")
    else:
        c.font = font()
    c.alignment = Alignment(wrap_text=True, vertical="top")
ws.column_dimensions["A"].width = 130

# ===== Sheet 2: Literature Matrix =====
ws = wb.create_sheet("Literature Matrix")
headers = ["ID", "Strand", "Short cite", "Full citation", "Year", "Venue type", "Peer-reviewed journal?",
           "DOI / URL", "Research question", "Data (public?)", "Identification / method", "Key finding"] + \
          [f"{q} {n}" for q, n, _ in QUESTIONS] + \
          ["Total relevance", "Tier", "Counts toward requirement", "How we use it (paper section)",
           "How our paper differs / gap", "In previous map?", "Verification"]
widths = [5, 20, 22, 48, 7, 16, 11, 30, 34, 34, 30, 44] + [10]*6 + [10, 12, 13, 40, 40, 10, 28]
for j, h in enumerate(headers, start=1):
    c = ws.cell(row=1, column=j, value=h)
    c.font = font(bold=True, color="FFFFFF")
    c.fill = H_FILL
    c.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
    c.border = BOX
    ws.column_dimensions[get_column_letter(j)].width = widths[j-1]
ws.row_dimensions[1].height = 42

SCORE_COL0 = 13  # M
for i, p in enumerate(P, start=2):
    (strand, short, full, year, venue, journal, url, q, data, method, finding,
     scores, use, gap, prev, ver) = p
    vals = [i-1, strand, short, full, year, venue, journal, url, q, data, method, finding] + scores
    for j, v in enumerate(vals, start=1):
        c = ws.cell(row=i, column=j, value=v)
        c.font = font()
        c.alignment = WRAP
        c.border = BOX
    for j in range(SCORE_COL0, SCORE_COL0+6):
        ws.cell(row=i, column=j).fill = INPUT_FILL
        ws.cell(row=i, column=j).alignment = Alignment(horizontal="center", vertical="top")
    for col in (5, 7):
        ws.cell(row=i, column=col).fill = INPUT_FILL
    ws.cell(row=i, column=5).alignment = Alignment(horizontal="center", vertical="top")
    ws.cell(row=i, column=7).alignment = Alignment(horizontal="center", vertical="top")
    if url:
        ws.cell(row=i, column=8).hyperlink = url
        ws.cell(row=i, column=8).font = font(color="0563C1", underline="single")
    r = i
    ws.cell(row=r, column=19, value=f"=SUM(M{r}:R{r})")
    ws.cell(row=r, column=20, value=f'=IF(B{r}="Methods","Method",IF(S{r}>=6,"Core",IF(S{r}>=4,"Supporting","Background")))')
    ws.cell(row=r, column=21, value=f'=IF(AND(G{r}="Yes",E{r}>=2015),"Yes","No")')
    for j, v in zip((22, 23, 24, 25), (use, gap, prev, ver)):
        ws.cell(row=r, column=j, value=v)
    for j in range(19, 26):
        c = ws.cell(row=r, column=j)
        c.font = font(bold=(j in (19, 20)))
        c.alignment = WRAP if j >= 22 else Alignment(horizontal="center", vertical="top")
        c.border = BOX
last = len(P) + 1
ws.freeze_panes = "D2"
ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{last}"

dv_score = DataValidation(type="whole", operator="between", formula1="0", formula2="2",
                          showErrorMessage=True, errorTitle="Score", error="Enter 0, 1 or 2")
dv_yn = DataValidation(type="list", formula1='"Yes,No"', allow_blank=True)
ws.add_data_validation(dv_score); ws.add_data_validation(dv_yn)
dv_score.add(f"M2:R{last+50}")
dv_yn.add(f"G2:G{last+50}"); dv_yn.add(f"X2:X{last+50}")

green = PatternFill("solid", fgColor="C6EFCE"); amber = PatternFill("solid", fgColor="FFEB9C")
grey = PatternFill("solid", fgColor="EDEDED"); blue = PatternFill("solid", fgColor="DDEBF7")
rng = f"T2:T{last+50}"
ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=['"Core"'], fill=green))
ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=['"Supporting"'], fill=amber))
ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=['"Background"'], fill=grey))
ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=['"Method"'], fill=blue))
ws.conditional_formatting.add(f"M2:R{last+50}", CellIsRule(operator="equal", formula=["2"], fill=green))
ws.conditional_formatting.add(f"Y2:Y{last+50}", FormulaRule(formula=[f'ISNUMBER(SEARCH("verify",Y2))'], fill=amber))

# ===== Sheet 3: Coverage =====
ws = wb.create_sheet("Coverage")
ws.sheet_view.showGridLines = False
ws["A1"] = "Coverage check: does the literature support every part of the research question?"
ws["A1"].font = font(size=12, bold=True, color="1F3864")
ws["A2"] = "All counts are formulas on the Literature Matrix; they update when scores change."
ws["A2"].font = font(italic=True, color="595959")
hdr = ["Sub-question", "Papers scoring 2 (central)", "Papers scoring 1+", "Of which journal 2015+ scoring 2", "Status"]
for j, h in enumerate(hdr, start=1):
    c = ws.cell(row=4, column=j, value=h)
    c.font = font(bold=True, color="FFFFFF"); c.fill = H_FILL; c.border = BOX
    c.alignment = Alignment(wrap_text=True, horizontal="center", vertical="center")
LM = "'Literature Matrix'"
for k, (q, name, _) in enumerate(QUESTIONS):
    r = 5 + k
    col = get_column_letter(SCORE_COL0 + k)
    rngq = f"{LM}!${col}$2:${col}${last+50}"
    ws.cell(row=r, column=1, value=f"{q} {name}")
    ws.cell(row=r, column=2, value=f"=COUNTIF({rngq},2)")
    ws.cell(row=r, column=3, value=f"=COUNTIF({rngq},\">=1\")")
    ws.cell(row=r, column=4, value=f"=COUNTIFS({rngq},2,{LM}!$U$2:$U${last+50},\"Yes\")")
    ws.cell(row=r, column=5, value=f'=IF(D{r}>=2,"Well covered",IF(B{r}>=1,"Thin: mostly non-journal","GAP"))')
    for j in range(1, 6):
        c = ws.cell(row=r, column=j); c.font = font(); c.border = BOX
        c.alignment = Alignment(horizontal="left" if j == 1 else "center")
r0 = 5 + len(QUESTIONS) + 1
summary = [
 ("Papers in matrix", f"=COUNTA({LM}!$C$2:$C${last+50})"),
 ("Core papers", f"=COUNTIF({LM}!$T$2:$T${last+50},\"Core\")"),
 ("Supporting papers", f"=COUNTIF({LM}!$T$2:$T${last+50},\"Supporting\")"),
 ("Methods references", f"=COUNTIF({LM}!$T$2:$T${last+50},\"Method\")"),
 ("Recent journal articles (counts toward requirement)", f"=COUNTIF({LM}!$U$2:$U${last+50},\"Yes\")"),
 ("Requirement: at least 3 (5+ better)", f'=IF(B{r0+4}>=5,"Met (5+)",IF(B{r0+4}>=3,"Met (3+)","Not met"))'),
 ("Entries still to verify", f"=COUNTIF({LM}!$Y$2:$Y${last+50},\"*verify*\")"),
]
for k, (lab, f) in enumerate(summary):
    r = r0 + k
    a = ws.cell(row=r, column=1, value=lab); a.font = font(bold=True); a.border = BOX
    b = ws.cell(row=r, column=2, value=f); b.font = font(); b.border = BOX
    b.alignment = Alignment(horizontal="center")
ws.cell(row=r0+len(summary)+1, column=1,
        value="Status rule: 'Well covered' = 2+ recent journal articles score 2; 'Thin' = only working papers/conference/case studies; 'GAP' = nothing central.").font = font(italic=True, color="595959")
ws.conditional_formatting.add(f"E5:E{4+len(QUESTIONS)}", CellIsRule(operator="equal", formula=['"Well covered"'], fill=green))
ws.conditional_formatting.add(f"E5:E{4+len(QUESTIONS)}", FormulaRule(formula=['LEFT(E5,4)="Thin"'], fill=amber))
ws.conditional_formatting.add(f"E5:E{4+len(QUESTIONS)}", CellIsRule(operator="equal", formula=['"GAP"'], fill=PatternFill("solid", fgColor="FFC7CE")))
for col, w in zip("ABCDE", (52, 16, 14, 18, 26)):
    ws.column_dimensions[col].width = w

# ===== Sheet 4: Excluded =====
ws = wb.create_sheet("Excluded from previous map")
ws["A1"] = "Entries in dynamic_pricing_literature_map.xlsx (ECO2905) not carried over, and why"
ws["A1"].font = font(size=12, bold=True, color="1F3864")
ws["A2"] = KEPT_NOTE; ws["A2"].font = font(italic=True, color="595959")
for j, h in enumerate(["Paper", "Strand in previous map", "Reason excluded"], start=1):
    c = ws.cell(row=4, column=j, value=h); c.font = font(bold=True, color="FFFFFF"); c.fill = H_FILL; c.border = BOX
for i, e in enumerate(EXCLUDED, start=5):
    for j, v in enumerate(e, start=1):
        c = ws.cell(row=i, column=j, value=v); c.font = font(); c.border = BOX; c.alignment = WRAP
for col, w in zip("ABC", (38, 30, 70)):
    ws.column_dimensions[col].width = w

# ===== Sheet 5: Search Log =====
ws = wb.create_sheet("Search Log")
ws["A1"] = "Searches run 2026-11-01 (web search; abstracts and publisher/RePEc pages)"
ws["A1"].font = font(size=12, bold=True, color="1F3864")
for j, h in enumerate(["#", "Query", "Result"], start=1):
    c = ws.cell(row=3, column=j, value=h); c.font = font(bold=True, color="FFFFFF"); c.fill = H_FILL; c.border = BOX
for i, (qq, res) in enumerate(SEARCHES, start=4):
    for j, v in enumerate((i-3, qq, res), start=1):
        c = ws.cell(row=i, column=j, value=v); c.font = font(); c.border = BOX; c.alignment = WRAP
ws.column_dimensions["A"].width = 5; ws.column_dimensions["B"].width = 60; ws.column_dimensions["C"].width = 70

wb.active = 1
wb.calculation.fullCalcOnLoad = True
wb.save(OUT)
print("saved", OUT, "papers:", len(P))
