// =============================================================================
// Archivo      : uart_baud_gen.sv
// Descripción  : Generador de tick de baudrate para UART TX.
// =============================================================================

module uart_baud_gen #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 9600
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic tx_active_i,
    output logic tx_tick_o
);

    localparam int TX_DIV = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CW     = ($clog2(TX_DIV) > 0) ? $clog2(TX_DIV) : 1;

    logic [CW-1:0] cnt_q;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i || !tx_active_i) begin
            cnt_q     <= '0;
            tx_tick_o <= 1'b0;
        end else if (cnt_q == CW'(TX_DIV - 1)) begin
            cnt_q     <= '0;
            tx_tick_o <= 1'b1;
        end else begin
            cnt_q     <= cnt_q + CW'(1);
            tx_tick_o <= 1'b0;
        end
    end

endmodule : uart_baud_gen
