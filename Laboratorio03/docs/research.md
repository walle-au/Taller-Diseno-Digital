# Investigación previa — Laboratorio 3

**Curso:** EL3313 Taller de Diseño Digital · I-2026
**Fecha:** 07/05/2026
**Autores:** Walter-Allan-Alexander-Esteban

Este documento congela las decisiones técnicas que guían el diseño antes de
escribir RTL/firmware. Cada decisión incluye la justificación y la cita
relevante del datasheet/spec.

---

## 1. Bus SPI — parámetros del enlace

### 1.1 Modo SPI

El ADXL362 funciona en **SPI Mode 0** (CPOL=0, CPHA=0):
- SCLK reposa en `0` (CPOL=0).
- Los datos se muestrean en el flanco de **subida** de SCLK (CPHA=0).
- MSB primero.

### 1.2 Frecuencia de SCLK

| Parámetro | Valor | Origen |
|---|---|---|
| Reloj de sistema | 50 MHz | PLL `clk_wiz_main` (Lab 2) |
| Máx SCLK ADXL362 | 8 MHz | Datasheet ADXL362, Tabla 1 |
| **SCLK elegido** | **6.25 MHz** | sysclk / 8 |

Divisor implementado en el periférico SPI (registro `SPI_CTRL[7:4]` = clock
divider). Default 8 (=6.25 MHz), modificable por software para depurar.

### 1.3 Framing

- **CSn**: activo bajo, controlado por software vía `SPI_CTRL[3]`. Se baja
  antes del comando, se mantiene durante todos los bytes de la transacción y
  se sube al final.
- **Tamaño de palabra**: 8 bits.
- **Orden**: MSB-first.

### 1.4 Pinout en la Nexys4 DDR (ADXL362 onboard)

El **ADXL362 viene montado de fábrica en la Nexys4 DDR** — la conexión al
FPGA es interna a la PCB de la tarjeta y está fijada por hardware.
No requiere PMOD externo ni cableado adicional.

Pines según el *Nexys 4 DDR Master XDC* oficial de Digilent:

| Señal       | Pin FPGA | Notas |
|---|---|---|
| `ACL_CSN`   | **D15** | Chip select activo bajo |
| `ACL_MOSI`  | **F14** | Master Out / Slave In |
| `ACL_MISO`  | **E15** | Master In / Slave Out |
| `ACL_SCLK`  | **F15** | SPI clock |
| `ACL_INT1`  | B13     | Interrupt 1 (no se usa en este lab) |
| `ACL_INT2`  | C16     | Interrupt 2 (no se usa en este lab) |

Estándar I/O: `LVCMOS33`. Estos seis pines deben descomentarse en
`constraints/nexys4ddr.xdc` durante la Etapa 3.

---

## 2. Sensor ADXL362 — configuración

### 2.1 Registros utilizados

| Dir  | Nombre        | Acceso | Uso en este lab |
|------|---------------|--------|-----------------|
| 0x00 | `DEVID_AD`    | RO | Sanity check al boot — debe leer `0xAD` |
| 0x01 | `DEVID_MST`   | RO | Debe leer `0x1D` (Analog Devices) |
| 0x02 | `PARTID`      | RO | Debe leer `0xF2` |
| 0x08 | `XDATA`       | RO | X axis 8-bit (±2g full scale) |
| 0x09 | `YDATA`       | RO | Y axis 8-bit |
| 0x0A | `ZDATA`       | RO | Z axis 8-bit |
| 0x2C | `FILTER_CTL`  | RW | Range = ±2g, ODR = 100 Hz |
| 0x2D | `POWER_CTL`   | RW | Measurement mode |

### 2.2 Comandos SPI

| Byte | Comando |
|------|---------|
| `0x0A` | Write register |
| `0x0B` | Read register |
| `0x0D` | Read FIFO (no se usa en este lab) |

Estructura de una transacción de lectura de 1 registro:
```
CSn↓  | 0x0B | <addr> | <dummy>→<data> | CSn↑
```

Estructura de una escritura:
```
CSn↓  | 0x0A | <addr> | <data> | CSn↑
```

