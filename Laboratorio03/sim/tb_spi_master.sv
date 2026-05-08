// =============================================================================
// Archivo      : sim/tb_spi_master.sv
// Autor        : Walter-Allan-Alexander-Esteban
// Fecha        : 7 de mayo de 2026
// Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
// Lab 3        : TB self-checking del núcleo spi_master.
//
// Verifica:
//   1. Una transacción de 8 bits con tx_data_i=0x5A intercambia datos con
//      un slave-stub que responde 0xA5 (siempre).
//   2. El byte recibido en rx_data_o es 0xA5.
//   3. El número de flancos de subida de SCLK es exactamente 8.
//   4. La frecuencia de SCLK = sysclk / (2 * clk_div) = 50/(2*4) = 6.25 MHz.
//   5. busy_o sube al iniciar y baja al pulso de done_o.
//
// El slave-stub usado aquí es un shift register sencillo (no modela el
// ADXL362 — eso se hace en tb_spi_axil). Solo entrega un byte fijo MSB-first.
// =============================================================================

`timescale 1ns/1ps

module tb_spi_master;

    localparam int  CLK_PER_NS    = 20;          // 50 MHz
    localparam int  CLK_DIV       = 4;           // SCLK = 6.25 MHz
    localparam byte MASTER_TX     = 8'h5A;       // patrón master -> slave
    localparam byte SLAVE_TX      = 8'hA5;       // patrón slave  -> master

    logic clk = 0;
    always #(CLK_PER_NS/2) clk = ~clk;

    logic        rst_n;
    logic [7:0]  clk_div;
    logic        start;
    logic [7:0]  tx_data;
    logic        busy, done;
    logic [7:0]  rx_data;

    logic        sclk, mosi, miso;

    // ---- DUT --------------------------------------------------------------
    spi_master #(.DATA_WIDTH(8)) u_dut (
        .clk_i     (clk),
        .rst_n_i   (rst_n),
        .clk_div_i (clk_div),
        .start_i   (start),
        .tx_data_i (tx_data),
        .busy_o    (busy),
        .done_o    (done),
        .rx_data_o (rx_data),
        .sclk_o    (sclk),
        .mosi_o    (mosi),
        .miso_i    (miso)
    );

    // ---- Slave stub: shift register que entrega SLAVE_TX MSB-first --------
    //  - tx_shift_q es el shift register de salida del slave.
    //  - Se carga con SLAVE_TX antes del primer flanco de SCLK.
    //  - Cada flanco de bajada de SCLK desplaza un bit (MSB sale, LSB entra 0).
    //  - MISO = tx_shift_q[7].
    // -------------------------------------------------------------------------
    logic [7:0] slave_tx_shift_q;
    logic [7:0] slave_rx_shift_q;
    int unsigned slave_rising_count;

    initial begin
        slave_tx_shift_q   = SLAVE_TX;
        slave_rx_shift_q   = '0;
        slave_rising_count = 0;
    end

    // Importante: gateamos por rst_n para evitar que la transición X->0
    // de sclk al arrancar la sim (antes de que el master haya manejado el
    // reset) dispare un negedge espurio que shiftee el TX prematuramente.
    always @(posedge sclk) begin
        if (rst_n) begin
            slave_rx_shift_q   <= {slave_rx_shift_q[6:0], mosi};
            slave_rising_count <= slave_rising_count + 1;
        end
    end

    always @(negedge sclk) begin
        if (rst_n) slave_tx_shift_q <= {slave_tx_shift_q[6:0], 1'b0};
    end

    assign miso = slave_tx_shift_q[7];

    // ---- Cronómetro de SCLK (medir período) -------------------------------
    time t_first_rise, t_last_rise;
    int unsigned rise_count;

    initial begin
        rise_count = 0;
        t_first_rise = 0;
        t_last_rise  = 0;
    end

    always @(posedge sclk) begin
        if (rise_count == 0) t_first_rise = $time;
        t_last_rise = $time;
        rise_count <= rise_count + 1;
    end

    // ---- Helpers de chequeo ----------------------------------------------
    int errors = 0;
    int checks = 0;

    task automatic check(input bit cond, input string msg);
        checks++;
        if (cond) $display("[PASS] %s", msg);
        else begin errors++; $display("[FAIL] %s", msg); end
    endtask

    // ---- Watchdog ---------------------------------------------------------
    initial begin
        #5_000;
        $fatal(1, "Timeout 5 us en tb_spi_master");
    end

    // ---- Estímulo principal -----------------------------------------------
    initial begin
        // Locales del initial (XSim requiere automatic/static explícito si
        // viven dentro de bloques begin/end anidados — los movemos arriba).
        int  max_polls;
        bit  got_done;
        real medido_ns;
        real esperado;
        real err_pct;

        // Init
        rst_n   = 0;
        clk_div = CLK_DIV[7:0];
        start   = 0;
        tx_data = '0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("==== tb_spi_master (CLK_DIV=%0d) ====", CLK_DIV);

        // T1: estado en reposo
        check(busy === 1'b0, "T1 busy=0 en reposo");
        check(sclk === 1'b0, "T1 SCLK=0 en reposo (CPOL=0)");

        // T2: disparar transferencia
        @(posedge clk);
        tx_data <= MASTER_TX;
        start   <= 1'b1;
        @(posedge clk);
        start   <= 1'b0;

        // Esperar busy=1 (entró a S_LOW)
        @(posedge clk);
        check(busy === 1'b1, "T2 busy=1 tras start");

        // T3: esperar done_o (pulso 1 ciclo) con polling
        max_polls = 16 * 2 * CLK_DIV + 50;
        got_done  = 0;
        for (int i = 0; i < max_polls; i++) begin
            @(posedge clk);
            if (done) begin
                got_done = 1;
                break;
            end
        end
        check(got_done, "T3 done pulsó dentro del timeout");

        // T4: byte recibido
        check(rx_data === SLAVE_TX,
              $sformatf("T4 rx_data = 0x%02h (esperado 0x%02h)", rx_data, SLAVE_TX));

        // T5: byte recibido por el slave
        check(slave_rx_shift_q === MASTER_TX,
              $sformatf("T5 slave recibió 0x%02h (esperado 0x%02h)",
                        slave_rx_shift_q, MASTER_TX));

        // T6: número de flancos de subida = 8
        check(rise_count == 8, $sformatf("T6 SCLK rising edges = %0d (esperado 8)", rise_count));

        // T7: período medio de SCLK
        // 7 períodos completos entre el 1er y el 8vo flanco de subida.
        // Período esperado = 2 * CLK_DIV * CLK_PER_NS = 2*4*20 = 160 ns.
        medido_ns = (real'(t_last_rise - t_first_rise)) / 7.0;
        esperado  = 2.0 * CLK_DIV * CLK_PER_NS;
        err_pct   = (medido_ns - esperado) / esperado * 100.0;
        $display("[INFO] T7 período SCLK medido = %.2f ns (esperado %.2f, err %.2f%%)",
                 medido_ns, esperado, err_pct);
        check(err_pct > -1.0 && err_pct < 1.0,
              "T7 período SCLK dentro de +/-1%");

        // T8: vuelta a reposo
        @(posedge clk); @(posedge clk);
        check(busy === 1'b0, "T8 busy=0 al volver a IDLE");
        check(sclk === 1'b0, "T8 SCLK=0 al volver a IDLE");

        // ---- Resumen ------------------------------------------------------
        $display("==== Resultado: %0d/%0d checks OK, %0d FAIL ====",
                 checks - errors, checks, errors);

        if (errors == 0) $display("[PASS] tb_spi_master OK");
        else             $fatal(1, "tb_spi_master FALLO (%0d errores)", errors);

        $finish;
    end

endmodule : tb_spi_master
