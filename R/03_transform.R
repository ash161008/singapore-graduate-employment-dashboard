# ==============================================================================
# 03_transform.R  --  Derived measures and the dimensional model
# ==============================================================================
# The survey gives eight figures per programme, which say what the number was
# but not whether it is good, for whom, or improving. This script works out the
# measures needed for those comparisons, then splits the cleaned table into a
# star schema.
#
# Why a star schema: Power BI cross-filters through relationships, and a single
# flat table can only filter itself, so slicers would not interact. One fact
# table of measures with small dimension tables around it is what lets a
# university slicer filter a chart built on field of study. It also stores each
# university name six times instead of 1,445.
#
# All aggregation happens here in R, not in Power Query.
# ==============================================================================

message("\n== 03_transform.R ==")

# ---- Derived measures --------------------------------------------------------
# Each measure below answers a question the eight published figures cannot.
employment <- employment_clean |>
  mutate(
    # The subject, independent of how each university words its award, so the
    # same programme can be compared across universities.
    subject = shorten_degree(degree),
    subject = coalesce(SUBJECT_ALIASES$subject_canonical[
      match(subject, SUBJECT_ALIASES$subject_raw)], subject),

    # Structure of the award, read from its title.
    is_honours       = is_honours_degree(degree),
    is_double_degree = is_double_degree(degree),

    # Pay spread. Two programmes can have the same median but very different
    # risk. The gap between the 25th and 75th percentile shows how much
    # outcomes vary between graduates of the same programme, which the median
    # on its own hides.
    pay_spread_sgd   = gross_mthly_75_percentile - gross_mthly_25_percentile,
    pay_spread_ratio = gross_mthly_75_percentile / gross_mthly_25_percentile,

    # Variable pay. Gross includes overtime, allowances and bonuses; basic does
    # not. The gap shows how much of the starting salary is guaranteed and how
    # much depends on hours or performance.
    variable_pay_sgd = gross_monthly_median - basic_monthly_median,
    variable_pay_pct = 100 * (gross_monthly_median - basic_monthly_median) /
      basic_monthly_median,

    # Job quality. The headline employment rate counts any kind of employment,
    # so the gap between it and the full-time permanent rate is the share of
    # the labour force in part-time, temporary, freelance or contract work.
    #
    # Named for what it measures rather than "insecure", because part-time work
    # is not always involuntary and the survey does not say which is which.
    #
    # This also matters for reading the pay columns. MOE's salary figures cover
    # full-time permanently employed graduates only, so the graduates counted
    # here have no salary recorded anywhere in the dataset. A programme with a
    # large gap has a pay figure describing a smaller share of its graduates.
    non_ft_perm_employment_pp = employment_rate_overall - employment_rate_ft_perm,

    # A readable version of the follow-up flag, so a legend or caption can say
    # what it means instead of showing TRUE/FALSE. These records cover
    # graduates of an earlier year surveyed after practical training, so their
    # pay cannot be read against a fresh-graduate figure.
    cohort_basis = if_else(flag_followup_survey,
                           "Follow-up survey (post-training)",
                           "Fresh graduates")
  )

# ---- Year benchmarks ---------------------------------------------------------
# Salaries are in nominal dollars, so a 2024 figure is not comparable with a
# 2013 one. Comparing each programme against the median of its own year takes
# wage growth and inflation out, so a rising index means the programme is
# pulling ahead of its peers rather than that time has passed.
#
# The benchmark leaves out two sets of records:
#
#   1. The SMU honours subset, which would count those graduates twice.
#   2. The 76 follow-up-survey records, which cover Law, Medicine, Pharmacy and
#      Architecture graduates surveyed after their practical training, when
#      they are qualified and better paid. Including them would make the
#      benchmark a mix of two career stages and "100" would mean nothing in
#      particular.
#
# So the benchmark is the median fresh-graduate programme in that year. A
# follow-up record still gets an index against it, which reads as "relative to
# that year's fresh graduates" and is flagged as not like-for-like.
year_benchmark <- employment |>
  filter(cohort_tier == "All graduates", !flag_followup_survey,
         !is.na(gross_monthly_median)) |>
  group_by(year) |>
  summarise(
    cohort_median_gross = median(gross_monthly_median),
    cohort_mean_employment = mean(employment_rate_overall, na.rm = TRUE),
    n_programmes = n()
  )

