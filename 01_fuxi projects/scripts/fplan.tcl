##############################################################################
# PROJECT VARIABLES
##############################################################################
set design           top_tof
set arch             griffin
set arch_ver         2.0
set speed_grade      -3
set pvt_factor       1.35046
puts "ANDARA: ###############################"
puts "ANDARA: # Starting step: fplan "
puts "ANDARA: ###############################"
set step fplan
set inFile outputs/top_tof.amv
set outFile netlist/chip_fplan.v
set outDbFile db/chip_fplan.db
set outFplanFixedCellsFile scripts/fplan.fixed_cells.tcl
set outAocFile outputs/top_tof_pr.aoc
set inAocFile top_tof.aoc
source "$env(CSTOOLS)/scripts/cswitch/fplan.tcl"
catch {exec reportProgress 8 45 3}
puts "ANDARA: ###############################"
puts "ANDARA: # Ending step: fplan "
puts "ANDARA: ###############################"