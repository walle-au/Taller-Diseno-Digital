#!/usr/bin/env python3
"""
sw/host/asteroids.py — Lab 3 Etapa 6: juego Asteroids controlado por ADXL362.

Reusa el path UART validado por visualizer.py. Mapea:
    X (inclinación lateral)  -> rotación de la nave
    Y (inclinación frontal)  -> thrust
    |ΔZ| > umbral            -> disparo (gesto "shake")

Fallback de teclado para testear sin sostener la placa:
    ←/→ o A/D     rotación
    ↑ o W         thrust
    Space         disparo

Otras teclas:
    c     recalibrar offset (1 s placa quieta)
    p / s pause / resume UART
    r     reset sensor (re-ejecuta adxl_init)
    Enter restart en Game Over
    q/Esc salir

Uso:
    python3 sw/host/asteroids.py             # /dev/ttyUSB1
    python3 sw/host/asteroids.py /dev/ttyUSB0
Deps:
    sudo apt install python3-pygame python3-serial
"""

import math
import queue
import random
import sys
import threading
import time

import pygame
import serial

# --- UART (igual que visualizer.py) -----------------------------------------
PORT          = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
BAUD          = 9600
FRAME_START   = 0xAA
FRAME_END     = 0x55
CAL_DURATION  = 1.0

# --- Pantalla y juego --------------------------------------------------------
WIN_W, WIN_H        = 1024, 720
FPS                 = 60

# Mapeo ADXL -> juego
X_DEADZONE          = 8       # LSB; |X| menor = sin rotación
ROT_SPEED_MAX       = 4.0     # grados/frame al máximo tilt (X = ±128)
Y_THRUST_THRESHOLD  = 16      # LSB; Y > esto = thrust ON
THRUST_FORCE        = 0.11
FRICTION            = 0.988
MAX_SHIP_SPEED      = 4.5

# Disparo por shake (gesto vertical)
SHAKE_THRESHOLD     = 24      # |ΔZ| en LSB entre samples
SHAKE_COOLDOWN      = 0.25    # segundos entre disparos por shake

# Bala
BULLET_SPEED        = 8.0
BULLET_LIFE         = 60      # frames

# Asteroides
ASTEROID_SIZES = {
    "L": {"r": 50, "speed": 1.5, "score": 20,  "next": "M"},
    "M": {"r": 28, "speed": 2.5, "score": 50,  "next": "S"},
    "S": {"r": 15, "speed": 3.5, "score": 100, "next": None},
}
INITIAL_ASTEROIDS   = 4

# Colores
COLOR_BG     = (8, 8, 16)
COLOR_STAR   = (55, 55, 75)
COLOR_SHIP   = (220, 230, 255)
COLOR_THRUST = (255, 180, 80)
COLOR_BULLET = (255, 240, 180)
COLOR_ASTER  = (190, 190, 200)
COLOR_TEXT   = (220, 220, 220)
COLOR_DIM    = (130, 130, 140)
COLOR_ALERT  = (240, 90, 90)


def s8(b: int) -> int:
    return b - 256 if b >= 128 else b


class FrameReader(threading.Thread):
    """Lee la UART, sincroniza con 0xAA..0x55 y empuja (x,y,z) a una queue."""

    def __init__(self, port: str, q: "queue.Queue"):
        super().__init__(daemon=True)
        self.ser = serial.Serial(port, BAUD, timeout=0.1)
        self.q = q
        self.running = True

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


# --- Entidades ---------------------------------------------------------------

