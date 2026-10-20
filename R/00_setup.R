# ==============================================================================
# 00_setup.R  --  Environment, paths and project-wide constants
# ==============================================================================
# MA1580 Assessment 2 -- Graduate Employment Dashboard
#
# PURPOSE
#   Single place where packages, file paths and shared lookup tables are
#   defined, so that every later script depends on configuration rather than
#   on hard-coded literals. Sourced first by run_all.R.
#
# CONTRACT
#   data/raw/   is immutable. It is only ever read.
#   data/clean/ is rebuilt from scratch on every run, so the pipeline is
#               reproducible end to end and no stale output can survive.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(tibble)
})

options(dplyr.summarise.inform = FALSE)

# ---- Paths -------------------------------------------------------------------
PATHS <- list(
  raw   = file.path("data", "raw", "GraduateEmploymentSurveyNTUNUSSITSMUSUSSSUTD.csv"),
  clean = file.path("data", "clean")
)

if (!dir.exists(PATHS$clean)) dir.create(PATHS$clean, recursive = TRUE)

# ---- Column groups -----------------------------------------------------------
# The eight survey measures. They arrive as character because missing values
# are coded as text ("na" / "N.A."), which forces the whole column to text.
MEASURE_COLS <- c(
  "employment_rate_overall", "employment_rate_ft_perm",
  "basic_monthly_mean", "basic_monthly_median",
  "gross_monthly_mean", "gross_monthly_median",
  "gross_mthly_25_percentile", "gross_mthly_75_percentile"
)

RATE_COLS   <- MEASURE_COLS[1:2]   # percentages, valid range 0-100
INCOME_COLS <- MEASURE_COLS[3:8]   # SGD per month, must be positive

# ---- Missing-value tokens ----------------------------------------------------
# data.gov.sg encodes "not available" inconsistently across survey years.
NA_TOKENS <- c("na", "n.a.", "n.a", "nil", "-", "", "null")

# ---- University short codes --------------------------------------------------
# Full legal names are 30-45 characters and unusable as chart axis labels.
UNIVERSITY_LOOKUP <- tribble(
  ~university_full,                                 ~university_code, ~university_type,
  "Nanyang Technological University",               "NTU",            "Comprehensive",
  "National University of Singapore",               "NUS",            "Comprehensive",
  "Singapore Institute of Technology",              "SIT",            "Applied",
  "Singapore Management University",                "SMU",            "Specialised",
  "Singapore University of Social Sciences",        "SUSS",           "Applied",
  "Singapore University of Technology and Design",  "SUTD",           "Specialised"
)

# ---- Field-of-study classification ------------------------------------------
# 331 distinct degree titles cannot be plotted or filtered meaningfully, so each
# is assigned to one broad field. Rules are applied IN ORDER and the first match
# wins; the order encodes deliberate precedence decisions for interdisciplinary
# and double-degree titles, e.g.
#   "Computer Engineering"                      -> Computing & IT   (not Engineering)
#   "Aerospace Engineering and Economics"       -> Engineering      (not Economics)
#   "Naval Architecture"                        -> Engineering      (not Architecture)
#   "Computer Science & Game Design"            -> Computing & IT   (not Design & Media)
# Every precedence choice is listed in the report so results are interpretable.
FIELD_RULES <- tribble(
  ~field, ~pattern,

  # Professional degrees first: unambiguous and must not be captured by the
  # generic "science" or "arts" patterns further down.
  "Education",                        "education|early childhood",
  "Medicine & Dentistry",             "medicine|surgery|mbbs|dental|dentistry",
  "Health Sciences",                  "nursing|pharmac|physiotherap|occupational therapy|radiograph|radiation therapy|dietetic|nutrition|speech and language",

  # Computing is claimed before Engineering and Design so that titles awarded as
  # a BEng or a BA but taught as computing are grouped with their discipline.
  "Computing & IT",                   "computer science|computer engineering|computational|computing|information system|information security|information & communications technology|software engineering|data science|artificial intelligence|analytics|electronic commerce|interactive simulation",

  "Design & Media",                   "art, design|fine arts|digital art|animation|interior design|industrial design|communication design|user experience|game design|digital communications|integrated media",

  # Marine/naval titles are engineering despite containing "architecture".
  "Engineering",                      "naval architecture|marine engineering|offshore engineering",
  "Architecture & Built Environment", "architecture|real estate|project and facilities|landscape|sustainable design",
  "Engineering",                      "engineering|engineer|mechatronics|telematics|aeronautical|aircraft systems|aerospace|materials science|electromechanical",

  "Law",                              "\\blaws?\\b|llb",
  "Economics",                        "economic",
  "Business & Management",            "business|accountanc|management|marketing|finance|supply chain|human resource|hospitality|culinary|air transport|maritime studies",

  # "Social Sciences" must be tested before "Science".
  "Arts, Humanities & Social Sciences", "social science|social work|psycholog|sociolog|philosoph|history|english|chinese|linguistic|communication studies|public policy|global affairs|criminolog|music|humanities|sport science|sports science|public safety|environmental studies|\\barts\\b",
  "Science",                          "science|biolog|chemistr|physics|mathemat|biomedical|environmental earth|food technology|food & human|food and human",

  "Interdisciplinary",                "double major|cum laude and above"
)

