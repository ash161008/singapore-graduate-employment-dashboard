# Data provenance

Notes for the report's Data section, which asks for the dataset's origin, custodian,
variables and content, and for the source to be cited.

---

## Origin and custodian

| | |
|---|---|
| Dataset | Graduate Employment Survey - NTU, NUS, SIT, SMU, SUSS & SUTD |
| Who runs the survey | The six Singapore autonomous universities, jointly |
| Custodian and publishing agency | Ministry of Education (MOE), Singapore, which compiles and releases the joint results |
| Distribution platform | [data.gov.sg](https://data.gov.sg), the Singapore Government's open data portal |
| Dataset identifier | `d_3c55210de27fcccda2ed0c63fdd2b352` (collection 415) |
| Dataset URL | https://data.gov.sg/datasets/d_3c55210de27fcccda2ed0c63fdd2b352/view |
| Accessed | 18 September 2026 |
| Licence | [Singapore Open Data Licence v1.0](https://data.gov.sg/open-data-licence) |
| File as collected | `data/raw/GraduateEmploymentSurveyNTUNUSSITSMUSUSSSUTD.csv` |

MOE publishes it so prospective students and their families can compare employment
outcomes across institutions and courses before choosing. That is the same audience this
dashboard is built for, which is worth saying in the introduction when stating that the
dashboard's objectives match its audience.

### Attribution required by the licence

The Singapore Open Data Licence requires a visible acknowledgement of the source and a
link to the licence, so this is a condition of use rather than a courtesy. Put it in the
report and on the dashboard's Overview page:

> Contains information from the Graduate Employment Survey - NTU, NUS, SIT, SMU, SUSS &
> SUTD, accessed on 18 September 2026 from
> https://data.gov.sg/datasets/d_3c55210de27fcccda2ed0c63fdd2b352/view, which is made
> available under the terms of the Singapore Open Data Licence version 1.0
> (https://data.gov.sg/open-data-licence).

The licence also provides the data as-is, with no warranty of accuracy, completeness or
fitness for purpose. That is part of the reason the pipeline checks the data rather than
assuming it is correct.

---

## Dataset size against the brief

The task asks for at least 200 rows and 6 columns. The file as collected has 1,550 rows
and 12 columns, covering 12 survey years (2013-2024) and 6 universities. Worth stating
these figures in the report, since they are a listed requirement.

---

## Content and coverage

One row per university, faculty, degree programme and survey year.

- 1,550 rows as collected, 1,445 after cleaning. The 105 removed records had no
  published figures at all (see `known-limitations.md` section 4).
- 6 universities, 43 faculties or awarding institutions, 234 degree programmes, 149
  subjects, 13 fields of study.
- Coverage is uneven. NTU, NUS and SMU appear in all 12 years; SIT, SUTD and SUSS joined
  later (`known-limitations.md` section 3).

### Variables as published

| Column | Type | Content |
|---|---|---|
| `year` | integer | Survey year, which is the year of graduation |
| `university` | text | Full name of the awarding university |
| `school` | text | Faculty, school or overseas awarding partner |
| `degree` | text | Full award title |
| `employment_rate_overall` | per cent | Percentage of graduates in the labour force who are employed, about six months after final examinations |
| `employment_rate_ft_perm` | per cent | Percentage of graduates in the labour force in full-time permanent employment |
| `basic_monthly_mean` | SGD/month | Mean basic salary, excluding overtime, allowances and bonuses |
| `basic_monthly_median` | SGD/month | Median basic salary |
| `gross_monthly_mean` | SGD/month | Mean gross salary, including overtime, allowances and bonuses |
| `gross_monthly_median` | SGD/month | Median gross salary |
| `gross_mthly_25_percentile` | SGD/month | 25th percentile of gross salary |
| `gross_mthly_75_percentile` | SGD/month | 75th percentile of gross salary |

Two definitions here need stating carefully in the report, because getting them loosely
wrong changes what the figures mean.

**The employment rates are percentages of the labour force, not of all graduates.** The
labour force means graduates who are working, plus those not working but actively looking
and available for work. Graduates not in the labour force at all, for example those in
further study or national service, are outside the denominator. So a 90% employment rate
is not "90% of graduates have jobs".

**The salary figures cover full-time permanently employed graduates only.** This is the
important one. The six pay columns describe a smaller population than the employment
rates do, which means a programme with a large gap between its overall and full-time
permanent rates has a pay figure that describes a smaller share of its graduates.
Graduates in part-time, temporary or freelance work have no salary recorded anywhere in
the dataset. See `known-limitations.md` section 2.

All eight measures import as text, because missing values are written as the words "na"
and "N.A.". Every column, including the measures the pipeline derives, is defined in
`data/clean/data_dictionary.csv`.

---

## How and when graduates are surveyed

Everything in this section comes from the dataset page rather than being inferred from
the data, because why the source looks a certain way is not something the data itself
can say.

### Survey months differ by institution

| University | Surveyed |
|---|---|
| NTU, NUS, SMU, SUSS | November of the graduation year |
| SIT | March of the following year |
| SUTD | February of the following year up to 2024, then November of the graduation year from 2024 |

So the `year` column is not a simultaneous snapshot. A 2024 row means November 2024 for
NTU but March 2025 for SIT, four months apart in a different labour market. Any
cross-university comparison within one survey year carries that offset, and it cannot be
corrected for because the published figures are already aggregated.

### Why SUTD has no 2023 rows

MOE states that SUTD's GES 2023 results were reported in the following year alongside its
GES 2024 results, because of a "very small and atypical graduating cohort in 2023" caused
by a change in academic calendar.

Two things follow:

1. The 2023 absence is a reporting decision by MOE, not a cleaning artefact.
2. SUTD's 2024 figures therefore include 2023 graduates, so a SUTD point is not
   comparable with the other universities' 2024 points and needs a footnote or tooltip.

One inference to avoid: SUTD's five rows in 2024, against four in every other year, are
not evidence of the merged cohort. The fifth row is Bachelor of Science (Design and
Artificial Intelligence), appearing for the first time in 2024 with no data published.
SUTD's row counts follow programme changes instead: ISTD ran 2015-2020, CSD replaced it
from 2021, and DAI arrived in 2024. After cleaning, SUTD 2024 has three usable records.

### Start years are staggered

NTU, NUS and SMU from 2013, SIT from 2014, SUTD from 2015, SUSS from 2018. This matches
the data. It means the 2013 and 2014 "all universities" figures are really three- and
four-university figures, so growth measured from 2013 partly reflects institutions being
added rather than outcomes changing. Covered in `known-limitations.md` section 3.

---

## MOE's footnote legend

The CSV has footnote symbols against programme names but not the legend that defines
them, which is only on the dataset page. It is transcribed into `FOOTNOTE_LEGEND` in
`R/00_setup.R` and exported to `data/clean/footnote_legend.csv`.

| Marker | Meaning | How the pipeline handles it |
|---|---|---|
| `*` | SMU courses are direct four-year programmes whose graduates may be awarded Cum Laude and above, and SMU publishes the whole cohort and that subset | Separated into `cohort_tier` |
| `^` | Figures are based on fewer than 30 respondents | `flag_small_sample`, 119 records |
| `^^` | Includes Bioengineering graduates; that course merged into Biomedical Engineering in 2014 | Documented only, 1 record |
| `**` | No figures published, because of small graduate numbers or a low response rate | Explains the 105 excluded records |
| `#` | Figures come from a follow-up survey of the previous year's graduates, after practical training (Law, Medicine, Pharmacy, Biomedical Sciences & Chinese Medicine); for Architecture, graduates three years earlier | `flag_followup_survey`, 76 records |
| `##` | NTU Medicine, from a follow-up survey after housemanship or first-year residency | `flag_followup_survey` |
| `###` | SUTD Architecture and Sustainable Design, from a follow-up survey after practical training | `flag_followup_survey` |

Without the legend these look like formatting. Removing them would lose a sample-size
warning on 119 records and a cohort-timing warning on 76, so they are read in cleaning
step 3, before any name cleaning touches them.

Having them available made one useful check possible: all 105 suppressed records carry a
marker explaining the absence. MOE documents every omission it makes, and the pipeline
now tests that rather than assuming it.

### Which fields the follow-up basis affects

| Field | Records | From a follow-up survey |
|---|---|---|
| Law | 24 | 24 (100%) |
| Medicine & Dentistry | 35 | 22 (63%) |
| Architecture & Built Environment | 40 | 8 (20%) |
| Health Sciences | 90 | 10 (11%) |
| All other nine fields | | 0 |

Law's figures are entirely follow-up data: qualified lawyers surveyed after pupillage,
not fresh graduates. Its S$7,000 median is a real number but not a fresh-graduate
salary, so it should not be put next to Design & Media's S$3,600 without saying so.

The flag says which programmes are reported that way and is not a bias in one direction.
Inside Medicine & Dentistry the follow-up records sit at both ends of the field: MBBS at
a S$5,237 median against Biomedical Sciences & Chinese Medicine at S$3,000, with
fresh-graduate Dental Surgery at S$4,125 in between. So it should be treated as a warning
that two records are not measuring the same thing, never as a correction factor. It also
shows the Medicine & Dentistry field figure is not interpretable, since it averages three
programmes S$2,237 apart.

The headline year-on-year figures are not affected. Recomputing the national median on
fresh-graduate records only moves it by at most S$99 in any year (2013: S$3,100 to
S$3,065; 2024 unchanged at S$4,350), so the "pay rose about 40% since 2013" finding
holds either way. The problem was limited to field-level comparison.

---

## Ethical risk

The task asks for a theme of minimal risk, and this dataset qualifies. Worth a sentence
in the introduction:

- There is no personal data. Every figure is an aggregate over a degree programme's
  graduating cohort, and programmes with too few graduates to report anonymously are
  suppressed by MOE before publication.
- It is official government open data, published for public comparison under a licence
  that allows modification and redistribution.
- No individual, and no group smaller than a degree cohort, can be identified from it.

The obligation that does apply is about interpretation rather than law. These figures
inform real course choices, so the actual risk is overstating what an unweighted median
across programmes can support. That is why the limitations appear on the dashboard
itself and not only in the report.