employment <- employment |>
  left_join(year_benchmark, by = "year") |>
  mutate(
    pay_vs_cohort_sgd = gross_monthly_median - cohort_median_gross,
    pay_index         = 100 * gross_monthly_median / cohort_median_gross,
    employment_vs_cohort_pp = employment_rate_overall - cohort_mean_employment,
    era = assign_era(year)
  )

check_that(!is.na(employment$era), "Every year maps to exactly one era")
# These checks test whether a label is plausible, not just present.
#
# They were added after a bug the structural checks could not catch.
# shorten_degree() was turning "Arts (with Education)" into the subject "with
# Education", and "Business (3-year direct Honours)" into "3-year direct
# Honours". Both are non-empty strings on a valid record, so every structural
# check passed. Nothing was structurally wrong; the values were just wrong, and
# they would have appeared on the dashboard as if they were subjects.
#
# Checking that a value exists is not the same as checking it makes sense, so
# these test that each subject label looks like the name of a subject.
check_that(!is.na(employment$subject) & employment$subject != "",
           "Every record has a subject label")

check_that(!str_detect(employment$subject, regex("^(and|with|or|in|of)\\b",
                                                 ignore_case = TRUE)),
           "No subject label begins with a connective, which would mean a title was split at the wrong point",
           employment |> filter(str_detect(subject, regex("^(and|with|or|in|of)\\b",
                                                          ignore_case = TRUE))) |>
             distinct(degree, subject))

check_that(!str_detect(employment$subject,
                       regex("^[0-9]+-year|^honours|programme$|^hons", ignore_case = TRUE)),
           "No subject label is a programme-structure descriptor rather than a subject",
           employment |> filter(str_detect(subject,
                       regex("^[0-9]+-year|^honours|programme$|^hons", ignore_case = TRUE))) |>
             distinct(degree, subject))

check_that(!str_detect(employment$subject, "^(School|Faculty|College) of "),
           "No subject label is a school or faculty name",
           employment |> filter(str_detect(subject, "^(School|Faculty|College) of ")) |>
             distinct(degree, subject))

check_that(nchar(employment$subject) >= 3,
           "No subject label is shorter than three characters",
           employment |> filter(nchar(subject) < 3) |> distinct(degree, subject))

# ---- Dimension tables --------------------------------------------------------
# These hold the descriptive columns a user slices by. Each has one row per
# thing and an integer key the fact table points at. Rows are ordered so Power
# BI's default sort makes sense.

dim_year <- employment |>
  distinct(year) |>
  arrange(year) |>
  left_join(year_benchmark, by = "year") |>
  mutate(
    year_key = row_number(),
    # A real date column lets Power BI use a continuous time axis and its
    # time-intelligence functions, which it cannot do with an integer year.
    year_date = as.Date(paste0(year, "-01-01")),
    era = assign_era(year),
    era_order = match(era, ERA_BREAKS$era),
    .before = 1
  )

dim_university <- UNIVERSITY_LOOKUP |>
  semi_join(employment, by = c("university_full" = "university")) |>
  arrange(university_code) |>
  mutate(university_key = row_number(), .before = 1) |>
  rename(university = university_full)

dim_school <- employment |>
  distinct(university_code, school, award_route) |>
  arrange(university_code, school) |>
  mutate(
    school_key = row_number(),
    # Two universities each have a "School of Business", so the display label
    # is qualified by university to keep slicer entries unambiguous.
    school_label = paste0(university_code, " – ", school),
    .before = 1
  )

