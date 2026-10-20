# Limitations and assumptions

Notes for the report's Data section and its Key findings and limitations section. All
figures here come from the pipeline rather than being worked out by hand.

---

## 1. Every headline number is the median programme, not the median graduate

This is the most important limitation in the project and belongs in Key findings rather
than buried in a footnote.

The survey publishes no cohort sizes, so there is no way to weight a programme by how
many graduates it had. Every aggregate in the dashboard is an unweighted median across
programmes. The 2024 data shows how uneven that is:

| Field | Programmes in 2024 |
|---|---|
| Engineering | 37 |
| Computing & IT | 22 |
| Business & Management | 20 |
| Arts, Humanities & Social Sciences | 19 |
| ... | ... |
| Economics | 2 |
| Law | 2 |
| Medicine & Dentistry | 2 |

One Law programme counts as much as one Engineering programme, even though Engineering
has 37 programmes to Law's 2 and an unknown but much larger number of graduates. So the
S$4,350 figure for 2024 is the pay of the typical programme, not the typical graduate.

Which way it biases: small specialist fields are over-represented relative to their
share of graduates. Law and Medicine are both small and well paid, so the headline
median probably sits above a true graduate-weighted median.

Nothing in this data can fix it. The response is to label it wherever it appears, which
the data dictionary, the dashboard notes and this document all do, and to avoid any
claim about "the average Singapore graduate".

---

## 2. Coverage is incomplete and the gaps are not random

| University | Years present | Missing |
|---|---|---|
| NTU | 2013-2024 (12) | none |
| NUS | 2013-2024 (12) | none |
| SMU | 2013-2024 (12) | none |
| SIT | 2014-2024 (11) | 2013 |
| SUTD | 2015-2024 (9) | 2013, 2014, 2023 |
| SUSS | 2018-2024 (7) | 2013-2017 |

Checked against `data/raw/`: these rows are missing from the source, not dropped in
cleaning. SIT, SUTD and SUSS are younger institutions and joined the survey later.

That matters more than it looks. 2013 is a three-university figure (NTU, NUS, SMU) and
2014 a four-university one, so growth measured from 2013 partly reflects universities
being added to the survey rather than outcomes changing. The "+40% since 2013" headline
should be read with that in mind, and the per-university trend lines are better evidence
for it.

The 2023 SUTD gap has two consequences. A user who slices to 2023 sees SUTD disappear
from every visual, which is part of why the `[Thin Evidence Warning]` measure and the
`[Selected Scope]` caption exist. More importantly, MOE reported SUTD's 2023 results
together with its 2024 results, because a change in academic calendar left a very small
and atypical 2023 cohort. SUTD's 2024 point therefore includes 2023 graduates and is not
comparable with the other universities' 2024 points. `data-provenance.md` has the source
wording.

---

## 3. Programmes with few graduates are missing by design

105 records (6.8% of the raw file) have no figure for any of the eight measures, because
MOE suppresses results for programmes with too few graduates to publish. They cover 5
universities and 11 years. They are excluded since they add nothing to any visual, and
the full list is in `data/clean/excluded_suppressed_records.csv`.

The exclusion is not neutral. Small programmes are absent by design, so the data
describes established programmes better than new or niche ones, and a new degree's first
cohorts are the most likely to be suppressed.

---

## 4. The field grouping is ours, not MOE's

The survey publishes no field grouping. The 13 fields come from keyword rules in
`R/00_setup.R`, tested in a fixed order.

The rule: a degree goes to the discipline whose method it teaches, not the industry that
method is applied in.

| Degree | Field | Method / industry |
|---|---|---|
| Business Analytics | Computing & IT | analytics / business |
| Computational Biology | Computing & IT | computation / biology |
| Pharmaceutical Engineering | Engineering | engineering / pharmaceuticals |
| Pharmaceutical Science | Health Sciences | science / pharmaceuticals |
| Computer Engineering | Computing & IT | computing / hardware |
| Maritime Studies | Business & Management | management / shipping |

