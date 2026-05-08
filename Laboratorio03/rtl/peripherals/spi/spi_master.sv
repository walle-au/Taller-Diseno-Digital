// =============================================================================
// Archivo      : rtl/peripherals/spi/spi_master.sv
// Autor        : Walter-Allan-Alexander-Esteban
// Fecha        : 7 de mayo de 2026
// Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
// Lab 3        : Núcleo SPI master para comunicación con el ADXL362
//                (acelerómetro onboard de la Nexys4 DDR).
//
// Spec:
//   - Modo SPI 0 (CPOL=0, CPHA=0):
//       * SCLK reposa en 0.
//       * Master presenta MOSI; slave muestrea en flanco de SUBIDA.
//       * Master cambia MOSI en flanco de BAJADA (excepto el primer bit,
//         que sale al cargar el shift register en S_LOW de la primera ronda).
//   - Tamaño de palabra: 8 bits, MSB-first.
//   - SCLK = sysclk / (2 * clk_div_i)  (clk_div_i >= 1)
//   - El control de CSn NO está en este módulo: queda a cargo del wrapper
//     AXI-Lite (lo maneja el firmware vía bit dedicado).
//
// Una transacción de N bytes se hace con N pulsos de start_i por SW;
// el caller mantiene CSn bajo durante toda la ráfaga.
//
// Asistencia IA: estructura de la FSM revisada con Claude (Anthropic).
// =============================================================================

module spi_master #(
    parameter int unsigned DATA_WIDTH = 8
) (
    input  logic                    clk_i,
    input  logic                    rst_n_i,

    // Configuración (sampled implícitamente en cada transferencia)
    input  logic [7:0]              clk_div_i,    // ciclos sysclk por semi-período (>=1)

    // Control / status
    input  logic                    start_i,      // pulso de 1 ciclo para iniciar
    input  logic [DATA_WIDTH-1:0]   tx_data_i,    // capturado en S_IDLE->S_LOW
    output logic                    busy_o,
    output logic                    done_o,       // pulso de 1 ciclo al terminar
    output logic [DATA_WIDTH-1:0]   rx_data_o,

    // Bus SPI (modo 0)
    output logic                    sclk_o,
    output logic                    mosi_o,
    input  logic                    miso_i
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_LOW,    // SCLK = 0  (master presenta MOSI estable)
        S_HIGH    // SCLK = 1  (slave muestrea MOSI; master ya capturó MISO)
    } state_e;

    state_e                  state_q;
    logic [7:0]              tick_q;          // contador del semi-período
    logic [3:0]              bit_q;           // bits transferidos (0..DATA_WIDTH-1)
    logic [DATA_WIDTH-1:0]   shift_q;
    logic                    miso_sample_q;   // MISO capturado en flanco de subida
    logic                    sclk_q;

    // tick_q va de 0 a (clk_div_i - 1). Cuando (tick_q + 1 == clk_div_i),
    // estamos en el último ciclo del semi-período actual.
    logic tick_done;
    assign tick_done = ((tick_q + 8'd1) == clk_div_i);

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            state_q       <= S_IDLE;
            tick_q        <= '0;
            bit_q         <= '0;
            shift_q       <= '0;
            miso_sample_q <= 1'b0;
            sclk_q        <= 1'b0;
            rx_data_o     <= '0;
            done_o        <= 1'b0;
        end else begin
            done_o <= 1'b0;

            unique case (state_q)
                // -----------------------------------------------------------
                // S_IDLE: SCLK=0. Espera start.
                // -----------------------------------------------------------
                S_IDLE: begin
                    sclk_q <= 1'b0;
                    tick_q <= '0;
                    if (start_i) begin
                        shift_q <= tx_data_i;
                        bit_q   <= '0;
                        state_q <= S_LOW;
                    end
                end

                // -----------------------------------------------------------
                // S_LOW: SCLK=0; MOSI=shift_q[MSB] estable durante semi-período.
                // Al final, flanco de subida → muestreamos MISO.
                // -----------------------------------------------------------
                S_LOW: begin
                    if (tick_done) begin
                        tick_q        <= '0;
                        sclk_q        <= 1'b1;          // flanco de subida
                        miso_sample_q <= miso_i;        // master sample MISO
                        state_q       <= S_HIGH;
                    end else begin
                        tick_q <= tick_q + 8'd1;
                    end
                end

                // -----------------------------------------------------------
                // S_HIGH: SCLK=1; MOSI sigue estable. Al final, flanco de
                // bajada → desplazamos shift_q y avanzamos al siguiente bit
                // (o capturamos byte completo si era el último).
                // -----------------------------------------------------------
                S_HIGH: begin
                    if (tick_done) begin
                        tick_q <= '0;
                        sclk_q <= 1'b0;                 // flanco de bajada
                        if (bit_q == DATA_WIDTH - 1) begin
                            // Último bit: capturar byte recibido completo
                            rx_data_o <= {shift_q[DATA_WIDTH-2:0], miso_sample_q};
                            done_o    <= 1'b1;
                            state_q   <= S_IDLE;
                        end else begin
                            // Shift-left + insertar MISO en LSB; nuevo MOSI listo
                            shift_q <= {shift_q[DATA_WIDTH-2:0], miso_sample_q};
                            bit_q   <= bit_q + 4'd1;
                            state_q <= S_LOW;
                        end
                    end else begin
                        tick_q <= tick_q + 8'd1;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

    assign sclk_o = sclk_q;
    assign mosi_o = shift_q[DATA_WIDTH-1];
    assign busy_o = (state_q != S_IDLE);

endmodule : spi_master
