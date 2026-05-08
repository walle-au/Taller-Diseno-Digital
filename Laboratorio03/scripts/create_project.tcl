## ============================================================================
## scripts/create_project.tcl  – LAB 3
## Crea el proyecto Vivado lab03 desde cero con:
##   - RTL completo (SPI master + wrapper AXI-Lite incluidos)
##   - Testbenches en fileset sim_1 (top por defecto: tb_spi_master)
##   - IPs: clk_wiz_main, rom_program, data_ram
##   - Constraints Nexys4 DDR
##
## Uso (desde la raiz del repo Laboratorio03):
##   vivado -mode batch -source scripts/create_project.tcl
## Luego abrir GUI:
##   vivado /home/wally/Documentos/Vivado/2024.1/lab03/lab03.xpr &
## ============================================================================

set repo_dir [pwd]
set proj_name "lab03"
set proj_dir  "/home/wally/Documentos/Vivado/2024.1/$proj_name"
set part      "xc7a100tcsg324-1"

puts "==========================================="
puts "Creando proyecto Vivado Lab 3"
puts "  Repo: $repo_dir"
puts "  Proy: $proj_dir"
puts "==========================================="

## --- 0. Validacion de archivos ----------------------------------------------
set required_files [list \
    "rtl/bus/axil_defs.svh" \
    "rtl/bus/axil_interconnect.sv" \
    "rtl/core/picorv32.v" \
    "rtl/memory/rom_axil_with_ip.sv" \
    "rtl/memory/ram_axil_with_ip.sv" \
    "rtl/peripherals/gpio_leds_axil.sv" \
    "rtl/peripherals/gpio_sw_btn_axil.sv" \
    "rtl/peripherals/spi/spi_master.sv" \
    "rtl/peripherals/spi/spi_axil.sv" \
    "rtl/peripherals/uart/uart_axil.sv" \
    "rtl/peripherals/uart/uart_baud_gen.sv" \
    "rtl/peripherals/uart/uart_tx.sv" \
    "rtl/peripherals/uart/uart_rx.sv" \
    "rtl/util/synchronizer.sv" \
    "rtl/util/debouncer.sv" \
    "rtl/util/reset_sync.sv" \
    "rtl/top.sv" \
    "constraints/nexys4ddr.xdc" \
    "ip/clk_wiz_main.tcl" \
    "ip/rom_program.tcl" \
    "ip/data_ram.tcl" \
    "sim/tb_spi_master.sv" \
    "sim/tb_spi_axil.sv" \
    "sim/common/adxl362_stub.sv" \
    "sim/common/axil_master_bfm.sv" \
]



set missing 0
foreach f $required_files {
    if {![file exists $repo_dir/$f]} {
        puts "ERROR: falta archivo $repo_dir/$f"
        incr missing
    }
}
if {$missing > 0} {
    error "Abortando: $missing archivos faltan."
}
puts "OK: todos los archivos requeridos presentes."

## --- 1. Cerrar y borrar proyecto previo ------------------------------------
catch {close_project}
if {[file exists $proj_dir]} {
    puts "INFO: borrando proyecto previo $proj_dir"
    file delete -force $proj_dir
}

## --- 2. Crear proyecto ------------------------------------------------------
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

## --- 3. RTL de diseno -------------------------------------------------------
puts "\n\[1/5\] Agregando RTL..."

set design_files [list \
    "$repo_dir/rtl/bus/axil_defs.svh" \
    "$repo_dir/rtl/bus/axil_interconnect.sv" \
    "$repo_dir/rtl/core/picorv32.v" \
    "$repo_dir/rtl/memory/rom_axil_with_ip.sv" \
    "$repo_dir/rtl/memory/ram_axil_with_ip.sv" \
    "$repo_dir/rtl/peripherals/gpio_leds_axil.sv" \
    "$repo_dir/rtl/peripherals/gpio_sw_btn_axil.sv" \
    "$repo_dir/rtl/peripherals/spi/spi_master.sv" \
    "$repo_dir/rtl/peripherals/spi/spi_axil.sv" \
    "$repo_dir/rtl/peripherals/uart/uart_axil.sv" \
    "$repo_dir/rtl/peripherals/uart/uart_baud_gen.sv" \
    "$repo_dir/rtl/peripherals/uart/uart_tx.sv" \
    "$repo_dir/rtl/peripherals/uart/uart_rx.sv" \
    "$repo_dir/rtl/util/synchronizer.sv" \
    "$repo_dir/rtl/util/debouncer.sv" \
    "$repo_dir/rtl/util/reset_sync.sv" \
    "$repo_dir/rtl/top.sv" \
]

add_files -norecurse -fileset sources_1 $design_files

foreach f [get_files *.sv -of_objects [get_filesets sources_1]] {
    set_property file_type SystemVerilog $f
}
foreach f [get_files *.svh -of_objects [get_filesets sources_1]] {
    set_property file_type "Verilog Header" $f
    set_property is_global_include true $f
}

set_property include_dirs "$repo_dir/rtl/bus" [get_filesets sources_1]
set_property top top [get_filesets sources_1]

puts "      [llength $design_files] archivos RTL agregados"

## --- 4. Constraints ---------------------------------------------------------
puts "\n\[2/5\] Agregando constraints..."
add_files -fileset constrs_1 -norecurse "$repo_dir/constraints/nexys4ddr.xdc"

## --- 5. IPs (PLL + ROM + RAM) -----------------------------------------------
puts "\n\[3/5\] Creando IPs..."
source "$repo_dir/ip/clk_wiz_main.tcl"
source "$repo_dir/ip/rom_program.tcl"
source "$repo_dir/ip/data_ram.tcl"

## --- 6. Fileset de simulacion -----------------------------------------------
puts "\n\[4/5\] Configurando sim_1..."

set sim_files [list \
    "$repo_dir/sim/common/adxl362_stub.sv" \
    "$repo_dir/sim/common/axil_master_bfm.sv" \
    "$repo_dir/sim/tb_spi_master.sv" \
    "$repo_dir/sim/tb_spi_axil.sv" \
]

add_files -norecurse -fileset sim_1 $sim_files

foreach f [get_files *.sv -of_objects [get_filesets sim_1]] {
    set_property file_type SystemVerilog $f
}

# axil_defs.svh como global include en sim_1 (igual que en sources_1)
add_files -norecurse -fileset sim_1 "$repo_dir/rtl/bus/axil_defs.svh"
set_property file_type "Verilog Header" [get_files -of_objects [get_filesets sim_1] {axil_defs.svh}]
set_property is_global_include true     [get_files -of_objects [get_filesets sim_1] {axil_defs.svh}]

set_property include_dirs "$repo_dir/rtl/bus" [get_filesets sim_1]
set_property top tb_spi_master [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

puts "      [llength $sim_files] archivos de simulacion agregados"
puts "      Top de simulacion por defecto: tb_spi_master"

## --- 7. Compile order -------------------------------------------------------
puts "\n\[5/5\] Actualizando compile order..."
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n==========================================="
puts "Proyecto lab03 listo."
puts ""
puts "Para abrir en GUI:"
puts "  vivado $proj_dir/$proj_name.xpr &"
puts ""
puts "Testbenches disponibles (cambiar top en sim_1):"
puts "  tb_spi_master       <- top por defecto"
puts "  tb_spi_axil"
puts "==========================================="
