#!/usr/bin/env python3
"""
sw/host/visualizer.py — Lab 3 Etapa 6 (paso previo al juego)

Conecta a la FPGA por UART (9600 8N1), arranca el streaming con 's',
decodifica los frames "0xAA X Y Z 0x55" del firmware adxl_uart_stream.s
y muestra los 3 ejes en vivo: barras + gráfica de scroll de los últimos
~2 segundos. Calibra el offset de gravedad residual durante el primer
segundo (placa quieta), tal como prevé docs/research.md §4.4.

Uso:
    python3 sw/host/visualizer.py             # /dev/ttyUSB1 por defecto
    python3 sw/host/visualizer.py /dev/ttyUSB0
Deps:
    sudo apt install python3-pygame python3-serial
    (o pip install pygame pyserial en un venv)
Teclas en la ventana:
    s     start streaming      p     pause
    r     reset sensor          c     recalibrar offset
    q/Esc salir
"""

import queue
import sys
import threading
import time

import pygame
import serial

PORT          = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
BAUD          = 9600
FRAME_START   = 0xAA
FRAME_END     = 0x55
G_PER_LSB     = 2.0 / 128.0          # ±2g range, 8-bit signed -> 15.625 mg/LSB
HISTORY_LEN   = 200                  # ~2 s a 100 Hz
CAL_DURATION  = 1.0                  # segundos de calibración

WIN_W, WIN_H  = 720, 540
COLOR_BG      = (18, 18, 26)
COLOR_GRID    = (50, 50, 60)
COLOR_TEXT    = (220, 220, 220)
COLOR_DIM     = (140, 140, 140)
COLOR_X       = (240, 90, 90)
COLOR_Y       = (90, 220, 110)
COLOR_Z       = (110, 160, 250)


def s8(b: int) -> int:
    """Byte a entero con signo de 8 bits."""
    return b - 256 if b >= 128 else b


class FrameReader(threading.Thread):
    """Lee la UART, sincroniza con 0xAA..0x55 y empuja (x,y,z) a una queue."""

    def __init__(self, port: str, q: "queue.Queue"):
        super().__init__(daemon=True)
        self.ser = serial.Serial(port, BAUD, timeout=0.1)
        self.q = q
        self.running = True
        self.bad_frames = 0

    def run(self):
        buf = bytearray()
        while self.running:
            chunk = self.ser.read(64)
            if not chunk:
                continue
            for b in chunk:
                if not buf:
                    if b == FRAME_START:
                        buf.append(b)
                else:
                    buf.append(b)
                    if len(buf) == 5:
                        if buf[0] == FRAME_START and buf[4] == FRAME_END:
                            self.q.put((s8(buf[1]), s8(buf[2]), s8(buf[3])))
                        else:
                            self.bad_frames += 1
                        buf.clear()

    def send(self, cmd: bytes):
        try:
            self.ser.write(cmd)
        except serial.SerialException:
            pass

    def close(self):
        self.running = False
        self.send(b"ppp")
        try:
            self.ser.close()
        except serial.SerialException:
            pass


def calibrate(q: "queue.Queue", duration: float) -> tuple[int, int, int]:
    """Promedia los frames recibidos durante `duration` segundos."""
    samples = []
    t_end = time.time() + duration
    while time.time() < t_end:
        try:
            samples.append(q.get(timeout=0.1))
        except queue.Empty:
            pass
    if not samples:
        return (0, 0, 0)
    n = len(samples)
    return (
        sum(s[0] for s in samples) // n,
        sum(s[1] for s in samples) // n,
        sum(s[2] for s in samples) // n,
    )


