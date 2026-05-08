## ============================================================================
## scripts/impl_bitstream.tcl
## Abre el proyecto lab03 (creado por create_project.tcl) y corre impl_1
## hasta write_bitstream. Espera a que termine y reporta estado.
##
## Uso: vivado -mode batch -source scripts/impl_bitstream.tcl
##
## Pre-requisitos:
##   - El proyecto /home/wally/Documentos/Vivado/2024.1/lab03/lab03.xpr existe
##     (creado por scripts/create_project.tcl o scripts/synth_check.tcl).
##   - synth_1 ya corrió y quedó "Complete" (si no, impl_1 lo dispara solo).
##
## Salida:
##   - Bitstream en:
##     /home/wally/Documentos/Vivado/2024.1/lab03/lab03.runs/impl_1/top.bit
## ============================================================================

set proj_xpr "/home/wally/Documentos/Vivado/2024.1/lab03/lab03.xpr"

if {![file exists $proj_xpr]} {
    error "No existe $proj_xpr. Corré antes scripts/create_project.tcl."
}

open_project $proj_xpr

puts "==========================================="
puts "Lanzando impl_1 -to_step write_bitstream..."
puts "==========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
puts "==========================================="
puts "impl_1 STATUS: $status"
puts "==========================================="

if {[string match "*write_bitstream Complete*" $status] && \
    ![string match "*ERROR*" $status]} {
    set bit "/home/wally/Documentos/Vivado/2024.1/lab03/lab03.runs/impl_1/top.bit"
    if {[file exists $bit]} {
        puts "OK: bitstream generado:"
        puts "    $bit"
    } else {
        puts "WARN: STATUS dice OK pero $bit no existe."
    }
    exit 0
} else {
    puts "ERROR: impl_1 no completó write_bitstream. Revisar el log."
    exit 1
}