dim_degree <- employment |>
  distinct(degree, subject, field, is_honours, is_double_degree) |>
  arrange(field, subject, degree) |>
  mutate(degree_key = row_number(), .before = 1)

dim_field <- employment |>
  filter(cohort_tier == "All graduates") |>
  count(field, name = "n_programmes") |>
  # Ordered by size so the largest fields lead in legends and small-multiple
  # grids instead of appearing in arbitrary alphabetical order.
  arrange(desc(n_programmes)) |>
  mutate(field_key = row_number(), .before = 1)

dim_tier <- tibble(
  tier_key = 1:2,
  cohort_tier = c("All graduates", "Cum Laude and above"),
  tier_note = c(
    "Whole graduating cohort, as published for every university",
    "Subset graduating Cum Laude or above; published by SMU only"
  )
)

# ---- Fact table --------------------------------------------------------------
# One row per programme per survey year per reporting tier, holding only keys
# and measures. Descriptive text lives in the dimensions above, which is what
# keeps the model compact and the relationships unambiguous.
fact_employment <- employment |>
  left_join(dim_year     |> select(year_key, year), by = "year") |>
  left_join(dim_university |> select(university_key, university_code),
            by = "university_code") |>
  left_join(dim_school   |> select(school_key, university_code, school),
            by = c("university_code", "school")) |>
  left_join(dim_degree   |> select(degree_key, degree), by = "degree") |>
  left_join(dim_field    |> select(field_key, field), by = "field") |>
  left_join(dim_tier     |> select(tier_key, cohort_tier), by = "cohort_tier") |>
  select(
    year_key, university_key, school_key, degree_key, field_key, tier_key,
    # The faculty label as that year's survey published it, kept for tooltips
    # because it varies by year and therefore belongs with the measures.
    school_reported,
    all_of(MEASURE_COLS),
    pay_spread_sgd, pay_spread_ratio,
    variable_pay_sgd, variable_pay_pct,
    non_ft_perm_employment_pp,
    pay_vs_cohort_sgd, pay_index, employment_vs_cohort_pp,
    # Flags taken from MOE's footnote markers in cleaning step 3. They go in
    # the fact table rather than a dimension because they vary record by
    # record, and they need to reach the dashboard: a follow-up record covers a
    # different cohort at a different career stage, so its pay cannot be
    # compared with a fresh-graduate record's.
    footnote_markers, flag_small_sample, flag_followup_survey, cohort_basis,
    flag_gross_below_basic
  )

check_that(rowSums(is.na(fact_employment |>
                           select(ends_with("_key")))) == 0,
           "Every fact row resolves to a row in all six dimensions")
check_that(nrow(fact_employment) == nrow(employment),
           "The joins to the dimensions neither dropped nor duplicated rows")

# ---- Aggregates for reference lines and trend pages -------------------------
# Aggregating here keeps the Power BI measures simple and means the report and
# the dashboard quote the same numbers.
#
# Important caveat, repeated in the data dictionary and the report: the survey
# publishes no cohort sizes, so a programme with 15 graduates counts the same
# as one with 400. Everything below is an unweighted median across programmes,
# not a median across graduates, and is labelled that way wherever it appears.

#' Summarise a set of programmes on the measures the dashboard reports
summarise_outcomes <- function(data) {
  data |>
    summarise(
      n_programmes        = n(),
      median_gross        = median(gross_monthly_median, na.rm = TRUE),
      median_basic        = median(basic_monthly_median, na.rm = TRUE),
      median_p25          = median(gross_mthly_25_percentile, na.rm = TRUE),
      median_p75          = median(gross_mthly_75_percentile, na.rm = TRUE),
      mean_employment     = mean(employment_rate_overall, na.rm = TRUE),
      mean_ft_perm        = mean(employment_rate_ft_perm, na.rm = TRUE),
      mean_non_ft_perm_pp    = mean(non_ft_perm_employment_pp, na.rm = TRUE),
      median_pay_spread   = median(pay_spread_sgd, na.rm = TRUE),
      # Each aggregate reports how much of it is not fresh-graduate data and
      # how much rests on fewer than 30 respondents, so the caveat sits in the
      # same table as the figure. For Law these show the median is entirely
      # follow-up-survey data.
      n_followup_records  = sum(flag_followup_survey),
      n_small_sample      = sum(flag_small_sample),
      .groups = "drop"
    )
}

