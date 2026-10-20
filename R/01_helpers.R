# ==============================================================================
# 01_helpers.R  --  Cleaning and validation functions
# ==============================================================================
# One named function per cleaning decision, so 02_clean.R reads as a list of
# steps instead of a wall of string handling. Each function takes a vector or a
# data frame and returns a new one; nothing modifies its input.
# ==============================================================================

# ---- Encoding ----------------------------------------------------------------
#' Repair text that was double-encoded on export
#'
#' Names with accents ("Technische Universitaet Muenchen") were written as
#' UTF-8, read back as Latin-1 and encoded again, so the file holds the bytes
#' C3 83 C2 A4 where C3 A4 was meant. Undoing the second pass restores the
#' characters, which matters because these names appear on axis labels and in
#' slicers.
repair_encoding <- function(x) {
  recoded <- iconv(x, from = "UTF-8", to = "latin1")
  # iconv gives NA for a string with no Latin-1 form. Those are already correct,
  # so keep the original.
  out <- ifelse(is.na(recoded), x, recoded)
  Encoding(out) <- "UTF-8"
  # Some characters were lost on export and survive only as the Unicode
  # replacement character, standing in for an en dash. Replaced after the pass
  # above, because it was double-encoded too and is not recognisable until then.
  str_replace_all(out, "�", "-")
}

# ---- Missing values ----------------------------------------------------------
#' Turn every spelling of "not available" into NA
#'
#' Missing figures are written "na" in some years and "N.A." in others. As text
#' they force the whole column to character, which is why all eight measures
#' import as text. Converting them to NA first lets the columns be typed.
blank_na_tokens <- function(x) {
  x <- str_squish(x)
  if_else(str_to_lower(x) %in% NA_TOKENS, NA_character_, x)
}

#' Convert a measure column to numeric once the NA tokens are gone
#'
#' Strips thousands separators and stray percent signs first so no real value
#' is lost. Anything that still fails to parse is reported rather than dropped
#' quietly.
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

# ---- Text tidying ------------------------------------------------------------
#' Read the footnote markers off the end of a programme name
#'
#' Has to run before strip_footnotes(), which removes them. FOOTNOTE_LEGEND
#' gives their meanings; two of them are warnings about how the figure was
#' produced, so they are kept as flags. Returns "" rather than NA when there is
#' no marker, so str_detect() on the result does not produce missing values.
read_footnote_markers <- function(x) {
  x |>
    str_extract("[*#^~†‡\\s]+$") |>
    str_remove_all("\\s") |>
    replace_na("")
}

#' Remove the footnote symbols and digits from a programme name
#'
#' The symbols split one programme into several different labels, which would
#' fragment every filter and chart. Safe to remove here because
#' read_footnote_markers() has already captured what they mean.
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
#' Engineering" in different years. Collapsing those lets one programme be a
#' single line on a trend chart.
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

#' Collapse SMU's inconsistent programme-length wording
#'
#' "(4-year programme)" and "(4-years programme)" are the same programme.
normalise_programme_length <- function(x) {
  x |>
    str_replace_all(regex("\\(4-years? programme\\)", ignore_case = TRUE), "(4-year)") |>
    str_replace_all(regex("\\(3-yr direct honours programme\\)", ignore_case = TRUE), "(3-year direct Honours)") |>
    str_squish()
}

#' Write honours awards one consistent way
#'
#' "(Hons)", "(Hons.)", "with Honours" and "with Honours in X" all mean an
#' honours degree. Without this a programme's honours and non-honours records
#' look like two unrelated programmes.
normalise_honours <- function(x) {
  x |>
    str_replace_all(regex("\\(\\s*hons\\.?\\s*\\)", ignore_case = TRUE), "(Hons)") |>
    str_replace_all(regex("\\bwith honours in\\b", ignore_case = TRUE), "(Hons) in") |>
    str_replace_all(regex("\\bwith honours\\b", ignore_case = TRUE), "(Hons)") |>
    str_squish()
}

# ---- Classification ----------------------------------------------------------
#' Assign a degree title to one field of study
#'
#' Tests FIELD_RULES in order and takes the first match, so the ordering set
#' out in 00_setup.R is applied consistently. Written as one vectorised pass
#' over the 14 rules rather than a loop over records, so the cost depends on
#' the number of rules and not the number of rows.
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

#' Label a survey year with its era
assign_era <- function(year) {
  idx <- map_int(year, function(y) {
    m <- which(y >= ERA_BREAKS$year_from & y <= ERA_BREAKS$year_to)
    if (length(m) == 1) m else NA_integer_
  })
  ERA_BREAKS$era[idx]
}

# ---- Validation --------------------------------------------------------------
#' Test an assumption about the data and stop the run if it fails
#'
#' Cleaning can only be trusted if its assumptions are tested, so each one is
#' stated here and the run stops rather than writing a wrong table to
#' data/clean/.
#'
#' Two cases where a check can look like it passed without testing anything:
#'
#'   1. The condition contains NA. Comparing with a missing value gives NA, not
#'      FALSE, so counting with na.rm = TRUE would skip those records and report
#'      success. An NA here means the check could not be evaluated, so it fails.
#'      A check that has to cope with missing data should say so, as
#'      is.na(x) | <test on x>.
#'   2. The condition is empty because the thing being checked had no rows.
#'      That can be legitimate, so it does not fail, but the message says so.
#'
#' The count of values tested is printed on every line, so the run log shows
#' how much each check actually covered.
check_that <- function(condition, description, offenders = NULL) {
  n_total <- length(condition)
  n_na    <- sum(is.na(condition))
  n_bad   <- sum(!condition, na.rm = TRUE)

  report_offenders <- function(msg) {
    if (is.null(offenders)) return(msg)
    paste0(msg, "\n",
           paste(utils::capture.output(print(utils::head(offenders, 5))),
                 collapse = "\n"))
  }

  if (n_na > 0) {
    stop(report_offenders(paste0(
      "VALIDATION NOT EVALUABLE: ", description, " -- ", n_na, " of ", n_total,
      " value(s) came out as NA, so the check could not test them. ",
      "Rewrite the condition to handle missing values, ",
      "e.g. is.na(x) | <test on x>.")), call. = FALSE)
  }

  if (n_bad > 0) {
    stop(report_offenders(paste0(
      "VALIDATION FAILED: ", description, " (", n_bad, " of ", n_total,
      " record(s))")), call. = FALSE)
  }

  if (n_total == 0) {
    message("  [ok, nothing to test] ", description)
  } else {
    message("  [ok, ", n_total, " tested] ", description)
  }
  invisible(TRUE)
}

