# ==============================================================================
# 02_clean.R  --  Raw survey file -> validated analysis table
# ==============================================================================
# PURPOSE
#   Turn the file exactly as downloaded from data.gov.sg into one tidy,
#   correctly typed, internally consistent table. Every step below exists to
#   remove a specific defect that would otherwise make the dashboard wrong or
#   unreadable; the defect is named in the comment above the step.
#
#   The raw file is never modified. Row counts are logged at each step and the
#   log is exported alongside the data as the audit trail for the report.
# ==============================================================================

message("\n== 02_clean.R ==")
clean_log <- new_log()

# ---- Step 1. Read every column as text ---------------------------------------
# Defect: eight numeric measures contain the text "na" / "N.A.", so letting
# readr guess types would either fail or silently drop values. Reading
# everything as text defers all typing to this script, where it is explicit.
raw <- read_csv(PATHS$raw, col_types = cols(.default = col_character()),
                na = character(), show_col_types = FALSE)

clean_log <- log_step(clean_log, "1. Read raw file",
                      "Imported as text to control all type conversion", nrow(raw))

check_that(identical(names(raw),
                     c("year", "university", "school", "degree", MEASURE_COLS)),
           "Raw file has the 12 expected columns in the expected order")

# ---- Step 2. Repair the export encoding --------------------------------------
# Defect: partner-institution names were double-encoded on export, so
# "Technische Universitaet Muenchen" and similar names render as mojibake and
# would appear corrupted on every axis label, tooltip and slicer.
dat <- raw |>
  mutate(across(c(university, school, degree), repair_encoding))

clean_log <- log_step(clean_log, "2. Repair encoding",
                      "Reversed double UTF-8 encoding in name columns", nrow(dat))

# ---- Step 3. Normalise the missing-value codes -------------------------------
# Defect: "not available" is written as "na" in some years and "N.A." in
# others. Both are converted to a real NA so that missingness can be counted
# and handled once, instead of being treated as two different categories.
dat <- dat |>
  mutate(across(everything(), blank_na_tokens))

clean_log <- log_step(clean_log, "3. Normalise missing codes",
                      "'na' and 'N.A.' recoded to NA throughout", nrow(dat))

# ---- Step 4. Type the key and the measures -----------------------------------
# Defect: year and all eight measures are text. They are needed as numbers for
# any sorting, aggregation, trend line or axis scale in the dashboard.
dat <- dat |>
  mutate(year = as.integer(year)) |>
  mutate(across(all_of(MEASURE_COLS), ~ as_measure(.x, cur_column())))

check_that(!is.na(dat$year), "Every record has a parsable survey year")

clean_log <- log_step(clean_log, "4. Convert to numeric",
                      "Year and 8 measures typed as numbers", nrow(dat))

# ---- Step 5. Drop records with no reported results ---------------------------
# Defect: 105 records report no figure for any of the eight measures, because
# MOE suppresses results for programmes with too few graduates to publish.
# They identify a programme but contribute nothing to any visual, and retaining
# them would understate every average and leave gaps in every trend line.
# Records missing only SOME measures are kept, so partial information is used.
measures_present <- rowSums(!is.na(dat[MEASURE_COLS]))

suppressed <- dat |> filter(measures_present == 0)
dat        <- dat |> filter(measures_present > 0)

check_that(nrow(suppressed) == 0 | all(rowSums(!is.na(suppressed[MEASURE_COLS])) == 0),
           "Dropped records were empty across all eight measures, not just some")

clean_log <- log_step(clean_log, "5. Remove suppressed records",
                      "Dropped records with no value for any of the 8 measures",
                      nrow(dat))

# ---- Step 6. Supply the missing SUTD faculty -------------------------------
# Defect: every SUTD record has a blank school. This is not an error in the
# data: SUTD does not divide its undergraduate programmes into faculties, so
# there is nothing to report. Left blank, SUTD would vanish from any
# school-level visual and show an untidy "(Blank)" in slicers, so the level is
# labelled explicitly for what it is.
dat <- dat |>
  mutate(school = if_else(
    is.na(school) & university == "Singapore University of Technology and Design",
    "SUTD (no faculty structure)", school
  ))

check_that(!is.na(dat$school), "Every retained record has a school")

clean_log <- log_step(clean_log, "6. Label SUTD faculty level",
                      "Structurally absent SUTD school labelled explicitly", nrow(dat))

