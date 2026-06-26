// =============================================================================
// Archivo      : mux_x1_x10.sv
// Descripción  : Selector para usar un dígito multiplicado por 1 o por 10.
// =============================================================================

module mux_x1_x10 (
    input  logic [3:0] digit_i,
    input  logic       sel_x10_i,
    output logic [7:0] value_o
);

    always_comb begin
        if (sel_x10_i)
            value_o = {4'd0, digit_i} * 8'd10;
        else
            value_o = {4'd0, digit_i};
    end

endmodule : mux_x1_x10
