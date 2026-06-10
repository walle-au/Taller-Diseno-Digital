# Simulación — Testbenches del Lab 3

Pruebas self-checking del periférico SPI agregado en el Lab 3. Cada testbench
lleva un contador global de errores y usa `check(cond, msg)` para reportar
PASS/FAIL; el TB termina con un resumen y código de salida distinto de cero si
algún check falla.

## Contenido

| Archivo | Qué prueba |
|---|---|
| `tb_spi_master.sv` | Núcleo `spi_master`. (1) Transacción de 8 bits con `tx_data=0x5A` contra un slave-stub que responde `0xA5`. (2) `rx_data_o == 0xA5`. (3) Exactamente 8 flancos de subida de SCLK. (4) `SCLK = sysclk/(2·clk_div) = 6.25 MHz`. (5) `busy_o` sube al iniciar y baja con el pulso `done_o`. |
| `tb_spi_axil.sv` | Wrapper `spi_axil` + modelo del ADXL362. **T1:** estado por defecto (`csn=1`, `clk_div=4`). **T2:** asserta CSn y lee `DEVID_AD` enviando `0x0B, 0x00, dummy` → `SPI_RX == 0xAD`. **T3:** lectura ráfaga de `XDATA/YDATA/ZDATA` en una sola activación de CSn → `{0x12, 0x34, 0x56}`. |

### `common/` — Modelos reutilizables

| Archivo | Descripción |
|---|---|
| `adxl362_stub.sv` | Modelo simplificado del ADXL362 para simulación: SPI Mode 0, comandos `0x0A` (write) / `0x0B` (read), auto-incremento de dirección en ráfaga. Registros emulados: `DEVID_AD=0xAD`, `DEVID_MST=0x1D`, `PARTID=0xF2`, `XDATA=0x12`, `YDATA=0x34`, `ZDATA=0x56`. No modela timing real, FIFO ni interrupciones. |
| `axil_master_bfm.sv` | Bus Functional Model de master AXI-Lite. Expone tareas bloqueantes `axil_write(addr,data,strb,resp)`, `axil_read(addr,data,resp)` y `axil_write_simple(addr,data,resp)`. No sintetizable. |

## Cómo correr las simulaciones

Con Vivado (modo proyecto o batch), usando el script del repo:

```tcl
cd /ruta/al/repo/Laboratorio03
source scripts/run_sim.tcl
```

O en batch desde la terminal:

```bash
vivado -mode batch -source scripts/run_sim.tcl
```

El script compila los fuentes RTL de `../rtl/`, los modelos de `common/` y el
testbench seleccionado, y corre la simulación reportando el resumen de checks.


