# ==============================================================================
# 00_setup.R  --  Packages, paths and lookup tables
# ==============================================================================
# MA1580 -- Graduate Employment Dashboard
#
# Keeps all configuration in one file so the later scripts contain logic
# rather than hard-coded values. Sourced first by run_all.R.
#
# data/raw/ is only ever read. data/clean/ is rebuilt on every run, so there
# is no chance of stale output surviving.
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
# The eight survey measures. All eight import as text because missing values
# are written as words ("na" / "N.A."), which forces the column to character.
MEASURE_COLS <- c(
  "employment_rate_overall", "employment_rate_ft_perm",
  "basic_monthly_mean", "basic_monthly_median",
  "gross_monthly_mean", "gross_monthly_median",
  "gross_mthly_25_percentile", "gross_mthly_75_percentile"
)

RATE_COLS   <- MEASURE_COLS[1:2]   # percentages, 0-100
INCOME_COLS <- MEASURE_COLS[3:8]   # SGD per month, must be positive

# ---- Missing-value tokens ----------------------------------------------------
# "Not available" is written differently in different survey years.
NA_TOKENS <- c("na", "n.a.", "n.a", "nil", "-", "", "null")

# ---- University short codes --------------------------------------------------
# The full names run to 45 characters and do not fit on a chart axis.
UNIVERSITY_LOOKUP <- tribble(
  ~university_full,                                 ~university_code,
  "Nanyang Technological University",               "NTU",
  "National University of Singapore",               "NUS",
  "Singapore Institute of Technology",              "SIT",
  "Singapore Management University",                "SMU",
  "Singapore University of Social Sciences",        "SUSS",
  "Singapore University of Technology and Design",  "SUTD"
)

# ---- Field-of-study classification ------------------------------------------
# There are over 300 distinct degree titles, far too many to put on a chart or
# in a slicer, so each is assigned to one of 13 broader fields.
#
# The rule used throughout: a degree goes to the discipline whose method it
# teaches, not the industry that method is applied in. Examples:
#
#   Business Analytics          -> Computing & IT  (method analytics, domain business)
#   Computational Biology       -> Computing & IT  (method computation, domain biology)
#   Pharmaceutical Engineering  -> Engineering     (method engineering, domain pharma)
#   Computer Engineering        -> Computing & IT
#   Maritime Studies            -> Business        (method management, domain shipping)
#
# The rules are tested in order and the first match wins, so the ordering is
# what enforces the rule. Double degrees take the field of the discipline named
# first, so "Aerospace Engineering and Economics" is Engineering.
FIELD_RULES <- tribble(
  ~field, ~pattern,

  # Professional degrees first, so the general "science" and "arts" patterns
  # lower down cannot claim them.
  "Education",                        "education|early childhood",
  "Medicine & Dentistry",             "medicine|surgery|mbbs|dental|dentistry",

  # Computing before Engineering, so a computing course awarded as a BEng or a
  # BA is still grouped with computing.
  "Computing & IT",                   "computer science|computer engineering|computational|computing|information system|information security|information & communications technology|software engineering|data science|artificial intelligence|analytics|electronic commerce|interactive simulation",

  "Design & Media",                   "art, design|fine arts|digital art|animation|interior design|industrial design|communication design|user experience|game design|digital communications|integrated media",

  # Marine and naval courses are engineering even though they say "architecture".
  "Engineering",                      "naval architecture|marine engineering|offshore engineering",
  "Architecture & Built Environment", "architecture|real estate|project and facilities|landscape|sustainable design",

  # Engineering before Health Sciences, which is what puts Pharmaceutical
  # Engineering in Engineering. No health course in this data says "engineering",
  # so this ordering changes nothing else.
  "Engineering",                      "engineering|engineer|mechatronics|telematics|aeronautical|aircraft systems|aerospace|materials science|electromechanical",
  "Health Sciences",                  "nursing|pharmac|physiotherap|occupational therapy|radiograph|radiation therapy|dietetic|nutrition|speech and language",

  "Law",                              "\\blaws?\\b|llb",
  "Economics",                        "economic",
  "Business & Management",            "business|accountanc|management|marketing|finance|supply chain|human resource|hospitality|culinary|air transport|maritime studies",

  # "Social Sciences" has to be tested before "Science".
  "Arts, Humanities & Social Sciences", "social science|social work|psycholog|sociolog|philosoph|history|english|chinese|linguistic|communication studies|public policy|global affairs|criminolog|music|humanities|sport science|sports science|public safety|environmental studies|\\barts\\b",
  "Science",                          "science|biolog|chemistr|physics|mathemat|biomedical|environmental earth|food technology|food & human|food and human",

  "Interdisciplinary",                "double major"
)

# ---- Cohort eras -------------------------------------------------------------
# Years are grouped so the dashboard can compare three labour markets instead
# of asking the reader to interpret twelve separate years.
ERA_BREAKS <- tribble(
  ~era,                 ~year_from, ~year_to,
  "Pre-pandemic",             2013L,    2019L,
  "Pandemic cohorts",         2020L,    2021L,
  "Post-pandemic",            2022L,    2024L
)

