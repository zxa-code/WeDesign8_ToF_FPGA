## PROGRAM "Primace"
## VERSION "Version 8.0.2 win64"
##
## Device: HR03PN0U81C7

set design          top_tof
set inFile          "outputs/top_tof.arvx"
set inSdfFile       "outputs/top_tof_router.sdf"
set sdcFile         [list "constraint/constraint.sdc" "$env(AGATE_ROOT)/bin/template/project/propagated_clock.sdc"]
set report_file     "top_tof.trpt"
set lib_file        "$env(AGATE_ROOT)/andara/csdata/C1/arch/general/fabric_timing.lib"
set extlib_tcl_file "$env(AGATE_ROOT)/data/csta/scripts/C1_extlib.tcl"
set max_path        10000000
source "$env(AGATE_ROOT)/bin/template/project/scripts/run_sta.tcl"