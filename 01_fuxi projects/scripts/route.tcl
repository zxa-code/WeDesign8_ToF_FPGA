##############################################################################
# PROJECT VARIABLES
##############################################################################
set design           top_tof
set arch             griffin
set arch_ver         2.0
set speed_grade      -3
set pvt_factor       1.35046
puts "ANDARA: ###############################"
puts "ANDARA: # Starting step: route "
puts "ANDARA: ###############################"
set step route
set inDbFile       db/chip_pack.db
set inSdcFile      [list "outputs/top_tof_auto.sdc" "$env(CSTESTS)/lib/special.sdc" "$env(AGATE_ROOT)/bin/template/project/propagated_clock.sdc"]
set ntiming_paths  500
set routeLog       outputs/chip_rte.ro
set outDbFile      db/chip_rte.db
set outFile        netlist/chip_rte.v
set arafile        outputs/top_tof.ara
set dev_name       HR03PN0U81C7
set outSdcFile     ""
set routeSdf       "outputs/top_tof_router.sdf"
set apafile        outputs/top_tof.apa
set arvfile        outputs/top_tof.arv
set andara_ver     5.1.2
set delayType      max
cs_route_config MAX_ITER 95
cs_route_config  FUTURE_WEIGHT 95
set rgraph         "$env(USE_RGRAPH_ARCH)"
set rgraph_delay   "$env(USE_RGRAPH_DELAY)"
source "$env(CSTOOLS)/scripts/cswitch/route.tcl"
catch {exec reportProgress 16 100 3}
puts "ANDARA: ###############################"
puts "ANDARA: # Ending step: route "
puts "ANDARA: ###############################"