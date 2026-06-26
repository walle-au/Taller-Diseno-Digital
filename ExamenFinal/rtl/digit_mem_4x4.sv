// =============================================================================
// Archivo      : digit_mem_4x4.sv
// Descripción  : Memoria de cuatro posiciones de 4 bits para A, B, C y D.
// =============================================================================

module digit_mem_4x4 (
    input  logic       clk_i,
    input  logic       en_i,
    input  logic       wr_i,
    input  logic [1:0] addr_i,
    input  logic [3:0] din_i,
    output logic [3:0] dout_o
);

    logic [3:0] mem_q [0:3];

    always_ff @(posedge clk_i) begin
        if (en_i && wr_i) begin
            mem_q[addr_i] <= din_i;
        end
    end

    // Lectura combinacional para que el dato esté disponible durante
    // los estados de cálculo de la FSM.
    assign dout_o = mem_q[addr_i];

endmodule : digit_mem_4x4
