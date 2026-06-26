// =============================================================================
// Archivo      : sync_2ff.sv
// Descripción  : Sincronizador de dos flip-flops para señales asíncronas.
// =============================================================================

module sync_2ff (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic async_i,
    output logic sync_o
);

    logic ff1_q;
    logic ff2_q;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            ff1_q <= 1'b1;
            ff2_q <= 1'b1;
        end else begin
            ff1_q <= async_i;
            ff2_q <= ff1_q;
        end
    end

    assign sync_o = ff2_q;

endmodule : sync_2ff
