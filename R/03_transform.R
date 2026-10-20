# ==============================================================================
# 03_transform.R  --  Derived measures and the dimensional model
# ==============================================================================
# PURPOSE
#   The survey publishes eight raw figures per programme. On their own they
#   answer only "what was the number"; the dashboard needs to answer "is that
#   good, for whom, and is it getting better". This script derives the measures
#   that make those comparisons possible, then reshapes the single cleaned
#   table into a star schema.
#
#   WHY A STAR SCHEMA. Power BI cross-filters through relationships. A single
#   flat table can only filter itself, so slicers do not interact and the same
#   university name is stored 1,445 times. Splitting the data into one fact
#   table of measures surrounded by small descriptive dimension tables is what
#   makes a slicer on university filter a chart built on field of study, and
#   what keeps the model small enough to stay responsive.
#
#   ALL aggregation lives here, in R, not in Power Query.
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

    # PAY DISPERSION. Two programmes can share a median and offer completely
    # different risk: the gap between the 25th and 75th percentile says how
    # widely outcomes vary between graduates of the same programme, which a
    # median alone conceals.
    pay_spread_sgd   = gross_mthly_75_percentile - gross_mthly_25_percentile,
    pay_spread_ratio = gross_mthly_75_percentile / gross_mthly_25_percentile,

    # VARIABLE PAY. Gross pay includes overtime, allowances and bonuses, basic
    # pay does not. The gap between them shows how much of a starting salary is
    # guaranteed and how much depends on hours worked or performance.
    variable_pay_sgd = gross_monthly_median - basic_monthly_median,
    variable_pay_pct = 100 * (gross_monthly_median - basic_monthly_median) /
      basic_monthly_median,

    # JOB QUALITY. The headline employment rate counts any employment. The gap
    # between it and the full-time permanent rate is the share of employed
    # graduates in part-time, temporary or freelance work -- a measure of job
    # security that the headline rate hides.
    insecure_work_pp = employment_rate_overall - employment_rate_ft_perm
  )

# ---- Year benchmarks ---------------------------------------------------------
# Salaries are reported in nominal dollars, so a 2024 figure is not comparable
# with a 2013 one. Expressing each programme relative to the median of its own
# graduating year removes general wage growth and inflation from the comparison,
# so a rising index means a programme is pulling ahead of its peers rather than
# simply that time has passed.
#
# The benchmark is computed from the "All graduates" tier only. Including the
# SMU honours subset would count those graduates twice and bias the benchmark
# upwards.
year_benchmark <- employment |>
  filter(cohort_tier == "All graduates", !is.na(gross_monthly_median)) |>
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
check_that(!is.na(employment$subject) & employment$subject != "",
           "Every record has a subject label")

# ---- Dimension tables --------------------------------------------------------
# Dimensions hold the descriptive attributes a user slices by. Each is small,
# has one row per thing, and carries a surrogate integer key that the fact
# table references. Rows are ordered so Power BI's default sort is meaningful.

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
    insecure_work_pp,
    pay_vs_cohort_sgd, pay_index, employment_vs_cohort_pp,
    flag_gross_below_basic
  )

check_that(rowSums(is.na(fact_employment |>
                           select(ends_with("_key")))) == 0,
           "Every fact row resolves to a row in all six dimensions")
check_that(nrow(fact_employment) == nrow(employment),
           "The joins to the dimensions neither dropped nor duplicated rows")

# ---- Aggregates for reference lines and trend pages -------------------------
# Pre-aggregating in R keeps the Power BI measures simple and guarantees the
# report and the dashboard quote identical numbers.
#
# IMPORTANT CAVEAT, carried into the data dictionary and the report: the survey
# publishes no cohort sizes, so a programme with 15 graduates and one with 400
# carry equal weight in every aggregate below. These are therefore unweighted
# medians across programmes, not population medians across graduates, and are
# labelled as such wherever they appear.

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
      mean_insecure_pp    = mean(insecure_work_pp, na.rm = TRUE),
      median_pay_spread   = median(pay_spread_sgd, na.rm = TRUE),
      .groups = "drop"
    )
}

#' Add a year-on-year change on the headline pay measure
#'
#' Computed in R rather than left to a DAX measure, so that the growth figures
#' quoted in the written report are produced by this pipeline and cannot drift
#' from the ones shown on the dashboard.
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
  # Subjects observed in only a year or two cannot support a trend claim, so the
  # count is published alongside and used to gate the dashboard's "top subject"
  # visuals.
  arrange(desc(median_gross))

agg_award_route_year <- all_graduates |>
  filter(university_code == "SIT") |>
  group_by(year, award_route) |> summarise_outcomes() |> add_yoy("award_route")

# ---- The honours premium ----------------------------------------------------
# SMU is the only university that publishes the same programme twice, once for
# the whole cohort and once for the subset graduating Cum Laude or above. Paired
# on programme and year, the two give a direct estimate of what graduating with
# higher honours is worth -- a question the dataset answers for nobody else, and
# the basis of the dashboard's comparison page.
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
