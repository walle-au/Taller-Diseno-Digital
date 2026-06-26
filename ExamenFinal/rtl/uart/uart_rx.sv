// =============================================================================
// Archivo      : uart_rx.sv
// Descripción  : Receptor UART 8N1 autosuficiente.
// =============================================================================

module uart_rx #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 9600
) (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       rx_i,
    output logic       byte_valid_o,
    output logic [7:0] data_o
);

    localparam int BIT_PERIOD  = CLK_FREQ_HZ / BAUD_RATE;
    localparam int HALF_PERIOD = BIT_PERIOD / 2;
    localparam int CW          = ($clog2(BIT_PERIOD) > 0) ? $clog2(BIT_PERIOD) : 1;

    typedef enum logic [1:0] {
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP
    } state_e;

    state_e        state_q;
    logic [CW-1:0] cnt_q;
    logic [3:0]    bit_idx_q;
    logic [7:0]    shreg_q;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            state_q       <= S_IDLE;
            cnt_q         <= '0;
            bit_idx_q     <= '0;
            shreg_q       <= '0;
            data_o        <= '0;
            byte_valid_o  <= 1'b0;
        end else begin
            byte_valid_o <= 1'b0;

            unique case (state_q)
                S_IDLE: begin
                    cnt_q     <= '0;
                    bit_idx_q <= '0;
                    if (!rx_i) begin
                        state_q <= S_START;
                    end
                end

                S_START: begin
                    if (cnt_q == CW'(HALF_PERIOD - 1)) begin
                        cnt_q <= '0;
                        if (rx_i) begin
                            state_q <= S_IDLE;
                        end else begin
                            state_q <= S_DATA;
                        end
                    end else begin
                        cnt_q <= cnt_q + CW'(1);
                    end
                end

                S_DATA: begin
                    if (cnt_q == CW'(BIT_PERIOD - 1)) begin
                        cnt_q   <= '0;
                        shreg_q <= {rx_i, shreg_q[7:1]};
                        if (bit_idx_q == 4'd7) begin
                            state_q <= S_STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 4'd1;
                        end
                    end else begin
                        cnt_q <= cnt_q + CW'(1);
                    end
                end

                S_STOP: begin
                    if (cnt_q == CW'(BIT_PERIOD - 1)) begin
                        cnt_q        <= '0;
                        data_o       <= shreg_q;
                        byte_valid_o <= 1'b1;
                        state_q      <= S_IDLE;
                    end else begin
                        cnt_q <= cnt_q + CW'(1);
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule : uart_rx
