# Registro de asistencia con Inteligencia Artificial

Este documento registra de forma transparente el uso de herramientas de IA
generativa durante el desarrollo de este proyecto

## Políticas seguidas

1. **Toda línea de código generada con IA fue revisada y comprendida por el
   autor** antes de incorporarla al proyecto. No se incluyó código cuya
   funcionalidad no se entienda plenamente.
2. Las **decisiones de arquitectura** (mapa de memoria, selección del core
   `picorv32_axi`, número de slaves AXI-Lite, convención de señales) fueron
   tomadas por el autor.
3. Los **testbenches** se validaron ejecutándolos en Vivado XSim; los casos
   de prueba críticos se diseñaron manualmente.
4. La IA se usó principalmente como asistente de (a) generación de esqueletos,
   (b) revisión y debug de bugs, (c) explicación de estándares (AXI-Lite,
   ABI RISC-V, timing en FPGAs), (d) apoyo en el bring-up de hardware.

## Herramientas utilizadas

- **Claude (Anthropic)** — modelos Claude Sonnet 4.6 y Claude Opus 4 (vía
  claude.ai, en múltiples sesiones a lo largo del desarrollo).

## Registro por archivo

### RTL — Lógica sintetizable

| Archivo | Tipo de asistencia | Alcance de la IA | Validación del autor |
|---|---|---|---|
| `rtl/top.sv` | Generación + debug extenso en HW | Esqueleto de instanciación, conexión del bus, fix de LEDs de debug (`pll_locked`, `rst_n`, `core_trap`). **Lab 3:** instanciación de `spi_axil` como 6.º slave y exposición de los pines `acl_csn/mosi/miso/sclk` hacia el ADXL362 onboard | Revisado manualmente; probado en FPGA Nexys4 DDR hasta validación completa |
| `rtl/bus/axil_defs.svh` | Generación | Parámetros globales del bus y mapa de memoria (`NUM_SLAVES`, `SLAVE_IDX_*`, rangos de direcciones). **Lab 3:** ampliado a 6 slaves (agregado `SLAVE_IDX_SPI` en `0x02020`) | Revisado; contrastado con el mapa de memoria del enunciado |
| `rtl/bus/axil_interconnect.sv` | Generación + debug | Decoder 1M→N con lógica DECERR para direcciones no mapeadas. **Lab 3:** parametrización generaliza a 6 slaves sin cambios estructurales | Testbench manual: 36/36 checks; simulado con rutas a todos los slaves |
| `rtl/peripherals/spi/spi_master.sv` | Generación + revisión | FSM SPI Mode 0, 8 bits, MSB-first, con divisor de reloj parametrizable. Latencia y forma de onda revisadas en simulación con `tb_spi_master.sv` | Testbench manual + verificación contra datasheet ADXL362 (CPOL/CPHA, t_setup, t_hold) |
| `rtl/peripherals/spi/spi_axil.sv` | Generación | Wrapper AXI-Lite del SPI master. Registros `SPI_CTRL` (start/busy + csn + clk_div), `SPI_TX`, `SPI_RX`. Patrón de pulso start↗ (1 ciclo) reutilizado de `uart_axil` | Testbench manual `tb_spi_axil.sv`; validado contra `adxl362_stub` (loopback DEVID_AD = 0xAD) y en HW |
| `rtl/core/picorv32.v` | **Sin IA** — terceros | Core RV32I de YosysHQ (repositorio público); solo se seleccionó la variante `picorv32_axi` | Parámetros revisados contra documentación oficial de YosysHQ |
| `rtl/memory/rom_axil.sv` | Generación | Wrapper AXI-Lite con `$readmemh` (versión inferrable para simulación) | No usado en síntesis; validado en sim |
| `rtl/memory/ram_axil.sv` | Generación | Wrapper AXI-Lite con byte-write-enable inferrable | No usado en síntesis; validado en sim |
| `rtl/memory/rom_axil_with_ip.sv` | Generación | Wrapper que adapta el IP `rom_program` (Block Memory Generator) a AXI-Lite | Probado en FPGA; depurado el problema de cache del IP en Vivado |
| `rtl/memory/ram_axil_with_ip.sv` | Generación | Wrapper que adapta el IP `data_ram` a AXI-Lite con byte-enables | Probado en FPGA |
| `rtl/peripherals/gpio_leds_axil.sv` | Generación | Registro de 12 bits RW mapeado en AXI-Lite | Testbench manual: 7/7 checks |
| `rtl/peripherals/gpio_sw_btn_axil.sv` | Generación | Switches (16) + botones (4), con sincronizador 2FF y debounce 10 ms | Testbench manual: 4/4 checks; probado en FPGA con switches físicos |
| `rtl/peripherals/uart/uart_axil.sv` | Generación | Wrapper AXI-Lite para TX/RX; registros CTRL, TX, RX; auto-clear de `send` | Testbench manual: 7/7 checks |
| `rtl/peripherals/uart/uart_baud_gen.sv` | Generación | Generador de `tx_tick` a partir de `CLK_FREQ_HZ` y `BAUD_RATE` | Validado calculando divisor manualmente para 50 MHz / 9600 baud |
| `rtl/peripherals/uart/uart_tx.sv` | **Sin IA** — reutilizado de Lab 1 | — | — |
| `rtl/peripherals/uart/uart_rx.sv` | Revisión y reescritura | RX original usaba tick 16× separado con drift acumulado; reescrito con `BIT_PERIOD` en ciclos de reloj directos | Testbench de loopback: 8 bytes OK; probado en FPGA |
| `rtl/util/synchronizer.sv` | **Sin IA** | — | — |
| `rtl/util/debouncer.sv` | Revisión parcial | Explicación del cálculo del contador para 50 MHz / 10 ms | Parámetros recalculados manualmente (`DEBOUNCE_CYCLES = 500_000`) |
| `rtl/util/reset_sync.sv` | Generación | Reset async-assert, sync-deassert con 3 etapas; atributo `ASYNC_REG` | Revisado; comportamiento verificado en simulación |

