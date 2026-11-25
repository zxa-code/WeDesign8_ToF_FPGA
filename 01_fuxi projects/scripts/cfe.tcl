####################################################
# CFE CONFIGURATION
####################################################
set top_design top_tof
set include_path {"."}
set verilog_design_files {alarm_ctrl.v bcd_conv.v crc16_modbus.v disp_chargen.v font8x8.v iic_master.v key_scan.v oled_sh1107.v oled_ssd1306.v rotary_enc.v seg7_595.v tof1_parser.v top_tof.v uart_rx.v uart_tx.v ui_ctrl.v ws2812_drv.v}
set user_bbox_lib ""
set bbox_lib "$env(AGATE_ROOT)/data/lib/cst_lib_hr3.v"
source "$env(AGATE_ROOT)/data/syn/cfe/cfe_base.tcl"