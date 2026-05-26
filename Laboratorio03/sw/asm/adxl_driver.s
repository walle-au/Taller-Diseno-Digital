# =============================================================================
# Archivo      : sw/asm/adxl_driver.s
# Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
# Lab 3 Etapa 4: Driver del acelerómetro ADXL362 en ensamblador RV32I.
#
# Refactoriza la transacción inline de devid_test.s en subrutinas reutilizables
# llamables vía `jal ra, ...` / `jalr x0, 0(ra)`. Sienta la base para la
# Etapa 5 (streaming UART): el `_start` actual sólo muestra el eje X en los
# LEDs como feedback visual, pero `adxl_read_xyz` ya entrega los 3 bytes en
# un buffer listo para empaquetar en el frame UART (`0xAA X Y Z 0x55`).
#
# API expuesta (todas siguen la calling convention RV32 estándar):
#
#   spi_xfer(a0=byte_tx)            -> a0=byte_rx
#       Una transferencia SPI de 8 bits. Bloquea hasta SPI_CTRL.busy=0.
#       Clobbers: t0, t1.
#
#   spi_cs_low()  /  spi_cs_high()
#       Bajan/suben CSn (manteniendo el clock divider por defecto).
#       Clobbers: t0, t1.
#
#   adxl_read_reg(a0=addr)          -> a0=valor
#       Lee 1 registro del ADXL362 (secuencia: CSn↓ | 0x0B | addr | 00 | CSn↑).
#
#   adxl_write_reg(a0=addr, a1=val)
#       Escribe 1 registro (CSn↓ | 0x0A | addr | val | CSn↑).
#
#   adxl_read_xyz(a0=ptr_buf3)
#       Lectura ráfaga de XDATA/YDATA/ZDATA en 1 transacción SPI.
#       Escribe 3 bytes (X, Y, Z) en *a0..a0+2.
#
#   adxl_init()                     -> a0=0 OK, a0!=0 fallo
#       1. Sanity-check DEVID_AD (0xAD) y PARTID (0xF2).
#       2. FILTER_CTL = 0x13  (range=±2g, HALF_BW=1, ODR=100 Hz).
#       3. POWER_CTL  = 0x02  (measurement mode).
#       4. Espera ~10 ms para que arranque el ADC.
#
#   delay_cycles(a0=iters)
#       Loop ocupado de ~iters iteraciones (≈ 5 ciclos/iter en picorv32).
#
# _start: inicializa SP, llama adxl_init y, en bucle, hace adxl_read_xyz y
# pinta X en LED[7:0] (los LED[11:8] quedan en 0xF como indicador de
# "init OK"). Si init falla -> los 12 LEDs encendidos + hang.
#
# Mapa de registros usado (ver axil_defs.svh):
#   0x02004  GPIO_LED
#   0x02020  SPI_CTRL   bit0=start/busy, bit3=csn, bits[11:4]=clk_div
#   0x02028  SPI_TX     [7:0] dato a enviar
#   0x0202C  SPI_RX     [7:0] último byte recibido
# =============================================================================

    # ---- Mapa de I/O ---------------------------------------------------------
    .equ GPIO_LED,        0x02004
    .equ SPI_CTRL,        0x02020
    .equ SPI_TX,          0x02028
    .equ SPI_RX,          0x0202C

    # ---- Patrones de SPI_CTRL (clk_div=4 -> SCLK 6.25 MHz) -------------------
    .equ CTRL_IDLE,       0x048      # csn=1, start=0, div=4 (deselected)
    .equ CTRL_SEL,        0x040      # csn=0, start=0, div=4 (CSn asserted)
    .equ CTRL_GO,         0x041      # csn=0, start=1, div=4 (dispara xfer)

    # ---- Registros del ADXL362 ----------------------------------------------
    .equ ADXL_DEVID_AD,   0x00
    .equ ADXL_PARTID,     0x02
    .equ ADXL_XDATA,      0x08       # base de la ráfaga X/Y/Z (8-bit)
    .equ ADXL_FILTER_CTL, 0x2C
    .equ ADXL_POWER_CTL,  0x2D

    # ---- Comandos SPI del ADXL362 -------------------------------------------
    .equ ADXL_CMD_WRITE,  0x0A
    .equ ADXL_CMD_READ,   0x0B

    # ---- Valores esperados / configuración ----------------------------------
    .equ ADXL_ID_AD,      0xAD       # DEVID_AD
    .equ ADXL_ID_PART,    0xF2       # PARTID
    .equ FILTER_CTL_VAL,  0x13       # range=±2g, HALF_BW=1, ODR=100 Hz
    .equ POWER_CTL_VAL,   0x02       # measurement mode (MEASURE=10)

    # ---- Top del stack: tope alineado de la RAM (100K en 0x40000..0x59000) --
    .equ STACK_TOP,       0x58FFC

    # ---- Iteraciones del busy-wait para ~10 ms a 50 MHz --------------------
    # ~5 ciclos por iter en picorv32 -> 100_000 iter * 5 ciclos / 50e6 ≈ 10 ms.
    .equ DELAY_10MS,      100000

    .section .text
    .globl  _start

