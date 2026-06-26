// =============================================================================
// Archivo      : uart_sum_top.sv
// Descripción  : Módulo superior para examen práctico EL3313.
//                Recibe cuatro dígitos ASCII por UART RX, forma AB y CD,
//                calcula AB + CD y transmite el resultado como binario sin signo.
// =============================================================================

module uart_sum_top #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic clk_i,
    input  logic rst_n_i,

    input  logic uart_rx_i,
    output logic uart_tx_o
);

    // -------------------------------------------------------------------------
    // Señales UART
    // -------------------------------------------------------------------------
    logic uart_rx_sync;

    logic [7:0] rx_data;
    logic       rx_valid;

    logic       tx_tick;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;
    logic [7:0] tx_data;

    // -------------------------------------------------------------------------
    // Señales decodificador ASCII
    // -------------------------------------------------------------------------
    logic [3:0] digit;
    logic       digit_valid;

    // -------------------------------------------------------------------------
    // Señales memoria
    // -------------------------------------------------------------------------
    logic       mem_en;
    logic       mem_wr;
    logic [1:0] mem_addr;
    logic [3:0] mem_dout;

    // -------------------------------------------------------------------------
    // Señales camino de datos
    // -------------------------------------------------------------------------
    logic       sel_x10;
    logic       acc_clr;
    logic       acc_en;

    logic [7:0] mux_out;
    logic [7:0] adder_out;
    logic [7:0] acc_out;

    // -------------------------------------------------------------------------
    // Sincronizador para RX externo
    // -------------------------------------------------------------------------
    sync_2ff u_sync_rx (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .async_i (uart_rx_i),
        .sync_o  (uart_rx_sync)
    );

    // -------------------------------------------------------------------------
    // UART RX del repositorio/laboratorio
    // -------------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) u_uart_rx (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .rx_i         (uart_rx_sync),
        .byte_valid_o (rx_valid),
        .data_o       (rx_data)
    );

    // -------------------------------------------------------------------------
    // Generador de tick para UART TX
    // -------------------------------------------------------------------------
    uart_baud_gen #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) u_uart_baud_gen (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .tx_active_i (tx_busy),
        .tx_tick_o   (tx_tick)
    );

    // -------------------------------------------------------------------------
    // UART TX del repositorio/laboratorio
    // -------------------------------------------------------------------------
    uart_tx u_uart_tx (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .tx_tick_i (tx_tick),
        .start_i   (tx_start),
        .data_i    (tx_data),
        .busy_o    (tx_busy),
        .done_o    (tx_done),
        .tx_o      (uart_tx_o)
    );

    // -------------------------------------------------------------------------
    // Conversión ASCII a dígito
    // -------------------------------------------------------------------------
    ascii_to_digit u_ascii_to_digit (
        .ascii_i       (rx_data),
        .digit_o       (digit),
        .digit_valid_o (digit_valid)
    );

    // -------------------------------------------------------------------------
    // Memoria para los cuatro dígitos A, B, C y D
    // -------------------------------------------------------------------------
    digit_mem_4x4 u_digit_mem (
        .clk_i  (clk_i),
        .en_i   (mem_en),
        .wr_i   (mem_wr),
        .addr_i (mem_addr),
        .din_i  (digit),
        .dout_o (mem_dout)
    );

    // -------------------------------------------------------------------------
    // Bloque x1/x10 del camino de datos
    // -------------------------------------------------------------------------
    mux_x1_x10 u_mux_x1_x10 (
        .digit_i   (mem_dout),
        .sel_x10_i (sel_x10),
        .value_o   (mux_out)
    );

    // -------------------------------------------------------------------------
    // Sumador del camino de datos
    // -------------------------------------------------------------------------
    adder_8bit u_adder (
        .a_i   (acc_out),
        .b_i   (mux_out),
        .sum_o (adder_out)
    );

    // -------------------------------------------------------------------------
    // Registro acumulador
    // -------------------------------------------------------------------------
    acc_reg u_acc_reg (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .clr_i   (acc_clr),
        .en_i    (acc_en),
        .d_i     (adder_out),
        .q_o     (acc_out)
    );

    assign tx_data = acc_out;

    // -------------------------------------------------------------------------
    // FSM de control
    // -------------------------------------------------------------------------
    fsm_control u_fsm_control (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),

        .rx_valid_i    (rx_valid),
        .digit_valid_i (digit_valid),
        .tx_busy_i     (tx_busy),
        .tx_done_i     (tx_done),

        .mem_en_o      (mem_en),
        .mem_wr_o      (mem_wr),
        .mem_addr_o    (mem_addr),

        .sel_x10_o     (sel_x10),
        .acc_clr_o     (acc_clr),
        .acc_en_o      (acc_en),

        .tx_start_o    (tx_start)
    );

endmodule : uart_sum_top
