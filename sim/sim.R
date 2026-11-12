# Simulated data for code development without the data store
#
# source("sim/sim.R")                                   # from the repo root
# source("../nyc_transport/sim/sim.R")            # from a project next to the repo
# cr <- sim_crashes(5000)
#
# Loads R/simulate.R and every sim/sim_<source>.R. Each sim_<source>() returns a table shaped like
# what the reader in R/nyc_transport.R returns (same columns and types; see the header of each
# script and profiles/<source>.csv), drawn from the profiles in profiles/. Only data.table is
# needed, sf for spatial sources. The data are made up: use them to write and test code, never for
# results. sim_list() lists the simulators.

library(data.table)

local({
  ofiles <- unlist(lapply(sys.frames(), function(f) if (is.character(f$ofile)) f$ofile))
  this <- tail(ofiles[grepl("sim\\.R$", ofiles)], 1)
  sim_dir <- if (length(this)) dirname(this) else "sim"
  source(file.path(dirname(sim_dir), "R", "simulate.R"), local = FALSE)
  source(file.path(sim_dir, "helpers.R"), local = FALSE)
  for (f in list.files(sim_dir, "^sim_.+\\.R$", full.names = TRUE)) source(f, local = FALSE)
  assign("sim_scripts", sub("\\.R$", "", list.files(sim_dir, "^sim_.+\\.R$")), envir = globalenv())
})

# the simulators, one per script in sim/
sim_list <- function() sim_scripts
