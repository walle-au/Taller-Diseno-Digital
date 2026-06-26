// =============================================================================
// Archivo      : adder_8bit.sv
// Descripción  : Sumador combinacional de 8 bits.
// =============================================================================

module adder_8bit (
    input  logic [7:0] a_i,
    input  logic [7:0] b_i,
    output logic [7:0] sum_o
);

    assign sum_o = a_i + b_i;

endmodule : adder_8bit