Lectura ráfaga de XYZ (3 bytes consecutivos desde `XDATA`):
```
CSn↓  | 0x0B | 0x08 | <X> | <Y> | <Z> | CSn↑
```

### 2.3 Resolución elegida: 8-bit por eje

Usamos los registros de 8-bit (`0x08–0x0A`) en lugar de los de 12-bit
(`0x0E–0x13`) porque:
- Para un juego (asteroides) la precisión sub-bit es innecesaria.
- Reduce el frame UART a 5 bytes (vs. 8 bytes con 12-bit) — más holgura.
- Lectura ráfaga es 1 transacción SPI de 5 bytes (cmd+addr+3 datos) en vez
  de 1 de 8 bytes.
- Si en el futuro queremos más resolución, basta con cambiar la dirección
  base de la lectura ráfaga y ampliar el frame.

Con range = ±2g y 8-bit con signo, **1 LSB ≈ 15.6 mg**. Suficiente para
detectar inclinaciones de ~5° con margen.

### 2.4 Secuencia de inicialización

```
1. Read  DEVID_AD          → debe ser 0xAD  (verifica bus SPI)
2. Read  PARTID            → debe ser 0xF2
3. Write FILTER_CTL = 0x13 → range=±2g, ODR=100 Hz, half_BW=0
4. Write POWER_CTL  = 0x02 → measurement mode (MEASURE=10)
5. Esperar ~10 ms para que arranque el ADC
```

`FILTER_CTL = 0x13`:
- Bits [7:6] = `00` (range ±2g)
- Bit  [4]   = `1`  (HALF_BW: low-pass at ODR/4 — más estable)
- Bits [2:0] = `011` (ODR = 100 Hz)

Si los DEVID/PARTID no coinciden → SoC enciende todos los LEDs (error
visible) y queda en bucle infinito. Mecanismo de debug obvio.

---

## 3. Protocolo UART app ↔ FPGA

### 3.1 Parámetros físicos

Heredados del Lab 2 sin cambios:

| Parámetro | Valor |
|---|---|
| Baud rate | 9600 |
| Data bits | 8 |
| Parity    | None |
| Stop bits | 1 |
| Flow ctrl | None |

### 3.2 Verificación de ancho de banda

- **Tasa requerida**: 1 frame cada 10 ms = 100 frames/s.
- **Tamaño del frame**: 5 bytes (ver 3.3).
- **Carga útil**: 5 × 100 = 500 bytes/s.
- **Capacidad UART 9600 8N1**: 9600 / 10 = 960 B/s.
- **Margen**: ~48% libres → válido sin tocar el baud rate.

### 3.3 Formato del frame FPGA → laptop

```
+------+------+------+------+------+
| 0xAA |  X   |  Y   |  Z   | 0x55 |
+------+------+------+------+------+
  start  s8     s8     s8    end
```

