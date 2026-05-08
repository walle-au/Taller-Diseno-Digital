// =============================================================================
// Archivo      : rtl/peripherals/spi/spi_axil.sv
// Autor        : Walter-Allan-Alexander-Esteban
// Fecha        : 7 de mayo de 2026
// Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
// Lab 3        : Wrapper AXI-Lite del periférico SPI master.
//
//                Mapa de registros (base 0x02020 en el SoC):
//
//                  Offset 0x0  (addr abs 0x02020)  SPI_CTRL
//                    [0]      start (W) / busy (R)
//                             SW pone 1 para iniciar; HW lo baja al terminar.
//                    [3]      csn (R/W) - controla la línea ACL_CSN
//                    [11:4]   clk_div (R/W) - SCLK = sysclk / (2 * clk_div)
//                             default 4 -> SCLK = 6.25 MHz @ 50 MHz
//                    [31:12]  reservado (lee 0)
//
//                  Offset 0x8  (addr abs 0x02028)  SPI_TX
//                    [7:0]    byte a enviar (sampled en S_IDLE -> S_LOW)
//
//                  Offset 0xC  (addr abs 0x0202C)  SPI_RX
//                    [7:0]    último byte recibido (RO)
//
// Asistencia IA: estructura del wrapper basada en uart_axil.sv del Lab 2,
//                adaptada con Claude (Anthropic).
// =============================================================================

