# ==============================================================================
# 02_clean.R  --  Raw survey file -> validated analysis table
# ==============================================================================
# Turns the file as downloaded from data.gov.sg into one tidy, correctly typed
# table. Each step fixes one problem with the raw data, named in the comment
# above it.
#
# The raw file is not modified. Row counts are logged at each step and exported
# with the data, so the counts quoted in the report come from here.
# ==============================================================================

message("\n== 02_clean.R ==")
clean_log <- new_log()

# ---- Step 1. Read every column as text ---------------------------------------
# The eight measure columns contain the words "na" and "N.A.", so letting readr
# guess the types would drop values. Reading everything as text means all type
# conversion happens below, where it can be seen.
raw <- read_csv(PATHS$raw, col_types = cols(.default = col_character()),
                na = character(), show_col_types = FALSE)

clean_log <- log_step(clean_log, "1. Read raw file",
                      "Imported as text to control all type conversion", nrow(raw))

check_that(identical(names(raw),
                     c("year", "university", "school", "degree", MEASURE_COLS)),
           "Raw file has the 12 expected columns in the expected order")

# ---- Step 2. Repair the export encoding --------------------------------------
# Partner-institution names with accents were double-encoded when the file was
# exported, so they come out garbled and would show that way on every axis
# label, tooltip and slicer.
dat <- raw |>
  mutate(across(c(university, school, degree), repair_encoding))

clean_log <- log_step(clean_log, "2. Repair encoding",
                      "Reversed double UTF-8 encoding in name columns", nrow(dat))

# ---- Step 3. Read the footnote markers before they are stripped --------------
# MOE marks programme names with footnote symbols. The legend is printed under
# the original table and is not in the CSV, so without it the symbols look like
# formatting. Two of them matter:
#
#   ^   figures based on fewer than 30 respondents
#   #   figures from a follow-up survey of the prior year's graduates, taken
#       after their practical training, so the record is not a fresh-graduate
#       cohort. Law, Medicine, Pharmacy and Biomedical Sciences & Chinese
#       Medicine are reported this way, and Architecture from graduates three
#       years earlier.
#   **  no figures published, because of small numbers or a low response rate
#
# Removing them would lose a sample-size warning on 120 records and a cohort
# warning on 94. A "#" record's pay cannot be compared with an unmarked
# record's pay, so the warning has to reach the dashboard. The markers are read
# here, before any name cleaning, and kept as flags. FOOTNOTE_LEGEND in
# 00_setup.R has the definitions and is exported for the appendix.
dat <- dat |>
  mutate(
    footnote_markers = read_footnote_markers(degree),
    flag_small_sample    = str_detect(footnote_markers, fixed("^")),
    flag_followup_survey = str_detect(footnote_markers, fixed("#"))
  )

# Checked here, on all 1,550 rows, rather than after the suppressed records are
# dropped. The ** and ## symbols only appear on records with no figures, so a
# check further down would never see them and would cover half the legend.
observed_markers <- dat$footnote_markers |> str_split("") |> unlist() |> unique()
observed_markers <- setdiff(observed_markers, "")
check_that(observed_markers %in% c("*", "^", "#"),
           "Every footnote symbol in the file is one the legend defines",
           setdiff(observed_markers, c("*", "^", "#")))

message("  [note] footnote markers read from the file as imported: ",
        sum(dat$flag_small_sample), " record(s) based on fewer than 30 ",
        "respondents, ", sum(dat$flag_followup_survey),
        " from a follow-up survey of an earlier cohort")

clean_log <- log_step(clean_log, "3. Read footnote markers",
                      "Sample-size and follow-up-survey warnings captured as flags before names were cleaned",
                      nrow(dat))

# ---- Step 4. Normalise the missing-value codes -------------------------------
# "Not available" is written "na" in some years and "N.A." in others. Both
# become NA so missingness is one thing rather than two categories.
#
# The columns are named rather than using where(is.character). The footnote
# column added in step 3 uses "" for "no marker", and "" is itself an NA token,
# so a sweep over all character columns would turn every unmarked record's
# marker into NA and weaken the checks that read it.
dat <- dat |>
  mutate(across(c(year, university, school, degree, all_of(MEASURE_COLS)),
                blank_na_tokens))

clean_log <- log_step(clean_log, "4. Normalise missing codes",
                      "'na' and 'N.A.' recoded to NA throughout", nrow(dat))

# ---- Step 5. Type the key and the measures -----------------------------------
# Year and the eight measures are text. They have to be numbers for any
# sorting, aggregation, trend line or axis scale.
dat <- dat |>
  mutate(year = as.integer(year)) |>
  mutate(across(all_of(MEASURE_COLS), ~ as_measure(.x, cur_column())))

check_that(!is.na(dat$year), "Every record has a parsable survey year")