- `0xAA` (10101010₂): byte de inicio. Sincronización fácil de detectar.
- `X, Y, Z`: enteros con signo de 8 bits (two's complement) — directos del
  ADXL362.
- `0x55` (01010101₂): byte de fin. Permite detectar desincronización.

> Ningún byte de payload puede coincidir simultáneamente con `0xAA` Y `0x55`,
> pero sí puede coincidir con uno de ellos. Por eso se usa el par `start`+`end`
> como marco redundante. Si la app recibe `0xAA … 0x55` con offset incorrecto,
> sabe que perdió sync y puede esperar al próximo `0xAA` que vaya seguido por
> 3 bytes y luego `0x55`.

### 3.4 Formato del frame laptop → FPGA (control)

| Byte | Significado |
|------|-------------|
| `0x73` (`'s'`) | START — la FPGA empieza a transmitir |
| `0x70` (`'p'`) | PAUSE — la FPGA deja de transmitir |
| `0x72` (`'r'`) | RESET — la FPGA reinicia el contador interno |

Los bytes son ASCII imprimibles para que el debug con `minicom` o `screen`
sea trivial: el operador puede teclear `s`, `p`, `r` directamente.

### 3.5 Diagrama de secuencia

```
Laptop                              FPGA (RV32 + ADXL362)
  |                                    |
  |---- 's' (START) ------------------>|  arma flag streaming=1
  |                                    |
  |<--- 0xAA X Y Z 0x55 (frame 1) -----|  cada 10 ms
  |<--- 0xAA X Y Z 0x55 (frame 2) -----|
  |<--- 0xAA X Y Z 0x55 (frame 3) -----|
  |              ...                   |
  |---- 'p' (PAUSE) ------------------>|  streaming=0
  |                                    |
```

---

## 4. Aplicación de laptop — *Asteroids-like*

### 4.1 Concepto

Juego clásico tipo Asteroids: una nave en pantalla que rota, acelera, y
dispara contra meteoritos. La Nexys4 DDR es el control.

### 4.2 Mapeo de ejes

| Eje del ADXL362 | Acción en el juego | Cómo se calcula |
|---|---|---|
| **X** (inclinación lateral) | Rotación de la nave | Ángulo proporcional a `X`, con zona muerta para gravedad residual (`abs(X) < 0x10` ⇒ 0). |
| **Y** (inclinación adelante/atrás) | Empuje / freno | `Y > +0x20` ⇒ thrust, `Y < -0x20` ⇒ freno. |
| **Z** (eje vertical) | Disparo (detección de "shake") | Si `|ΔZ entre frames| > umbral` durante <2 frames ⇒ disparo. Equivale a un golpecito vertical. |

Botones físicos auxiliares (vía GPIO_SW_BTN ya disponible en Lab 2):
- `BTNC` — disparo redundante (más fiable que el shake al inicio).
- `SW0` — pausar el juego.

> El acceso a botones requiere una segunda vía de comunicación o codificarlos
> dentro del frame UART. **Decisión:** mantener el frame fijo en 5 bytes y
> manejar todo el input en SW; los botones serán solo de debug local (LEDs).

### 4.3 Stack tecnológico de la app

- **Lenguaje:** Python 3.11
- **Gráficos:** `pygame`
- **Serial:** `pyserial`
- **Estructura:** hilo lector de UART + hilo principal de juego @ 60 FPS,
  comunicados por una `queue.Queue` thread-safe.

### 4.4 Calibración

Al arrancar, la nave permanece quieta durante 1 s mientras la app promedia
los valores X/Y/Z recibidos. Ese promedio se usa como **offset de gravedad**
(la placa probablemente queda en la mesa con Z apuntando al techo, gravedad
residual en X/Y por imperfecciones del montaje). Restamos el offset en cada
frame antes de mapear.

---

## 5. Resumen de decisiones (cheat sheet)

| Tema | Decisión |
|---|---|
| SPI mode | 0 (CPOL=0, CPHA=0) |
| SCLK | 6.25 MHz (sysclk/8) |
| ADXL362 range | ±2g |
| ADXL362 ODR | 100 Hz |
| Resolución | 8-bit/eje (registros `XDATA`/`YDATA`/`ZDATA`) |
| Frame UART | `0xAA X Y Z 0x55` (5 bytes) |
| Tasa | 100 frames/s (1 cada 10 ms) |
| Baud | 9600 8N1 (ya en Lab 2) |
| Comandos laptop→FPGA | `'s'` start, `'p'` pause, `'r'` reset |
| App | Asteroids-like en Python + pygame |
| Mapeo | X→rotación, Y→thrust, Z→disparo (shake) |

---

## 6. Referencias

1. Analog Devices. *ADXL362 — Micropower, 3-Axis, ±2g/±4g/±8g Digital Output
   MEMS Accelerometer*. Datasheet Rev D, 2018.
2. Digilent. *Nexys 4 DDR FPGA Board Reference Manual*, 2016.
3. Digilent. *PmodACL2 Reference Manual*. (Evaluation board del ADXL362).
4. Motorola. *SPI Block Guide V04.01*, 2003. (Modos CPOL/CPHA estándar).
5. Instructivo de laboratorio 3, EL3313, I-2026, TEC.