The two pharmaceutical rows show the rule is doing real work: the same industry splits
across two fields according to the discipline of the award. Any individual call is
arguable. The defence is that one stated rule decides all of them the same way, and that
the full mapping is in `data/clean/degree_field_mapping.csv` so all 239 rows can be
checked.

Double degrees take the field of the discipline named first, so "Aerospace Engineering
and Economics" is Engineering.

---

## 5. Subjects are merged across universities on purpose

The `subject` column removes award wording so the same subject can be compared between
institutions. That means some deliberate merges:

- NUS "Bachelor of Laws (LLB)", NTU "Law" and SMU "Law (4-year)" all become Law
- NTU "Business (3-year direct Honours)" and "Business" both become Business
- "Arts (and Education)" and "Arts (with Education)" both become Arts with Education

Programme structure (3-year or 4-year, honours or not) is dropped from the subject
label because it is not a subject. It is still in the `degree` column and the
`is_honours` flag, so nothing is lost, but a reader working at subject level is
comparing subjects and not programme structures.

---

## 6. Four fields are not fresh-graduate data

This is the most serious problem for interpretation, and it is invisible unless you read
MOE's footnote legend, which is on the dataset page and not in the CSV.

MOE marks some programmes `#`, which means the figures come from a follow-up survey of
the previous year's graduates, taken after they finished their practical training. For
Architecture it is graduates from three years earlier. Those records describe qualified
professionals, not fresh graduates.

| Field | Records | From a follow-up survey |
|---|---|---|
| Law | 24 | 24 (100%) |
| Medicine & Dentistry | 35 | 22 (63%) |
| Architecture & Built Environment | 40 | 8 (20%) |
| Health Sciences | 90 | 10 (11%) |
| All other nine fields | | 0 |

Law's figures are entirely follow-up data. Its S$7,000 median is a real number for
qualified lawyers after pupillage, but it is not a graduate starting salary, so putting
it next to Design & Media's S$3,600 of genuine fresh-graduate data compares two career
stages.

The flag is not a bias in one direction, and reading it that way would be wrong. Inside
Medicine & Dentistry the follow-up records sit at both the top and the bottom:

| Programme inside Medicine & Dentistry | Basis | Records | Median |
|---|---|---|---|
| Medicine / MBBS (NUS, NTU) | follow-up | 11 | S$5,237 (S$4,500-5,700) |
| Dental Surgery (NUS) | fresh | 12 | S$4,125 (S$4,000-4,550) |
| Biomedical Sciences & Chinese Medicine (NTU) | follow-up | 11 | S$3,000 (S$2,500-3,350) |

So `flag_followup_survey` says which programmes are reported that way. It is a warning
about comparability, not a correction factor.

That table shows a second problem: Medicine & Dentistry is not a coherent field. It
holds three programmes whose medians differ by S$2,237, so the field-level figure
describes nothing real, and in 2024 the field has only 2 programmes. The same applies to
Law (2), Economics (2) and Interdisciplinary (1). Those fields are too thin to compare
at field level, which is what `[Thin Evidence Warning]` and `n_programmes` are for.
Read them at subject level or not at all.

What this breaks and what it does not:

- It breaks field-level pay comparison, which the dashboard's page 3 scatter was built
  on. That chart now separates the two bases instead of mixing them.
- It does not break the headline trend. Recomputing the national median on
  fresh-graduate records only moves it by at most S$99 in any year (2013: S$3,100 to
  S$3,065; 2024 unchanged). The "pay rose about 40% since 2013" finding holds either way.

Every record carries `flag_followup_survey` and a readable `cohort_basis`, and every
aggregate table carries `n_followup_records`, so a figure cannot be quoted without the
caveat sitting in the same table.

A second flag comes from the same legend. `^` marks figures based on fewer than 30
respondents, which is 120 records, 8.3% of the cleaned data. Those figures are published
but thin, and should not carry a trend claim on their own. They are kept as
`flag_small_sample`, with `n_small_sample` on every aggregate.

---

## 7. Two data-quality issues kept rather than corrected

Gross pay below basic pay. One record has a gross median 0.50% below its basic median.
This comes from the source: MOE works the gross and basic figures out from the
respondents who answered each question, and those groups are not the same. The record is
kept and flagged in `fact_employment[flag_gross_below_basic]` instead of corrected,
since making up a value would be worse than carrying a known 0.5% inconsistency.

