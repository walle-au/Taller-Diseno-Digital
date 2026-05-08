// =============================================================================
// Archivo      : sim/common/adxl362_stub.sv
// Autor        : Walter-Allan-Alexander-Esteban
// Fecha        : 7 de mayo de 2026
// Curso        : EL3313 - Taller de Diseño Digital (TEC, VII semestre)
// Lab 3        : Modelo simplificado del ADXL362 para simulación.
//
// Implementa lo mínimo necesario para validar el bus SPI:
//   - SPI Mode 0 (CPOL=0, CPHA=0)
//   - Comandos 0x0A (write) y 0x0B (read), MSB-first, 8 bits/byte
//   - Estructura de transacción:  CSn↓ | <cmd> | <addr> | <data...> | CSn↑
//   - Auto-incremento de dirección en lecturas/escrituras tipo "burst"
//
// "Registros" emulados (valores fijos para el TB):
//     0x00 DEVID_AD = 0xAD
//     0x01 DEVID_MST = 0x1D
//     0x02 PARTID    = 0xF2
//     0x08 XDATA     = 0x12
//     0x09 YDATA     = 0x34
//     0x0A ZDATA     = 0x56
//     resto         = 0xDE  (centinela de "addr no soportada")
//
// NO modela: timing real, FIFO, interrupciones, registros de configuración.
// =============================================================================

module adxl362_stub (
    input  logic rst_n_i,
    input  logic csn_i,
    input  logic sclk_i,
    input  logic mosi_i,
    output logic miso_o
);

    typedef enum logic [1:0] { S_CMD, S_ADDR, S_DATA } state_e;

    state_e      state_q;
    logic [7:0]  cmd_byte_q;
    logic [7:0]  addr_byte_q;
    logic [7:0]  rx_shift_q;
    logic [7:0]  tx_shift_q;
    int          bit_count_q;

    function automatic logic [7:0] lookup_reg(input logic [7:0] addr);
        unique case (addr)
            8'h00:   return 8'hAD;     // DEVID_AD
            8'h01:   return 8'h1D;     // DEVID_MST
            8'h02:   return 8'hF2;     // PARTID
            8'h08:   return 8'h12;     // XDATA
            8'h09:   return 8'h34;     // YDATA
            8'h0A:   return 8'h56;     // ZDATA
            default: return 8'hDE;
        endcase
    endfunction

    initial begin
        state_q     = S_CMD;
        cmd_byte_q  = '0;
        addr_byte_q = '0;
        rx_shift_q  = '0;
        tx_shift_q  = '0;
        bit_count_q = 0;
    end

    // Flanco de bajada de CSn -> empieza nueva transacción.
    // El gate por rst_n_i evita falsos disparos por X->0 al t=0.
    always @(negedge csn_i) begin
        if (rst_n_i) begin
            state_q     <= S_CMD;
            bit_count_q <= 0;
            rx_shift_q  <= '0;
            tx_shift_q  <= '0;
        end
    end

    // Flanco de subida de SCLK con CS activo -> muestrear MOSI
    always @(posedge sclk_i) begin
        if (rst_n_i && !csn_i) begin
            rx_shift_q  <= {rx_shift_q[6:0], mosi_i};
            bit_count_q <= bit_count_q + 1;
        end
    end

    // Flanco de bajada de SCLK con CS activo -> procesar byte o shift TX
    always @(negedge sclk_i) begin
        if (rst_n_i && !csn_i) begin
            if (bit_count_q == 8) begin
                // Byte completo: procesar y posiblemente cargar siguiente TX
                bit_count_q <= 0;
                unique case (state_q)
                    S_CMD: begin
                        cmd_byte_q <= rx_shift_q;
                        state_q    <= S_ADDR;
                        tx_shift_q <= 8'h00;
                    end
                    S_ADDR: begin
                        addr_byte_q <= rx_shift_q;
                        state_q     <= S_DATA;
                        tx_shift_q  <= lookup_reg(rx_shift_q);
                    end
                    S_DATA: begin
                        // Lectura tipo burst: auto-incremento de dirección
                        if (cmd_byte_q == 8'h0B) begin
                            addr_byte_q <= addr_byte_q + 8'h01;
                            tx_shift_q  <= lookup_reg(addr_byte_q + 8'h01);
                        end
                    end
                    default: ;
                endcase
            end else begin
                // Bit intermedio: shift hacia la izquierda
                tx_shift_q <= {tx_shift_q[6:0], 1'b0};
            end
        end
    end

    assign miso_o = tx_shift_q[7];

endmodule : adxl362_stub
