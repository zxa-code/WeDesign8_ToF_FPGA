#!/bin/bash
# Match working project environment
mkdir outputs
mkdir netlist
mkdir db
mkdir misc
mkdir tmp

cst "-tcl" "scripts/cst_option.tcl"
agv2aoc "-v" "outputs/top_tof.amv" "-o" "top_tof.aoc" "-dev" "HR03PN0U81C7" "-io" "-top" "top_tof"