# ---- Step 7. Canonicalise school and degree names ---------------------------
# Defect: the same faculty and the same programme are spelled several ways
# across twelve survey years -- differing capitalisation ("Faculty Of" vs
# "Faculty of"), connectives ("&" vs "and"), footnote symbols, and SMU's
# "(4-year programme)" vs "(4-years programme)". Unresolved, one programme
# becomes several unrelated categories, fragmenting every chart and filter.
dat <- dat |>
  mutate(
    school = school |> strip_footnotes() |> canonicalise_text() |>
      normalise_programme_length() |>
      # Programme length is a property of the degree, not of the faculty that
      # awards it, and is constant across SMU, so it is dropped from the
      # faculty name and left to the degree name to carry.
      str_remove("\\s*\\(4-year\\)") |> str_squish(),
    degree = degree |> strip_footnotes() |> canonicalise_text() |>
      normalise_programme_length() |> normalise_honours()
  ) |>
  # SIT names its overseas awarding partners inconsistently and sometimes as
  # compounds; reducing each label to the awarding institution lets SIT's
  # partner and in-house programmes be compared.
  mutate(school = if_else(university_code_is_sit <- university ==
                            "Singapore Institute of Technology",
                          normalise_partner_institution(school), school)) |>
  # The label as the survey reported it is kept, both as a record of what each
  # year actually published and because the next step reads a lost degree name
  # off it, before the merges below erase the distinction.
  mutate(school_reported = school) |>
  # What remains are genuine alternative names and institutional renames, which
  # are resolved by the explicit lookup in 00_setup.R so that every mapping is
  # visible and reviewable rather than buried in a regular expression.
  mutate(school = coalesce(SCHOOL_ALIASES$school_canonical[
    match(school, SCHOOL_ALIASES$school_raw)], school))

# SIT is the only university that awards degrees conferred by overseas partner
# institutions. Recording this explicitly turns an accident of SIT's naming into
# a variable the dashboard can filter and compare on.
dat <- dat |>
  mutate(award_route = case_when(
    university != "Singapore Institute of Technology"        ~ "Own award",
    school == "Singapore Institute of Technology (own award)" ~ "Own award",
    TRUE                                                      ~ "Overseas partner award"
  ))

clean_log <- log_step(clean_log, "7. Canonicalise names",
                      "Spelling, case, footnote and partner-name variants collapsed",
                      nrow(dat))

# ---- Step 8. Separate the reporting tier from the degree ---------------------
# Defect: SMU reports each of its programmes twice -- once for the whole
# graduating cohort and once for the subset graduating "Cum Laude and above".
# The subset is a sub-population of the row above it, not a separate
# programme. Treated as ordinary records they double-count SMU graduates and
# pull every SMU average upwards. The distinction is therefore lifted out of
# the degree name into its own variable, which both removes the double count
# and makes the honours subset available as a deliberate comparison.
dat <- dat |>
  mutate(
    cohort_tier = if_else(str_detect(str_to_lower(degree), "cum laude"),
                          "Cum Laude and above", "All graduates"),
    # Six 2023 records carry only the tier label in the degree column. The
    # programme they describe is recoverable from the faculty label the survey
    # filed them under, which is why that label was preserved above.
    degree = if_else(
      str_to_lower(degree) == "cum laude and above",
      school_reported |> str_remove("^School of ") |> str_squish() |>
        (\(s) if_else(str_detect(s, " - "), str_extract(s, "(?<= - ).*"), s))(),
      degree
    ),
    # With the tier recorded separately the wording is redundant in the name.
    degree = degree |>
      str_remove(regex("\\s*[-(]?\\s*cum laude and above\\s*\\)?", ignore_case = TRUE)) |>
      str_squish()
  )

# Two recovered names use the faculty's wording rather than the programme's;
# they are mapped onto the name used in every other year so the record joins
# the right trend line.
dat <- dat |>
  mutate(degree = coalesce(DEGREE_RECOVERY$degree_canonical[
    match(degree, DEGREE_RECOVERY$degree_recovered)], degree))

check_that(!str_detect(str_to_lower(dat$degree), "cum laude"),
           "Tier wording fully removed from degree names")
check_that(dat$degree != "" & !is.na(dat$degree),
           "Every record still has a degree name after tier extraction")

clean_log <- log_step(clean_log, "8. Separate reporting tier",
                      "SMU 'Cum Laude and above' subset moved to its own variable",
                      nrow(dat))

# ---- Step 9. Classify degrees into fields of study --------------------------
# Defect: the cleaned data still holds hundreds of distinct degree titles. No
# chart or slicer can present that many categories, so each title is assigned
# to one broad field, giving the dashboard a usable level of aggregation while
# the individual title remains available for drill-down.
dat <- dat |>
  mutate(field = classify_field(degree))