### Simulación

| Archivo | Tipo de asistencia | Alcance de la IA | Validación del autor |
|---|---|---|---|
| `sim/common/axil_master_bfm.sv` | Generación | Bus Functional Model AXI-Lite para testbenches (tareas `axil_write`, `axil_read`) | Validado comparando transacciones contra IP de Xilinx en sim |
| `sim/common/adxl362_stub.sv` | Generación + revisión | Modelo simple del ADXL362 que responde sólo a `0x0B 0x00` (READ DEVID_AD) devolviendo `0xAD`, suficiente para cerrar el loop SPI en sim | Validado contra `tb_spi_axil.sv`; respuesta confirmada bit a bit |
| `sim/tb_axil_interconnect.sv` | Generación parcial + asserts manuales | Estructura general; stimulus y verificación de DECERR | 36/36 checks; casos de error de dirección escritos por el autor |
| `sim/tb_gpio_leds_axil.sv` | Generación parcial | Estructura del testbench | 7/7 checks |
| `sim/tb_gpio_sw_btn_axil.sv` | Generación parcial | Estructura + debounce acelerado por parámetro | 4/4 checks |
| `sim/tb_uart_axil.sv` | Generación parcial | Estructura; casos TX, RX, send auto-clear | 7/7 checks |
| `sim/tb_uart_loopback.sv` | Generación parcial | Loopback de 8 bytes con verificación byte a byte | 8/8 bytes OK (0x5A, 0xA5, 0x00, 0xFF, 0x01, 0x80, 0x55, 0xAA) |
| `sim/tb_spi_master.sv` | Generación parcial | Cobertura de la FSM SPI sola: clock divider, polaridad, latching de MISO en flanco correcto | Forma de onda revisada en XSim |
| `sim/tb_spi_axil.sv` | Generación parcial | Wrapper + stub ADXL: transacción completa READ DEVID_AD vía registros AXI-Lite | Resultado `SPI_RX = 0xAD` verificado |

### Software (ensamblador RISC-V)

