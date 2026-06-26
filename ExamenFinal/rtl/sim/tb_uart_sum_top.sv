`timescale 1ns/1ps

// =============================================================================
// Archivo      : tb_uart_sum_top.sv
// Descripción  : Testbench autoverificable para uart_sum_top.
// =============================================================================

module tb_uart_sum_top;

    localparam int CLK_FREQ_HZ = 100_000_000;
    localparam int BAUD_RATE   = 115200;
    localparam int BIT_PERIOD  = CLK_FREQ_HZ / BAUD_RATE;

    logic clk_i;
    logic rst_n_i;
    logic uart_rx_i;
    logic uart_tx_o;

    logic [7:0] tx_byte;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    uart_sum_top #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) dut (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o)
    );

    // -------------------------------------------------------------------------
    // Reloj de 100 MHz
    // -------------------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    // -------------------------------------------------------------------------
    // Enviar byte UART hacia el RX del DUT, formato 8N1, LSB primero.
    // -------------------------------------------------------------------------
    task automatic send_uart_byte(input logic [7:0] data);
        int i;
        begin
            // Start bit
            uart_rx_i = 1'b0;
            repeat (BIT_PERIOD) @(posedge clk_i);

            // 8 bits de datos, LSB primero
            for (i = 0; i < 8; i++) begin
                uart_rx_i = data[i];
                repeat (BIT_PERIOD) @(posedge clk_i);
            end

            // Stop bit
            uart_rx_i = 1'b1;
            repeat (BIT_PERIOD) @(posedge clk_i);

            // Pequeña separación entre caracteres
            repeat (BIT_PERIOD) @(posedge clk_i);
        end
    endtask

    // -------------------------------------------------------------------------
    // Leer byte UART desde el TX del DUT, formato 8N1, LSB primero.
    // -------------------------------------------------------------------------
    task automatic receive_uart_byte(output logic [7:0] data);
        int i;
        begin
            data = 8'd0;

            // Esperar start bit
            @(negedge uart_tx_o);

            // Llegar al centro del bit 0:
            // 1 periodo para pasar el start + medio periodo del bit 0.
            repeat (BIT_PERIOD + (BIT_PERIOD / 2)) @(posedge clk_i);

            for (i = 0; i < 8; i++) begin
                data[i] = uart_tx_o;
                repeat (BIT_PERIOD) @(posedge clk_i);
            end

            // Stop bit
            repeat (BIT_PERIOD) @(posedge clk_i);
        end
    endtask

    // -------------------------------------------------------------------------
    // Ejecutar una prueba completa: enviar A,B,C,D y verificar AB+CD.
    // -------------------------------------------------------------------------
    task automatic run_test(
        input logic [7:0] ascii_A,
        input logic [7:0] ascii_B,
        input logic [7:0] ascii_C,
        input logic [7:0] ascii_D,
        input logic [7:0] expected
    );
        begin
            tx_byte = 8'h00;

            fork
                begin
                    send_uart_byte(ascii_A);
                    send_uart_byte(ascii_B);
                    send_uart_byte(ascii_C);
                    send_uart_byte(ascii_D);
                end

                begin
                    receive_uart_byte(tx_byte);
                end
            join

            if (tx_byte !== expected) begin
                $error("FALLO: A=%s B=%s C=%s D=%s | esperado=0x%02h (%0d), recibido=0x%02h (%0d)",
                       ascii_A, ascii_B, ascii_C, ascii_D,
                       expected, expected, tx_byte, tx_byte);
            end else begin
                $display("OK: A=%s B=%s C=%s D=%s | resultado=0x%02h (%0d)",
                         ascii_A, ascii_B, ascii_C, ascii_D,
                         tx_byte, tx_byte);
            end

            repeat (10 * BIT_PERIOD) @(posedge clk_i);
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia principal
    // -------------------------------------------------------------------------
    initial begin
        uart_rx_i = 1'b1;
        rst_n_i   = 1'b0;

        repeat (20) @(posedge clk_i);
        rst_n_i = 1'b1;
        repeat (20) @(posedge clk_i);

        // Prueba 1:
        // AB = 12, CD = 34, AB + CD = 46 = 0x2E
        run_test("1", "2", "3", "4", 8'h2E);

        // Prueba 2:
        // AB = 99, CD = 99, AB + CD = 198 = 0xC6
        run_test("9", "9", "9", "9", 8'hC6);

        // Prueba 3:
        // AB = 05, CD = 07, AB + CD = 12 = 0x0C
        run_test("0", "5", "0", "7", 8'h0C);

        $display("Todas las pruebas finalizaron.");
        $finish;
    end

endmodule : tb_uart_sum_top
