# Power BI build specification
**MA1580 Assessment 2 — Graduate Employment Dashboard**

Build this in Power BI Desktop against the CSVs in `data/clean/`. Follow it in order;
every visual lists its exact field wells. Nothing here requires a Power Query step —
load the CSVs as they are.

---

## 0. The story the dashboard tells

The marking scheme caps a "generic or linear" structure at Satisfactory. So the
dashboard is not organised as *overview → breakdowns → detail*; it is organised as an
**argument in four moves**, each page overturning the impression left by the one before.

| Page | Claim the page makes | The number that makes it |
|---|---|---|
| 1. A decade of rising pay | Graduate pay has risen steadily and substantially | Median gross **S$3,100 → S$4,350**, +40.3% since 2013 |
| 2. The headline rate lies | Employment "peaked" in the pandemic — because the jobs got worse | 2020: **94.0%** employed, but only **70.3%** in full-time permanent work (23.7pp gap) |
| 3. Not everyone carries the risk | The insecurity is concentrated in specific fields | Design & Media: **21.4pp** gap, 80.8% employed, S$3,600 median · Law: **1.8pp**, 96.5%, S$7,000 |
| 4. So what can you actually control? | Less than you'd think, and less than you used to | Within-programme spread up to **p75/p25 = 1.40**; honours premium fell **17.5% (2014) → 5.9% (2024)** |

Page 5 is the interactive explorer, which lets the reader test all four claims against
any programme they are considering.

