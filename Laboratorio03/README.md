# SoC RISC-V con periférico SPI y sensor ADXL362

**Curso:** EL3313 Taller de Diseño Digital — I Semestre 2026
**Institución:** Escuela de Ingeniería Electrónica, Tecnológico de Costa Rica
**Profesor:** Kaled Alfaro Badilla, M.Sc.
**Autores:** Walter-Allan-Alexander-Esteban
**Tarjeta FPGA:** Digilent Nexys4 DDR (Artix-7 XC7A100T-1CSG324C)
**Herramientas:** Xilinx Vivado 2024.1, SystemVerilog, Python 3

---

## 1. Descripción del proyecto

Extensión del SoC RISC-V del Lab 2 con un periférico SPI master que comunica
el núcleo PicoRV32 con el acelerómetro **ADXL362** montado en la Nexys4 DDR.
El firmware lee los ejes X/Y/Z y los envía por UART a una aplicación Python
en la laptop que los usa como control de un juego tipo **Asteroids**.

## 2. Arquitectura

La arquitectura hereda el bus AXI4-Lite del Lab 2 y agrega un sexto slave (SPI):

### 2.1 Mapa de memoria

| Rango             | Tamaño  | Bloque            | Descripción                        |
|-------------------|---------|-------------------|------------------------------------|
| `0x00000–0x00FFF` | 4 KiB   | ROM               | Programa (512 palabras de 32 bits) |
| `0x02000`         | 4 B     | GPIO SW/BTN       | Registro de datos (RO)             |
| `0x02004`         | 4 B     | GPIO LEDs         | Registro de datos (RW)             |
| `0x02010`         | 4 B     | UART Control      | `[0]=send`, `[1]=new_rx`           |
| `0x02018`         | 4 B     | UART Data TX      | Dato a enviar                      |
| `0x0201C`         | 4 B     | UART Data RX      | Último dato recibido               |
| `0x02020`         | 4 B     | SPI Control       | `[0]=start/busy`, `[3]=csn`, `[11:4]=clk_div` |
| `0x02028`         | 4 B     | SPI TX            | Byte a enviar                      |
| `0x0202C`         | 4 B     | SPI RX            | Último byte recibido               |
| `0x40000–0x7FFFF` | 256 KiB | RAM (stack/heap)  | Datos                              |

### 2.2 Periférico SPI

- **Modo:** SPI Mode 0 (CPOL=0, CPHA=0), MSB-first
- **SCLK:** 6.25 MHz (sysclk / 8, dentro del límite de 8 MHz del ADXL362)
- **CSn:** controlado por software vía `SPI_CTRL[3]`
- **Pins FPGA:** `ACL_CSN`=D15, `ACL_MOSI`=F14, `ACL_MISO`=E15, `ACL_SCLK`=F15

### 2.3 Protocolo UART (FPGA → laptop)

Frame de 5 bytes enviado cada 10 ms:

```
+------+------+------+------+------+
| 0xAA |  X   |  Y   |  Z   | 0x55 |
+------+------+------+------+------+
```

Comandos laptop → FPGA: `'s'` = start streaming, `'p'` = pause, `'r'` = reset.

## 3. Estructura del repositorio

```
rtl/
  bus/           axil_defs.svh, axil_interconnect.sv
  core/          picorv32.v
  memory/        rom_axil*.sv, ram_axil*.sv
  peripherals/
    spi/         spi_master.sv, spi_axil.sv   ← nuevo en Lab 3
    uart/        uart_axil.sv, uart_baud_gen.sv, uart_tx.sv, uart_rx.sv
    gpio_leds_axil.sv, gpio_sw_btn_axil.sv
  util/          synchronizer.sv, debouncer.sv, reset_sync.sv
  top.sv
sim/
  common/        axil_master_bfm.sv, adxl362_stub.sv
  tb_spi_master.sv
  tb_spi_axil.sv
sw/
  asm/           blink.s          (smoke test)
                 devid_test.s     (Etapa 3: sanity SPI -> DEVID_AD en LEDs)
                 adxl_driver.s    (Etapa 4: driver completo, X en LEDs)
                 adxl_uart_stream.s (Etapa 5: streaming UART de XYZ)
  host/          visualizer.py    (Etapa 6a: barras + gráfica en vivo)
                 asteroids.py     (Etapa 6b: juego Asteroids con ADXL362)
  ld/            link.ld
  tools/         bin2coe.py
  build/         (salidas .elf/.bin/.o/main.coe)
  build.sh
ip/              clk_wiz_main.tcl, rom_program.tcl, data_ram.tcl
scripts/         create_project.tcl, impl_bitstream.tcl,
                 run_sim.tcl, synth_check.tcl
constraints/     nexys4ddr.xdc
docs/
  research.md    Decisiones de diseño previas al RTL
  figures/       FSM UART, diagramas
```

## 4. Cómo correr

### 4.1 Firmware en la FPGA (RV32 + ADXL362)

```bash
bash sw/build.sh sw/asm/adxl_uart_stream.s     # genera sw/build/main.coe
```

En Vivado, regenerar el IP `rom_program` (toma el `.coe` nuevo) y volver a
implementar:

```tcl
reset_target  all [get_ips rom_program]
generate_target all [get_ips rom_program]
synth_ip                 [get_ips rom_program]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

Después: `Open Hardware Manager` → `Program Device`.

### 4.2 Aplicación host (laptop)

```bash
sudo apt install python3-pygame python3-serial    # una vez

python3 sw/host/visualizer.py     # barras + gráfica X/Y/Z en vivo
python3 sw/host/asteroids.py      # juego controlado por la placa
```

Ambas apps abren `/dev/ttyUSB1` a 9600 8N1, mandan `'s'` para arrancar el
streaming, calibran 1 s (placa quieta) y descuentan el offset de gravedad.
Pasar otro puerto como `argv[1]` si es necesario. Teclas `c` (recalibrar),
`p`/`s` (pause/resume UART), `r` (reset sensor), `q`/`Esc` (salir).

## 5. Créditos y licencia

- **PicoRV32** por Claire Xenia Wolf (YosysHQ). Licencia ISC.
- Todo el código propio se distribuye bajo licencia MIT.
- Asistencia de IA en el desarrollo: ver `AI_USAGE.md`.

## 6. Referencias

1. Analog Devices. *ADXL362 Datasheet Rev D*, 2018.
2. Digilent. *Nexys 4 DDR FPGA Board Reference Manual*, 2016.
3. ARM. *AMBA AXI and ACE Protocol Specification* IHI 0022H, 2021.
4. Instructivo de laboratorio 3, EL3313, I-2026, TEC.
