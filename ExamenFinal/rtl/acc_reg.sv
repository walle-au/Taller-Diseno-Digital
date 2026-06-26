module acc_reg (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       clr_i,
    input  logic       en_i,
    input  logic [7:0] d_i,
    output logic [7:0] q_o
);

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            q_o <= 8'd0;
        end else if (clr_i) begin
            q_o <= 8'd0;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end

endmodule : acc_reg