# ---- Audit trail -------------------------------------------------------------
#' Record the row count after a step
#'
#' The log is exported with the cleaned data, so the row counts quoted in the
#' report come from the pipeline rather than being copied out by hand, and a
#' reader can see what each step removed.
new_log <- function() tibble(step = character(), action = character(),
                             rows = integer(), removed = integer())

log_step <- function(log, step, action, rows) {
  previous <- if (nrow(log) == 0) rows else tail(log$rows, 1)
  bind_rows(log, tibble(step = step, action = action,
                        rows = as.integer(rows),
                        removed = as.integer(previous - rows)))
}

# ---- Partner institutions ----------------------------------------------------
#' Reduce SIT's partner labels to the awarding institution
#'
#' SIT awards its own degrees and degrees conferred by overseas partners, and
#' names the partners inconsistently: "Newcastle University",
#' "SIT-Newcastle University" and "SIT- Newcastle University" are one partner.
#' Joint awards appear as compounds like "SIT / SIT-Trinity College Dublin /
#' Trinity College Dublin". Removing the SIT prefix and de-duplicating leaves
#' one label per institution, so SIT's partner and in-house programmes can be
#' compared.
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
#' Reduce a full award title to its subject
#'
#' NUS, SIT and SUTD publish the full award ("Bachelor of Engineering (Hons) in
#' Mechanical Engineering") while NTU and SMU publish only the subject
#' ("Mechanical Engineering"). Full titles reach eighty characters and cannot be
#' read on a category axis, and the inconsistency makes one subject look like
#' two programmes when universities are compared. The full title is kept for
#' drill-down and tooltips.
shorten_degree <- function(x) {
  # Award names that wrap the real subject, e.g. the "Science" in "Bachelor of
  # Science in Nursing". Where the award name is itself the subject ("Bachelor
  # of Accountancy") nothing is removed.
  wrapper <- paste("Science", "Arts", "Fine Arts", "Engineering", "Business",
                   "Business Administration", "Computing", "Applied Science",
                   "Professional Studies", sep = "|")

  x |>
    # Honours wording comes out first and is carried by its own flag. Left in,
    # it sits between the award and the subject and blocks the patterns below.
    str_remove_all(regex("\\s*\\(hons\\)", ignore_case = TRUE)) |>
    # Programme length is not a subject. "Business (3-year direct Honours)" and
    # "Business" are the same subject over a different number of years, and the
    # full degree title still records the difference.
    str_remove(regex("\\s*\\([0-9]+-year[^)]*\\)", ignore_case = TRUE)) |>
    str_remove(regex("^double degree in\\s+", ignore_case = TRUE)) |>
    str_remove_all(regex("\\bbachelor (of|in)\\s+", ignore_case = TRUE)) |>
    # "Science in Nursing" -> "Nursing". Anchored, so a subject that contains an
    # award word itself ("Computer Science in Real-Time Interactive Simulation")
    # is left alone.
    str_remove(regex(paste0("^(", wrapper, ")\\s+in\\s+"), ignore_case = TRUE)) |>
    str_replace(regex(paste0("\\band (", wrapper, ")\\s+in\\s+"),
                      ignore_case = TRUE), " and ") |>
    # A bracket starting with "and" or "with" qualifies the award instead of
    # replacing it: "Arts (with Education)" is a degree in Arts and Education,
    # not a degree in "with Education". Flattening it also merges the survey's
    # "Arts (and Education)" and "Arts (with Education)" into one subject.
    str_replace(regex("^(.+?)\\s*\\((?:and|with)\\s+(.+)\\)$",
                      ignore_case = TRUE), "\\1 with \\2") |>
    # "Engineering (Mechanical Engineering)" -> "Mechanical Engineering", but
    # only when the bracket holds the whole subject. The lookahead stops this
    # firing on a bracket like "(with Education)" and keeping the modifier.
    str_replace(regex(paste0("^(", wrapper, ")\\s*\\((?!and |with |or )([^)]+)\\)$"),
                      ignore_case = TRUE), "\\2") |>
    str_remove(regex("^major in\\s+", ignore_case = TRUE)) |>
    str_squish() |>
    # If a title reduces to nothing, keep the original rather than an empty
    # label.
    (\(s) if_else(s == "" | is.na(s), x, s))()
}

#' Read the structure of an award off its title
is_honours_degree <- function(x) {
  # Does not test for "cum laude" on purpose. That is the reporting tier and is
  # moved into cohort_tier in cleaning step 10, before this runs, so a cum laude
  # branch here could never match.
  str_detect(x, regex("\\(hons\\)|honours", ignore_case = TRUE))
}

is_double_degree <- function(x) {
  str_detect(x, regex("double degree|double major|\\band\\b.*\\bdegree\\b",
                      ignore_case = TRUE))
}