A school name in the degree column. One 2024 SUSS record was published with "School of
Public Safety and Security" where the programme name belongs. It is corrected to
"Bachelor of Public Safety and Security", the name SUSS used for the same school in
2023, which lets the two years form one trend. This is the only place the pipeline
changes what a record is, and the mapping is listed in `R/00_setup.R`.

---

## 8. What the survey measures and what it does not

- Graduates are surveyed about six months after their final examinations: November of
  the graduation year for NTU, NUS, SMU and SUSS, March of the following year for SIT,
  and February of the following year for SUTD up to 2024. Every figure describes early
  outcomes and says nothing about careers after that. A field with weak six-month pay
  may overtake others within five years and this data cannot show it.
- A survey year is not a simultaneous snapshot. A 2024 row means November 2024 for NTU
  but March 2025 for SIT, four months apart in a different labour market. The offset
  cannot be corrected for, because the published figures are already aggregated, so any
  cross-university comparison within one year carries it.
- Salaries are self-reported and in nominal dollars with no inflation adjustment. This
  is why `pay_index` exists: it compares each programme with the median of its own year,
  which takes wage growth and inflation out of any year-on-year comparison. Raw dollar
  figures across years should be read with that in mind.
- Response rates are not published per programme, so a programme's figures may rest on a
  small or unrepresentative share of its cohort and there is no way to tell which.
- The employment rate counts employment of any kind, which is the reason for the
  `insecure_work_pp` measure: the headline rate treats a permanent job and a temporary
  placement the same way.

---

## 9. The honours premium covers one university

SMU is the only institution publishing a Cum Laude and above subset alongside its full
cohort, so the premium on page 4 is an SMU finding and not a sector one. It should not
be generalised to NTU, NUS, SIT, SUSS or SUTD, whose grading and employer markets may
differ.

The two tiers are a cohort and part of that same cohort. They must never be summed or
averaged together, since that double-counts SMU graduates and raises every SMU figure.
The pipeline separates them into `cohort_tier` and the dashboard keeps them apart with a
page-level filter.

---

## 10. Validation, and what it caught

The pipeline runs 29 checks (21 in cleaning, 8 in transformation) and stops on any
failure. They fall into three kinds, and the difference is worth a sentence in the Data
section because each describes a different way of being wrong.

Structural checks cover ranges, ordering, key uniqueness and join integrity. These found
two real problems: a record where gross pay fell below basic pay, and a duplicate key
created when a faculty rename was applied before a missing degree name was recovered.

Plausibility checks were added after a bug the structural checks could not catch. The
label shortener was producing subjects called "with Education" and "3-year direct
Honours". Both are non-empty strings on valid records, so every structural check passed.
Nothing was structurally wrong; the values were just wrong, and they would have appeared
on the dashboard as if they were subjects. Five checks now test that each subject label
looks like the name of a subject.

Provenance checks were added after the footnote markers were found to be meaningful. The
pipeline had been deleting them on the assumption that they carried no information once
the table was separated from its notes, but the notes were published on the dataset page
the whole time. The markers held a sample-size warning on 120 records and a cohort-timing
warning on 76, and one of the dashboard's main comparisons was built on the result. The
pipeline now checks that every footnote symbol in the file is one the legend defines, so
a new undocumented marker in a future release stops the run instead of passing through.
It also checks that all 105 suppressed records carry a marker explaining the absence,
which they do.

Three things worth stating from that:

1. Checking that a value exists is not the same as checking it makes sense.
2. Data you cannot interpret is not the same as data with no information in it. Find the
   documentation before discarding anything as noise.
3. Why the source looks a certain way cannot be worked out from the source itself. An
   earlier draft of the provenance notes guessed at a reason for SUTD's missing 2023
   rows and got it wrong; MOE's actual explanation was published and different.

`check_that()` also fails when a condition evaluates to NA rather than skipping it, and
prints how many values each check tested, so a check cannot report success without
having tested anything.