# ---- School aliases ----------------------------------------------------------
# Applied after the general formatting clean-up, for the differences that are
# left: alternative names and faculty renames rather than spelling. Listed here
# so each mapping can be checked.
SCHOOL_ALIASES <- tribble(
  ~school_raw,                                                         ~school_canonical,

  # Singular/plural and abbreviated versions of the same faculty.
  "College of Sciences",                                               "College of Science",
  "Multi-Disciplinary Programme",                                      "Multi-Disciplinary Programmes",
  "Multidisciplinary Programmes",                                      "Multi-Disciplinary Programmes",
  "YLL School of Medicine",                                            "Yong Loo Lin School of Medicine",
  "Yong Loo Lin School (Medicine)",                                    "Yong Loo Lin School of Medicine",
  "YST Conservatory of Music",                                         "Yong Siew Toh Conservatory of Music",

  # Some records lost their accents on export and the text cannot be repaired,
  # so they are mapped to the correct name.
  "Technische Universitat Munchen",                                    "Technische Universität München",

  # SMU renamed its School of Information Systems to the School of Computing
  # and Information Systems in 2022. Treating both names as one faculty keeps
  # the trend line continuous instead of showing one school stopping and
  # another starting.
  "School of Information Systems",                                     "School of Computing and Information Systems",

  # From 2023 SMU splits that faculty by major. The major is already in the
  # degree column, so both labels go back to the faculty.
  "School of Computing and Information Systems - Computer Science",    "School of Computing and Information Systems",
  "School of Computing and Information Systems - Information Systems", "School of Computing and Information Systems"
) |>
  mutate(school_canonical = stringi::stri_unescape_unicode(school_canonical))

# ---- Degree-name recovery ----------------------------------------------------
# Six 2023 SMU records have only the reporting tier in the degree column, so the
# programme has to be taken from the faculty they were filed under. Two of the
# resulting names need mapping to the wording SMU uses in other years, or the
# record becomes a one-year category of its own.
DEGREE_RECOVERY <- tribble(
  ~degree_recovered,                   ~degree_canonical,
  "Business",                          "Business Management",
  "Computing and Information Systems", "Information Systems"
)

# ---- Subject aliases ---------------------------------------------------------
# Once award titles are reduced to their subject, a few subjects still differ
# only by a plural, a hyphen or capitalisation, which would split one trend
# line in two. NUS "Bachelor of Laws (LLB)" and NTU/SMU "Law" are merged on
# purpose, since comparing the same subject across universities is what the
# subject column is for.
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

# ---- Footnote markers --------------------------------------------------------
# MOE marks some programme names with footnote symbols. The legend that defines
# them is printed under the original table and is not included in the CSV, so
# without it the symbols look like formatting. They are not: two of them say
# something important about how the figure was produced.
#
# Legend transcribed from the dataset page:
#   https://data.gov.sg/datasets/d_3c55210de27fcccda2ed0c63fdd2b352/view
FOOTNOTE_LEGEND <- tribble(
  ~marker, ~meaning, ~handled_as,

  "*",   "SMU courses are direct four-year programmes whose graduates may be awarded Cum Laude and above; SMU publishes both the whole cohort and that subset",
         "cohort_tier",

  "^",   "Figures are based on fewer than 30 respondents",
         "flag_small_sample",

  "^^",  "Figures include graduates of Bachelor of Engineering (Bioengineering), a course merged into Biomedical Engineering in 2014",
         "Documented only",

  "**",  "No figures published, because of a small number of graduates and/or a low response rate",
         "Explains the suppressed records",

  "#",   "Figures come from a follow-up survey of the prior year's graduates, taken after their practical training or equivalent (Law, Medicine, Pharmacy, Biomedical Sciences & Chinese Medicine); for Architecture, of graduates three years earlier",
         "flag_followup_survey",

  "##",  "NTU Medicine figures come from a follow-up survey taken after housemanship or first-year residency",
         "flag_followup_survey",

  "###", "SUTD Architecture and Sustainable Design figures come from a follow-up survey taken after practical training",
         "flag_followup_survey"
)

# Every marker combination that appears in the file as downloaded. Checking the
# whole combination rather than the individual symbols matters because the
# symbols overlap: "^" and "^^" are different markers that share a character,
# and "#", "##" and "###" are three different notes. If MOE publishes a
# combination that is not listed here, the run stops rather than guessing which
# of the overlapping readings applies.
KNOWN_MARKER_COMBINATIONS <- c(
  "",      # no note
  "^",     # fewer than 30 respondents
  "^^",    # includes Bioengineering graduates
  "#",     # follow-up survey
  "##",    # NTU Medicine follow-up
  "###",   # SUTD Architecture and Sustainable Design follow-up
  "#^",    # follow-up survey, and fewer than 30 respondents
  "**",    # no figures published
  "#**",   # follow-up programme, figures not published
  "**#"    # same pair, printed in the other order
)

# ---- Source errors -----------------------------------------------------------
# One 2024 SUSS record has a school name in its degree column, where MOE filed
# "School of Public Safety and Security" instead of the programme name. SUSS
# published "Bachelor of Public Safety and Security" for the same school in
# 2023, so the record is corrected to that rather than dropped, which keeps the
# observation and lets the two years form a trend. Listed here so the one place
# a record's identity is changed is easy to find.
DEGREE_CORRECTIONS <- tribble(
  ~degree_as_published,                    ~degree_corrected,
  "School of Public Safety and Security",  "Bachelor of Public Safety and Security"
)