def draw_axis_row(surf, font, y, label, color, val_lsb):
    """Renderiza una fila: 'X: +27 (+0.42 g)' + barra horizontal."""
    g = val_lsb * G_PER_LSB
    text = f"{label}: {val_lsb:+4d}   ({g:+.2f} g)"
    surf.blit(font.render(text, True, color), (20, y))

    center_x = 460
    half_w   = 220
    bar_y    = y + 8
    bar_h    = 16
    pygame.draw.line(surf, COLOR_DIM, (center_x, bar_y), (center_x, bar_y + bar_h), 1)
    pygame.draw.line(surf, COLOR_DIM,
                     (center_x - half_w, bar_y + bar_h // 2),
                     (center_x + half_w, bar_y + bar_h // 2), 1)
    bw = max(-half_w, min(half_w, int(val_lsb * half_w / 128)))
    if bw >= 0:
        pygame.draw.rect(surf, color, (center_x, bar_y, bw, bar_h))
    else:
        pygame.draw.rect(surf, color, (center_x + bw, bar_y, -bw, bar_h))


def draw_history(surf, history):
    """Gráfica de scroll: las 3 series superpuestas, ±128 LSB a fondo de escala."""
    gx, gy, gw, gh = 20, 320, 680, 200
    pygame.draw.rect(surf, (28, 28, 38), (gx, gy, gw, gh))
    pygame.draw.rect(surf, COLOR_GRID, (gx, gy, gw, gh), 1)
    mid = gy + gh // 2
    pygame.draw.line(surf, COLOR_GRID, (gx, mid), (gx + gw, mid), 1)
    for frac in (-0.5, 0.5):
        py = mid + int(frac * gh / 2)
        pygame.draw.line(surf, (35, 35, 45), (gx, py), (gx + gw, py), 1)

    if len(history) < 2:
        return
    n = len(history)

    for axis_i, color in enumerate((COLOR_X, COLOR_Y, COLOR_Z)):
        pts = []
        for i, s in enumerate(history):
            px = gx + int(i * gw / (HISTORY_LEN - 1))
            py = mid - int(s[axis_i] * (gh / 2) / 128)
            py = max(gy, min(gy + gh, py))
            pts.append((px, py))
        if len(pts) >= 2:
            pygame.draw.lines(surf, color, False, pts, 2)


def main():
    print(f"[host] abriendo {PORT} @ {BAUD} 8N1")
    try:
        q: "queue.Queue[tuple[int, int, int]]" = queue.Queue()
        reader = FrameReader(PORT, q)
    except serial.SerialException as e:
        print(f"[host] ERROR abriendo el puerto: {e}", file=sys.stderr)
        sys.exit(1)

    reader.start()
    # Ráfaga: el RTL gatea new_rx con !tx_busy && !send, así que un único byte
    # de comando se pierde ~50% de las veces si cae durante un TX-window.
    # Repetir el byte 3 veces garantiza que uno aterrice en ventana abierta.
    reader.send(b"sss")
    print("[host] enviado 's' (start). Calibrando — placa quieta 1 s...")
    offset = calibrate(q, CAL_DURATION)
    if offset == (0, 0, 0):
        print("[host] WARN: 0 frames durante calibración (revisar UART).")
    else:
        print(f"[host] offset = X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}")

    pygame.init()
    screen = pygame.display.set_mode((WIN_W, WIN_H))
    pygame.display.set_caption("ADXL362 Visualizer — Lab 3")
    font_big   = pygame.font.SysFont("monospace", 22, bold=True)
    font_small = pygame.font.SysFont("monospace", 14)
    clock = pygame.time.Clock()

    raw = (0, 0, 0)
    history: list[tuple[int, int, int]] = []
    running = True
    streaming = True

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key in (pygame.K_q, pygame.K_ESCAPE):
                    running = False
                elif event.key == pygame.K_s:
                    reader.send(b"sss")
                    streaming = True
                elif event.key == pygame.K_p:
                    reader.send(b"ppp")
                    streaming = False
                elif event.key == pygame.K_r:
                    reader.send(b"r")
                elif event.key == pygame.K_c:
                    history.clear()
                    print("[host] recalibrando — placa quieta 1 s...")
                    offset = calibrate(q, CAL_DURATION)
                    print(f"[host] offset = X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}")

        while True:
            try:
                raw = q.get_nowait()
            except queue.Empty:
                break
            cal = (raw[0] - offset[0], raw[1] - offset[1], raw[2] - offset[2])
            history.append(cal)
            if len(history) > HISTORY_LEN:
                history.pop(0)

        cal = (raw[0] - offset[0], raw[1] - offset[1], raw[2] - offset[2])

        screen.fill(COLOR_BG)
        screen.blit(font_big.render("ADXL362 — lectura en vivo", True, COLOR_TEXT), (20, 16))
        status_txt = "streaming" if streaming else "PAUSED"
        status_col = COLOR_Y if streaming else COLOR_X
        screen.blit(font_small.render(status_txt, True, status_col), (WIN_W - 130, 22))

        draw_axis_row(screen, font_big, 80,  "X", COLOR_X, cal[0])
        draw_axis_row(screen, font_big, 130, "Y", COLOR_Y, cal[1])
        draw_axis_row(screen, font_big, 180, "Z", COLOR_Z, cal[2])

        hints = [
            f"port {PORT} @ {BAUD} 8N1   offset X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}   bad={reader.bad_frames}",
            "[s] start    [p] pause    [r] reset sensor    [c] recalibrar    [q/Esc] salir",
        ]
        for i, line in enumerate(hints):
            screen.blit(font_small.render(line, True, COLOR_DIM), (20, 248 + i * 20))

        draw_history(screen, history)

        pygame.display.flip()
        clock.tick(60)

    reader.close()
    pygame.quit()


if __name__ == "__main__":
    main()