# =============================================================================
# _start
# =============================================================================
_start:
    li      sp, STACK_TOP            # inicializar stack para call/ret

    # Apagar todos los LEDs por si quedó algo del bring-up previo.
    li      t0, GPIO_LED
    sw      zero, 0(t0)

    # Inicializar el ADXL362 (verifica IDs + configura modo measurement).
    jal     ra, adxl_init
    bnez    a0, init_error           # a0 != 0 -> falló sanity check

    # Init OK: LED[11:8] = 0xF como "ready" (los 4 LEDs altos quedan fijos).
    li      t0, GPIO_LED
    li      t1, 0xF00
    sw      t1, 0(t0)

    # Buffer de 3 bytes en stack para X/Y/Z (alineado a 4 -> 4 bytes).
    addi    sp, sp, -4
    mv      s0, sp                   # s0 = &xyz_buf (callee-saved, sobrevive a call)

main_loop:
    mv      a0, s0
    jal     ra, adxl_read_xyz        # llena xyz_buf con X,Y,Z

    # Mostrar X (byte 0) en LED[7:0] y mantener LED[11:8] = 0xF.
    lbu     t0, 0(s0)                # X (sin extensión de signo: los LEDs
                                     # son bits crudos, no aritmética)
    li      t1, 0xF00                # mantener flag "ready" en LED[11:8]
    or      t0, t0, t1
    li      t1, GPIO_LED
    sw      t0, 0(t1)

    # ~10 ms entre lecturas -> 100 Hz, igual a la ODR del sensor.
    li      a0, DELAY_10MS
    jal     ra, delay_cycles
    j       main_loop

init_error:
    # Falló DEVID_AD o PARTID: encender los 12 LEDs y quedarse acá.
    li      t0, GPIO_LED
    li      t1, 0xFFF
    sw      t1, 0(t0)
hang:
    j       hang


# =============================================================================
# spi_xfer(a0=byte_tx) -> a0=byte_rx
# Una transferencia SPI completa: carga TX, pulsa start, espera busy=0,
# devuelve el byte de RX.
# =============================================================================
spi_xfer:
    li      t0, SPI_TX
    sw      a0, 0(t0)                # SPI_TX = byte a enviar

    li      t0, SPI_CTRL
    li      t1, CTRL_GO
    sw      t1, 0(t0)                # arranca: csn=0, start=1, div=4

spi_xfer_wait:
    lw      t1, 0(t0)                # poll SPI_CTRL
    andi    t1, t1, 1                # aislar bit 0 (start/busy)
    bnez    t1, spi_xfer_wait        # esperar HW auto-clear (=done)

    li      t0, SPI_RX
    lw      a0, 0(t0)
    andi    a0, a0, 0xFF             # quedarse con el byte bajo
    jalr    x0, 0(ra)


# =============================================================================
# spi_cs_low: assert CSn (línea hacia el ADXL362 -> activo bajo)
# =============================================================================
spi_cs_low:
    li      t0, SPI_CTRL
    li      t1, CTRL_SEL
    sw      t1, 0(t0)
    jalr    x0, 0(ra)


# =============================================================================
# spi_cs_high: deassert CSn
# =============================================================================
spi_cs_high:
    li      t0, SPI_CTRL
    li      t1, CTRL_IDLE
    sw      t1, 0(t0)
    jalr    x0, 0(ra)


# =============================================================================
# adxl_read_reg(a0=addr) -> a0=valor
# Secuencia: CSn↓ | 0x0B | addr | 0x00(dummy)->valor | CSn↑
# Stack: salva ra + s0 (s0 conserva la dir entre llamadas a spi_xfer).
# =============================================================================
adxl_read_reg:
    addi    sp, sp, -8
    sw      ra, 4(sp)
    sw      s0, 0(sp)
    mv      s0, a0                   # s0 = addr del registro ADXL

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_READ
    jal     ra, spi_xfer             # envía 0x0B
    mv      a0, s0
    jal     ra, spi_xfer             # envía addr
    li      a0, 0
    jal     ra, spi_xfer             # envía dummy, a0 <- valor leído
    mv      s0, a0                   # salvar el valor antes de tocar CSn

    jal     ra, spi_cs_high
    mv      a0, s0                   # valor de retorno

    lw      s0, 0(sp)
    lw      ra, 4(sp)
    addi    sp, sp, 8
    jalr    x0, 0(ra)


