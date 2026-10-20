# ==============================================================================
# 04_export.R  --  Write the Power BI inputs, the audit trail and the dictionary
# ==============================================================================
# Writes every table Power BI imports, plus the documentation needed to make
# sense of them without reading the code: row counts for each cleaning step, a
# dictionary of every column, and the degree-to-field mapping so the
# classification can be checked.
#
# Written as UTF-8 CSV, which Power BI imports directly and which stays
# readable and comparable between runs.
# ==============================================================================

message("\n== 04_export.R ==")

write_clean <- function(data, name) {
  path <- file.path(PATHS$clean, paste0(name, ".csv"))
  write_excel_csv(data, path, na = "")
  message(sprintf("  %-28s %5d rows  %3d cols", basename(path),
                  nrow(data), ncol(data)))
  invisible(path)
}

# ---- Analysis table ----------------------------------------------------------
# The whole cleaned table in one flat file. Power BI uses the star schema
# below; this file is the readable version and makes the cleaning checkable on
# its own.
write_clean(employment, "employment_clean")

# ---- Star schema for Power BI ------------------------------------------------
write_clean(fact_employment, "fact_employment")
write_clean(dim_year,        "dim_year")
write_clean(dim_university,  "dim_university")
write_clean(dim_school,      "dim_school")
write_clean(dim_degree,      "dim_degree")
write_clean(dim_field,       "dim_field")
write_clean(dim_tier,        "dim_tier")

# ---- Pre-aggregated tables ---------------------------------------------------
write_clean(agg_year,             "agg_year")
write_clean(agg_university_year,  "agg_university_year")
write_clean(agg_field_year,       "agg_field_year")
write_clean(agg_subject,          "agg_subject")
write_clean(agg_award_route_year, "agg_award_route_year")
write_clean(honours_premium,      "honours_premium")

# ---- Audit trail -------------------------------------------------------------
# Row counts after each cleaning step, so the figures quoted in the report come
# from the pipeline rather than being copied out by hand.
write_clean(clean_log, "cleaning_log")

# The removed records, kept so the exclusion can be inspected and shown to be
# the suppressed-result records it is claimed to be.
write_clean(
  suppressed |> select(year, university, school, degree),
  "excluded_suppressed_records"
)

# MOE's footnote legend, transcribed from the dataset page since it is not in
# the CSV. Exported for the report appendix and so the flags in the fact table
# can be traced back to their definitions.
write_clean(FOOTNOTE_LEGEND, "footnote_legend")

# Which records carry a warning, so the affected programmes can be found
# without opening the full table.
write_clean(
  employment |>
    filter(flag_followup_survey | flag_small_sample) |>
    count(university_code, field, subject, cohort_basis, flag_small_sample,
          name = "records") |>
    arrange(desc(records)),
  "flagged_records_summary"
)

# The full degree-to-field mapping, so the classification can be checked rather
# than taken on trust.
write_clean(
  employment |>
    distinct(university_code, degree, subject, field) |>
    arrange(field, subject, degree),
  "degree_field_mapping"
)

