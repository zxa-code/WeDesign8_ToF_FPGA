set_option dev HR03PN0U81C7
set_option v alarm_ctrl.v bcd_conv.v crc16_modbus.v disp_chargen.v font8x8.v iic_master.v key_scan.v oled_sh1107.v oled_ssd1306.v rotary_enc.v seg7_595.v tof1_parser.v top_tof.v uart_rx.v uart_tx.v ui_ctrl.v ws2812_drv.v
set_option top top_tof
set_option vo outputs/top_tof.amv
set_option whitebox true
set_option isyn true
set_option fca false
set_option keep_latch true
set_option keep_floating true
set_option rename_luts 0
set_option optimize_primitives false
set_option shift_register_inference false
set_option shift_register_merge false
set_option fast_io false
set_option aoc outputs/top_tof_ast.aoc
set_option min_ce_fanout 4
set_option carry_opt true
set_option magic true
set_option mode best_timing
set_option use_naming_rule true
set_option cfe scripts/cfe.tcl
set_option reg_opt false
set_option min_adder_width 6
set_option remove_identical_inst true
set_option disioc false
set_option extract_multiport_rams true
set_option max_fanout 100000
set_option reg_retime false
set_option debug false
set_option debug_formal false

source "$env(AGATE_ROOT)/data/syn/cst_flow.tcl"