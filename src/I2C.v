`default_nettype none

module I2C #(
    parameter CLK_FREQ = 66_000_000,
    parameter I2C_FREQ = 100_000
)(
    input  wire       clk,
    input  wire       rst,

    input  wire       start,

    input  wire [6:0] slave_addr,
    input  wire [7:0] reg_addr,

    input  wire [7:0] write_data,
    input  wire       read_en,

    output reg  [7:0] read_data,

    output reg        busy,
    output reg        done,
    output reg        ack_error,

    inout  wire       sda,
    output reg        scl
);

    /* =====================================================
       CLOCK DIVIDER
    ===================================================== */

    localparam integer DIVIDER = CLK_FREQ / (I2C_FREQ * 4);

    /* =====================================================
       FSM STATES
    ===================================================== */

    localparam [4:0]
        IDLE        = 5'd0,
        START       = 5'd1,

        ADDR_W      = 5'd2,
        ACK_ADDR_W  = 5'd3,

        REG_ADDR    = 5'd4,
        ACK_REG     = 5'd5,

        WRITE_DATA  = 5'd6,
        ACK_WRITE   = 5'd7,

        RESTART     = 5'd8,

        ADDR_R      = 5'd9,
        ACK_ADDR_R  = 5'd10,

        READ_DATA   = 5'd11,
        NACK        = 5'd12,

        STOP        = 5'd13;

    /* =====================================================
       REGISTERS
    ===================================================== */

    reg [4:0]  state;

    reg [31:0] counter;

    reg [2:0]  bit_idx;

    reg [7:0]  shift_reg;

    reg        sda_drive_low;

    /* =====================================================
       SDA OPEN DRAIN
    ===================================================== */

    assign sda = (sda_drive_low) ? 1'b0 : 1'bz;

    /* =====================================================
       TIMER EVENTS
    ===================================================== */

    wire tick_q1 = (counter == DIVIDER);
    wire tick_q2 = (counter == DIVIDER * 2);
    wire tick_q3 = (counter == DIVIDER * 3);
    wire tick_q4 = (counter == DIVIDER * 4);

    /* =====================================================
       MAIN FSM
    ===================================================== */

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            state <= IDLE;

            scl <= 1'b1;

            sda_drive_low <= 1'b0;

            counter <= 32'd0;

            bit_idx <= 3'd7;

            shift_reg <= 8'h00;

            read_data <= 8'h00;

            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;

        end else begin

            done <= 1'b0;

            case (state)

                /* =========================================
                   IDLE
                ========================================= */

                IDLE: begin

                    scl <= 1'b1;

                    sda_drive_low <= 1'b0;

                    counter <= 32'd0;

                    busy <= 1'b0;

                    if (start) begin

                        busy <= 1'b1;

                        ack_error <= 1'b0;

                        state <= START;
                    end
                end

                /* =========================================
                   START CONDITION
                ========================================= */

                START: begin

                    counter <= counter + 1;

                    if (tick_q1) begin
                        sda_drive_low <= 1'b1;
                    end

                    if (tick_q2) begin

                        scl <= 1'b0;

                        shift_reg <= {slave_addr, 1'b0};

                        bit_idx <= 3'd7;

                        counter <= 32'd0;

                        state <= ADDR_W;
                    end
                end

                /* =========================================
                   SEND SLAVE ADDRESS + WRITE
                ========================================= */

                ADDR_W: begin

                    counter <= counter + 1;

                    sda_drive_low <= ~shift_reg[bit_idx];

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (bit_idx == 3'd0)
                            state <= ACK_ADDR_W;
                        else
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                /* =========================================
                   ACK ADDRESS WRITE
                ========================================= */

                ACK_ADDR_W: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2) begin

                        if (sda)
                            ack_error <= 1'b1;
                    end

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        shift_reg <= reg_addr;

                        bit_idx <= 3'd7;

                        state <= REG_ADDR;
                    end
                end

                /* =========================================
                   SEND REGISTER ADDRESS
                ========================================= */

                REG_ADDR: begin

                    counter <= counter + 1;

                    sda_drive_low <= ~shift_reg[bit_idx];

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (bit_idx == 3'd0)
                            state <= ACK_REG;
                        else
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                /* =========================================
                   ACK REGISTER ADDRESS
                ========================================= */

                ACK_REG: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2) begin

                        if (sda)
                            ack_error <= 1'b1;
                    end

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (read_en) begin

                            state <= RESTART;

                        end else begin

                            shift_reg <= write_data;

                            bit_idx <= 3'd7;

                            state <= WRITE_DATA;
                        end
                    end
                end

                /* =========================================
                   WRITE DATA
                ========================================= */

                WRITE_DATA: begin

                    counter <= counter + 1;

                    sda_drive_low <= ~shift_reg[bit_idx];

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (bit_idx == 3'd0)
                            state <= ACK_WRITE;
                        else
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                /* =========================================
                   ACK WRITE DATA
                ========================================= */

                ACK_WRITE: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2) begin

                        if (sda)
                            ack_error <= 1'b1;
                    end

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        state <= STOP;
                    end
                end

                /* =========================================
                   REPEATED START
                ========================================= */

                RESTART: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2)
                        sda_drive_low <= 1'b1;

                    if (tick_q3) begin

                        scl <= 1'b0;

                        shift_reg <= {slave_addr, 1'b1};

                        bit_idx <= 3'd7;
                    end

                    if (tick_q4) begin

                        counter <= 32'd0;

                        state <= ADDR_R;
                    end
                end

                /* =========================================
                   SEND SLAVE ADDRESS + READ
                ========================================= */

                ADDR_R: begin

                    counter <= counter + 1;

                    sda_drive_low <= ~shift_reg[bit_idx];

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (bit_idx == 3'd0)
                            state <= ACK_ADDR_R;
                        else
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                /* =========================================
                   ACK ADDRESS READ
                ========================================= */

                ACK_ADDR_R: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2) begin

                        if (sda)
                            ack_error <= 1'b1;
                    end

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        bit_idx <= 3'd7;

                        read_data <= 8'h00;

                        state <= READ_DATA;
                    end
                end

                /* =========================================
                   READ DATA
                ========================================= */

                READ_DATA: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q2)
                        read_data[bit_idx] <= sda;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        if (bit_idx == 3'd0)
                            state <= NACK;
                        else
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                /* =========================================
                   MASTER NACK
                ========================================= */

                NACK: begin

                    counter <= counter + 1;

                    sda_drive_low <= 1'b0;

                    if (tick_q1)
                        scl <= 1'b1;

                    if (tick_q3)
                        scl <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        state <= STOP;
                    end
                end

                /* =========================================
                   STOP CONDITION
                ========================================= */

                STOP: begin

                    counter <= counter + 1;

                    if (tick_q1)
                        sda_drive_low <= 1'b1;

                    if (tick_q2)
                        scl <= 1'b1;

                    if (tick_q3)
                        sda_drive_low <= 1'b0;

                    if (tick_q4) begin

                        counter <= 32'd0;

                        busy <= 1'b0;

                        done <= 1'b1;

                        state <= IDLE;
                    end
                end

                default: begin

                    state <= IDLE;
                end

            endcase
        end
    end

endmodule

`default_nettype wire