| Archivo | Tipo de asistencia | Alcance de la IA | Validación del autor |
|---|---|---|---|
| `sw/asm/hello_blink.s` | Generación completa | Programa de test: envía "READY\r\n" por UART, refleja switches en LEDs, hace echo de bytes recibidos | Usado durante el bring-up completo del SoC; validado en FPGA |
| `sw/asm/calc.s` | Generación completa | Calculadora UART: parseo de operandos (hasta 4 dígitos), suma/resta, eco de entrada, `print_int` con división por restas repetidas (RV32I puro, sin extensión M) | Revisado línea a línea por el autor; validado en FPGA |
| `sw/asm/devid_test.s` | Generación | **Lab 3 Etapa 3:** secuencia SPI inline (sin subrutinas) que lee `DEVID_AD` (0x00) del ADXL362 y muestra el byte en LEDs. Smoke test del bus AXI-Lite + nuevo periférico SPI | Validado en FPGA: LEDs `1010_1101` = 0xAD confirmado |
| `sw/asm/adxl_driver.s` | Generación | **Lab 3 Etapa 4:** driver completo en ASM con subrutinas `spi_xfer`, `adxl_read_reg`, `adxl_write_reg`, `adxl_read_xyz`, `adxl_init`, calling convention RV32 estándar (`jal ra` / `jalr x0, 0(ra)`, stack alineado a 4). Muestra X en LED[7:0] | Validado en FPGA: LEDs reaccionan a tilt de la placa, init OK confirmado por LED11..8 = 0xF |
| `sw/asm/adxl_uart_stream.s` | Generación | **Lab 3 Etapa 5:** extiende el driver con `uart_send_byte` (read-modify-write para conservar `new_rx`) y `uart_poll_cmd`. Loop principal manda frames `0xAA X Y Z 0x55` a 100 Hz si streaming=1; comandos `'s'`/`'p'`/`'r'` cambian estado | Validado con `xxd /dev/ttyUSB1` + `printf` (frames con delimitadores correctos, comandos responsive) |
| `sw/build/main.coe` | Generado por toolchain | Salida del ensamblador convertida a formato COE para Block Memory Generator | Verificado comparando primeras y últimas palabras con el fuente ASM |

### Aplicación host (Python)

| Archivo | Tipo de asistencia | Alcance de la IA | Validación del autor |
|---|---|---|---|
| `sw/host/visualizer.py` | Generación | **Lab 3 Etapa 6a:** lector UART en hilo (`FrameReader` con sincronización por delimitadores `0xAA`/`0x55`) + visualizador pygame (3 barras X/Y/Z + gráfica de scroll de los últimos 2 s). Calibración de 1 s al arranque resta offset de gravedad residual | Probado en HW: offsets razonables, `bad_frames = 0`, gráficas responden a movimiento real de la placa |
| `sw/host/asteroids.py` | Generación | **Lab 3 Etapa 6b:** juego Asteroids clásico con wrap-around toroidal. Mapeo X→rotación (con deadzone), Y→thrust, \|ΔZ\|→disparo (shake detection con cooldown). Fallback de teclado para testing sin placa | Probado completo en HW: rompe asteroides en cadena (L→M→S), game over + restart funcionales, control responsive |

### IP, scripts y restricciones

| Archivo | Tipo de asistencia | Alcance de la IA | Validación del autor |
|---|---|---|---|
| `ip/clk_wiz_main.tcl` | Generación | Configuración del PLL Clocking Wizard (100 MHz → 50 MHz) | Verificado contra Product Guide PG065 de Xilinx |
| `ip/rom_program.tcl` | Generación | Block Memory Generator configurado como ROM simple-puerto con archivo `.coe` | Depurado extensamente; resuelto problema de cache de IP en Vivado |
| `ip/data_ram.tcl` | Generación | Block Memory Generator como RAM con byte-write-enable de 4 bits | Verificado contra Product Guide PG058 |
| `scripts/create_project.tcl` | Generación | Script Vivado que crea el proyecto, agrega fuentes, IPs y restricciones desde cero | Ejecutado múltiples veces; funcional en Vivado 2024.1 |
| `scripts/impl_bitstream.tcl` | Generación | Re-corre `impl_1 -to_step write_bitstream` en batch sobre el proyecto ya creado, útil para iterar sólo en firmware sin rebuild de RTL | Probado en headless |
| `scripts/synth_check.tcl` | Generación | Verificación rápida de síntesis sin completar impl | Usado en CI local |
| `scripts/run_sim.tcl` | Generación | Lanza XSim sobre un testbench específico | Útil durante bring-up de los testbenches SPI |
| `constraints/nexys4ddr.xdc` | **Sin IA** — referencia Digilent | Pines tomados del XDC oficial de Digilent para Nexys4 DDR. **Lab 3:** descomentados los pines `ACL_CSN`/`MOSI`/`MISO`/`SCLK` (D15/F14/E15/F15) hacia el ADXL362 onboard | Verificado pin a pin contra el manual de la placa |
| `docs/research.md` | Generación + revisión extensa | **Lab 3:** documento de decisiones técnicas previas al RTL (SPI mode, SCLK, framing, registros ADXL, frame UART, protocolo de comandos, mapeo a Asteroids, cálculo de ancho de banda) | Cada decisión revisada contra el datasheet del ADXL362 y el manual de la Nexys4 DDR |
| `AI_USAGE.md` | Plantilla + actualización | Estructura del documento | Contenido completado honestamente por el autor |
| `README.md` | Generación de plantilla | Estructura del documento | Contenido técnico adaptado por el autor |

