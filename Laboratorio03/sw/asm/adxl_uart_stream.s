# =============================================================================
# Archivo      : sw/asm/adxl_uart_stream.s
# Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
# Lab 3 Etapa 5: Streaming UART de las lecturas X/Y/Z del ADXL362.
#
# Extiende adxl_driver.s agregando la capa de transporte UART. La FPGA arranca
# pausada; al recibir el comando 's' por UART empieza a enviar el frame
#
#     +------+------+------+------+------+
#     | 0xAA |  X   |  Y   |  Z   | 0x55 |
#     +------+------+------+------+------+
#
# cada ~10 ms (≈ 97 Hz reales con el TX a 9600 8N1) — match con la ODR del
# sensor a 100 Hz. Protocolo y razonamiento del ancho de banda en
# docs/research.md §3.
#
# Comandos laptop -> FPGA (ASCII imprimibles para debug con minicom/screen):
#
#   's' (0x73)  START   -> streaming = 1
#   'p' (0x70) PAUSE   -> streaming = 0
#   'r' (0x72) RESET   -> re-ejecuta adxl_init (recupera el sensor de un
#                          estado raro sin reset HW del SoC)
#
# LEDs:
#   LED15..12  RTL debug (heartbeat, core_trap, rst_n, pll_locked)
#   LED11      streaming flag (1 = enviando frames)
#   LED10..8   = 0x7 (init OK fijo, 3 LEDs siempre encendidos post-init)
#   LED7..0    eje X en vivo (sanity visual sin necesidad de UART)
#
# RTL relevante: rtl/peripherals/uart/uart_axil.sv
#   - UART_CTRL[0]=send: SW=1 dispara TX; HW=0 al terminar (polling).
#   - UART_CTRL[1]=new_rx: HW=1 al recibir un byte (sólo si !tx_busy && !send,
#     ver línea 174); SW debe limpiarlo escribiendo 0.
#   - Implicación: durante la TX del frame no se reciben comandos. El polling
#     entre frames (~5 ms) es la ventana donde llegan 's'/'p'/'r'.
#
# Mapa de I/O (axil_defs.svh):
#   0x02004  GPIO_LED   (RW [11:0])
#   0x02010  UART_CTRL  ([0]=send, [1]=new_rx)
#   0x02018  UART_TX    ([7:0] byte a enviar)
#   0x0201C  UART_RX    ([7:0] último byte recibido)
#   0x02020  SPI_CTRL   ([0]=start/busy, [3]=csn, [11:4]=clk_div)
#   0x02028  SPI_TX
#   0x0202C  SPI_RX
# =============================================================================

    # ---- I/O ---------------------------------------------------------------
    .equ GPIO_LED,        0x02004
    .equ UART_CTRL,       0x02010
    .equ UART_TX,         0x02018
    .equ UART_RX,         0x0201C
    .equ SPI_CTRL,        0x02020
    .equ SPI_TX,          0x02028
    .equ SPI_RX,          0x0202C

    # ---- Patrones SPI_CTRL (clk_div=4 -> SCLK 6.25 MHz) --------------------
    .equ CTRL_IDLE,       0x048      # csn=1, start=0
    .equ CTRL_SEL,        0x040      # csn=0, start=0
    .equ CTRL_GO,         0x041      # csn=0, start=1

    # ---- ADXL362 -----------------------------------------------------------
    .equ ADXL_DEVID_AD,   0x00
    .equ ADXL_PARTID,     0x02
    .equ ADXL_XDATA,      0x08
    .equ ADXL_FILTER_CTL, 0x2C
    .equ ADXL_POWER_CTL,  0x2D
    .equ ADXL_CMD_WRITE,  0x0A
    .equ ADXL_CMD_READ,   0x0B
    .equ ADXL_ID_AD,      0xAD
    .equ ADXL_ID_PART,    0xF2
    .equ FILTER_CTL_VAL,  0x13       # range=±2g, HALF_BW=1, ODR=100 Hz
    .equ POWER_CTL_VAL,   0x02       # measurement mode

    # ---- Protocolo UART ----------------------------------------------------
    .equ FRAME_START,     0xAA
    .equ FRAME_END,       0x55
    .equ CMD_START,       0x73       # 's'
    .equ CMD_PAUSE,       0x70       # 'p'
    .equ CMD_RESET,       0x72       # 'r'

    # ---- Stack y timing ----------------------------------------------------
    .equ STACK_TOP,       0x58FFC
    .equ DELAY_10MS,      100000     # arranque del ADC tras POWER_CTL
    # ~5 ms entre iteraciones: con la TX bloqueante de 5 bytes a 9600 baud
    # (~5.2 ms total) da un ciclo total ≈ 10 ms -> ~97 Hz, match con la ODR.
    .equ DELAY_5MS,       50000

    .section .text
    .globl  _start

