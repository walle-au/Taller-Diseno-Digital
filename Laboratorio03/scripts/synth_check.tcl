## ============================================================================
## scripts/synth_check.tcl
## Crea el proyecto y lanza synth_1 para verificar que la base sintetiza.
## Uso: vivado -mode batch -source scripts/synth_check.tcl
## ============================================================================

source scripts/create_project.tcl

puts "==========================================="
puts "Lanzando synth_1..."
puts "==========================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set status [get_property STATUS [get_runs synth_1]]
puts "==========================================="
puts "synth_1 STATUS: $status"
puts "==========================================="

if {[string match "*Complete*" $status] && ![string match "*ERROR*" $status]} {
    puts "OK: sintesis completada sin errores."
    exit 0
} else {
    puts "ERROR: sintesis fallo. Revisar el log."
    exit 1
}
