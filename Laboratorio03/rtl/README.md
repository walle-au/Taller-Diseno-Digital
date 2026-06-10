## Carpetas

### `bus/` — Bus AXI-Lite

Implementación del bus interno que conecta el core con todos los slaves del sistema. Sigue el estándar AXI4-Lite con 5 canales (AW, W, B, AR, R).

| Archivo | Descripción |
|---|---|
| `axil_defs.svh` | Header global con anchos del bus, mapa de memoria (bases y máscaras), códigos de respuesta AXI e índices de slaves. Marcado como **Global Include** en Vivado. |
| `axil_interconnect.sv` | Interconnect 1 master → 6 slaves. Decodificación combinacional de direcciones, FSMs independientes para read/write, generación de DECERR cuando la dirección no matchea. |

### `core/` — Procesador RISC-V

| Archivo | Descripción |
|---|---|
| `picorv32.v` | Core PicoRV32 (third-party, [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32)). Variante `picorv32_axi` con interfaz AXI-Lite master. Configurado para RV32I sin extensiones (sin M, sin C). |

### `memory/` — Memorias

| Archivo | Descripción |
|---|---|
| `rom_axil.sv` | ROM inferrable con `$readmemh`. Versión alternativa para simulación pura (no usada en síntesis). |
| `rom_axil_with_ip.sv` | **Wrapper AXI-Lite del IP `rom_program`** (Block Memory Generator de Vivado). 512 palabras × 32 bits, inicializado desde `main.coe`. Read-only: las escrituras devuelven SLVERR. |
| `ram_axil.sv` | RAM inferrable. Versión alternativa para simulación. |
| `ram_axil_with_ip.sv` | **Wrapper AXI-Lite del IP `data_ram`** (Block Memory Generator). 25600 palabras × 32 bits = 100 KiB, con byte write enable para soportar `sb`/`sh`. |

### `peripherals/` — Periféricos

| Archivo | Descripción |
|---|---|
| `gpio_leds_axil.sv` | Slave AXI-Lite para los 12 LEDs controlados por programa. Mapeado a `0x02004`. |
| `gpio_sw_btn_axil.sv` | Slave AXI-Lite RO para 16 switches + 4 botones. Incluye sincronizador 2-FF y debouncer de 10 ms. Mapeado a `0x02000`. |
| `uart/` | Subcarpeta con la implementación completa del UART (ver abajo). |
| `spi/` | Subcarpeta con el periférico SPI master para el ADXL362 (Lab 3, ver abajo). |

#### `peripherals/uart/`

| Archivo | Descripción |
|---|---|
| `uart_axil.sv` | Wrapper AXI-Lite del UART. Expone CTRL (`0x02010`), TX_DATA (`0x02018`) y RX_DATA (`0x0201C`). Maneja registros `send` y `new_rx` con la lógica de handshake del lab. |
| `uart_baud_gen.sv` | Generador de tick para TX. Tick cada 5208 ciclos a 50 MHz = 9600 baud. |
| `uart_tx.sv` | FSM transmisor 8N1. Estados: IDLE → START → DATA (×8) → STOP. |
| `uart_rx.sv` | FSM receptor 8N1 autosuficiente. Cuenta ciclos directamente (no usa tick externo) para evitar drift acumulado. Muestrea en el centro de cada bit. |

#### `peripherals/spi/` — SPI master (Lab 3)

Periférico nuevo del Lab 3. Comunica el core con el acelerómetro **ADXL362**
onboard de la Nexys4 DDR. SPI Mode 0 (CPOL=0, CPHA=0), 8 bits MSB-first.

| Archivo | Descripción |
|---|---|
| `spi_master.sv` | Núcleo SPI master. FSM de 3 estados `S_IDLE → S_LOW → S_HIGH`: presenta MOSI en `S_LOW`, muestrea MISO en el flanco de subida (`S_LOW→S_HIGH`) y desplaza en el de bajada. `SCLK = sysclk / (2 · clk_div)`. El control de CSn **no** está aquí (lo maneja el wrapper por software). |
| `spi_axil.sv` | Wrapper AXI-Lite del SPI. Expone CTRL (`0x02020`: `[0]` start/busy, `[3]` csn, `[11:4]` clk_div), TX (`0x02028`) y RX (`0x0202C`). Default `clk_div=4` → SCLK = 6.25 MHz. |