# =============================================================================
# _start
# =============================================================================
_start:
    li      sp, STACK_TOP

    # Limpiar LEDs.
    li      t0, GPIO_LED
    sw      zero, 0(t0)

    # Inicializar el ADXL362.
    jal     ra, adxl_init
    bnez    a0, init_error

    # Init OK: LED10..8 = 0x7 (LED11 queda en 0 = paused al boot).
    li      t0, GPIO_LED
    li      t1, 0x700
    sw      t1, 0(t0)

    # Buffer XYZ en stack (alineado a 4 bytes, usamos 3).
    addi    sp, sp, -4
    mv      s0, sp                   # s0 = &xyz_buf (callee-saved)
    li      s1, 0                    # s1 = streaming flag (0=paused, 1=on)

main_loop:
    # 1) Leer XYZ siempre (mantiene la cadena SPI activa aunque estemos en
    #    pausa; total <100 µs, no afecta el cycle budget).
    mv      a0, s0
    jal     ra, adxl_read_xyz

    # 2) Poll de comando entrante por UART.
    jal     ra, uart_poll_cmd
    li      t0, -1
    beq     a0, t0, no_cmd           # a0 = -1 -> no llegó nada

    # Dispatch del comando.
    li      t0, CMD_START
    beq     a0, t0, cmd_start
    li      t0, CMD_PAUSE
    beq     a0, t0, cmd_pause
    li      t0, CMD_RESET
    beq     a0, t0, cmd_reset
    j       no_cmd                   # byte desconocido -> ignorar

cmd_start:
    li      s1, 1
    j       no_cmd
cmd_pause:
    li      s1, 0
    j       no_cmd
cmd_reset:
    # Re-init del sensor (no resetea el SoC, sólo el ADXL362).
    jal     ra, adxl_init
    bnez    a0, init_error           # si el sensor desapareció, error visible
    j       no_cmd

no_cmd:
    # 3) Si streaming activo, enviar frame 0xAA X Y Z 0x55.
    beqz    s1, skip_send
    li      a0, FRAME_START
    jal     ra, uart_send_byte
    lbu     a0, 0(s0)
    jal     ra, uart_send_byte       # X
    lbu     a0, 1(s0)
    jal     ra, uart_send_byte       # Y
    lbu     a0, 2(s0)
    jal     ra, uart_send_byte       # Z
    li      a0, FRAME_END
    jal     ra, uart_send_byte

skip_send:
    # 4) LEDs: LED11 = streaming, LED10..8 = 0x7, LED7..0 = X.
    slli    t0, s1, 11               # streaming<<11 -> 0x800 | 0x000
    li      t1, 0x700
    or      t0, t0, t1
    lbu     t1, 0(s0)
    or      t0, t0, t1
    li      t1, GPIO_LED
    sw      t0, 0(t1)

    # 5) Espera ~5 ms (con el TX, ciclo total ≈ 10 ms).
    li      a0, DELAY_5MS
    jal     ra, delay_cycles
    j       main_loop

init_error:
    # Fallo de DEVID/PARTID -> 12 LEDs encendidos + hang.
    li      t0, GPIO_LED
    li      t1, 0xFFF
    sw      t1, 0(t0)
hang:
    j       hang


# =============================================================================
# uart_send_byte(a0=byte)
# TX bloqueante. Conserva el bit new_rx via read-modify-write (no perdemos
# eventos RX pendientes al setear send=1).
# =============================================================================
uart_send_byte:
    li      t0, UART_CTRL

    # Espera a que TX previa termine (send=0).
uart_tx_wait_idle:
    lw      t1, 0(t0)
    andi    t1, t1, 1
    bnez    t1, uart_tx_wait_idle

    # Cargar el byte en UART_TX.
    li      t1, UART_TX
    sw      a0, 0(t1)

    # Set send=1 preservando new_rx (read-modify-write).
    lw      t1, 0(t0)
    ori     t1, t1, 1
    sw      t1, 0(t0)

    # Esperar a que HW baje send (TX completa).
uart_tx_wait_done:
    lw      t1, 0(t0)
    andi    t1, t1, 1
    bnez    t1, uart_tx_wait_done

    jalr    x0, 0(ra)


# =============================================================================
# uart_poll_cmd() -> a0 = byte recibido (0..255), o a0 = -1 si nada
# Limpia new_rx tras leer. En este punto del main loop send=0 (no estamos
# TXing), así que escribir CTRL=0 limpia sólo new_rx sin efectos colaterales.
# =============================================================================
uart_poll_cmd:
    li      t0, UART_CTRL
    lw      t1, 0(t0)
    andi    t1, t1, 2                # bit 1 = new_rx
    beqz    t1, uart_poll_empty

    li      t1, UART_RX
    lw      a0, 0(t1)
    andi    a0, a0, 0xFF
    sw      zero, 0(t0)              # clear new_rx (y send, que ya era 0)
    jalr    x0, 0(ra)