clean_log <- log_step(clean_log, "5. Convert to numeric",
                      "Year and 8 measures typed as numbers", nrow(dat))

# ---- Step 6. Drop records with no reported results ---------------------------
# 105 records have no figure for any of the eight measures, because MOE
# suppresses results for programmes with too few graduates to publish. They
# name a programme but add nothing to any visual, and keeping them would leave
# gaps in every trend line. Records missing only some measures are kept.
#
# The count is a column rather than a loose vector used inside filter(). A
# loose vector lines up with the rows only because of the current ordering, so
# any change above that reorders or subsets rows would filter the wrong records
# with no error.
dat <- dat |>
  mutate(measures_present = rowSums(!is.na(across(all_of(MEASURE_COLS)))))

suppressed <- dat |> filter(measures_present == 0)
dat        <- dat |> filter(measures_present > 0) |> select(-measures_present)

check_that(nrow(suppressed) == 0 | all(rowSums(!is.na(suppressed[MEASURE_COLS])) == 0),
           "Dropped records were empty across all eight measures, not just some")

# With the markers available the exclusion can be checked rather than assumed.
# Every suppressed record should carry a marker explaining the absence: either
# ** for small numbers or low response, or a follow-up marker meaning the
# figures were not available yet when the table was published.
check_that(suppressed$footnote_markers != "",
           "Every suppressed record carries a footnote marker explaining why it is empty",
           suppressed |> filter(footnote_markers == "") |>
             select(year, university, degree))

clean_log <- log_step(clean_log, "6. Remove suppressed records",
                      "Dropped records with no value for any of the 8 measures",
                      nrow(dat))

# ---- Step 7. Supply the missing SUTD faculty -------------------------------
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

clean_log <- log_step(clean_log, "7. Label SUTD faculty level",
                      "Structurally absent SUTD school labelled explicitly", nrow(dat))

# ---- Step 8. Tidy school and degree names -----------------------------------
# The same faculty and the same programme are spelled several ways across the
# twelve years: capitalisation ("Faculty Of" vs "Faculty of"), connectives
# ("&" vs "and"), footnote symbols, and SMU's "(4-year programme)" vs
# "(4-years programme)". Left alone, one programme becomes several categories
# and fragments every chart and filter. The footnote symbols can be removed
# here because step 3 already took their meaning out into flags.
dat <- dat |>
  mutate(
    school = school |> strip_footnotes() |> canonicalise_text() |>
      normalise_programme_length() |>
      # Programme length belongs to the degree, not the faculty, and is the same
      # across SMU, so it comes off the faculty name and stays on the degree.
      str_remove("\\s*\\(4-year\\)") |> str_squish(),
    degree = degree |> strip_footnotes() |> canonicalise_text() |>
      normalise_programme_length() |> normalise_honours()
  ) |>
  # SIT names its overseas partners inconsistently, sometimes as compounds.
  # Reducing each to the awarding institution lets its partner and in-house
  # programmes be compared.
  mutate(school = if_else(university == "Singapore Institute of Technology",
                          normalise_partner_institution(school), school)) |>
  # Keep the label as the survey published it. It records what each year
  # actually said, and step 10 reads a missing degree name off it before the
  # merges below remove the difference.
  mutate(school_reported = school) |>
  # What is left are alternative names and faculty renames, handled by the
  # lookup in 00_setup.R so each mapping can be checked.
  mutate(school = coalesce(SCHOOL_ALIASES$school_canonical[
    match(school, SCHOOL_ALIASES$school_raw)], school))

# SIT is the only university awarding degrees conferred by overseas partners.
# Recording it gives the dashboard something to filter and compare on.
dat <- dat |>
  mutate(award_route = case_when(
    university != "Singapore Institute of Technology"        ~ "Own award",
    school == "Singapore Institute of Technology (own award)" ~ "Own award",
    TRUE                                                      ~ "Overseas partner award"
  ))

clean_log <- log_step(clean_log, "8. Canonicalise names",
                      "Spelling, case, footnote and partner-name variants collapsed",
                      nrow(dat))

# ---- Step 9. Correct a filing error in the source ---------------------------
# One 2024 SUSS record has a school name in its degree column, where MOE put
# "School of Public Safety and Security" instead of the programme name. Left
# alone it would appear on the dashboard as if it were a course. SUSS published
# "Bachelor of Public Safety and Security" for the same school in 2023, so the
# record is corrected to that instead of being dropped, which keeps the
# observation and lets the two years form a trend. The mapping is in
# 00_setup.R so the change is easy to find.
corrections_applied <- sum(dat$degree %in% DEGREE_CORRECTIONS$degree_as_published)

dat <- dat |>
  mutate(degree = coalesce(DEGREE_CORRECTIONS$degree_corrected[
    match(degree, DEGREE_CORRECTIONS$degree_as_published)], degree))

