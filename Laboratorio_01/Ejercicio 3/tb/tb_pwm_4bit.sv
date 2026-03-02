module tb_pwm_4bit_compact;

    // Clock 100 MHz (10 ns)
    localparam int unsigned CLK_HZ = 100_000_000;

    // PWM rápido SOLO para simulación (periodo corto => waveform pequeña)
    // 1 MHz => PERIOD_CYCLES = 100
    localparam int unsigned PWM_HZ = 1_000_000;
    localparam int unsigned PERIOD_CYCLES = CLK_HZ / PWM_HZ;

    logic clk, rst;
    logic [3:0] duty_code;
    logic pwm_out;

    // DUT
    pwm_4bit #(
        .CLK_HZ(CLK_HZ),
        .PWM_HZ(PWM_HZ)
    ) dut (
        .clk(clk),
        .rst(rst),
        .duty_code(duty_code),
        .pwm_out(pwm_out)
    );

    // Clock generation: 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Tarea compacta: aplica un duty y espera 1 periodo
    task automatic show(input logic [3:0] code);
        duty_code = code;                 // cambia el duty
        repeat (PERIOD_CYCLES) @(posedge clk); // espera 1 periodo completo
    endtask

    initial begin
        // Init
        rst = 1'b1;
        duty_code = 4'd0;

        // Reset por pocos ciclos
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // Pruebas MINIMAS pero representativas (waveform corta)
        show(4'd0);   // 0%
        show(4'd4);   // ~26%
        show(4'd8);   // ~53%
        show(4'd12);  // ~80%
        show(4'd15);  // 100%

        $finish;
    end

endmodule
