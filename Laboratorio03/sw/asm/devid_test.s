# =============================================================================
# Archivo      : sw/asm/devid_test.s
# Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
# Lab 3        : Test de integración SPI -> ADXL362.
#
# Lee el registro DEVID_AD (0x00) del ADXL362 onboard de la Nexys4 DDR
# vía el periférico SPI master del SoC y muestra el byte recibido en
# LED[7:0]. Si todo funciona, los LEDs deben mostrar 0xAD = 1010_1101.
#
# Mapa de registros relevantes (axil_defs.svh):
#     0x02004  GPIO_LED   (RW, [11:0] = LEDs físicos)
#     0x02020  SPI_CTRL   (RW)
#                bit  0   start (1=disparar; HW auto-clear al done)
#                bit  3   csn   (1=idle high, 0=activo low)
#                bits[11:4] clk_div (default 4 -> SCLK 6.25 MHz)
#     0x02028  SPI_TX     (W, [7:0] byte a enviar)
#     0x0202C  SPI_RX     (R, [7:0] último byte recibido)
#
# Secuencia de transacción ADXL362:
#     CSn↓  | 0x0B (cmd READ) | 0x00 (addr DEVID_AD) | 0x00 (dummy) | CSn↑
#                                                       ↑
#                                          en este byte llega 0xAD por MISO
# =============================================================================
    .equ SPI_CTRL,  0x02020
    .equ SPI_TX,    0x02028
    .equ SPI_RX,    0x0202C
    .equ GPIO_LED,  0x02004

    # CTRL pre-armados: bits[11:4]=4 (div=4 -> SCLK 6.25 MHz)
    .equ CTRL_IDLE,  0x048      # csn=1, start=0, div=4 (idle deselected)
    .equ CTRL_SEL,   0x040      # csn=0, start=0, div=4 (CSn asserted)
    .equ CTRL_GO,    0x041      # csn=0, start=1, div=4 (arrancar transferencia)

    .section .text
    .globl  _start

_start:
    # Punteros a registros del SoC
    li      s0, SPI_CTRL
    li      s1, SPI_TX
    li      s2, SPI_RX
    li      s3, GPIO_LED

    # 1) Forzar CSn idle (1) por si quedó algún residuo
    li      t0, CTRL_IDLE
    sw      t0, 0(s0)

    # 2) Bajar CSn (asserted) sin disparar transferencia aún
    li      t0, CTRL_SEL
    sw      t0, 0(s0)

    # ---- Byte 1: comando READ (0x0B) -----------------------------------
    li      t0, 0x0B
    sw      t0, 0(s1)               # SPI_TX = 0x0B
    li      t0, CTRL_GO
    sw      t0, 0(s0)               # arranca: pulso start
1:  lw      t1, 0(s0)               # poll SPI_CTRL
    andi    t1, t1, 1               # aislar bit start
    bnez    t1, 1b                  # esperar a HW auto-clear

    # ---- Byte 2: dirección DEVID_AD (0x00) -----------------------------
    sw      zero, 0(s1)             # SPI_TX = 0x00
    li      t0, CTRL_GO
    sw      t0, 0(s0)
2:  lw      t1, 0(s0)
    andi    t1, t1, 1
    bnez    t1, 2b

    # ---- Byte 3: dummy (0x00) -> en RX llega DEVID_AD ------------------
    sw      zero, 0(s1)             # SPI_TX = 0x00
    li      t0, CTRL_GO
    sw      t0, 0(s0)
3:  lw      t1, 0(s0)
    andi    t1, t1, 1
    bnez    t1, 3b

    # 3) Subir CSn (deselect) — fin de la transacción
    li      t0, CTRL_IDLE
    sw      t0, 0(s0)

    # 4) Leer SPI_RX y mostrarlo en LED[7:0]
    lw      t2, 0(s2)
    andi    t2, t2, 0xFF            # quedarse con el byte bajo
    sw      t2, 0(s3)               # GPIO_LED = DEVID_AD esperado 0xAD

hang:
    j       hang
