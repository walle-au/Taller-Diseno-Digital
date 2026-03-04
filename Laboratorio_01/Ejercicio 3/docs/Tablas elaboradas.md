## Tabla Funcional del PWM

El módulo PWM funciona según las siguientes relaciones generales:

- `PERIOD_CYCLES = 100000`
- `threshold = floor(duty_code × PERIOD_CYCLES / 15)`
- `pwm_out = 1 si counter < threshold`
- `pwm_out = 0 si counter ≥ threshold`

### Relación general duty_code → threshold

| duty_code | threshold (ciclos) | Duty (%) |
|------------|--------------------|-----------|
| 0 | 0 | 0% |
| 1 – 14 | ⌊(duty_code × 100000) / 15⌋ | (threshold / 100000) × 100 |
| 15 | 100000 | 100% |

---

## Tabla de Niveles PWM (PERIOD_CYCLES = 100000)

Para un reloj de 100 MHz (10 ns por ciclo):

- Período total = 1 ms = 1000 µs
- `Ton (µs) = threshold × 0.01`

| duty_code | threshold (ciclos) | Ton (µs) | Duty (%) |
|------------|--------------------|----------|-----------|
| 0  | 0       | 0.00    | 0.000 |
| 1  | 6666    | 66.66   | 6.666 |
| 2  | 13333   | 133.33  | 13.333 |
| 3  | 20000   | 200.00  | 20.000 |
| 4  | 26666   | 266.66  | 26.666 |
| 5  | 33333   | 333.33  | 33.333 |
| 6  | 40000   | 400.00  | 40.000 |
| 7  | 46666   | 466.66  | 46.666 |
| 8  | 53333   | 533.33  | 53.333 |
| 9  | 60000   | 600.00  | 60.000 |
| 10 | 66666   | 666.66  | 66.666 |
| 11 | 73333   | 733.33  | 73.333 |
| 12 | 80000   | 800.00  | 80.000 |
| 13 | 86666   | 866.66  | 86.666 |
| 14 | 93333   | 933.33  | 93.333 |
| 15 | 100000  | 1000.00 | 100.000 |

> Nota: `Toff = 1000 µs − Ton`

---

## Tabla de Verdad Funcional del Comparador PWM

La salida PWM depende del valor del contador y del threshold:

| Condición | pwm_out |
|------------|----------|
| threshold = 0 | 0 |
| 0 < threshold < 100000 y counter < threshold | 1 |
| 0 < threshold < 100000 y counter ≥ threshold | 0 |
| threshold = 100000 | 1 |

---

## Tabla de Comportamiento del Contador

| rst | Evento de reloj | counter |
|------|----------------|----------|
| 1 | flanco positivo | 0 |
| 0 | flanco positivo | counter + 1 |
| counter = 99999 | siguiente flanco | 0 |

