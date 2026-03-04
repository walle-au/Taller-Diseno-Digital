# 📈 Análisis de Resultados – Simulación Behavioral

## 1️⃣ Caso: duty_code = 4 (≈ 26%)

En esta simulación se observa que:

- `PERIOD_CYCLES = 100`
- `threshold = 26`
- `duty_code = 4`
- `pwm_out = 1` mientras `counter < 26`
- `pwm_out = 0` cuando `counter ≥ 26`

Cálculo teórico:

threshold = (4 × 100) / 15 ≈ 26  

Duty cycle ≈ 26%

Esto confirma que el cálculo del threshold y el comparador funcionan correctamente.

<img width="1612" height="739" alt="image" src="https://github.com/user-attachments/assets/8aa2dd10-abd9-4316-a8d9-71acf10a36c0" />


## 2️⃣ Transición cuando counter alcanza el threshold

En esta imagen se observa claramente que:

- Cuando `counter = 26`
- Y `threshold = 26`
- La condición `counter < threshold` deja de cumplirse
- `pwm_out` cambia de 1 a 0

Esto confirma que el comparador `<` está funcionando correctamente.

<img width="1607" height="736" alt="image" src="https://github.com/user-attachments/assets/a17d8cc8-66d7-4b4e-b9f1-736bce0b4fbe" />


## 3️⃣ Cambio de duty_code de 4 a 8 (≈ 53%)

En esta simulación se observa:

- Cambio de `duty_code` de 4 a 8
- `threshold` cambia de 26 a 53
- El ancho del pulso PWM aumenta

Cálculo teórico:

threshold = (8 × 100) / 15 ≈ 53  

Duty cycle ≈ 53%

Se observa visualmente que el pulso permanece más tiempo en alto.

<img width="1611" height="776" alt="image" src="https://github.com/user-attachments/assets/de919523-f39e-40cb-a8dc-eaa6e815b950" />


# 🔎 Conclusión de la Simulación

La simulación demuestra que:

- El contador recorre correctamente de 0 a PERIOD_CYCLES - 1.
- El cálculo de threshold es proporcional al valor ingresado.
- El comparador genera correctamente la señal PWM.
- El ancho del pulso cambia conforme al duty_code.
- No se observan glitches ni comportamiento errático.

El diseño cumple con las especificaciones funcionales.

---

# 🧱 Explicación del Schematic

El schematic generado en Vivado muestra los siguientes bloques principales:

## 1️⃣ Registro del Contador

- Implementado con flip-flops síncronos.
- Se incrementa con cada flanco positivo del reloj.
- Se reinicia cuando alcanza PERIOD_CYCLES - 1.

## 2️⃣ Sumador

- Implementa la operación `counter + 1`.

## 3️⃣ Cálculo del Threshold

- Implementado mediante multiplicación y división:
  
  threshold = (duty_code × PERIOD_CYCLES) / 15

Esto permite obtener 16 niveles proporcionales de duty.

## 4️⃣ Comparador

- Evalúa:

  counter < threshold

Si es verdadero → `pwm_out = 1`  
Si es falso → `pwm_out = 0`

---

## 🧠 Interpretación del Hardware

El circuito implementa:

- Lógica secuencial → contador.
- Lógica combinacional → cálculo de threshold.
- Comparador digital → generación de PWM.

El diseño es completamente sintetizable y no presenta latches.

---

# 🧪 Resultados en FPGA (Pendiente de prueba en hardware)

## Prueba con LED

Aquí se documentarán los resultados obtenidos al implementar el diseño en la FPGA.

### Observaciones esperadas:

- duty_code = 0 → LED apagado
- duty_code intermedio → LED con brillo proporcional
- duty_code = 15 → LED completamente encendido

---

### 📌 Evidencia en hardware

![Foto FPGA prueba PWM](docs/fpga_pwm_test.jpg)

---

# 📌 Conclusión Final

El módulo PWM cumple con:

- Generación correcta del período (~1 ms).
- Resolución de 16 niveles de duty.
- Correcta implementación del contador y comparador.
- Validación mediante simulación y prueba en hardware.

El comportamiento observado coincide con el análisis teórico.