### `util/` — Utilitarios

| Archivo | Descripción |
|---|---|
| `synchronizer.sv` | Sincronizador de 2-FF parametrizable con atributo `ASYNC_REG = "TRUE"` para optimización de Vivado. Usado para entradas asíncronas (UART RX, switches, botones). |
| `debouncer.sv` | Anti-rebote de 10 ms para botones mecánicos. Cuenta ciclos a 50 MHz. |
| `reset_sync.sv` | Reset síncrono con asserción asíncrona y deasserción síncrona. 3 etapas de FF para minimizar metaestabilidad. |

### `top.sv`

Top-level del SoC. Instancia y conecta:

- PLL (clk_wiz_main): 100 MHz → 50 MHz
- `reset_sync`: maneja BTNC + locked del PLL
- `picorv32_axi` con `STACKADDR=0x58FFC` y `PROGADDR_RESET=0x0`
- `axil_interconnect` (1 master → 6 slaves)
- 6 slaves: ROM, RAM, GPIO_SW, GPIO_LED, UART, SPI
- `spi_axil` para el ADXL362 onboard (Lab 3)
- LEDs de debug en los 4 bits altos:
  - LED 12: `pll_locked`
  - LED 13: `rst_n`
  - LED 14: `core_trap`
  - LED 15: heartbeat (~1.5 Hz)

## Convenciones de código

- **SystemVerilog moderno**: `always_comb`, `always_ff`, tipo `logic`
- **Naming**: `snake_case` para señales, `MAYUSCULAS` para parámetros
- **Sufijos de I/O**: `_i` para entradas, `_o` para salidas (señales no-AXI)
- **Prefijos AXI**: `s_axi_` para slaves, `m_axi_` para masters
- **Reset**: activo-bajo, señal `s_axi_aresetn`
- **Diseño jerárquico**: cada bloque en su propio archivo con un módulo
- **Síntesis limpia**: sin latches inferidos, sin flip-flops no intencionales

## Mapa de memoria

| Dirección | Slave | Tipo | Tamaño |
|---|---|---|---|
| `0x00000 - 0x00FFF` | ROM | RO | 4 KiB |
| `0x02000` | GPIO_SW_BTN | RO | 1 word |
| `0x02004` | GPIO_LED | RW | 1 word |
| `0x02010` | UART_CTRL | RW | 1 word |
| `0x02018` | UART_TX | RW | 1 word |
| `0x0201C` | UART_RX | RO | 1 word |
| `0x02020` | SPI_CTRL | RW | 1 word (`[0]` start/busy, `[3]` csn, `[11:4]` clk_div) |
| `0x02028` | SPI_TX | RW | 1 word (byte a enviar) |
| `0x0202C` | SPI_RX | RO | 1 word (último byte recibido) |
| `0x40000 - 0x7FFFF` | RAM | RW | 256 KiB |

Las direcciones siguen el mapa de memoria del instructivo (Lab 2 + el bloque
SPI agregado en el Lab 3, definidas en `bus/axil_defs.svh`).

## Dependencias

- **Vivado 2024.1** o superior
- IPs requeridos (creados desde la GUI o con scripts en `../ip/`):
  - `clk_wiz_main` (Clocking Wizard, MMCM)
  - `rom_program` (Block Memory Generator, Single Port ROM, init desde `.coe`)
  - `data_ram` (Block Memory Generator, Single Port RAM, byte write enable)

## Testbenches

Los testbenches del Lab 3 están en `../sim/` (ver `../sim/README.md` para el
detalle de cada caso y cómo correrlos):

- `tb_spi_master.sv` — núcleo SPI: intercambio de 8 bits, conteo de flancos de
  SCLK, frecuencia 6.25 MHz, handshake `busy_o`/`done_o`.
- `tb_spi_axil.sv` — wrapper + modelo del ADXL362: defaults del CTRL, lectura de
  `DEVID_AD` (`0xAD`) y lectura ráfaga de XYZ.
- `common/adxl362_stub.sv` — modelo simplificado del ADXL362 (SPI Mode 0).
- `common/axil_master_bfm.sv` — BFM master AXI-Lite con tareas `axil_read`/`axil_write`.

Todos los testbenches son self-checking con un contador global de errores y una función `check(cond, msg)` para reportar resultados.