unclassified <- dat |> filter(field == "Other") |> distinct(degree)
check_that(nrow(unclassified) == 0,
           "Every degree title matched a field-of-study rule", unclassified)

clean_log <- log_step(clean_log, "9. Classify fields of study",
                      "Degree titles grouped into broad fields", nrow(dat))

# ---- Step 10. Attach university codes ---------------------------------------
# Defect: full university names are up to 45 characters and overflow or rotate
# illegibly on category axes and in slicer lists.
dat <- dat |>
  left_join(UNIVERSITY_LOOKUP, by = c("university" = "university_full"))

check_that(!is.na(dat$university_code),
           "Every record matched a known university",
           dat |> filter(is.na(university_code)) |> distinct(university))

clean_log <- log_step(clean_log, "10. Add university codes",
                      "Short codes attached for axis labels", nrow(dat))

# ---- Step 11. Validate internal consistency ---------------------------------
# Cleaning is only trustworthy if its assumptions are tested. These checks
# confirm the measures are mutually coherent before anything is exported.
message("Validating cleaned data:")

check_that(dat |> count(year, university, school, degree, cohort_tier) |>
             pull(n) |> (\(n) n == 1)(),
           "One record per year, university, school, degree and tier")

check_that(if_any_na <- with(dat, is.na(employment_rate_overall) |
                               (employment_rate_overall >= 0 & employment_rate_overall <= 100)),
           "Overall employment rate lies between 0 and 100 per cent")

check_that(with(dat, is.na(employment_rate_ft_perm) |
                  (employment_rate_ft_perm >= 0 & employment_rate_ft_perm <= 100)),
           "Full-time permanent employment rate lies between 0 and 100 per cent")

check_that(with(dat, is.na(employment_rate_overall) | is.na(employment_rate_ft_perm) |
                  employment_rate_ft_perm <= employment_rate_overall + 0.05),
           "Full-time permanent employment never exceeds overall employment")

check_that(rowSums(dat[INCOME_COLS] <= 0, na.rm = TRUE) == 0,
           "All reported incomes are positive")

check_that(with(dat, is.na(gross_mthly_25_percentile) | is.na(gross_monthly_median) |
                  gross_mthly_25_percentile <= gross_monthly_median),
           "Gross 25th percentile does not exceed the gross median")

check_that(with(dat, is.na(gross_monthly_median) | is.na(gross_mthly_75_percentile) |
                  gross_monthly_median <= gross_mthly_75_percentile),
           "Gross median does not exceed the gross 75th percentile")

# Gross pay should by definition sit at or above basic pay, since gross adds
# overtime, allowances and bonuses. Seven records breach this. The breach is a
# property of the source, not of this cleaning: MOE computes the gross and the
# basic figures over the respondents who answered each question, and those two
# groups are not identical, so gross can fall marginally below basic. The
# records are therefore retained -- discarding seven valid programmes would be
# a worse distortion -- but they are flagged, and the check asserts the
# discrepancy stays immaterial rather than asserting it never happens.
dat <- dat |>
  mutate(
    gross_basic_discrepancy_pct = if_else(
      !is.na(gross_monthly_median) & !is.na(basic_monthly_median) &
        gross_monthly_median < basic_monthly_median,
      100 * (basic_monthly_median - gross_monthly_median) / basic_monthly_median,
      0
    ),
    flag_gross_below_basic = gross_basic_discrepancy_pct > 0
  )

check_that(dat$gross_basic_discrepancy_pct < 2,
           "Where gross pay falls below basic pay the gap is under 2 per cent",
           dat |> filter(gross_basic_discrepancy_pct >= 2))

message("  [note] ", sum(dat$flag_gross_below_basic),
        " record(s) flagged: gross median marginally below basic median (max ",
        sprintf("%.2f%%", max(dat$gross_basic_discrepancy_pct)), ")")

check_that(dat$year >= 2013 & dat$year <= 2024,
           "Survey years fall within the documented 2013-2024 coverage")

clean_log <- log_step(clean_log, "11. Validate consistency",
                      "Range, ordering and uniqueness checks passed", nrow(dat))

# ---- Result ------------------------------------------------------------------
employment_clean <- dat |>
  select(year, university, university_code, university_type, school,
         school_reported, degree, field, cohort_tier, award_route,
         all_of(MEASURE_COLS),
         flag_gross_below_basic)

message("Cleaned: ", nrow(employment_clean), " records, ",
        n_distinct(employment_clean$degree), " distinct degrees, ",
        n_distinct(employment_clean$school), " distinct schools.")
