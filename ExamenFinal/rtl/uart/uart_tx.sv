// =============================================================================
// Archivo      : uart_tx.sv
// Descripción  : Transmisor UART 8N1.
// =============================================================================

module uart_tx (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       tx_tick_i,
    input  logic       start_i,
    input  logic [7:0] data_i,
    output logic       busy_o,
    output logic       done_o,
    output logic       tx_o
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP
    } state_e;

    state_e     state_q;
    logic [7:0] shreg_q;
    logic [2:0] bit_idx_q;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            state_q   <= S_IDLE;
            shreg_q   <= '0;
            bit_idx_q <= '0;
            tx_o      <= 1'b1;
            done_o    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            unique case (state_q)
                S_IDLE: begin
                    tx_o <= 1'b1;
                    if (start_i) begin
                        shreg_q   <= data_i;
                        bit_idx_q <= '0;
                        tx_o      <= 1'b0;        // start bit
                        state_q   <= S_START;
                    end
                end

                S_START: begin
                    tx_o <= 1'b0;
                    if (tx_tick_i) begin
                        tx_o      <= shreg_q[0];
                        shreg_q   <= {1'b0, shreg_q[7:1]};
                        bit_idx_q <= 3'd1;
                        state_q   <= S_DATA;
                    end
                end

                S_DATA: begin
                    if (tx_tick_i) begin
                        if (bit_idx_q == 3'd0) begin
                            tx_o    <= 1'b1;
                            state_q <= S_STOP;
                        end else begin
                            tx_o      <= shreg_q[0];
                            shreg_q   <= {1'b0, shreg_q[7:1]};
                            bit_idx_q <= bit_idx_q + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    tx_o <= 1'b1;
                    if (tx_tick_i) begin
                        done_o  <= 1'b1;
                        state_q <= S_IDLE;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

    assign busy_o = (state_q != S_IDLE);

endmodule : uart_tx