uart_poll_empty:
    li      a0, -1
    jalr    x0, 0(ra)


# =============================================================================
# spi_xfer(a0=byte_tx) -> a0=byte_rx
# =============================================================================
spi_xfer:
    li      t0, SPI_TX
    sw      a0, 0(t0)

    li      t0, SPI_CTRL
    li      t1, CTRL_GO
    sw      t1, 0(t0)

spi_xfer_wait:
    lw      t1, 0(t0)
    andi    t1, t1, 1
    bnez    t1, spi_xfer_wait

    li      t0, SPI_RX
    lw      a0, 0(t0)
    andi    a0, a0, 0xFF
    jalr    x0, 0(ra)


# =============================================================================
# spi_cs_low / spi_cs_high
# =============================================================================
spi_cs_low:
    li      t0, SPI_CTRL
    li      t1, CTRL_SEL
    sw      t1, 0(t0)
    jalr    x0, 0(ra)

spi_cs_high:
    li      t0, SPI_CTRL
    li      t1, CTRL_IDLE
    sw      t1, 0(t0)
    jalr    x0, 0(ra)


# =============================================================================
# adxl_read_reg(a0=addr) -> a0=valor
# =============================================================================
adxl_read_reg:
    addi    sp, sp, -8
    sw      ra, 4(sp)
    sw      s2, 0(sp)
    mv      s2, a0

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_READ
    jal     ra, spi_xfer
    mv      a0, s2
    jal     ra, spi_xfer
    li      a0, 0
    jal     ra, spi_xfer
    mv      s2, a0

    jal     ra, spi_cs_high
    mv      a0, s2

    lw      s2, 0(sp)
    lw      ra, 4(sp)
    addi    sp, sp, 8
    jalr    x0, 0(ra)


# =============================================================================
# adxl_write_reg(a0=addr, a1=valor)
# =============================================================================
adxl_write_reg:
    addi    sp, sp, -12
    sw      ra, 8(sp)
    sw      s2, 4(sp)
    sw      s3, 0(sp)
    mv      s2, a0
    mv      s3, a1

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_WRITE
    jal     ra, spi_xfer
    mv      a0, s2
    jal     ra, spi_xfer
    mv      a0, s3
    jal     ra, spi_xfer

    jal     ra, spi_cs_high

    lw      s3, 0(sp)
    lw      s2, 4(sp)
    lw      ra, 8(sp)
    addi    sp, sp, 12
    jalr    x0, 0(ra)


# =============================================================================
# adxl_read_xyz(a0=ptr_buf3)
# Ráfaga SPI: CSn↓ | 0x0B | 0x08 | X | Y | Z | CSn↑
# =============================================================================
adxl_read_xyz:
    addi    sp, sp, -8
    sw      ra, 4(sp)
    sw      s2, 0(sp)
    mv      s2, a0

    jal     ra, spi_cs_low

    li      a0, ADXL_CMD_READ
    jal     ra, spi_xfer
    li      a0, ADXL_XDATA
    jal     ra, spi_xfer

    li      a0, 0
    jal     ra, spi_xfer
    sb      a0, 0(s2)                # X
    li      a0, 0
    jal     ra, spi_xfer
    sb      a0, 1(s2)                # Y
    li      a0, 0
    jal     ra, spi_xfer
    sb      a0, 2(s2)                # Z

    jal     ra, spi_cs_high

    lw      s2, 0(sp)
    lw      ra, 4(sp)
    addi    sp, sp, 8
    jalr    x0, 0(ra)


# =============================================================================
# adxl_init() -> a0=0 OK, a0=1 (DEVID malo), a0=2 (PARTID malo)
# OJO: usa s2 internamente (callee-saved). _start usa s0/s1, sin conflicto.
# =============================================================================
adxl_init:
    addi    sp, sp, -4
    sw      ra, 0(sp)

    jal     ra, spi_cs_high

    li      a0, ADXL_DEVID_AD
    jal     ra, adxl_read_reg
    li      t0, ADXL_ID_AD
    bne     a0, t0, init_bad_devid

    li      a0, ADXL_PARTID
    jal     ra, adxl_read_reg
    li      t0, ADXL_ID_PART
    bne     a0, t0, init_bad_partid

    li      a0, ADXL_FILTER_CTL
    li      a1, FILTER_CTL_VAL
    jal     ra, adxl_write_reg

    li      a0, ADXL_POWER_CTL
    li      a1, POWER_CTL_VAL
    jal     ra, adxl_write_reg

    li      a0, DELAY_10MS
    jal     ra, delay_cycles

    li      a0, 0
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
# delay_cycles(a0=iters): busy-loop, ~5 ciclos por iteración en picorv32.
# =============================================================================
delay_cycles:
    beqz    a0, delay_done
delay_loop:
    addi    a0, a0, -1
    bnez    a0, delay_loop
delay_done:
    jalr    x0, 0(ra)
