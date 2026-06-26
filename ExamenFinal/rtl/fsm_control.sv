// =============================================================================
// Archivo      : fsm_control.sv
// Descripción  : FSM de control tipo Moore para recepción, cálculo y transmisión.
// =============================================================================

module fsm_control (
    input  logic clk_i,
    input  logic rst_n_i,

    input  logic rx_valid_i,
    input  logic digit_valid_i,
    input  logic tx_busy_i,
    input  logic tx_done_i,

    output logic       mem_en_o,
    output logic       mem_wr_o,
    output logic [1:0] mem_addr_o,

    output logic       sel_x10_o,
    output logic       acc_clr_o,
    output logic       acc_en_o,

    output logic       tx_start_o
);

    typedef enum logic [4:0] {
        S_IDLE,
        S_WAIT_A,
        S_STORE_A,
        S_WAIT_B,
        S_STORE_B,
        S_WAIT_C,
        S_STORE_C,
        S_WAIT_D,
        S_STORE_D,
        S_CLR_ACC,
        S_ADD_A10,
        S_ADD_B,
        S_ADD_C10,
        S_ADD_D,
        S_WAIT_TX,
        S_SEND_TX,
        S_WAIT_DONE,
        S_CLEAR
    } state_t;

    state_t state_q;
    state_t state_d;

    // -------------------------------------------------------------------------
    // Registro de estado
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_n_i)
            state_q <= S_IDLE;
        else
            state_q <= state_d;
    end

    // -------------------------------------------------------------------------
    // Lógica de próximo estado
    // -------------------------------------------------------------------------
    always_comb begin
        state_d = state_q;

        unique case (state_q)

            S_IDLE:
                state_d = S_WAIT_A;

            S_WAIT_A:
                if (rx_valid_i && digit_valid_i)
                    state_d = S_STORE_A;

            S_STORE_A:
                state_d = S_WAIT_B;

            S_WAIT_B:
                if (rx_valid_i && digit_valid_i)
                    state_d = S_STORE_B;

            S_STORE_B:
                state_d = S_WAIT_C;

            S_WAIT_C:
                if (rx_valid_i && digit_valid_i)
                    state_d = S_STORE_C;

            S_STORE_C:
                state_d = S_WAIT_D;

            S_WAIT_D:
                if (rx_valid_i && digit_valid_i)
                    state_d = S_STORE_D;

            S_STORE_D:
                state_d = S_CLR_ACC;

            S_CLR_ACC:
                state_d = S_ADD_A10;

            S_ADD_A10:
                state_d = S_ADD_B;

            S_ADD_B:
                state_d = S_ADD_C10;

            S_ADD_C10:
                state_d = S_ADD_D;

            S_ADD_D:
                state_d = S_WAIT_TX;

            S_WAIT_TX:
                if (!tx_busy_i)
                    state_d = S_SEND_TX;

            S_SEND_TX:
                state_d = S_WAIT_DONE;

            S_WAIT_DONE:
                if (tx_done_i)
                    state_d = S_CLEAR;

            S_CLEAR:
                state_d = S_WAIT_A;

            default:
                state_d = S_IDLE;

        endcase
    end

    // -------------------------------------------------------------------------
    // Salidas Moore
    // -------------------------------------------------------------------------
    always_comb begin
        mem_en_o    = 1'b0;
        mem_wr_o    = 1'b0;
        mem_addr_o  = 2'd0;

        sel_x10_o   = 1'b0;
        acc_clr_o   = 1'b0;
        acc_en_o    = 1'b0;

        tx_start_o  = 1'b0;

        unique case (state_q)

            // Guardar A, B, C y D ya convertidos desde ASCII a dígito.
            S_STORE_A: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b1;
                mem_addr_o = 2'd0;
            end

            S_STORE_B: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b1;
                mem_addr_o = 2'd1;
            end

            S_STORE_C: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b1;
                mem_addr_o = 2'd2;
            end

            S_STORE_D: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b1;
                mem_addr_o = 2'd3;
            end

            // Limpiar acumulador antes de iniciar la operación:
            // acc = 0
            S_CLR_ACC: begin
                acc_clr_o = 1'b1;
            end

            // acc = acc + 10*A
            S_ADD_A10: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b0;
                mem_addr_o = 2'd0;
                sel_x10_o  = 1'b1;
                acc_en_o   = 1'b1;
            end

            // acc = acc + B
            S_ADD_B: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b0;
                mem_addr_o = 2'd1;
                sel_x10_o  = 1'b0;
                acc_en_o   = 1'b1;
            end

            // acc = acc + 10*C
            S_ADD_C10: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b0;
                mem_addr_o = 2'd2;
                sel_x10_o  = 1'b1;
                acc_en_o   = 1'b1;
            end

            // acc = acc + D
            // Al final: acc = 10*A + B + 10*C + D = AB + CD.
            S_ADD_D: begin
                mem_en_o   = 1'b1;
                mem_wr_o   = 1'b0;
                mem_addr_o = 2'd3;
                sel_x10_o  = 1'b0;
                acc_en_o   = 1'b1;
            end

            // Pulso de un ciclo para iniciar transmisión.
            S_SEND_TX: begin
                tx_start_o = 1'b1;
            end

            // Preparar el sistema para una nueva secuencia de cuatro ASCII.
            S_CLEAR: begin
                acc_clr_o = 1'b1;
            end

            default: begin
                // Valores por defecto.
            end

        endcase
    end

endmodule : 
