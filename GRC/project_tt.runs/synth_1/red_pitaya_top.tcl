# 
# Synthesis run script generated by Vivado
# 

create_project -in_memory -part xc7z010clg400-1

set_param project.singleFileAddWarning.threshold 0
set_param project.compositeFile.enableAutoGeneration 0
set_param synth.vivado.isSynthRun true
set_msg_config -source 4 -id {IP_Flow 19-2162} -severity warning -new_severity info
set_property webtalk.parent_dir C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.cache/wt [current_project]
set_property parent.project_path C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.xpr [current_project]
set_property default_lib xil_defaultlib [current_project]
set_property target_language Verilog [current_project]
set_property ip_output_repo c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.cache/ip [current_project]
set_property ip_cache_permissions {read write} [current_project]
read_verilog -library xil_defaultlib -sv {
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/interface/axi4_if.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/axi4_slave.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/interface/gpio_if.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/red_pitaya_dfilt1.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/red_pitaya_pll.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/prj/classic/rtl/red_pitaya_ps.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_pwm.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/interface/sys_bus_if.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/sys_bus_interconnect.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/sys_bus_stub.sv
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/prj/classic/rtl/red_pitaya_top.sv
}
read_verilog -library xil_defaultlib {
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/axi_wr_fifo.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_ams.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_asg.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_asg_ch.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_id.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_pid.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_pid_block.v
  C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/imports/fpga/rtl/classic/red_pitaya_scope.v
}
add_files C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/system.bd
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_axi_protocol_converter_0_0/system_axi_protocol_converter_0_0_ooc.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_proc_sys_reset_0/system_proc_sys_reset_0_board.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_proc_sys_reset_0/system_proc_sys_reset_0.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_proc_sys_reset_0/system_proc_sys_reset_0_ooc.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_processing_system7_0/system_processing_system7_0.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_xadc_0/system_xadc_0_ooc.xdc]
set_property used_in_implementation false [get_files -all c:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/ip/system_xadc_0/system_xadc_0.xdc]
set_property used_in_implementation false [get_files -all C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/system_ooc.xdc]
set_property is_locked true [get_files C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/sources_1/bd/system/system.bd]

# Mark all dcp files as not used in implementation to prevent them from being
# stitched into the results of this synthesis run. Any black boxes in the
# design are intentionally left as such for best results. Dcp files will be
# stitched into the design at a later time, either when this synthesis run is
# opened, or when it is stitched into a dependent implementation run.
foreach dcp [get_files -quiet -all -filter file_type=="Design\ Checkpoint"] {
  set_property used_in_implementation false $dcp
}
read_xdc C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/constrs_1/imports/sdc/red_pitaya.xdc
set_property used_in_implementation false [get_files C:/Users/adam/Documents/Quantaser_RP_FPGA/GRC/project_tt.srcs/constrs_1/imports/sdc/red_pitaya.xdc]

read_xdc dont_touch.xdc
set_property used_in_implementation false [get_files dont_touch.xdc]

synth_design -top red_pitaya_top -part xc7z010clg400-1


write_checkpoint -force -noxdef red_pitaya_top.dcp

catch { report_utilization -file red_pitaya_top_utilization_synth.rpt -pb red_pitaya_top_utilization_synth.pb }