**Intended audience** (state this in the report's introduction): prospective
undergraduates in Singapore and the families advising them, plus JC and polytechnic
career counsellors. The dashboard's objectives are (i) to show what outcomes actually
look like across all six autonomous universities over 2013–2024, (ii) to separate pay
from job security, which the published employment rate conflates, and (iii) to let a
user find and compare the specific programmes they are choosing between.

---

## 0a. If you are building this inside a Windows VM on Apple Silicon

Power BI Desktop runs on Windows on ARM as the x64 build under emulation. It is
officially supported (Microsoft's minimum requirements require the 2025-09 cumulative
update, KB5065789, or later), but emulated builds have historically thrown
**"Error fetching data for this visual"** on visuals using a *continuous date axis*.

If that happens, you do not need to redesign anything. Every date-axis visual in this
spec has an integer fallback already in the model:

- Swap `dim_year[year_date]` for `dim_year[year]` on the X axis
- Set the axis type to **Categorical** instead of Continuous

You lose the proportionally-spaced time axis, which costs nothing here because the
series has no gaps — all twelve years are present and evenly spaced, so a categorical
axis renders identically. No measure in §4 depends on `year_date`.

---

## 1. Load the data

`Home → Get data → Text/CSV`, then **Load** (never *Transform Data* — opening Power
Query would breach the assessment's R-only constraint). Import these nine files.

The CSVs are UTF-8 with a byte-order mark, which keeps the German partner-institution
names correct in Excel. Power BI normally detects this; if the first column of a table
imports with a stray character in its name, set the file encoding to **65001: Unicode
(UTF-8)** in the import dialog's dropdown.


| File | Role |
|---|---|
| `fact_employment.csv` | Fact table — 1,445 rows, keys + measures |
| `dim_year.csv` | 12 rows |
| `dim_university.csv` | 6 rows |
| `dim_school.csv` | 44 rows |
| `dim_degree.csv` | 235 rows |
| `dim_field.csv` | 13 rows |
| `dim_tier.csv` | 2 rows |
| `agg_subject.csv` | Pooled subject ranking for page 4 |
| `honours_premium.csv` | Paired SMU comparison for page 4 |

Do **not** import `employment_clean.csv` — it is the flat human-readable copy of the
same data and would double the model. `cleaning_log.csv`, `data_dictionary.csv`,
`degree_field_mapping.csv` and `excluded_suppressed_records.csv` are documentation for
the report appendix, not model tables.

### Why a star schema at all

Power BI cross-filters *through relationships*. A single flat table can only filter
itself: a university slicer and a field-of-study chart built on the same flat table
cannot interact the way the assessment requires. Splitting the data into one fact table
of measures surrounded by small descriptive dimension tables is precisely what makes a
slicer on one attribute filter a chart built on another — and it stores each university
name 6 times instead of 1,445. This is the single most important sentence to put in the
report's Dashboard section about model design.

---

## 2. Build the model

`Model view`. Create six relationships, all **one-to-many, single cross-filter
direction**, dimension → fact:

| From (one side) | To (many side) |
|---|---|
| `dim_year[year_key]` | `fact_employment[year_key]` |
| `dim_university[university_key]` | `fact_employment[university_key]` |
| `dim_school[school_key]` | `fact_employment[school_key]` |
| `dim_degree[degree_key]` | `fact_employment[degree_key]` |
| `dim_field[field_key]` | `fact_employment[field_key]` |
| `dim_tier[tier_key]` | `fact_employment[tier_key]` |

`agg_subject` and `honours_premium` stay **unrelated** — they are pre-aggregated at a
different grain, and relating them would create ambiguous filter paths. They feed only
their own visuals.

Then:

1. **Confirm `dim_year[year_date]` imported as type Date** (`Column tools → Data type`).
   A date-typed column is all a continuous time axis needs. Do **not** use
   `Mark as date table` — that requires a contiguous daily date column, and this table
   has one row per year, so it will be rejected. None of the measures below depend on
   it; `Pay YoY %` is written to work on annual grain without time intelligence.
2. **Sort columns by their order columns**, so categories read meaningfully rather than
   alphabetically. Select the column, then `Column tools → Sort by column`:
   - `dim_field[field]` → sort by `dim_field[field_key]` (orders fields by size)
   - `dim_year[era]` → sort by `dim_year[era_order]` (chronological, not alphabetical)
3. **Hide from report view** (right-click → Hide): every `*_key` column in both the fact
   table and the dimensions, plus `dim_degree[field]` and `dim_school[university_code]`.
   Field-of-study comes from `dim_field[field]` only and university from
   `dim_university[university_code]` only — one column per concept in use means no
   ambiguity about which one a visual is sliced by, and no chance of two slicers on the
   same concept disagreeing.
4. **Build the drill hierarchy**: in a matrix, row levels can come from different
   tables, so the Field → Subject → Degree hierarchy is assembled in the visual
   (page 5), not in the model.

### The one modelling trap

`dim_tier` has two rows, and the "Cum Laude and above" row is a **sub-population of**
the "All graduates" row for the same SMU programme, not an additional programme.
Summing or averaging across both double-counts SMU graduates and pulls every SMU figure
upward.

Guard it with a **page-level filter**, not a report-level one, because page 4 needs to
see both tiers:

- Pages 1, 2, 3, 5 → page-level filter `dim_tier[cohort_tier] is All graduates`
- Page 4 → no tier filter; the comparison is the point

---

## 3. Apply the theme

`View → Themes → Browse for themes` → `powerbi/ma1580-theme.json`.

The palette is a published, validated categorical set (worst adjacent-pair
colour-vision-deficiency ΔE 9.1 against a ≥8 target), used in its documented slot
order. Three consequences to respect while building:

- **Never reorder or recolour series by rank.** Colour follows the entity. If a slicer
  changes how many series are on screen, the survivors keep their colours.
- **Scatter and bubble charts cap at three colour series.** Every pair of points can be
  adjacent in a scatter, so the full eight hues cannot stay distinguishable. The scatters
  below therefore use a single hue plus emphasis, not a colour-per-field.
- **Never a second y-axis.** Two measures on different scales become two charts or an
  indexed common base. Where this spec shows two lines on one chart, both are the same
  unit on one shared axis.

---

## 4. DAX measures

New measure on `fact_employment`. These are presentation-layer aggregations of
already-cleaned data — no cleaning, reshaping or deriving happens here, which is what
keeps the R-only constraint intact. Say exactly that in the report.

```dax
-- Headline measures ---------------------------------------------------------
Median Gross Pay      = MEDIAN ( fact_employment[gross_monthly_median] )
Median Basic Pay      = MEDIAN ( fact_employment[basic_monthly_median] )
Employment Rate       = AVERAGE ( fact_employment[employment_rate_overall] )
FT Permanent Rate     = AVERAGE ( fact_employment[employment_rate_ft_perm] )
Insecure Work Gap     = AVERAGE ( fact_employment[insecure_work_pp] )
Programmes            = COUNTROWS ( fact_employment )

-- Distribution -------------------------------------------------------------
Median P25            = MEDIAN ( fact_employment[gross_mthly_25_percentile] )
Median P75            = MEDIAN ( fact_employment[gross_mthly_75_percentile] )
Median Pay Spread     = MEDIAN ( fact_employment[pay_spread_sgd] )
Median Spread Ratio   = MEDIAN ( fact_employment[pay_spread_ratio] )

-- Relative standing (inflation-neutral) -----------------------------------
Median Pay Index      = MEDIAN ( fact_employment[pay_index] )

-- Growth -------------------------------------------------------------------
Pay Growth Since 2013 =
VAR Base =
    CALCULATE ( [Median Gross Pay],
                ALL ( dim_year ),
                dim_year[year] = 2013 )
RETURN
    DIVIDE ( [Median Gross Pay] - Base, Base )

-- Written without DATEADD on purpose: time intelligence expects a contiguous
-- daily date table, and dim_year holds one row per year.
Pay YoY % =
VAR ThisYear = SELECTEDVALUE ( dim_year[year] )
VAR Prev =
    CALCULATE ( [Median Gross Pay],
                ALL ( dim_year ),
                dim_year[year] = ThisYear - 1 )
RETURN
    DIVIDE ( [Median Gross Pay] - Prev, Prev )

-- Honours premium (page 4; needs both tiers in scope) ---------------------
Pay, All Graduates =
    CALCULATE ( [Median Gross Pay],
                dim_tier[cohort_tier] = "All graduates" )

Pay, Cum Laude =
    CALCULATE ( [Median Gross Pay],
                dim_tier[cohort_tier] = "Cum Laude and above" )

Honours Premium % =
    DIVIDE ( [Pay, Cum Laude] - [Pay, All Graduates], [Pay, All Graduates] )

-- Dynamic titles and captions (creativity: titles that react to slicers) ---
Selected Scope =
VAR Unis   = CONCATENATEX ( VALUES ( dim_university[university_code] ),
                            dim_university[university_code], ", " )
VAR Fields = CONCATENATEX ( VALUES ( dim_field[field] ), dim_field[field], ", " )
RETURN
    "Showing " & [Programmes] & " programme-years · " &
    IF ( ISFILTERED ( dim_university[university_code] ), Unis,   "all six universities" ) & " · " &
    IF ( ISFILTERED ( dim_field[field] ),                Fields, "all fields" )

Thin Evidence Warning =
    IF ( [Programmes] < 5,
         "⚠ Fewer than 5 programme-years in this selection — read with caution",
         BLANK () )
```

**Format these** (`Measure tools → Format`): pay measures as Whole number with a
`S$` custom format and thousands separator; rates and gaps as Decimal with 1 decimal
place; `Pay Growth Since 2013`, `Pay YoY %` and `Honours Premium %` as Percentage with
1 decimal place.

`Thin Evidence Warning` is worth building: it is an honest guard against reading a trend
off two data points, and the report's limitations section can point at it.

---

## 5. Page-by-page build

Canvas: 16:9, `View → Page view → Fit to page`. Each page gets a title textbox
(18pt Segoe UI Semibold, `#0b0b0b`) and a one-line subtitle in `#52514e` stating the
claim — the subtitle is what makes the page an argument rather than a collection of
charts.

---

### Page 1 — "A decade of rising pay"
*Subtitle: Starting salaries rose 40% between 2013 and 2024. Every number on this page says the same thing.*

**Layout**: KPI strip across the top, one large chart bottom-left, two supporting
charts right. The eye lands on the big number, then the trend confirms it.

| # | Visual | Field wells | Why this form |
|---|---|---|---|
| 1 | **Card** ×4 (KPI strip) | `[Median Gross Pay]`, `[Pay Growth Since 2013]`, `[Employment Rate]`, `[Programmes]` | A single current value is a stat tile, not a one-bar chart. Four headline numbers read in under a second |
| 2 | **Line chart** | X `dim_year[year_date]` (continuous) · Y `[Median Gross Pay]` | Trend over time, one series → one hue, no legend needed; the title names the series |
| 3 | **Clustered bar chart** | Y `dim_university[university_code]` · X `[Median Gross Pay]` · sorted descending | Magnitude comparison across 6 short labels. Horizontal because the labels are categorical codes |
| 4 | **Treemap** | Category `dim_field[field]` · Values `[Programmes]` | Part-to-whole over 13 classes — shows how the sector's teaching capacity is distributed before any outcome is discussed |

**Visual 2 detail**: set the X axis to *Continuous* (not Categorical) — available
because `year_date` is date-typed. Add a dotted constant line at the 2013 value
(`Analytics → Constant line`, value 3100, `#898781`) so the growth is visible as a
distance, not inferred from the slope. Add data labels on the **first and last points
only** (`Analytics` is not needed — turn labels on, then set
`Data labels → Apply settings to → Series`, and use *Customize series* to suppress the
middle; or place two text boxes). Never a number on every point.

**Bookmark pair on this page** (creativity requirement): two bookmarks, `Pay view`
and `Jobs view`, toggled by two buttons styled as tabs. `Jobs view` swaps visual 2's
measure group to `[Employment Rate]` and `[FT Permanent Rate]` — so the reader
discovers the page-2 twist themselves by clicking. Build it with two stacked line
charts in the same position and use `Selection pane → Hide/Show` + `Bookmark → Update`.

---

### Page 2 — "The headline rate lies"
*Subtitle: Employment peaked in the pandemic. The jobs behind that peak were the worst in the series.*

**Layout**: the argument chart gets two-thirds of the canvas. This is the page the whole
dashboard turns on, so nothing competes with it.

| # | Visual | Field wells | Why this form |
|---|---|---|---|
| 1 | **Line chart** (2 series, ONE axis) | X `dim_year[year_date]` · Y `[Employment Rate]` + `[FT Permanent Rate]` | Both series are percentages, so they share one axis — the **gap between the lines is the finding**, and a second y-axis would destroy it. Legend on, plus direct labels on both final points |
| 2 | **Column chart** | X `dim_year[year]` · Y `[Insecure Work Gap]` | The same story as a magnitude: the 2020 column at 23.7pp against a 5–10pp norm needs no explanation |
| 3 | **Card** ×3 | `[Employment Rate]`, `[FT Permanent Rate]`, `[Insecure Work Gap]` with a page filter of `year = 2020` | Pins the specific numbers the argument rests on |
| 4 | **Textbox** | Annotation: *"2020's record employment rate counted traineeships and temporary placements. Only 70.3% of that cohort held a full-time permanent job — the lowest in twelve years."* | A chart that needs a sentence should get the sentence |

**Visual 1 detail**: shade the pandemic years. Add a `Shaded area` via
`Analytics → Shaded area` if available for your build, or place a rectangle shape at
20% transparency `#e1e0d9` behind the 2020–2021 band and send it backward. Label it
"Pandemic cohorts" in `#898781` 9pt.

**Visual 2 detail**: this is a magnitude chart, so it is **one hue, not categorical** —
set all columns to `#2a78d6` and then use `Format → Columns → Apply settings to → 2020`
to give that single column the status colour `#d03b3b`. Emphasis, the most underused
form: one bar in the accent, the rest recessive.

---

### Page 3 — "Not everyone carries the risk"
*Subtitle: Pay and job security are different questions, and they have different answers by field.*

| # | Visual | Field wells | Why this form |
|---|---|---|---|
| 1 | **Scatter chart** | X `[Median Gross Pay]` · Y `[Insecure Work Gap]` · Details `dim_field[field]` · Size `[Programmes]` | Two measures, one point per field — the only form that shows pay and security are *not* the same ranking. 13 points, **single hue `#2a78d6`**, category labels on. No colour-per-field: scatter is an all-pairs form and caps at three colour series |
| 2 | **Clustered bar chart** | Y `dim_field[field]` · X `[Insecure Work Gap]` · sorted descending | Magnitude over 13 long category names → horizontal bars, one sequential hue |
| 3 | **Line chart, small multiples** | X `dim_year[year_date]` · Y `[Median Pay Index]` · Small multiples `dim_field[field]` · grid 4×2, "Show all" off | 13 series on one chart is three times the colour ceiling. Small multiples is the correct answer, not more hues. `Median Pay Index` not raw pay, so inflation and sector-wide wage growth are already removed and a rising panel means genuinely pulling ahead |
| 4 | **Line chart** | X `dim_field[field]` sorted · Y `[Median P25]`, `[Median Gross Pay]`, `[Median P75]` | Three series, same unit, one axis: shows the *distribution* behind each field's median. Health Sciences' S$391 spread against Computing's S$1,452 is the point |

**Visual 1 detail**: add quadrant reference lines (`Analytics → X-Axis constant line` at
the all-field median pay, `Y-Axis constant line` at the all-field mean gap), both
`#c3c2b7` dotted. Then emphasise the two extremes: set `Details` colours so every field
is `#898781` except Law (`#2a78d6`) and Design & Media (`#d03b3b`). Label the quadrants
with four small textboxes — "well paid, secure" / "well paid, insecure" / "lower paid,
secure" / "lower paid, insecure".

**Visual 1 is the single most valuable chart in the dashboard** for the report's
Dashboard section: name it, explain that a scatter was chosen because the reader's task
is to see that two rankings disagree, and explain the emphasis colouring.

---

### Page 4 — "What is honours actually worth?"
*Subtitle: SMU is the only university that publishes the same degree twice. The gap between the two is shrinking.*

This page exists because the cleaning found something: SMU reports every programme once
for the whole cohort and once for the subset graduating Cum Laude or above. Paired on
programme and year, that is a natural experiment nobody else in the dataset supports.

**Remove the tier page filter on this page.**

| # | Visual | Field wells | Why this form |
|---|---|---|---|
| 1 | **Clustered bar chart** | Y `dim_degree[subject]` · X `[Pay, All Graduates]` + `[Pay, Cum Laude]` · page filter `university_code = SMU`, `year = 2024` | Before→after per item. Two shades of one hue (`#2a78d6` / `#cde2fb`), not two categorical hues — they are the same quantity in two states, not two different things |
| 2 | **Line chart** | X `honours_premium[year]` · Y `Average of honours_premium[premium_pct]` | The decline from 17.5% (2014) to 5.9% (2024) is the finding. Uses the unrelated `honours_premium` table |
| 3 | **Card** ×2 | `Median of honours_premium[premium_sgd]`, `Median of honours_premium[premium_pct]` | The premium in dollars and in per cent |
| 4 | **Textbox** | Why only SMU, and the caveat that the subset is a sub-population of the cohort row and the two must never be summed | Honest about the limit of the evidence |

---

### Page 5 — "Explore a programme"
*Subtitle: Find the programmes you are choosing between and compare them on all four measures.*

**Layout**: slicer rail down the left (one column, ~200px), everything else right of it.
Filters belong in one place, not scattered between charts.

| # | Visual | Configuration |
|---|---|---|
| 1 | **Slicer** | `dim_year[year]`, style **Between** (range slider) |
| 2 | **Slicer** | `dim_university[university_code]`, **Tile** style, multi-select on |
| 3 | **Slicer** | `dim_field[field]`, **Dropdown**, "Select all" on |
| 4 | **Slicer** | `dim_school[award_route]`, Tile — SIT's own awards vs overseas partner awards |
| 5 | **Matrix** | Rows: `dim_field[field]` → `dim_degree[subject]` → `dim_degree[degree]` (three levels, drill-down on). Values: `[Median Gross Pay]`, `[Employment Rate]`, `[Insecure Work Gap]`, `[Median Pay Index]`, `[Programmes]`. Conditional formatting: **data bars** on Median Gross Pay, a `#cde2fb`→`#0d366b` background scale on Median Pay Index, and a `#0ca30c`/`#d03b3b` scale on Insecure Work Gap (reversed — low is good) |
| 6 | **Decomposition tree** | Analyse `[Median Gross Pay]`, Explain by `dim_field[field]`, `dim_university[university_code]`, `dim_degree[subject]`, `dim_year[era]` | Lets the reader ask "why is this high?" and follow it down themselves |
| 7 | **Line chart** | X `dim_year[year_date]` · Y `[Median Pay Index]` alone, with a constant line at 100 (`#c3c2b7`, dotted). The index already carries the comparison, so pairing it with raw pay on the same frame would need a second axis — which this dashboard never uses |
| 8 | **Card** | `[Selected Scope]` — the dynamic caption, so the reader always knows what is on screen |
| 9 | **Card** | `[Thin Evidence Warning]` |

**More than ~7 classes that all carry meaning → a table.** With 235 degrees, the matrix
is the right primary visual on this page, not another chart.

**Cross-filtering check** (explicitly assessed): click a field in the matrix and confirm
the decomposition tree and line chart respond. `Format → Edit interactions` lets you set
each pair deliberately — set the slicers to **Filter** everything, and the matrix to
**Highlight** the charts. Being able to say *which* interaction each visual uses and
why is what the Dashboard section needs.

---

### Hidden page A — tooltip report
`Page information → Allow use as tooltip = On`, canvas size **Tooltip** (320×240).
Build: a card with `[Median Gross Pay]`, a card with `[Programmes]`, and a small line
chart of `[Median Pay Index]` by year. Then on pages 1–3, set each chart's
`Format → Tooltips → Type = Report page → Page = Tooltip`.

A hover that shows a *trend* rather than a repeat of the clicked value is a genuine
interaction-design decision and is named in the Creativity band.

### Hidden page B — drill-through: single programme
`Page information → Allow use as drill-through`, with `dim_degree[degree]` in the
**Drill through** well. Contents: the programme's name as a dynamic title, four cards
(`[Median Gross Pay]`, `[Employment Rate]`, `[FT Permanent Rate]`, `[Median Spread
Ratio]`), a line chart of its pay against `dim_year[cohort_median_gross]` as the
benchmark, and a card showing `fact_employment[school_reported]` so the reader sees the
faculty label as that year's survey actually published it. Add a **back button**
(Power BI adds one automatically — keep it).

Right-click any degree in the page-5 matrix → *Drill through* → this page.

---

## 6. Accessibility and labelling pass

Five marks ride on labelling alone, and this pass is quick:

- Every axis has a title with its unit (`Median gross monthly pay (S$)`, not `Pay`).
- Every chart with ≥2 series has a legend **and** direct labels on the final points, so
  identity never rests on colour alone.
- Values, labels and legend text stay in the ink colours (`#0b0b0b`, `#52514e`,
  `#898781`) — never in the series colour.
- Set `Alt text` on every visual (`Format → General → Alt text`): one sentence saying
  what the visual shows and what the reader should take from it.
- Set the **tab order** on each page (`View → Selection → Tab order`): title, then KPIs,
  then charts in reading order, slicers last.
- `Insert → Text box` a one-line source credit on page 1: *Source: MOE Graduate
  Employment Survey (NTU, NUS, SIT, SMU, SUSS, SUTD), 2013–2024, via data.gov.sg.
  Cleaned and transformed in R; see appendix.*
- The two caveats that must appear on the canvas, not only in the report:
  1. On pages 1, 3 and 5: *Figures are unweighted medians across programmes. The survey
     publishes no cohort sizes, so a 15-graduate programme counts as much as a
     400-graduate one.*
  2. On page 4: the tiers are a population and its subset and must never be summed.

---

## 7. Checks before you export

| Requirement | Check |
|---|---|
| ≥3 pages | 5 visible pages ✔ |
| ≥5 visual types | card, line, column, clustered bar, treemap, scatter, matrix, decomposition tree, small-multiple line = **9** ✔ |
| Slicers work | Change each page-5 slicer; confirm the matrix, tree and line all move |
| Cross-filtering works | Click a treemap tile on page 1 and a matrix row on page 5 |
| Drill-down works | Expand the page-5 matrix Field → Subject → Degree |
| Drill-through works | Right-click a degree → drill through → back button returns |
| Bookmarks work | Page 1 Pay/Jobs toggle |
| Tooltips work | Hover a point on page 2 |
| No double counting | Pages 1, 2, 3, 5 each show the tier page-level filter in the Filters pane |
| No dual axis | No chart has a secondary y-axis |
| Everything labelled | Axis titles, legends, alt text, source credit |

Save as `GradEmploymentDashboard.pbix` in the project root.

---

## 8. What to carry into the report's Dashboard section (40 marks)

This section is the heaviest single item in the report. It needs three things, and this
spec has supplied each:

1. **Layout rationale** — §0 (the four-move argument, and why not overview→detail→done)
   and the per-page layout notes (KPI strip first because a stat tile beats a one-bar
   chart; the argument chart given two-thirds of page 2 so nothing competes with it;
   slicers in one rail rather than scattered).
2. **Why each visual type** — the "Why this form" column in every page table. The
   reasoning to reproduce: the data's *job* picks the form. Magnitude → bar. Trend →
   line. Two measures that disagree → scatter. One value → card. More than ~7 meaningful
   classes → matrix. Before/after per item → paired bar in two shades of one hue.
   13 series → small multiples, never 13 colours.
3. **How each interactive feature aids the user** — slicers narrow to the programmes a
   specific reader is choosing between; the matrix drill-down moves from a field to a
   named degree without a new page; the drill-through answers "tell me everything about
   this one programme"; the page-1 bookmark toggle makes the reader *discover* the pay/
   security divergence rather than being told it; the report-page tooltip shows a trend
   on hover instead of repeating the number already on screen; `[Selected Scope]` and
   `[Thin Evidence Warning]` keep the reader honest about what is on screen and whether
   it is enough data to support a claim.

Two design decisions worth naming explicitly, because they show judgment rather than
default settings: **no dual-axis chart anywhere** (two scales on one frame invite a
false visual correlation; where two measures share a unit they share one axis, and the
gap between the lines becomes the finding), and **colour assigned by the entity rather
than by rank** (a slicer that changes the series count must never repaint the
survivors, or the reader loses the thread between pages).