module spi_axil (
    // ------ AXI-Lite slave ------------------------------------------------
    input  logic                         s_axi_aclk,
    input  logic                         s_axi_aresetn,

    input  logic [AXIL_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic                         s_axi_awvalid,
    output logic                         s_axi_awready,
    input  logic [AXIL_DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0]   s_axi_wstrb,
    input  logic                         s_axi_wvalid,
    output logic                         s_axi_wready,
    output logic [1:0]                   s_axi_bresp,
    output logic                         s_axi_bvalid,
    input  logic                         s_axi_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic                         s_axi_arvalid,
    output logic                         s_axi_arready,
    output logic [AXIL_DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]                   s_axi_rresp,
    output logic                         s_axi_rvalid,
    input  logic                         s_axi_rready,

    // ------ Pines SPI hacia el ADXL362 (interno a la PCB Nexys4 DDR) ------
    output logic                         spi_sclk_o,
    output logic                         spi_mosi_o,
    input  logic                         spi_miso_i,
    output logic                         spi_csn_o
);

    // ---- Offsets internos del slave (addr[3:0]) --------------------------
    localparam logic [3:0] SPI_OFFSET_CTRL = 4'h0;
    localparam logic [3:0] SPI_OFFSET_TX   = 4'h8;
    localparam logic [3:0] SPI_OFFSET_RX   = 4'hC;

    // ---- Bits del registro SPI_CTRL --------------------------------------
    localparam int SPI_CTRL_BIT_START = 0;
    localparam int SPI_CTRL_BIT_CSN   = 3;
    localparam int SPI_CTRL_DIV_LSB   = 4;
    localparam int SPI_CTRL_DIV_MSB   = 11;

    // ---- Default del clock divider ---------------------------------------
    // 50 MHz / (2 * 4) = 6.25 MHz, dentro del límite (8 MHz) del ADXL362.
    localparam logic [7:0] DEFAULT_DIV = 8'd4;

    // ---- Registros internos ---------------------------------------------
    logic        reg_ctrl_start_q;
    logic        reg_ctrl_csn_q;
    logic [7:0]  reg_ctrl_div_q;
    logic [7:0]  reg_tx_data_q;
    logic [7:0]  reg_rx_data_q;

    // ---- Sub-módulo SPI master ------------------------------------------
    logic        spi_start_pulse;
    logic        spi_busy;
    logic        spi_done;
    logic [7:0]  spi_rx_byte;

    spi_master #(
        .DATA_WIDTH(8)
    ) u_spi (
        .clk_i     (s_axi_aclk),
        .rst_n_i   (s_axi_aresetn),
        .clk_div_i (reg_ctrl_div_q),
        .start_i   (spi_start_pulse),
        .tx_data_i (reg_tx_data_q),
        .busy_o    (spi_busy),
        .done_o    (spi_done),
        .rx_data_o (spi_rx_byte),
        .sclk_o    (spi_sclk_o),
        .mosi_o    (spi_mosi_o),
        .miso_i    (spi_miso_i)
    );

    // Pulso de 1 ciclo en el flanco 0->1 de reg_ctrl_start_q.
    // Sin esto, después del done el master vería start=1 todavía y arrancaría
    // una segunda transferencia (mismo bug que evita uart_tx).
    logic reg_ctrl_start_d1;
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) reg_ctrl_start_d1 <= 1'b0;
        else                reg_ctrl_start_d1 <= reg_ctrl_start_q;
    end
    assign spi_start_pulse = reg_ctrl_start_q & ~reg_ctrl_start_d1;

    // ---- Write FSM (mismo patrón de uart_axil) --------------------------
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_e;
    w_state_e w_state_q, w_state_d;
    logic [AXIL_ADDR_WIDTH-1:0] w_addr_q;

    always_comb begin
        w_state_d = w_state_q;
        unique case (w_state_q)
            W_IDLE: if (s_axi_awvalid && s_axi_awready) w_state_d = W_DATA;
            W_DATA: if (s_axi_wvalid  && s_axi_wready)  w_state_d = W_RESP;
            W_RESP: if (s_axi_bvalid  && s_axi_bready)  w_state_d = W_IDLE;
            default: w_state_d = W_IDLE;
        endcase
    end

    logic [3:0] w_offset;
    assign w_offset = w_addr_q[3:0];

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            w_state_q        <= W_IDLE;
            w_addr_q         <= '0;
            reg_ctrl_start_q <= 1'b0;
            reg_ctrl_csn_q   <= 1'b1;          // CSn idle high (deselected)
            reg_ctrl_div_q   <= DEFAULT_DIV;
            reg_tx_data_q    <= '0;
        end else begin
            w_state_q <= w_state_d;

            if (w_state_q == W_IDLE && s_axi_awvalid && s_axi_awready) begin
                w_addr_q <= s_axi_awaddr;
            end

            if (w_state_q == W_DATA && s_axi_wvalid && s_axi_wready) begin
                unique case (w_offset)
                    SPI_OFFSET_CTRL: begin
                        // Asumimos sw (store word) -> wstrb=4'b1111, así que
                        // gateamos toda la palabra con wstrb[0] como hace uart.
                        if (s_axi_wstrb[0]) begin
                            reg_ctrl_start_q <= s_axi_wdata[SPI_CTRL_BIT_START];
                            reg_ctrl_csn_q   <= s_axi_wdata[SPI_CTRL_BIT_CSN];
                            reg_ctrl_div_q   <= s_axi_wdata[SPI_CTRL_DIV_MSB:SPI_CTRL_DIV_LSB];
                        end
                    end
                    SPI_OFFSET_TX: begin
                        if (s_axi_wstrb[0]) reg_tx_data_q <= s_axi_wdata[7:0];
                    end
                    default: ;
                endcase
            end

            // Auto-clear de start cuando termina la transferencia (paralelo
            // exacto a UART send/done).
            if (spi_done && reg_ctrl_start_q) begin
                reg_ctrl_start_q <= 1'b0;
            end
        end
    end

    assign s_axi_awready = (w_state_q == W_IDLE);
    assign s_axi_wready  = (w_state_q == W_DATA);
    assign s_axi_bvalid  = (w_state_q == W_RESP);
    assign s_axi_bresp   = AXI_RESP_OKAY;

    // ---- Captura de RX al done -------------------------------------------
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)        reg_rx_data_q <= '0;
        else if (spi_done)         reg_rx_data_q <= spi_rx_byte;
    end

    // ---- Read FSM ---------------------------------------------------------
    typedef enum logic {R_IDLE, R_RESP} r_state_e;
    r_state_e r_state_q, r_state_d;
    logic [AXIL_DATA_WIDTH-1:0] rdata_q;

    always_comb begin
        r_state_d = r_state_q;
        unique case (r_state_q)
            R_IDLE: if (s_axi_arvalid && s_axi_arready) r_state_d = R_RESP;
            R_RESP: if (s_axi_rvalid  && s_axi_rready)  r_state_d = R_IDLE;
            default: r_state_d = R_IDLE;
        endcase
    end

    logic [3:0] r_offset;
    assign r_offset = s_axi_araddr[3:0];

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            r_state_q <= R_IDLE;
            rdata_q   <= '0;
        end else begin
            r_state_q <= r_state_d;
            if (r_state_q == R_IDLE && s_axi_arvalid && s_axi_arready) begin
                unique case (r_offset)
                    // Layout: {20'h0, div[7:0], csn, 2'h0, start}
                    SPI_OFFSET_CTRL: rdata_q <= {20'h0, reg_ctrl_div_q,
                                                 reg_ctrl_csn_q, 2'h0,
                                                 reg_ctrl_start_q};
                    SPI_OFFSET_TX:   rdata_q <= {24'h0, reg_tx_data_q};
                    SPI_OFFSET_RX:   rdata_q <= {24'h0, reg_rx_data_q};
                    default:         rdata_q <= '0;
                endcase
            end
        end
    end

    assign s_axi_arready = (r_state_q == R_IDLE);
    assign s_axi_rvalid  = (r_state_q == R_RESP);
    assign s_axi_rdata   = rdata_q;
    assign s_axi_rresp   = AXI_RESP_OKAY;

    // ---- Salida directa de CSn -------------------------------------------
    assign spi_csn_o = reg_ctrl_csn_q;

endmodule : spi_axil
