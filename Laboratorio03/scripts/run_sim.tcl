## ============================================================================
## scripts/run_sim.tcl
## Compila y corre un testbench standalone con XSim sin abrir Vivado GUI.
## Uso:
##   vivado -mode batch -source scripts/run_sim.tcl -tclargs <tb_module>
## Ejemplo:
##   vivado -mode batch -source scripts/run_sim.tcl -tclargs tb_spi_master
## ============================================================================

if {$argc < 1} {
    error "Uso: ... -tclargs <tb_module>"
}
set tb_name [lindex $argv 0]
set repo_dir [pwd]
set work_dir "$repo_dir/sim/work"

file mkdir $work_dir
cd $work_dir

set rtl_files [list \
    "$repo_dir/rtl/bus/axil_defs.svh" \
    "$repo_dir/rtl/peripherals/spi/spi_master.sv" \
    "$repo_dir/rtl/peripherals/spi/spi_axil.sv" \
    "$repo_dir/sim/common/axil_master_bfm.sv" \
    "$repo_dir/sim/common/adxl362_stub.sv" \
]

set tb_files [list "$repo_dir/sim/${tb_name}.sv"]

set xvlog_args "-sv --include $repo_dir/rtl/bus"
foreach f $rtl_files {
    append xvlog_args " $f"
}
foreach f $tb_files {
    append xvlog_args " $f"
}

puts "==== xvlog ===="
puts $xvlog_args
if {[catch {exec xvlog {*}[split $xvlog_args " "]} result]} {
    puts "XVLOG output:\n$result"
    error "xvlog falló"
}
puts $result

puts "==== xelab ===="
if {[catch {exec xelab -debug typical -timescale 1ns/1ps $tb_name -s ${tb_name}_sim} result]} {
    puts "XELAB output:\n$result"
    error "xelab falló"
}
puts $result

puts "==== xsim ===="
set runfile "${tb_name}_run.tcl"
set fp [open $runfile w]
puts $fp "run all; quit"
close $fp

if {[catch {exec xsim ${tb_name}_sim -tclbatch $runfile} result]} {
    puts "XSIM output:\n$result"
    error "xsim falló"
}
puts $result

cd $repo_dir
puts "==== FIN ===="
