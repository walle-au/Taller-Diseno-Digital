// =============================================================================
// Archivo      : sim/tb_spi_axil.sv
// Autor        : Walter-Allan-Alexander-Esteban
// Fecha        : 7 de mayo de 2026
// Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
// Lab 3        : TB del wrapper spi_axil + modelo del ADXL362.
//
// Verifica:
//   T1: Estado por defecto: SPI_CTRL.csn=1, SPI_CTRL.div=4
//   T2: Asserto CSn (csn=0) y leo DEVID_AD del modelo:
//       - Envío 0x0B (cmd READ)
//       - Envío 0x00 (addr DEVID_AD)
//       - Envío 0x00 (dummy) y leo SPI_RX -> debe ser 0xAD
//   T3: Lectura ráfaga de XDATA, YDATA, ZDATA en una sola activación de CSn
//       - Envío 0x0B, 0x08, 0x00, 0x00, 0x00 -> recibo {?,?,0x12,0x34,0x56}
// =============================================================================

`timescale 1ns/1ps

module tb_spi_axil;

    localparam int CLK_PER_NS = 20;            // sysclk = 50 MHz

    logic clk = 0;
    always #(CLK_PER_NS/2) clk = ~clk;
    logic rst_n;

    // ---- AXI-Lite -------------------------------------------------------
    logic [AXIL_ADDR_WIDTH-1:0]  awaddr, araddr;
    logic                        awvalid, awready, arvalid, arready;
    logic [AXIL_DATA_WIDTH-1:0]  wdata, rdata;
    logic [AXIL_STRB_WIDTH-1:0]  wstrb;
    logic                        wvalid, wready, bvalid, bready, rvalid, rready;
    logic [1:0]                  bresp, rresp;

    axil_master_bfm u_m (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .m_axi_awaddr(awaddr),   .m_axi_awvalid(awvalid),   .m_axi_awready(awready),
        .m_axi_wdata (wdata),    .m_axi_wstrb (wstrb),
        .m_axi_wvalid(wvalid),   .m_axi_wready(wready),
        .m_axi_bresp (bresp),    .m_axi_bvalid(bvalid),     .m_axi_bready(bready),
        .m_axi_araddr(araddr),   .m_axi_arvalid(arvalid),   .m_axi_arready(arready),
        .m_axi_rdata (rdata),    .m_axi_rresp (rresp),
        .m_axi_rvalid(rvalid),   .m_axi_rready(rready)
    );

    // ---- DUT y modelo ADXL362 -------------------------------------------
    logic spi_sclk, spi_mosi, spi_miso, spi_csn;

    spi_axil u_dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata),   .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp),   .s_axi_bvalid(bvalid),   .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata),   .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .spi_sclk_o(spi_sclk),
        .spi_mosi_o(spi_mosi),
        .spi_miso_i(spi_miso),
        .spi_csn_o (spi_csn)
    );

    adxl362_stub u_sensor (
        .rst_n_i(rst_n),
        .csn_i  (spi_csn),
        .sclk_i (spi_sclk),
        .mosi_i (spi_mosi),
        .miso_o (spi_miso)
    );

    // ---- Direcciones del slave SPI (offsets relativos a 0x02020) --------
    localparam logic [AXIL_ADDR_WIDTH-1:0] SPI_BASE = 20'h02020;
    localparam logic [AXIL_ADDR_WIDTH-1:0] ADDR_CTRL = SPI_BASE + 20'h0;
    localparam logic [AXIL_ADDR_WIDTH-1:0] ADDR_TX   = SPI_BASE + 20'h8;
    localparam logic [AXIL_ADDR_WIDTH-1:0] ADDR_RX   = SPI_BASE + 20'hC;

    // ---- Codificación de SPI_CTRL ----------------------------------------
    //   bit 0      = start (auto-clear en done)
    //   bit 3      = csn  (1 = idle, 0 = activo)
    //   bits[11:4] = clk_div (default 4 -> 6.25 MHz)
    function automatic logic [31:0] make_ctrl(input bit start, input bit csn,
                                              input logic [7:0] div);
        logic [31:0] r;
        r       = '0;
        r[0]    = start;
        r[3]    = csn;
        r[11:4] = div;
        return r;
    endfunction

    // ---- Helpers ---------------------------------------------------------
    int errors = 0, checks = 0;
    task automatic check(input bit cond, input string msg);
        checks++;
        if (cond) $display("[PASS] %s", msg);
        else      begin errors++; $display("[FAIL] %s", msg); end
    endtask

    // Espera que SPI_CTRL.start vuelva a 0 (HW lo bajó al terminar)
    task automatic wait_done(input int max_polls);
        logic [31:0] rb;
        logic [1:0]  resp;
        for (int i = 0; i < max_polls; i++) begin
            u_m.axil_read(ADDR_CTRL, rb, resp);
            if (rb[0] == 1'b0) return;
        end
        $fatal(1, "wait_done timeout (start nunca volvió a 0)");
    endtask

    // Envía un byte por SPI manteniendo CSn como esté en `csn`
    task automatic spi_xfer(input logic [7:0] tx, input bit csn,
                            output logic [7:0] rx);
        logic [31:0] rb;
        logic [1:0]  resp;
        u_m.axil_write_simple(ADDR_TX,   {24'h0, tx},               resp);
        u_m.axil_write_simple(ADDR_CTRL, make_ctrl(1'b1, csn, 8'd4), resp);
        wait_done(2_000);
        u_m.axil_read(ADDR_RX, rb, resp);
        rx = rb[7:0];
    endtask

    // ---- Watchdog --------------------------------------------------------
    initial begin
        #200_000;
        $fatal(1, "Timeout 200 us en tb_spi_axil");
    end

    // ---- Estímulo --------------------------------------------------------
    initial begin
        logic [31:0]  rb;
        logic [1:0]   resp;
        logic [7:0]   rx;
        logic [7:0]   x_byte, y_byte, z_byte;

        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        $display("==== tb_spi_axil ====");

        // -- T1: estado por defecto --
        u_m.axil_read(ADDR_CTRL, rb, resp);
        check(resp == AXI_RESP_OKAY, "T1 read CTRL OKAY");
        check(rb[0] === 1'b0,   "T1 start = 0 en reset");
        check(rb[3] === 1'b1,   "T1 csn   = 1 en reset (deselected)");
        check(rb[11:4] === 8'd4,"T1 div   = 4 en reset");

        // -- T2: leer DEVID_AD del ADXL362 --
        // Asertar CSn (csn=0) sin start
        u_m.axil_write_simple(ADDR_CTRL, make_ctrl(1'b0, 1'b0, 8'd4), resp);

        // Byte 1: command READ (0x0B)
        spi_xfer(8'h0B, 1'b0, rx);
        // Byte 2: addr DEVID_AD (0x00)
        spi_xfer(8'h00, 1'b0, rx);
        // Byte 3: dummy -> recibe DEVID_AD = 0xAD
        spi_xfer(8'h00, 1'b0, rx);
        check(rx == 8'hAD,
              $sformatf("T2 DEVID_AD recibido = 0x%02h (esperado 0xAD)", rx));

        // Desasertar CSn
        u_m.axil_write_simple(ADDR_CTRL, make_ctrl(1'b0, 1'b1, 8'd4), resp);

        // -- T3: ráfaga XDATA, YDATA, ZDATA --
        u_m.axil_write_simple(ADDR_CTRL, make_ctrl(1'b0, 1'b0, 8'd4), resp);

        spi_xfer(8'h0B, 1'b0, rx);    // cmd READ
        spi_xfer(8'h08, 1'b0, rx);    // addr XDATA
        spi_xfer(8'h00, 1'b0, x_byte); // recibe XDATA
        spi_xfer(8'h00, 1'b0, y_byte); // recibe YDATA (auto-inc)
        spi_xfer(8'h00, 1'b0, z_byte); // recibe ZDATA (auto-inc)

        u_m.axil_write_simple(ADDR_CTRL, make_ctrl(1'b0, 1'b1, 8'd4), resp);

        check(x_byte == 8'h12,
              $sformatf("T3 XDATA = 0x%02h (esperado 0x12)", x_byte));
        check(y_byte == 8'h34,
              $sformatf("T3 YDATA = 0x%02h (esperado 0x34)", y_byte));
        check(z_byte == 8'h56,
              $sformatf("T3 ZDATA = 0x%02h (esperado 0x56)", z_byte));

        // ---- Resumen ----------------------------------------------------
        $display("==== Resultado: %0d/%0d checks OK, %0d FAIL ====",
                 checks - errors, checks, errors);

        if (errors == 0) $display("[PASS] tb_spi_axil OK");
        else             $fatal(1, "tb_spi_axil FALLO (%0d errores)", errors);

        $finish;
    end

endmodule : tb_spi_axil
