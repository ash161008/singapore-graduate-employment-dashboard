# ==============================================================================
# 01_helpers.R  --  Reusable cleaning and validation functions
# ==============================================================================
# PURPOSE
#   Each cleaning decision is expressed once, as a named function, so that the
#   cleaning script below reads as a sequence of intentions rather than a wall
#   of in-line string surgery. Every function is pure: it takes a vector or a
#   data frame and returns a new one, never modifying the raw input.
# ==============================================================================

# ---- Encoding ----------------------------------------------------------------
#' Repair text that was double-encoded on export from data.gov.sg
#'
#' Non-ASCII names ("Technische Universitaet Muenchen") were written out as
#' UTF-8, read back as Latin-1 and re-encoded, leaving the byte sequence
#' C3 83 C2 A4 where C3 A4 was intended. Reversing the second encoding pass
#' restores the correct characters so partner-institution names display
#' properly on axis labels and in slicers.
#' Characters that were lost outright on export survive only as the Unicode
#' replacement character; those stood in for an en dash and are restored as
#' a plain hyphen.
repair_encoding <- function(x) {
  recoded <- iconv(x, from = "UTF-8", to = "latin1")
  # iconv returns NA for any string with no Latin-1 representation; in that
  # case the original text is already correct and is kept unchanged.
  out <- ifelse(is.na(recoded), x, recoded)
  Encoding(out) <- "UTF-8"
  # The Unicode replacement character stands where an en dash was lost outright
  # on export. It is substituted only after the repair pass above, because it
  # was itself double-encoded and is unrecognisable until that pass is undone.
  str_replace_all(out, "\uFFFD", "-")
}

# ---- Missing values ----------------------------------------------------------
#' Convert every spelling of "not available" to a true NA
#'
#' Missing income and employment figures are coded as "na" in some survey years
#' and "N.A." in others. Left as text they silently force whole columns to
#' character, which is why all eight measures import as text. Normalising them
#' to NA first lets the columns be typed as numbers.
blank_na_tokens <- function(x) {
  x <- str_squish(x)
  if_else(str_to_lower(x) %in% NA_TOKENS, NA_character_, x)
}

#' Coerce a measure column to numeric after the NA tokens have been removed
#'
#' Thousands separators and stray percent signs are stripped first so that no
#' legitimate value is lost to coercion. Any value that still fails to parse is
#' reported rather than silently discarded.
as_measure <- function(x, col_name = "column") {
  cleaned  <- str_remove_all(x, "[,%\\s$]")
  numeric  <- suppressWarnings(as.numeric(cleaned))
  unparsed <- unique(cleaned[!is.na(cleaned) & is.na(numeric)])
  if (length(unparsed) > 0) {
    warning("Unparsed values in ", col_name, ": ",
            paste(unparsed, collapse = ", "), call. = FALSE)
  }
  numeric
}

# ---- Text canonicalisation ---------------------------------------------------
#' Strip the footnote apparatus that MOE attaches to programme names
#'
#' Survey tables mark programmes with symbols (*, #, ^, **, ###) and occasional
#' footnote digits that refer to notes printed beneath the original table. These
#' carry no information once the table is separated from its notes, but they
#' split one programme into several distinct labels, which would fragment every
#' filter and chart in the dashboard.
strip_footnotes <- function(x) {
  x |>
    str_remove_all("[*#^~†‡]") |>
    str_remove("\\s*\\d+\\s*$") |>     # trailing footnote digit, e.g. "...Engineering6"
    str_squish()
}

#' Standardise capitalisation, connectives and bracket spacing
#'
#' The same programme appears as "Chemical and Biomolecular Engineering",
#' "Chemical And Biomolecular Engineering" and "Chemical & Biomolecular
#' Engineering" across years. Collapsing these spelling variants is what allows
#' a single programme to be tracked as one line on a trend chart.
canonicalise_text <- function(x) {
  x |>
    str_replace_all("&", "and") |>
    str_replace_all("\\s*/\\s*", " / ") |>
    str_replace_all("\\bAnd\\b", "and") |>
    str_replace_all("\\bOf\\b", "of") |>
    str_replace_all("\\bWith\\b", "with") |>
    str_replace_all("\\bIn\\b", "in") |>
    str_replace_all("\\(\\s+", "(") |>
    str_replace_all("\\s+\\)", ")") |>
    str_replace_all("\\s*\\(", " (") |>
    str_squish()
}

