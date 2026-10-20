# ==============================================================================
# run_all.R  --  Run the whole pipeline, raw file to Power BI inputs
# ==============================================================================
# Usage, from the project root:   Rscript R/run_all.R
#
# The pipeline runs in order and each script does one job:
#
#   00_setup.R      packages, paths and the lookup tables
#   01_helpers.R    one function per cleaning decision
#   02_clean.R      raw file to one tidy, typed, checked table (13 steps)
#   03_transform.R  derived measures, star schema and aggregates
#   04_export.R     the CSVs, the step log and the data dictionary
#
# Nothing is cleaned, reshaped or aggregated after this. Power BI loads the
# exported CSVs as they are, with no Power Query steps.
#
# Running it twice gives the same output. data/raw/ is only ever read.
# ==============================================================================

started <- Sys.time()

source("R/00_setup.R")
source("R/01_helpers.R")
source("R/02_clean.R")
source("R/03_transform.R")
source("R/04_export.R")

message("\nPipeline completed in ",
        round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1),
        " seconds.")