# ---- Data dictionary ---------------------------------------------------------
# Typed out rather than generated from the column names, since what a
# dictionary is for is the definition and the caveat, neither of which can be
# worked out from a name.
data_dictionary <- tribble(
  ~table, ~column, ~type, ~definition,

  "fact_employment", "year_key",        "key",     "Links to dim_year",
  "fact_employment", "university_key",  "key",     "Links to dim_university",
  "fact_employment", "school_key",      "key",     "Links to dim_school",
  "fact_employment", "degree_key",      "key",     "Links to dim_degree",
  "fact_employment", "field_key",       "key",     "Links to dim_field",
  "fact_employment", "tier_key",        "key",     "Links to dim_tier",
  "fact_employment", "school_reported", "text",    "Faculty label as published in that year's survey, before renames were reconciled; kept for tooltips",
  "fact_employment", "employment_rate_overall",   "per cent", "MOE definition: the percentage of graduates IN THE LABOUR FORCE who are employed, approximately six months after their final examinations. The labour force means those working, plus those not working but actively looking and available for work. Graduates not in the labour force, for example those in further study or national service, are outside the denominator entirely, so this is not the share of all graduates employed",
  "fact_employment", "employment_rate_ft_perm",   "per cent", "The percentage of graduates in the labour force in full-time permanent employment. Same denominator as employment_rate_overall",
  "fact_employment", "basic_monthly_mean",        "SGD/month", "Mean basic monthly salary, excluding overtime, allowances and bonuses. PERTAINS ONLY TO FULL-TIME PERMANENTLY EMPLOYED GRADUATES",
  "fact_employment", "basic_monthly_median",      "SGD/month", "Median basic monthly salary. Full-time permanently employed graduates only",
  "fact_employment", "gross_monthly_mean",        "SGD/month", "Mean gross monthly salary, including overtime, allowances and bonuses. Full-time permanently employed graduates only",
  "fact_employment", "gross_monthly_median",      "SGD/month", "Median gross monthly salary; the dashboard's headline pay measure. PERTAINS ONLY TO FULL-TIME PERMANENTLY EMPLOYED GRADUATES, so it describes a different and smaller population than the employment rates do. A programme with a large non_ft_perm_employment_pp has a pay figure covering a smaller share of its graduates",
  "fact_employment", "gross_mthly_25_percentile", "SGD/month", "25th percentile of gross monthly salary. Full-time permanently employed graduates only",
  "fact_employment", "gross_mthly_75_percentile", "SGD/month", "75th percentile of gross monthly salary. Full-time permanently employed graduates only",
  "fact_employment", "pay_spread_sgd",   "SGD/month", "DERIVED. 75th minus 25th percentile of gross pay: how widely pay varies between graduates of the same programme. Full-time permanently employed graduates only",
  "fact_employment", "pay_spread_ratio", "ratio",     "DERIVED. 75th percentile divided by 25th, so spread can be compared between high- and low-paying programmes. Full-time permanently employed graduates only",
  "fact_employment", "variable_pay_sgd", "SGD/month", "DERIVED. Gross median minus basic median: the part of pay that depends on overtime, allowances or bonuses. Full-time permanently employed graduates only",
  "fact_employment", "variable_pay_pct", "per cent",  "DERIVED. variable_pay_sgd as a percentage of basic median pay",
  "fact_employment", "non_ft_perm_employment_pp", "pct points","DERIVED. employment_rate_overall minus employment_rate_ft_perm: the share of the labour force employed but NOT in full-time permanent work, so in part-time, temporary, freelance or contract work. Named for what it measures rather than 'insecure', since part-time work is not always involuntary. These graduates have no salary recorded anywhere in the dataset, because the pay columns cover full-time permanent employees only",
  "fact_employment", "pay_vs_cohort_sgd","SGD/month", "DERIVED. Gross median minus the median of all fresh-graduate programmes in the same survey year",
  "fact_employment", "pay_index",        "index",     "DERIVED. Gross median as a percentage of the same year's median across fresh-graduate programmes. 100 = typical for that year. Removes wage growth and inflation from year-on-year comparison",
  "fact_employment", "employment_vs_cohort_pp", "pct points", "DERIVED. Overall employment rate minus the mean rate across all programmes that year",
  "fact_employment", "flag_gross_below_basic",  "logical", "DATA QUALITY. TRUE for the one record where the published gross median is 0.50 per cent below the basic median. The cause is not documented in the published source. The value is as published and is not produced by this pipeline; it is retained and flagged rather than corrected",
  "fact_employment", "footnote_markers",   "text",    "MOE's footnote symbols as published against the programme name, read before the name was cleaned. Defined in footnote_legend.csv",
  "fact_employment", "flag_small_sample",  "logical", "DATA QUALITY. TRUE where MOE marked the figures '^' -- based on fewer than 30 respondents. 119 records. The figure is published but thinly evidenced and should not carry a trend claim on its own. Note '^^' is a different marker, meaning the figures include Bioengineering graduates, and is excluded from this flag",
  "fact_employment", "flag_followup_survey", "logical", "COMPARABILITY. TRUE where MOE marked the figures '#', '##' or '###' -- they come from a follow-up survey of an EARLIER year's graduates, taken after practical training. Affects Law, Medicine, Pharmacy, Biomedical Sciences & Chinese Medicine, and Architecture (graduates three years earlier). These records are NOT fresh-graduate data and their pay must not be compared directly with unflagged records",
  "fact_employment", "cohort_basis",       "text",    "Readable form of flag_followup_survey: 'Fresh graduates' or 'Follow-up survey (post-training)'. Use it as a legend or caption so the distinction is visible on the chart rather than only in the model",

  "dim_year", "year",       "integer", "Survey year, i.e. the year of graduation",
  "dim_year", "year_date",  "date",    "1 January of the survey year, so Power BI can use a continuous date axis and time intelligence",
  "dim_year", "era",        "text",    "Pre-pandemic (2013-19), Pandemic cohorts (2020-21), Post-pandemic (2022-24)",
  "dim_year", "era_order",  "integer", "Sort order for era, so it reads chronologically rather than alphabetically",
  "dim_year", "cohort_median_gross", "SGD/month", "Median gross median pay across all FRESH-GRADUATE programmes that year; the benchmark behind pay_index. Excludes the SMU honours subset and the follow-up-survey records, so it means 'the median fresh-graduate programme that year'",
  "dim_year", "cohort_mean_employment", "per cent", "Mean overall employment rate across all programmes that year",
  "dim_year", "n_programmes", "count",  "Programmes with a published pay figure that year",

  "dim_university", "university",      "text", "Full registered name",
  "dim_university", "university_code", "text", "Short code (NTU, NUS, SIT, SMU, SUSS, SUTD) used on axes and in slicers",

  "dim_school", "school",       "text", "Faculty or awarding institution, reconciled across years",
  "dim_school", "school_label", "text", "University-qualified label, because two universities each have a School of Business",
  "dim_school", "award_route",  "text", "Own award, or Overseas partner award. Only SIT awards degrees conferred by partner institutions",

  "dim_degree", "degree",           "text",    "Full award title, cleaned of footnote markers and spelling variants",
  "dim_degree", "subject",          "text",    "The subject the award is in, stripped of award wording, so the same subject is comparable across universities",
  "dim_degree", "field",            "text",    "One of 13 broad fields of study, assigned by the documented rule order in 00_setup.R",
  "dim_degree", "is_honours",       "logical", "Award title denotes honours",
  "dim_degree", "is_double_degree", "logical", "Award title denotes a double degree or double major",

  "dim_field", "field",        "text",  "Broad field of study",
  "dim_field", "n_programmes", "count", "Programme-years in the field, used to order legends by size",

  "dim_tier", "cohort_tier", "text", "All graduates, or Cum Laude and above. SMU alone publishes the honours subset; it is a sub-population of the All graduates row, so the two must never be summed",
  "dim_tier", "tier_note",   "text", "Plain-language note shown in the dashboard to prevent the two tiers being added together",

  "agg_year",            "median_gross",      "SGD/month", "CAVEAT. Unweighted median across programmes, not across graduates: the survey publishes no cohort sizes, so a 15-graduate programme counts as much as a 400-graduate one",
  "agg_year",            "n_followup_records","count",     "How many records behind this figure are follow-up-survey data rather than fresh graduates. A figure whose n_followup_records approaches n_programmes is not a fresh-graduate figure at all",
  "agg_year",            "n_small_sample",    "count",     "How many records behind this figure rest on fewer than 30 respondents",
  "footnote_legend",     "marker",            "text",      "MOE's footnote symbol as it appears against a programme name",
  "footnote_legend",     "meaning",           "text",      "What the symbol means, transcribed from the dataset page on data.gov.sg, which is the only place the legend appears -- it is not in the CSV",
  "footnote_legend",     "handled_as",        "text",      "Where this pipeline carries the marker's meaning, or that it is documented only",
  "agg_year",            "gross_yoy_pct",     "per cent",  "Year-on-year change in median_gross",
  "agg_year",            "gross_vs_2013_pct", "per cent",  "Change in median_gross since 2013, the first survey year",
  "agg_year",            "mean_non_ft_perm_pp",  "pct points","Mean gap between the overall and full-time permanent employment rates, so the mean share of the labour force in work that is not full-time permanent",
  "agg_university_year", "university_code",   "text",      "Grouping column; all other columns as in agg_year",
  "agg_field_year",      "field",             "text",      "Grouping column; all other columns as in agg_year",
  "agg_subject",         "subject",           "text",      "Pooled across all years. n_programmes gives the number of programme-years behind each figure and should be used to discount thinly observed subjects",
  "agg_award_route_year","award_route",       "text",      "SIT only: its own awards against those conferred by overseas partners",

  "honours_premium", "gross_all",     "SGD/month", "Gross median pay, whole SMU cohort for that programme and year",
  "honours_premium", "gross_honours", "SGD/month", "Gross median pay, the Cum Laude and above subset of the same programme and year",
  "honours_premium", "premium_sgd",   "SGD/month", "DERIVED. gross_honours minus gross_all: what graduating with higher honours was worth in that programme and year",
  "honours_premium", "premium_pct",   "per cent",  "DERIVED. premium_sgd as a percentage of gross_all",
  "honours_premium", "employment_premium_pp", "pct points", "DERIVED. Difference in overall employment rate between the honours subset and the whole cohort",
  "honours_premium", "ft_perm_premium_pp",    "pct points", "DERIVED. Difference in full-time permanent employment rate between the honours subset and the whole cohort",

  "cleaning_log", "step",    "text",    "Pipeline step",
  "cleaning_log", "action",  "text",    "What the step did and why",
  "cleaning_log", "rows",    "count",   "Records remaining after the step",
  "cleaning_log", "removed", "count",   "Records removed by the step"
)

write_clean(data_dictionary, "data_dictionary")

# ---- Run summary -------------------------------------------------------------
message("\nAll outputs written to ", normalizePath(PATHS$clean))