# =============================================================================
# adxl_write_reg(a0=addr, a1=valor)
# Secuencia: CSn↓ | 0x0A | addr | valor | CSn↑
# =============================================================================
adxl_write_reg:
    addi    sp, sp, -12
    sw      ra, 8(sp)
    sw      s0, 4(sp)
    sw      s1, 0(sp)
    mv      s0, a0                   # s0 = addr
    mv      s1, a1                   # s1 = valor

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_WRITE
    jal     ra, spi_xfer             # 0x0A
    mv      a0, s0
    jal     ra, spi_xfer             # addr
    mv      a0, s1
    jal     ra, spi_xfer             # valor

    jal     ra, spi_cs_high

    lw      s1, 0(sp)
    lw      s0, 4(sp)
    lw      ra, 8(sp)
    addi    sp, sp, 12
    jalr    x0, 0(ra)


# =============================================================================
# adxl_read_xyz(a0=ptr_buf3)
# Lectura ráfaga: CSn↓ | 0x0B | 0x08 | X | Y | Z | CSn↑
# Escribe 3 bytes consecutivos (X, Y, Z) a partir del puntero recibido.
# =============================================================================
adxl_read_xyz:
    addi    sp, sp, -8
    sw      ra, 4(sp)
    sw      s0, 0(sp)
    mv      s0, a0                   # s0 = ptr al buffer

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_READ
    jal     ra, spi_xfer             # 0x0B
    li      a0, ADXL_XDATA
    jal     ra, spi_xfer             # 0x08 (dir de X)

    li      a0, 0
    jal     ra, spi_xfer             # X
    sb      a0, 0(s0)
    li      a0, 0
    jal     ra, spi_xfer             # Y
    sb      a0, 1(s0)
    li      a0, 0
    jal     ra, spi_xfer             # Z
    sb      a0, 2(s0)

    jal     ra, spi_cs_high

    lw      s0, 0(sp)
    lw      ra, 4(sp)
    addi    sp, sp, 8
    jalr    x0, 0(ra)


# =============================================================================
# adxl_init() -> a0=0 OK, a0=1/2 fallo
# 1) DEVID_AD == 0xAD ?           (si no -> a0=1)
# 2) PARTID   == 0xF2 ?           (si no -> a0=2)
# 3) FILTER_CTL = 0x13
# 4) POWER_CTL  = 0x02
# 5) delay ~10 ms (arranque del ADC)
# =============================================================================
adxl_init:
    addi    sp, sp, -4
    sw      ra, 0(sp)

    # CSn idle por si quedó residuo de un boot anterior.
    jal     ra, spi_cs_high

    # 1) DEVID_AD
    li      a0, ADXL_DEVID_AD
    jal     ra, adxl_read_reg
    li      t0, ADXL_ID_AD
    bne     a0, t0, init_bad_devid

    # 2) PARTID
    li      a0, ADXL_PARTID
    jal     ra, adxl_read_reg
    li      t0, ADXL_ID_PART
    bne     a0, t0, init_bad_partid

    # 3) FILTER_CTL = 0x13
    li      a0, ADXL_FILTER_CTL
    li      a1, FILTER_CTL_VAL
    jal     ra, adxl_write_reg

    # 4) POWER_CTL = 0x02 (measurement mode)
    li      a0, ADXL_POWER_CTL
    li      a1, POWER_CTL_VAL
    jal     ra, adxl_write_reg

    # 5) Esperar ~10 ms para que el ADC esté listo.
    li      a0, DELAY_10MS
    jal     ra, delay_cycles

    li      a0, 0                    # OK
    j       init_ret

init_bad_devid:
    li      a0, 1
    j       init_ret
init_bad_partid:
    li      a0, 2
init_ret:
    lw      ra, 0(sp)
    addi    sp, sp, 4
    jalr    x0, 0(ra)


# =============================================================================
# delay_cycles(a0=iters): busy-loop. ~5 ciclos por iteración en picorv32.
# =============================================================================
delay_cycles:
    beqz    a0, delay_done
delay_loop:
    addi    a0, a0, -1
    bnez    a0, delay_loop
delay_done:
    jalr    x0, 0(ra)
