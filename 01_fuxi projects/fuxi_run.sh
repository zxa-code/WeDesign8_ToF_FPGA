#!/bin/bash
# Match working project environment
# Placer
cstool "scripts/syn_gen_db.tcl"
cstool "scripts/fplan.tcl"
cstool "scripts/assigner_cstool.tcl"
cstool "scripts/refiner_new.tcl"
# Router
cstool "scripts/fixer.tcl"
cstool "scripts/fixer_drc.tcl"
cstool "scripts/pack.tcl"
cstool "scripts/route.tcl"
# Timing analysis
agtc "-n" "outputs/top_tof.arv" "-temperature" "85" "-voltage" "0.81" "-process" "3" "-cs"
cstimer "-encoding" "utf-8" "scripts/run_sta.tcl"
# Bitgen
abcgen "-p" "outputs/top_tof.apa" "-r" "outputs/top_tof.ara" "-aoc" "top_tof.aoc" "-abc" "outputs/top_tof.abc" "-iostatus" "x"
acfgen "-iostatus" "i" "-abc" "outputs/top_tof.abc" "-sf" "outputs/top_tof_spi.acf" "-bin" "outputs/top_tof_bin.acf" "-ipcmd" ""
