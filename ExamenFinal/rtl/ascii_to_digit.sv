// =============================================================================
// Archivo      : ascii_to_digit.sv
// Descripción  : Decodificador de ASCII numérico a dígito binario.
// =============================================================================

module ascii_to_digit (
    input  logic [7:0] ascii_i,
    output logic [3:0] digit_o,
    output logic       digit_valid_o
);

    always_comb begin
        if (ascii_i >= 8'h30 && ascii_i <= 8'h39) begin
            digit_o       = ascii_i[3:0]; // equivalente a ascii_i - 8'h30
            digit_valid_o = 1'b1;
        end else begin
            digit_o       = 4'd0;
            digit_valid_o = 1'b0;
        end
    end

endmodule : ascii_to_digit