class Ship:
    def __init__(self):
        self.reset_pose()

    def reset_pose(self):
        self.x = WIN_W / 2
        self.y = WIN_H / 2
        self.vx = 0.0
        self.vy = 0.0
        self.angle = -90.0          # apuntando arriba
        self.thrusting = False
        self.invuln = 120           # frames de invulnerabilidad al respawn
        self.radius = 14

    def update(self, rot_input: float, thrust_on: bool):
        self.angle += rot_input
        if thrust_on:
            self.thrusting = True
            rad = math.radians(self.angle)
            self.vx += math.cos(rad) * THRUST_FORCE
            self.vy += math.sin(rad) * THRUST_FORCE
            speed = math.hypot(self.vx, self.vy)
            if speed > MAX_SHIP_SPEED:
                self.vx *= MAX_SHIP_SPEED / speed
                self.vy *= MAX_SHIP_SPEED / speed
        else:
            self.thrusting = False
        self.vx *= FRICTION
        self.vy *= FRICTION
        self.x = (self.x + self.vx) % WIN_W
        self.y = (self.y + self.vy) % WIN_H
        if self.invuln > 0:
            self.invuln -= 1

    def draw(self, surf):
        # Blink durante invulnerabilidad
        if self.invuln > 0 and (self.invuln // 4) % 2 == 0:
            return
        rad = math.radians(self.angle)
        tip   = (self.x + math.cos(rad) * 18, self.y + math.sin(rad) * 18)
        rad_l = rad + math.radians(140)
        rad_r = rad - math.radians(140)
        left  = (self.x + math.cos(rad_l) * 14, self.y + math.sin(rad_l) * 14)
        right = (self.x + math.cos(rad_r) * 14, self.y + math.sin(rad_r) * 14)
        pygame.draw.polygon(surf, COLOR_SHIP, [tip, left, right], 2)
        if self.thrusting:
            back = (self.x - math.cos(rad) * 10, self.y - math.sin(rad) * 10)
            flame_len = 6 + random.random() * 8
            flame = (back[0] - math.cos(rad) * flame_len,
                     back[1] - math.sin(rad) * flame_len)
            pygame.draw.line(surf, COLOR_THRUST, back, flame, 2)


class Asteroid:
    def __init__(self, x, y, size_key):
        self.x, self.y = x, y
        cfg = ASTEROID_SIZES[size_key]
        self.size_key  = size_key
        self.radius    = cfg["r"]
        self.score     = cfg["score"]
        self.next_size = cfg["next"]
        ang = random.uniform(0, 2 * math.pi)
        self.vx = math.cos(ang) * cfg["speed"]
        self.vy = math.sin(ang) * cfg["speed"]
        self.spin = random.uniform(-2.5, 2.5)
        self.rot = 0.0
        n = random.randint(8, 12)
        self.shape = [
            (math.cos(2 * math.pi * i / n) * self.radius * random.uniform(0.75, 1.1),
             math.sin(2 * math.pi * i / n) * self.radius * random.uniform(0.75, 1.1))
            for i in range(n)
        ]

    def update(self):
        self.x = (self.x + self.vx) % WIN_W
        self.y = (self.y + self.vy) % WIN_H
        self.rot += self.spin

    def draw(self, surf):
        rad = math.radians(self.rot)
        cos_r, sin_r = math.cos(rad), math.sin(rad)
        pts = [(self.x + p[0] * cos_r - p[1] * sin_r,
                self.y + p[0] * sin_r + p[1] * cos_r) for p in self.shape]
        pygame.draw.polygon(surf, COLOR_ASTER, pts, 2)

    def split(self):
        if self.next_size is None:
            return []
        return [Asteroid(self.x, self.y, self.next_size),
                Asteroid(self.x, self.y, self.next_size)]


class Bullet:
    def __init__(self, x, y, angle):
        self.x, self.y = x, y
        rad = math.radians(angle)
        self.vx = math.cos(rad) * BULLET_SPEED
        self.vy = math.sin(rad) * BULLET_SPEED
        self.life = BULLET_LIFE
        self.radius = 2

    def update(self):
        self.x = (self.x + self.vx) % WIN_W
        self.y = (self.y + self.vy) % WIN_H
        self.life -= 1

    def alive(self) -> bool:
        return self.life > 0

    def draw(self, surf):
        pygame.draw.circle(surf, COLOR_BULLET, (int(self.x), int(self.y)), self.radius)


def spawn_wave(n: int) -> list:
    asteroids = []
    for _ in range(n):
        # Lejos del centro para no aplastar a la nave al spawnear
        while True:
            x = random.uniform(0, WIN_W)
            y = random.uniform(0, WIN_H)
            if math.hypot(x - WIN_W / 2, y - WIN_H / 2) > 220:
                break
        asteroids.append(Asteroid(x, y, "L"))
    return asteroids


def toroidal_collide(a, b) -> bool:
    """Colisión por círculos con wrap-around toroidal."""
    dx = abs(a.x - b.x)
    dy = abs(a.y - b.y)
    dx = min(dx, WIN_W - dx)
    dy = min(dy, WIN_H - dy)
    return math.hypot(dx, dy) < a.radius + b.radius


# --- Main --------------------------------------------------------------------

def main():
    print(f"[game] abriendo {PORT} @ {BAUD} 8N1")
    q: "queue.Queue[tuple[int, int, int]]" = queue.Queue()
    reader = None
    try:
        reader = FrameReader(PORT, q)
    except serial.SerialException as e:
        print(f"[game] WARN no se pudo abrir el puerto: {e}", file=sys.stderr)
        print("[game] siguiendo con solo teclado.")

    if reader:
        reader.start()
        reader.send(b"sss")
        print("[game] calibrando — placa quieta 1 s...")
        offset = calibrate(q, CAL_DURATION)
        print(f"[game] offset = X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}")
    else:
        offset = (0, 0, 0)

    pygame.init()
    screen = pygame.display.set_mode((WIN_W, WIN_H))
    pygame.display.set_caption("Asteroids — Lab 3 (ADXL362 + RV32 SoC)")
    font_big   = pygame.font.SysFont("monospace", 24, bold=True)
    font_huge  = pygame.font.SysFont("monospace", 56, bold=True)
    font_small = pygame.font.SysFont("monospace", 14)
    clock = pygame.time.Clock()

    stars = [(random.randint(0, WIN_W - 1),
              random.randint(0, WIN_H - 1),
              random.randint(1, 2)) for _ in range(140)]

    ship = Ship()
    asteroids = spawn_wave(INITIAL_ASTEROIDS)
    bullets: list = []
    score = 0
    lives = 3
    game_over = False

    last_z = 0
    last_shake_t = 0.0
    cal_xyz = (0, 0, 0)
    streaming = True

    running = True
    while running:
        # ---- eventos ----
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key in (pygame.K_q, pygame.K_ESCAPE):
                    running = False
                elif event.key == pygame.K_SPACE:
                    if not game_over and ship.invuln == 0:
                        bullets.append(Bullet(ship.x, ship.y, ship.angle))
                elif event.key == pygame.K_RETURN and game_over:
                    ship = Ship()
                    asteroids = spawn_wave(INITIAL_ASTEROIDS)
                    bullets = []
                    score = 0
                    lives = 3
                    game_over = False
                elif event.key == pygame.K_c and reader:
                    print("[game] recalibrando...")
                    offset = calibrate(q, CAL_DURATION)
                    print(f"[game] offset = X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}")
                elif event.key == pygame.K_p and reader:
                    reader.send(b"ppp")
                    streaming = False
                    cal_xyz = (0, 0, 0)        # neutralizar input ADXL
                elif event.key == pygame.K_s and reader:
                    reader.send(b"sss")
                    streaming = True
                elif event.key == pygame.K_r and reader:
                    reader.send(b"r")

        # ---- drenar UART ----
        if reader and streaming:
            while True:
                try:
                    raw = q.get_nowait()
                except queue.Empty:
                    break
                cal_xyz = (raw[0] - offset[0], raw[1] - offset[1], raw[2] - offset[2])
                # Shake detection sobre cada muestra (no por frame, así no
                # perdemos gestos rápidos a 60 FPS vs 100 Hz del sensor).
                if not game_over and ship.invuln == 0:
                    dz = abs(cal_xyz[2] - last_z)
                    now = time.time()
                    if dz > SHAKE_THRESHOLD and (now - last_shake_t) > SHAKE_COOLDOWN:
                        bullets.append(Bullet(ship.x, ship.y, ship.angle))
                        last_shake_t = now
                last_z = cal_xyz[2]

        # ---- input combinado: ADXL + teclado ----
        keys = pygame.key.get_pressed()
        rot_input = 0.0
        thrust_on = False

        if abs(cal_xyz[0]) > X_DEADZONE:
            mag = (abs(cal_xyz[0]) - X_DEADZONE) / (128 - X_DEADZONE)
            rot_input = math.copysign(min(1.0, mag), cal_xyz[0]) * ROT_SPEED_MAX
        if cal_xyz[1] > Y_THRUST_THRESHOLD:
            thrust_on = True

        if keys[pygame.K_LEFT] or keys[pygame.K_a]:
            rot_input -= ROT_SPEED_MAX
        if keys[pygame.K_RIGHT] or keys[pygame.K_d]:
            rot_input += ROT_SPEED_MAX
        if keys[pygame.K_UP] or keys[pygame.K_w]:
            thrust_on = True

        # ---- update ----
        if not game_over:
            ship.update(rot_input, thrust_on)
        for a in asteroids:
            a.update()
        for b in bullets:
            b.update()
        bullets = [b for b in bullets if b.alive()]

        # Colisiones bullet vs asteroid: cada bala mata como mucho 1 asteroide.
        hit_bullets: set = set()
        hit_asteroids: set = set()
        fragments: list = []
        for ai, a in enumerate(asteroids):
            if ai in hit_asteroids:
                continue
            for bi, b in enumerate(bullets):
                if bi in hit_bullets:
                    continue
                if toroidal_collide(a, b):
                    hit_bullets.add(bi)
                    hit_asteroids.add(ai)
                    score += a.score
                    fragments.extend(a.split())
                    break
        if hit_bullets:
            bullets = [b for i, b in enumerate(bullets) if i not in hit_bullets]
        if hit_asteroids:
            asteroids = [a for i, a in enumerate(asteroids) if i not in hit_asteroids]
            asteroids.extend(fragments)

        # Colisión ship vs asteroid
        if not game_over and ship.invuln == 0:
            for a in asteroids:
                if toroidal_collide(ship, a):
                    lives -= 1
                    if lives <= 0:
                        game_over = True
                    else:
                        ship.reset_pose()
                    break

        # Spawn de nueva oleada (escala suave con el score)
        if not asteroids and not game_over:
            asteroids = spawn_wave(INITIAL_ASTEROIDS + min(6, score // 2000))

        # ---- render ----
        screen.fill(COLOR_BG)
        for x, y, r in stars:
            pygame.draw.circle(screen, COLOR_STAR, (x, y), r)
        for a in asteroids:
            a.draw(screen)
        for b in bullets:
            b.draw(screen)
        if not game_over:
            ship.draw(screen)

        # HUD superior
        screen.blit(font_big.render(f"SCORE {score}", True, COLOR_TEXT), (20, 14))
        lives_text = font_big.render(f"LIVES {lives}", True, COLOR_TEXT)
        screen.blit(lives_text, (WIN_W - lives_text.get_width() - 20, 14))

        # Game over overlay
        if game_over:
            txt = font_huge.render("GAME OVER", True, COLOR_ALERT)
            screen.blit(txt, (WIN_W // 2 - txt.get_width() // 2, WIN_H // 2 - 70))
            sub = font_big.render(f"score {score}    Enter = restart    Q = salir",
                                  True, COLOR_TEXT)
            screen.blit(sub, (WIN_W // 2 - sub.get_width() // 2, WIN_H // 2))

        # HUD inferior con telemetría
        uart_state = "stream" if streaming else "PAUSED"
        hud1 = (f"ADXL  X{cal_xyz[0]:+4d}  Y{cal_xyz[1]:+4d}  Z{cal_xyz[2]:+4d}"
                f"   UART:{uart_state}"
                f"   offset X{offset[0]:+d} Y{offset[1]:+d} Z{offset[2]:+d}")
        hud2 = ("ADXL: X=rotar  Y=thrust  shake Z=disparar    "
                "kbd: ←/→ ↑ Space   [c]al [p]ause [s]tart [r]eset [Esc]")
        screen.blit(font_small.render(hud1, True, COLOR_DIM), (20, WIN_H - 38))
        screen.blit(font_small.render(hud2, True, COLOR_DIM), (20, WIN_H - 20))

        pygame.display.flip()
        clock.tick(FPS)

    if reader:
        reader.close()
    pygame.quit()


if __name__ == "__main__":
    main()