#' Collapse the programme-length wording used inconsistently by SMU
#'
#' "(4-year programme)" and "(4-years programme)" denote the same programme.
normalise_programme_length <- function(x) {
  x |>
    str_replace_all(regex("\\(4-years? programme\\)", ignore_case = TRUE), "(4-year)") |>
    str_replace_all(regex("\\(3-yr direct honours programme\\)", ignore_case = TRUE), "(3-year direct Honours)") |>
    str_squish()
}

#' Collapse the many ways an honours award is written into one marker
#'
#' "(Hons)", "(Hons.)", "with Honours" and "with Honours in X" all denote an
#' honours degree. Normalising the wording keeps a programme's honours and
#' non-honours records from appearing as two unrelated programmes.
normalise_honours <- function(x) {
  x |>
    str_replace_all(regex("\\(\\s*hons\\.?\\s*\\)", ignore_case = TRUE), "(Hons)") |>
    str_replace_all(regex("\\bwith honours in\\b", ignore_case = TRUE), "(Hons) in") |>
    str_replace_all(regex("\\bwith honours\\b", ignore_case = TRUE), "(Hons)") |>
    str_squish()
}

# ---- Classification ----------------------------------------------------------
#' Assign each degree title to one broad field of study
#'
#' Applies FIELD_RULES in order and takes the first match, so that the
#' precedence decisions documented in 00_setup.R are applied consistently.
#' Implemented as a single vectorised pass over the rule table rather than a
#' row-wise loop, so cost grows with the number of rules (14) and not with the
#' number of records.
classify_field <- function(x) {
  key   <- str_to_lower(x)
  field <- rep(NA_character_, length(key))
  for (i in seq_len(nrow(FIELD_RULES))) {
    unassigned <- is.na(field)
    if (!any(unassigned)) break
    hit <- unassigned & str_detect(key, FIELD_RULES$pattern[i])
    field[hit] <- FIELD_RULES$field[i]
  }
  replace_na(field, "Other")
}

#' Label each survey year with its labour-market era
assign_era <- function(year) {
  idx <- map_int(year, function(y) {
    m <- which(y >= ERA_BREAKS$year_from & y <= ERA_BREAKS$year_to)
    if (length(m) == 1) m else NA_integer_
  })
  ERA_BREAKS$era[idx]
}

# ---- Validation --------------------------------------------------------------
#' Assert a condition about the data and stop the pipeline if it fails
#'
#' Cleaning is only trustworthy if its assumptions are tested, so each
#' structural expectation is checked explicitly and the run aborts on breach
#' rather than exporting a quietly wrong table to Power BI.
check_that <- function(condition, description, offenders = NULL) {
  n_bad <- sum(!condition, na.rm = TRUE)
  if (n_bad > 0) {
    msg <- paste0("VALIDATION FAILED: ", description, " (", n_bad, " record(s))")
    if (!is.null(offenders)) {
      msg <- paste0(msg, "\n", paste(utils::capture.output(print(utils::head(offenders, 5))),
                                     collapse = "\n"))
    }
    stop(msg, call. = FALSE)
  }
  message("  [ok] ", description)
  invisible(TRUE)
}

# ---- Audit trail -------------------------------------------------------------
#' Record the row count after a cleaning step
#'
#' The resulting log is exported with the cleaned data so that the row counts
#' quoted in the report are generated by the pipeline rather than transcribed
#' by hand, and so a reader can see exactly what each step removed.
new_log <- function() tibble(step = character(), action = character(),
                             rows = integer(), removed = integer())

log_step <- function(log, step, action, rows) {
  previous <- if (nrow(log) == 0) rows else tail(log$rows, 1)
  bind_rows(log, tibble(step = step, action = action,
                        rows = as.integer(rows),
                        removed = as.integer(previous - rows)))
}

