`default_nettype none

module RAMIO #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DATA_FILE  = "",

    parameter CLK_FREQ   = 20_250_000,
    parameter BAUD_RATE  = 9600,

    parameter TOP_ADDR          = {(ADDR_WIDTH + 2){1'b1}},

    parameter ADDR_LEDS         = TOP_ADDR,
    parameter ADDR_UART_OUT     = TOP_ADDR - 1,
    parameter ADDR_UART_IN      = TOP_ADDR - 2,

    parameter ADDR_I2C_DATA     = TOP_ADDR - 3,
    parameter ADDR_I2C_CTRL     = TOP_ADDR - 4,
    parameter ADDR_I2C_STATUS   = TOP_ADDR - 5,
    parameter ADDR_I2C_REG      = TOP_ADDR - 6,
    parameter ADDR_I2C_SLAVE    = TOP_ADDR - 7
)(
    input  wire rst,
    input  wire clk,

    input  wire [1:0] weA,
    input  wire [2:0] reA,
    input  wire [ADDR_WIDTH+1:0] addrA,
    input  wire [DATA_WIDTH-1:0] dinA,
    output reg  [DATA_WIDTH-1:0] doutA,

    input  wire [ADDR_WIDTH+1:0] addrB,
    output wire [DATA_WIDTH-1:0] doutB,

    output reg  [5:0] led,

    output wire uart_tx,
    input  wire uart_rx,

    inout  wire i2c_sda,
    output wire i2c_scl
);

    /* =====================================================
       RAM
    ===================================================== */

    reg [ADDR_WIDTH-1:0] ram_addrA;
    reg [DATA_WIDTH-1:0] ram_dinA;
    wire [DATA_WIDTH-1:0] ram_doutA;
    reg [3:0] ram_weA;

    always @(*) begin

        ram_addrA = addrA >> 2;

        ram_weA  = 4'b0000;
        ram_dinA = 32'h0;

        case (weA)

            2'b01: begin
                case (addrA[1:0])

                    2'b00: begin
                        ram_weA = 4'b0001;
                        ram_dinA[7:0] = dinA[7:0];
                    end

                    2'b01: begin
                        ram_weA = 4'b0010;
                        ram_dinA[15:8] = dinA[7:0];
                    end

                    2'b10: begin
                        ram_weA = 4'b0100;
                        ram_dinA[23:16] = dinA[7:0];
                    end

                    2'b11: begin
                        ram_weA = 4'b1000;
                        ram_dinA[31:24] = dinA[7:0];
                    end
                endcase
            end

            2'b10: begin
                case (addrA[1:0])

                    2'b00: begin
                        ram_weA = 4'b0011;
                        ram_dinA[15:0] = dinA[15:0];
                    end

                    2'b10: begin
                        ram_weA = 4'b1100;
                        ram_dinA[31:16] = dinA[15:0];
                    end
                endcase
            end

            2'b11: begin
                ram_weA  = 4'b1111;
                ram_dinA = dinA;
            end
        endcase
    end

    /* =====================================================
       READ PIPELINE
    ===================================================== */

    reg [ADDR_WIDTH+1:0] addrA_prev;
    reg [2:0] reA_prev;

    /* =====================================================
       UART
    ===================================================== */

    reg  [7:0] uarttx_data;
    reg        uarttx_go;
    wire       uarttx_bsy;

    wire [7:0] uartrx_data;
    wire       uartrx_dr;

    reg        uartrx_go;
    reg [7:0]  uartrx_data_read;

    /* =====================================================
       I2C REGISTERS
    ===================================================== */

    reg [7:0] i2c_data_reg;
    reg [7:0] i2c_reg_reg;
    reg [6:0] i2c_slave_reg;

    reg       i2c_start;
    reg       i2c_read_en;

    wire [7:0] i2c_read_data;

    wire i2c_busy;
    wire i2c_done;
    wire i2c_ack_error;

    /* =====================================================
       MMIO READ
    ===================================================== */

    always @(*) begin

        doutA = 32'h0;

        case (addrA_prev)

            ADDR_UART_OUT:
                doutA = {24'h0, uarttx_data};

            ADDR_UART_IN:
                doutA = {24'h0, uartrx_data_read};

            ADDR_I2C_DATA:
                doutA = {24'h0, i2c_read_data};

            ADDR_I2C_REG:
                doutA = {24'h0, i2c_reg_reg};

            ADDR_I2C_SLAVE:
                doutA = {25'h0, i2c_slave_reg};

            ADDR_I2C_STATUS:
                doutA = {
                    29'b0,
                    i2c_ack_error,
                    i2c_done,
                    i2c_busy
                };

            default: begin

                case (reA_prev)

                    3'b001: begin

                        case (addrA_prev[1:0])

                            2'b00:
                                doutA = {{24{1'b0}}, ram_doutA[7:0]};

                            2'b01:
                                doutA = {{24{1'b0}}, ram_doutA[15:8]};

                            2'b10:
                                doutA = {{24{1'b0}}, ram_doutA[23:16]};

                            2'b11:
                                doutA = {{24{1'b0}}, ram_doutA[31:24]};
                        endcase
                    end

                    3'b111:
                        doutA = ram_doutA;

                    default:
                        doutA = 32'h0;
                endcase
            end
        endcase
    end

    /* =====================================================
       SEQUENTIAL
    ===================================================== */

    always @(posedge clk) begin

        if (rst) begin

            led <= 6'b111111;

            uarttx_go <= 0;
            uarttx_data <= 0;

            uartrx_go <= 1;
            uartrx_data_read <= 0;

            i2c_start <= 0;
            i2c_read_en <= 0;

            i2c_data_reg <= 0;
            i2c_reg_reg <= 0;
            i2c_slave_reg <= 7'h76;

        end else begin

            i2c_start <= 1'b0;

            reA_prev   <= reA;
            addrA_prev <= addrA;

            /* UART RX */

            if (uartrx_dr && uartrx_go) begin
                uartrx_data_read <= uartrx_data;
                uartrx_go <= 0;
            end

            if (!uartrx_go)
                uartrx_go <= 1;

            /* UART TX */

            if (!uarttx_bsy)
                uarttx_go <= 0;

            if (addrA == ADDR_UART_OUT && weA == 2'b01) begin
                uarttx_data <= dinA[7:0];
                uarttx_go <= 1;
            end

            /* LED */

            if (addrA == ADDR_LEDS && weA == 2'b01)
                led <= dinA[5:0];

            /* I2C DATA */

            if (addrA == ADDR_I2C_DATA && weA == 2'b01)
                i2c_data_reg <= dinA[7:0];

            /* I2C REG */

            if (addrA == ADDR_I2C_REG && weA == 2'b01)
                i2c_reg_reg <= dinA[7:0];

            /* I2C SLAVE */

            if (addrA == ADDR_I2C_SLAVE && weA == 2'b01)
                i2c_slave_reg <= dinA[6:0];

            /* I2C CTRL */

            if (addrA == ADDR_I2C_CTRL && weA == 2'b01) begin

                i2c_read_en <= dinA[1];

                if (dinA[0])
                    i2c_start <= 1'b1;
            end
        end
    end

    /* =====================================================
       RAM
    ===================================================== */

    RAM #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_FILE(DATA_FILE)
    ) ram (
        .clk(clk),

        .weA(ram_weA),

        .addrA(ram_addrA),
        .dinA(ram_dinA),
        .doutA(ram_doutA),

        .addrB(addrB[ADDR_WIDTH+1:2]),
        .doutB(doutB)
    );

    /* =====================================================
       UART
    ===================================================== */

    UartTx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uarttx (
        .rst(rst),
        .clk(clk),
        .data(uarttx_data),
        .go(uarttx_go),
        .tx(uart_tx),
        .bsy(uarttx_bsy)
    );

    UartRx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uartrx (
        .rst(rst),
        .clk(clk),
        .rx(uart_rx),
        .go(uartrx_go),
        .data(uartrx_data),
        .dr(uartrx_dr)
    );

    /* =====================================================
       I2C
    ===================================================== */

    I2C #(
        .CLK_FREQ(CLK_FREQ),
        .I2C_FREQ(100_000)
    ) i2c_inst (

        .clk(clk),
        .rst(rst),

        .start(i2c_start),

        .slave_addr(i2c_slave_reg),

        .reg_addr(i2c_reg_reg),

        .write_data(i2c_data_reg),

        .read_en(i2c_read_en),

        .read_data(i2c_read_data),

        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_ack_error),

        .sda(i2c_sda),
        .scl(i2c_scl)
    );

endmodule

`default_nettype wire