# ---- Cohort eras -------------------------------------------------------------
# Graduating cohorts are grouped so the dashboard can compare labour-market
# regimes rather than forcing the reader to interpret twelve separate years.
ERA_BREAKS <- tribble(
  ~era,                 ~year_from, ~year_to,
  "Pre-pandemic",             2013L,    2019L,
  "Pandemic cohorts",         2020L,    2021L,
  "Post-pandemic",            2022L,    2024L
)

# ---- School aliases ----------------------------------------------------------
# Applied after generic formatting clean-up, for the differences that remain:
# genuine alternative names and institutional renames, rather than formatting.
# Each mapping is listed explicitly so a reader can audit it, and each is
# justified in the report's data section.
SCHOOL_ALIASES <- tribble(
  ~school_raw,                                                         ~school_canonical,

  # Plural/singular and abbreviated forms of the same faculty.
  "College of Sciences",                                               "College of Science",
  "Multi-Disciplinary Programme",                                      "Multi-Disciplinary Programmes",
  "Multidisciplinary Programmes",                                      "Multi-Disciplinary Programmes",
  "YLL School of Medicine",                                            "Yong Loo Lin School of Medicine",
  "Yong Loo Lin School (Medicine)",                                    "Yong Loo Lin School of Medicine",
  "YST Conservatory of Music",                                         "Yong Siew Toh Conservatory of Music",

  # Diacritics were lost from some records on export and cannot be recovered
  # from the text itself, so the affected records are mapped to the correct name.
  "Technische Universitat Munchen",                                    "Technische Universit\u00e4t M\u00fcnchen",

  # SMU renamed its School of Information Systems to the School of Computing and
  # Information Systems in 2022. Treating the two names as one faculty keeps the
  # dashboard's trend lines continuous across the rename rather than showing one
  # school ending and another beginning.
  "School of Information Systems",                                     "School of Computing and Information Systems",

  # From 2023 SMU reports its computing faculty split by major. The split is a
  # degree-level distinction, already captured by the degree variable, so both
  # labels are returned to the faculty they belong to.
  "School of Computing and Information Systems - Computer Science",    "School of Computing and Information Systems",
  "School of Computing and Information Systems - Information Systems", "School of Computing and Information Systems"
) |>
  mutate(school_canonical = stringi::stri_unescape_unicode(school_canonical))

# ---- Degree-name recovery ----------------------------------------------------
# Six 2023 SMU records carry only the reporting tier in the degree column, so
# the programme has to be read off the faculty label they were filed under. Two
# of the resulting names need mapping onto the wording SMU uses for the same
# programme in every other year, so that the record joins its own trend line
# instead of creating a one-year orphan category.
DEGREE_RECOVERY <- tribble(
  ~degree_recovered,                   ~degree_canonical,
  "Business",                          "Business Management",
  "Computing and Information Systems", "Information Systems"
)

# ---- Subject aliases ---------------------------------------------------------
# After full award titles are reduced to their subject, a handful of subjects
# still differ only by a plural, a hyphen or internal capitalisation, which
# would split one subject's trend line in two. The surviving differences are
# resolved here. The NUS "Bachelor of Laws (LLB)" and the NTU and SMU "Law"
# are deliberately merged, because comparing the same subject across
# universities is the point of the subject level.
SUBJECT_ALIASES <- tribble(
  ~subject_raw,                                        ~subject_canonical,
  "Biomedical Science (Traditional Chinese Medicine)", "Biomedical Sciences (Traditional Chinese Medicine)",
  "Digital Art and Animation",                         "Digital Arts and Animation",
  "Environmental Earth Systems Science",               "Environmental Earth Systems Sciences",
  "Inter-Disciplinary Double Major",                   "Interdisciplinary Double Major",
  "Mathematical Science",                              "Mathematical Sciences",
  "Systems Engineering (Electromechanical Systems)",   "Systems Engineering (ElectroMechanical Systems)",
  "Laws",                                              "Law",
  "Laws (LLB)",                                        "Law",
  "Laws (L.L.B)",                                      "Law"
)