## Problemas detectados en código generado por IA y corregidos

Durante el desarrollo se identificaron y corrigeron los siguientes errores en
código producido por IA:

1. **Handshake AXI-Lite incorrecto**: `awready`/`wready` no se deasserteaban
   correctamente durante la fase `bvalid`, lo que hubiera causado deadlock en
   transacciones consecutivas.
2. **Drift acumulado en UART RX**: el receptor original usaba un generador de
   tick 16× independiente; los divisores no enteros generaban desviación
   acumulada. Solución: reescribir con `BIT_PERIOD` en ciclos de reloj directos.
3. **Incompatibilidad con XSim 2024.1**: asignaciones NBA a arrays asociativos
   no soportadas; resuelto usando asignación bloqueante en los BFMs de sim.
4. **`fork`/`join_any` en XSim**: fallaban silenciosamente; reemplazados por
   polling plano con contador de seguridad.
5. `` `default_nettype none `` en síntesis**: causaba errores "net type must be
   explicitly specified" en picorv32.v (terceros); removido de todos los
   archivos `.sv` propios.
6. **Cache del IP `rom_program` en Vivado**: el checkpoint `.dcp` del IP no se
   regeneraba aunque el `.coe` cambiara; resuelto borrando manualmente
   `.gen/sources_1/ip/rom_program*/` y forzando `generate_target all` +
   `synth_ip`.
7. **`core_pc` nunca actualizado en `top.sv`**: el bloque `always_ff` sin
   rama `else` dejaba el registro en cero permanentemente; corregido
   conectando señales de diagnóstico reales (`pll_locked`, `rst_n`,
   `core_trap`) a los LEDs de debug.
8. **Lab 3 – RX UART gateado durante TX hacía perder comandos**: el wrapper
   `uart_axil.sv` (línea 174) sólo levanta `new_rx` cuando `!tx_busy && !send`,
   para evitar crosstalk de la línea TX hacia el sincronizador RX. Detectado
   en HW al ver que `'p'` no pausaba el stream ~50% de las veces (cae en la
   ventana de TX de los 5 bytes del frame). Workaround del lado host: enviar
   cada comando como ráfaga de 3 bytes (`reader.send(b"ppp")` etc.) — garantiza
   que al menos uno aterrice en ventana abierta. Ver `sw/host/visualizer.py`
   y `sw/host/asteroids.py`.
9. **Lab 3 – SPI start sin auto-clear repetía la transferencia**: detectado
   preventivamente al portar el patrón de `uart_axil.sv`. El bit `start` del
   registro `SPI_CTRL` se baja vía `spi_done && reg_ctrl_start_q` en
   `spi_axil.sv`, y se genera un pulso de 1 ciclo en flanco de subida con un
   delay de 1 etapa (`reg_ctrl_start_d1`). Sin esto el master volvería a ver
   `start=1` después del done y arrancaría una segunda transferencia con el
   mismo byte.

## Resumen cualitativo

La IA aceleró significativamente la escritura de boilerplate (interfaces
AXI-Lite, scripts TCL, estructura de testbenches, rutinas UART en
ensamblador). Sin embargo, el **trabajo de diseño** — arquitectura del SoC,
mapa de memoria, selección del core, convención de señales, orden del
bring-up, decisiones de debug en hardware — fue realizado por el autor.

Los errores listados arriba refuerzan que el código generado por IA requiere
revisión crítica antes de usarse: ninguno hubiera sido detectado por la misma
IA que lo generó sin un testbench o prueba en hardware que lo ejercitara.

## Declaración

El autor asume **responsabilidad completa** por todo el código contenido en
este repositorio, independientemente de su origen, y declara comprender cada
línea entregada.

Walter-Alexander-Esteban-Allan — 12 de mayo de 2026