#' Add year-on-year change to the pay measure
#'
#' Done in R rather than left to a DAX measure, so the growth figures quoted in
#' the report come from this pipeline and cannot drift from the dashboard's.
add_yoy <- function(data, group_cols = character()) {
  data |>
    group_by(across(all_of(group_cols))) |>
    arrange(year, .by_group = TRUE) |>
    mutate(
      gross_yoy_sgd = median_gross - lag(median_gross),
      gross_yoy_pct = 100 * (median_gross - lag(median_gross)) / lag(median_gross),
      gross_vs_2013_pct = 100 * (median_gross - first(median_gross)) /
        first(median_gross)
    ) |>
    ungroup()
}

all_graduates <- employment |> filter(cohort_tier == "All graduates")

agg_year <- all_graduates |> group_by(year) |> summarise_outcomes() |> add_yoy()

agg_university_year <- all_graduates |>
  group_by(year, university_code) |> summarise_outcomes() |>
  add_yoy("university_code")

agg_field_year <- all_graduates |>
  group_by(year, field) |> summarise_outcomes() |> add_yoy("field")

agg_subject <- all_graduates |>
  group_by(subject, field) |> summarise_outcomes() |>
  # A subject seen in only one or two years cannot support a trend claim, so
  # n_programmes goes out alongside and gates the "top subject" visuals.
  arrange(desc(median_gross))

agg_award_route_year <- all_graduates |>
  filter(university_code == "SIT") |>
  group_by(year, award_route) |> summarise_outcomes() |> add_yoy("award_route")

# ---- The honours premium ----------------------------------------------------
# SMU is the only university publishing the same programme twice, once for the
# whole cohort and once for the Cum Laude and above subset. Pairing them on
# programme and year gives an estimate of what graduating with higher honours
# is worth. No other university's data allows this, and it is the basis of the
# dashboard's comparison page.
honours_premium <- employment |>
  filter(university_code == "SMU") |>
  select(year, subject, field, cohort_tier,
         gross_monthly_median, employment_rate_overall, employment_rate_ft_perm) |>
  pivot_wider(names_from = cohort_tier,
              values_from = c(gross_monthly_median, employment_rate_overall,
                              employment_rate_ft_perm),
              names_sep = " | ") |>
  rename(
    gross_all    = `gross_monthly_median | All graduates`,
    gross_honours = `gross_monthly_median | Cum Laude and above`,
    employment_all = `employment_rate_overall | All graduates`,
    employment_honours = `employment_rate_overall | Cum Laude and above`,
    ft_perm_all = `employment_rate_ft_perm | All graduates`,
    ft_perm_honours = `employment_rate_ft_perm | Cum Laude and above`
  ) |>
  mutate(
    premium_sgd = gross_honours - gross_all,
    premium_pct = 100 * (gross_honours - gross_all) / gross_all,
    employment_premium_pp = employment_honours - employment_all,
    ft_perm_premium_pp = ft_perm_honours - ft_perm_all
  ) |>
  filter(!is.na(premium_sgd)) |>
  arrange(year, subject)

message("Transformed: ", nrow(fact_employment), " fact rows; dimensions ",
        paste(c(nrow(dim_year), nrow(dim_university), nrow(dim_school),
                nrow(dim_degree), nrow(dim_field), nrow(dim_tier)),
              collapse = "/"), " (year/university/school/degree/field/tier).")
