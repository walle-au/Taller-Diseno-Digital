# Implementación de FSM para suma `AB + CD` mediante UART

## Descripción general

Este proyecto implementa en SystemVerilog un sistema digital basado en una máquina de estados finita. El sistema recibe cuatro caracteres ASCII por medio de UART RX, correspondientes a los dígitos `A`, `B`, `C` y `D`. Estos dígitos forman dos números decimales de dos cifras:

```text
AB = 10*A + B
CD = 10*C + D
```

Posteriormente, el sistema calcula:

```text
Resultado = AB + CD
```

El resultado se transmite por UART TX como un dato binario sin signo de 8 bits.

La implementación utiliza un reloj de sistema de `100 MHz` y una comunicación UART configurada a `115200 bps`.

---

## Jerarquía del sistema

El módulo superior del diseño es `uart_sum_top`, el cual integra la UART, la máquina de estados, la memoria y el camino de datos.

```text
uart_sum_top
├── sync_2ff
├── uart_rx
├── uart_baud_gen
├── uart_tx
├── ascii_to_digit
├── digit_mem_4x4
├── mux_x1_x10
├── adder_8bit
├── acc_reg
└── fsm_control
```

---

## Descripción de módulos

| Módulo           | Descripción                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `uart_sum_top`   | Módulo superior del sistema. Conecta todos los bloques internos.                             |
| `sync_2ff`       | Sincroniza la señal externa `uart_rx_i` al dominio de reloj del sistema.                     |
| `uart_rx`        | Receptor UART 8N1. Entrega el byte recibido y un pulso de dato válido.                       |
| `uart_baud_gen`  | Genera el pulso de baudrate utilizado por el transmisor UART.                                |
| `uart_tx`        | Transmisor UART 8N1. Envía el resultado final por `uart_tx_o`.                               |
| `ascii_to_digit` | Convierte caracteres ASCII numéricos `'0'` a `'9'` en valores binarios de 4 bits.            |
| `digit_mem_4x4`  | Memoria de cuatro posiciones para almacenar los dígitos `A`, `B`, `C` y `D`.                 |
| `mux_x1_x10`     | Selecciona si el dígito leído desde memoria se usa multiplicado por `1` o por `10`.          |
| `adder_8bit`     | Suma el valor seleccionado con el valor almacenado en el acumulador.                         |
| `acc_reg`        | Registro acumulador de 8 bits donde se construye el resultado `AB + CD`.                     |
| `fsm_control`    | Máquina de estados tipo Moore que controla recepción, almacenamiento, cálculo y transmisión. |

---

## Funcionamiento del camino de datos

El cálculo se realiza de forma secuencial utilizando el bloque `x1/x10`, el sumador y el acumulador. La operación realizada es:

```text
acc = 0
acc = acc + 10*A
acc = acc + B
acc = acc + 10*C
acc = acc + D
```

Por lo tanto:

```text
acc = 10*A + B + 10*C + D
acc = AB + CD
```

El valor final del acumulador se conecta al transmisor UART para ser enviado como un byte binario sin signo.

---

## Fuente de la UART

Para la comunicación UART se reutilizaron los módulos empleados en los laboratorios previos del curso:

```text
uart_rx.sv
uart_tx.sv
uart_baud_gen.sv
```

Estos módulos implementan una UART 8N1. El receptor `uart_rx` genera un pulso `byte_valid_o` cuando el dato recibido es válido. El transmisor `uart_tx` recibe una señal `start_i`, el dato `data_i`, y entrega señales de estado como `busy_o` y `done_o`.

---

## Testbench autoverificable

El archivo de simulación principal es:

```text
sim/tb_uart_sum_top.sv
```

El testbench envía cuatro caracteres ASCII por la entrada `uart_rx_i`, espera el resultado transmitido por `uart_tx_o` y compara automáticamente el dato recibido contra el valor esperado.

Se realizaron las siguientes pruebas:

| Entrada UART RX   | Operación esperada | Resultado esperado |
| ----------------- | -----------------: | -----------------: |
| `"1" "2" "3" "4"` |          `12 + 34` |       `46 = 8'h2E` |
| `"9" "9" "9" "9"` |          `99 + 99` |      `198 = 8'hC6` |
| `"0" "5" "0" "7"` |          `05 + 07` |       `12 = 8'h0C` |

---

## Resultados de consola

La simulación en Vivado/XSim produjo los siguientes resultados:

```text
OK: A=1 B=2 C=3 D=4 | resultado=0x2e (46)
OK: A=9 B=9 C=9 D=9 | resultado=0xc6 (198)
OK: A=0 B=5 C=0 D=7 | resultado=0x0c (12)
Todas las pruebas finalizaron.
```

Estos mensajes indican que el testbench verificó automáticamente los resultados transmitidos por UART TX y que todos coincidieron con los valores esperados.

---

## Archivos principales

```text
rtl/uart_sum_top.sv       Módulo superior
rtl/fsm_control.sv        Máquina de estados finita
rtl/ascii_to_digit.sv     Conversor ASCII a número
rtl/digit_mem_4x4.sv      Memoria de cuatro dígitos
rtl/mux_x1_x10.sv         Selector x1/x10
rtl/adder_8bit.sv         Sumador de 8 bits
rtl/acc_reg.sv            Registro acumulador
rtl/sync_2ff.sv           Sincronizador de entrada RX
rtl/uart/uart_rx.sv       Receptor UART
rtl/uart/uart_tx.sv       Transmisor UART
rtl/uart/uart_baud_gen.sv Generador de baudrate para TX
sim/tb_uart_sum_top.sv    Testbench autoverificable
```

---

## Parámetros de simulación

```text
Frecuencia de reloj: 100 MHz
Baud rate UART:      115200 bps
Formato UART:        8N1
```

---

## Conclusión

El sistema implementado cumple con la recepción de cuatro caracteres ASCII por UART, su conversión a valores numéricos, el almacenamiento en memoria, el cálculo de `AB + CD` mediante un camino de datos secuencial y la transmisión del resultado final por UART. La simulación autoverificable confirmó el funcionamiento correcto para diferentes casos de prueba.

