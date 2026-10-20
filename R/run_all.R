# ==============================================================================
# run_all.R  --  Run the whole pipeline, raw file to Power BI inputs
# ==============================================================================
# Usage, from the project root:   Rscript R/run_all.R
#
# The pipeline is deliberately linear and each stage has one job:
#
#   00_setup.R      packages, paths, and every lookup table used downstream
#   01_helpers.R    one named function per cleaning decision
#   02_clean.R      raw file -> one tidy, typed, validated table  (11 steps)
#   03_transform.R  derived measures -> star schema and aggregates
#   04_export.R     CSV outputs, audit trail and data dictionary
#
# Nothing is cleaned, reshaped or aggregated after this point: Power BI loads
# the exported CSVs as they are, with no Power Query transformation.
#
# Running it twice gives identical output. data/raw/ is only ever read.
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