# ---- Partner institutions ----------------------------------------------------
#' Reduce SIT's partner-institution labels to the institution itself
#'
#' SIT awards both its own degrees and degrees conferred by overseas partners,
#' and names the partner inconsistently across years: "Newcastle University",
#' "SIT-Newcastle University" and "SIT- Newcastle University" are one partner,
#' while joint awards appear as compounds such as "SIT / SIT-Trinity College
#' Dublin / Trinity College Dublin". Dropping the redundant SIT prefix and
#' de-duplicating the compounds leaves one label per awarding institution, so
#' SIT's partner programmes can be compared with its in-house programmes.
normalise_partner_institution <- function(x) {
  sit_prefix <- "^\\s*(SIT|Singapore Institute of Technology)\\s*[-]\\s*"
  sit_alone  <- "^\\s*(SIT|Singapore Institute of Technology( \\(SIT\\))?)\\s*$"

  map_chr(x, function(label) {
    parts <- str_split(label, "\\s*/\\s*")[[1]] |>
      str_remove(sit_prefix) |>
      str_remove("^The\\s+") |>
      str_squish()
    partners <- unique(parts[!str_detect(parts, sit_alone) & parts != ""])
    if (length(partners) == 0) "Singapore Institute of Technology (own award)"
    else paste(partners, collapse = " / ")
  })
}

# ---- Chart labels ------------------------------------------------------------
#' Reduce a full award title to the subject it is awarded in
#'
#' NUS, SIT and SUTD report the full award ("Bachelor of Engineering (Hons) in
#' Mechanical Engineering") while NTU and SMU report only the subject
#' ("Mechanical Engineering"). Full titles run to eighty characters and are
#' unreadable on a category axis, and the inconsistency makes the same subject
#' look like two different programmes when universities are compared side by
#' side. Reducing every title to its subject gives one short, comparable label
#' for charts, while the full title is retained for drill-down and tooltips.
shorten_degree <- function(x) {
  # Award names that act as a wrapper around the real subject, e.g. the
  # "Science" in "Bachelor of Science in Nursing". Where the award name IS the
  # subject ("Bachelor of Accountancy") nothing is stripped.
  wrapper <- paste("Science", "Arts", "Fine Arts", "Engineering", "Business",
                   "Business Administration", "Computing", "Applied Science",
                   "Professional Studies", sep = "|")

  x |>
    # Honours wording is removed first and carried by its own flag; left in
    # place it sits between the award and the subject and blocks the patterns
    # below from matching.
    str_remove_all(regex("\\s*\\(hons\\)", ignore_case = TRUE)) |>
    str_remove(regex("^double degree in\\s+", ignore_case = TRUE)) |>
    str_remove_all(regex("\\bbachelor (of|in)\\s+", ignore_case = TRUE)) |>
    # "Science in Nursing" -> "Nursing"; anchored so that a subject which itself
    # contains an award word ("Computer Science in Real-Time Interactive
    # Simulation") is left intact.
    str_remove(regex(paste0("^(", wrapper, ")\\s+in\\s+"), ignore_case = TRUE)) |>
    str_replace(regex(paste0("\\band (", wrapper, ")\\s+in\\s+"),
                      ignore_case = TRUE), " and ") |>
    # "Engineering (Mechanical Engineering)" -> "Mechanical Engineering", only
    # when the bracket holds the whole subject.
    str_replace(regex(paste0("^(", wrapper, ")\\s*\\(([^)]+)\\)$"),
                      ignore_case = TRUE), "\\2") |>
    str_remove(regex("^major in\\s+", ignore_case = TRUE)) |>
    str_squish() |>
    # A title that reduced to nothing keeps its original wording rather than
    # becoming an empty label.
    (\(s) if_else(s == "" | is.na(s), x, s))()
}

#' Flags describing the structure of an award, read from its title
is_honours_degree <- function(x) {
  str_detect(x, regex("\\(hons\\)|honours|cum laude", ignore_case = TRUE))
}

is_double_degree <- function(x) {
  str_detect(x, regex("double degree|double major|\\band\\b.*\\bdegree\\b",
                      ignore_case = TRUE))
}