check_that(corrections_applied == nrow(DEGREE_CORRECTIONS),
           "Every listed source correction matched exactly one record")
check_that(!str_detect(dat$degree, "^School of "),
           "No degree name is a school name",
           dat |> filter(str_detect(degree, "^School of ")) |> distinct(year, university, degree))

clean_log <- log_step(clean_log, "9. Correct source filing error",
                      "School name published in the degree column corrected to the programme name",
                      nrow(dat))

# ---- Step 10. Separate the reporting tier from the degree --------------------
# SMU reports each programme twice: once for the whole graduating cohort and
# once for the subset graduating Cum Laude or above. The subset is part of the
# cohort above it, not a separate programme, so treating both as ordinary
# records double-counts SMU graduates and raises every SMU average. Moving the
# distinction into its own column removes the double count and makes the
# honours subset available as a comparison instead.
dat <- dat |>
  mutate(
    cohort_tier = if_else(str_detect(str_to_lower(degree), "cum laude"),
                          "Cum Laude and above", "All graduates"),
    # Six 2023 records have only the tier label in the degree column. The
    # programme can be taken from the faculty they were filed under, which is
    # why that label was kept above.
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

# Two of the recovered names use the faculty's wording, not the programme's, so
# they are mapped to the name used in other years and join the right trend line.
dat <- dat |>
  mutate(degree = coalesce(DEGREE_RECOVERY$degree_canonical[
    match(degree, DEGREE_RECOVERY$degree_recovered)], degree))

check_that(!str_detect(str_to_lower(dat$degree), "cum laude"),
           "Tier wording fully removed from degree names")
check_that(dat$degree != "" & !is.na(dat$degree),
           "Every record still has a degree name after tier extraction")

clean_log <- log_step(clean_log, "10. Separate reporting tier",
                      "SMU 'Cum Laude and above' subset moved to its own variable",
                      nrow(dat))

# ---- Step 11. Classify degrees into fields of study -------------------------
# There are still over 200 distinct degree titles, more than any chart or
# slicer can show, so each is assigned to one broad field. The individual title
# stays in the data for drill-down.
dat <- dat |>
  mutate(field = classify_field(degree))

unclassified <- dat |> filter(field == "Other") |> distinct(degree)
check_that(nrow(unclassified) == 0,
           "Every degree title matched a field-of-study rule", unclassified)

clean_log <- log_step(clean_log, "11. Classify fields of study",
                      "Degree titles grouped into broad fields", nrow(dat))

# ---- Step 12. Attach university codes ---------------------------------------
# The full names are up to 45 characters and either overflow or rotate
# illegibly on a category axis and in slicer lists.
dat <- dat |>
  left_join(UNIVERSITY_LOOKUP, by = c("university" = "university_full"))

check_that(!is.na(dat$university_code),
           "Every record matched a known university",
           dat |> filter(is.na(university_code)) |> distinct(university))

clean_log <- log_step(clean_log, "12. Add university codes",
                      "Short codes attached for axis labels", nrow(dat))

# ---- Step 13. Check the measures agree with each other ----------------------
# These checks confirm the eight measures are consistent before anything is
# written to data/clean/.
message("Validating cleaned data:")

check_that(dat |> count(year, university, school, degree, cohort_tier) |>
             pull(n) |> (\(n) n == 1)(),
           "One record per year, university, school, degree and tier")

check_that(with(dat, is.na(employment_rate_overall) |
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

# Gross pay should be at or above basic pay, since gross adds overtime,
# allowances and bonuses. One record breaks this. It comes from the source
# rather than from this cleaning: MOE works out the gross and basic figures
# from the respondents who answered each question, and those groups are not the
# same, so gross can come out slightly below basic. The record is kept and
# flagged, since dropping a valid programme would distort more than a 0.5%
# inconsistency does. The check tests that the gap stays small rather than that
# it never happens.
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

clean_log <- log_step(clean_log, "13. Validate consistency",
                      "Range, ordering, uniqueness and footnote checks passed",
                      nrow(dat))

# ---- Result ------------------------------------------------------------------
employment_clean <- dat |>
  select(year, university, university_code, school,
         school_reported, degree, field, cohort_tier, award_route,
         all_of(MEASURE_COLS),
         footnote_markers, flag_small_sample, flag_followup_survey,
         flag_gross_below_basic)

message("Cleaned: ", nrow(employment_clean), " records, ",
        n_distinct(employment_clean$degree), " distinct degrees, ",
        n_distinct(employment_clean$school), " distinct schools.")
message("  of which ", sum(employment_clean$flag_small_sample),
        " rest on fewer than 30 respondents and ",
        sum(employment_clean$flag_followup_survey),
        " come from a follow-up survey of an earlier cohort.")
