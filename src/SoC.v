`default_nettype none
//`define DBG

module SoC #(
    parameter RAM_FILE = "",
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 9600,
    parameter RAM_ADDR_WIDTH = 13
)(
    input  wire rst,
    input  wire clk,

    output wire [5:0] led,

    input  wire uart_rx,
    output wire uart_tx,

    input  wire btn,

    inout  wire i2c_sda,
    output wire i2c_scl
);

    /* =====================================================
       PROGRAM COUNTER
    ===================================================== */

    reg [31:0] pc;
    reg [31:0] pc_next;
    reg [31:0] pc_ir;

    /* =====================================================
       INSTRUCTION
    ===================================================== */

    wire [31:0] ir;

    wire [6:0] opcode = ir[6:0];

    wire [4:0] rd     = ir[11:7];
    wire [2:0] funct3 = ir[14:12];

    wire [4:0] rs1    = ir[19:15];
    wire [4:0] rs2    = ir[24:20];

    wire [6:0] funct7 = ir[31:25];

    /* =====================================================
       IMMEDIATE
    ===================================================== */

    wire signed [31:0] I_imm12 =
        {{20{ir[31]}}, ir[31:20]};

    wire signed [31:0] S_imm12 =
        {{20{ir[31]}}, ir[31:25], ir[11:7]};

    wire signed [31:0] B_imm12 =
        {{19{ir[31]}},
          ir[31],
          ir[7],
          ir[30:25],
          ir[11:8],
          1'b0};

    wire [31:0] U_imm20 =
        {ir[31:12], 12'b0};

    wire signed [31:0] J_imm20 =
        {{11{ir[31]}},
          ir[31],
          ir[19:12],
          ir[20],
          ir[30:21],
          1'b0};

    /* =====================================================
       REGISTER FILE
    ===================================================== */

    reg  [31:0] regs_rd_wd;
    reg         regs_rd_we;

    wire signed [31:0] regs_rd1;
    wire signed [31:0] regs_rd2;

    /* =====================================================
       RAM INTERFACE
    ===================================================== */

    reg  [1:0]  ram_weA;
    reg  [2:0]  ram_reA;

    reg  [31:0] ram_addrA;
    reg  [31:0] ram_dinA;

    wire [31:0] ram_doutA;

    /* =====================================================
       LOAD PIPELINE
    ===================================================== */

    reg         is_ld;
    reg  [4:0]  ld_rd;

    reg         regs_we3;

    /* =====================================================
       FORWARDING
    ===================================================== */

    reg signed [31:0] rs1_dat;
    reg signed [31:0] rs2_dat;

    /* =====================================================
       PIPELINE CONTROL
    ===================================================== */

    reg bubble;
    reg is_bubble;

    /* =====================================================
       COMBINATIONAL CPU
    ===================================================== */

    always @(*) begin

        regs_rd_we = 1'b0;
        regs_rd_wd = 32'h00000000;

        ram_weA    = 2'b00;
        ram_reA    = 3'b000;

        ram_addrA  = 32'h00000000;
        ram_dinA   = 32'h00000000;

        is_ld      = 1'b0;

        bubble     = 1'b0;

        pc_next    = pc + 32'd4;

        /* ---------------------------------------------
           FORWARDING
        --------------------------------------------- */

        rs1_dat = (regs_we3 && (rs1 == ld_rd) && (rs1 != 0))
                    ? ram_doutA
                    : regs_rd1;

        rs2_dat = (regs_we3 && (rs2 == ld_rd) && (rs2 != 0))
                    ? ram_doutA
                    : regs_rd2;

        /* ---------------------------------------------
           EXECUTE
        --------------------------------------------- */

        if (!is_bubble) begin

            case (opcode)

                /* =====================================
                   LUI
                ===================================== */

                7'b0110111: begin

                    regs_rd_we = 1'b1;
                    regs_rd_wd = U_imm20;
                end

                /* =====================================
                   AUIPC
                ===================================== */

                7'b0010111: begin

                    regs_rd_we = 1'b1;
                    regs_rd_wd = pc_ir + U_imm20;
                end

                /* =====================================
                   OP-IMM
                ===================================== */

                7'b0010011: begin

                    regs_rd_we = 1'b1;

                    case (funct3)

                        3'b000: begin
                            regs_rd_wd = rs1_dat + I_imm12;
                        end

                        3'b010: begin
                            regs_rd_wd = (rs1_dat < I_imm12);
                        end

                        3'b011: begin
                            regs_rd_wd =
                                ($unsigned(rs1_dat) <
                                 $unsigned(I_imm12));
                        end

                        3'b100: begin
                            regs_rd_wd = rs1_dat ^ I_imm12;
                        end

                        3'b110: begin
                            regs_rd_wd = rs1_dat | I_imm12;
                        end

                        3'b111: begin
                            regs_rd_wd = rs1_dat & I_imm12;
                        end

                        3'b001: begin
                            regs_rd_wd =
                                rs1_dat << ir[24:20];
                        end

                        3'b101: begin

                            if (ir[30])
                                regs_rd_wd =
                                    rs1_dat >>> ir[24:20];
                            else
                                regs_rd_wd =
                                    rs1_dat >> ir[24:20];
                        end
                    endcase
                end

                /* =====================================
                   OP
                ===================================== */

                7'b0110011: begin

                    regs_rd_we = 1'b1;

                    case (funct3)

                        3'b000: begin

                            if (funct7[5])
                                regs_rd_wd =
                                    rs1_dat - rs2_dat;
                            else
                                regs_rd_wd =
                                    rs1_dat + rs2_dat;
                        end

                        3'b001: begin
                            regs_rd_wd =
                                rs1_dat << rs2_dat[4:0];
                        end

                        3'b010: begin
                            regs_rd_wd =
                                (rs1_dat < rs2_dat);
                        end

                        3'b011: begin
                            regs_rd_wd =
                                ($unsigned(rs1_dat) <
                                 $unsigned(rs2_dat));
                        end

                        3'b100: begin
                            regs_rd_wd =
                                rs1_dat ^ rs2_dat;
                        end

                        3'b101: begin

                            if (funct7[5])
                                regs_rd_wd =
                                    rs1_dat >>> rs2_dat[4:0];
                            else
                                regs_rd_wd =
                                    rs1_dat >> rs2_dat[4:0];
                        end

                        3'b110: begin
                            regs_rd_wd =
                                rs1_dat | rs2_dat;
                        end

                        3'b111: begin
                            regs_rd_wd =
                                rs1_dat & rs2_dat;
                        end
                    endcase
                end

                /* =====================================
                   LOAD
                ===================================== */

                7'b0000011: begin

                    ram_addrA = rs1_dat + I_imm12;

                    is_ld = 1'b1;

                    case (funct3)

                        3'b000: begin
                            ram_reA = 3'b101; // LB
                        end

                        3'b001: begin
                            ram_reA = 3'b110; // LH
                        end

                        3'b010: begin
                            ram_reA = 3'b111; // LW
                        end

                        3'b100: begin
                            ram_reA = 3'b001; // LBU
                        end

                        3'b101: begin
                            ram_reA = 3'b010; // LHU
                        end
                    endcase
                end

                /* =====================================
                   STORE
                ===================================== */

                7'b0100011: begin

                    ram_addrA = rs1_dat + S_imm12;

                    ram_dinA  = rs2_dat;

                    case (funct3)

                        3'b000: begin
                            ram_weA = 2'b01; // SB
                        end

                        3'b001: begin
                            ram_weA = 2'b10; // SH
                        end

                        3'b010: begin
                            ram_weA = 2'b11; // SW
                        end
                    endcase
                end

                /* =====================================
                   JAL
                ===================================== */

                7'b1101111: begin

                    regs_rd_we = 1'b1;

                    regs_rd_wd = pc;

                    pc_next = pc_ir + J_imm20;

                    bubble = 1'b1;
                end

                /* =====================================
                   JALR
                ===================================== */

                7'b1100111: begin

                    regs_rd_we = 1'b1;

                    regs_rd_wd = pc;

                    pc_next =
                        (rs1_dat + I_imm12) & 32'hFFFFFFFE;

                    bubble = 1'b1;
                end

                /* =====================================
                   BRANCH
                ===================================== */

                7'b1100011: begin

                    case (funct3)

                        3'b000: begin
                            if (rs1_dat == rs2_dat) begin
                                pc_next = pc_ir + B_imm12;
                                bubble = 1'b1;
                            end
                        end

                        3'b001: begin
                            if (rs1_dat != rs2_dat) begin
                                pc_next = pc_ir + B_imm12;
                                bubble = 1'b1;
                            end
                        end

                        3'b100: begin
                            if (rs1_dat < rs2_dat) begin
                                pc_next = pc_ir + B_imm12;
                                bubble = 1'b1;
                            end
                        end

                        3'b101: begin
                            if (rs1_dat >= rs2_dat) begin
                                pc_next = pc_ir + B_imm12;
                                bubble = 1'b1;
                            end
                        end

                        3'b110: begin
                            if ($unsigned(rs1_dat) <
                                $unsigned(rs2_dat)) begin

                                pc_next = pc_ir + B_imm12;

                                bubble = 1'b1;
                            end
                        end

                        3'b111: begin
                            if ($unsigned(rs1_dat) >=
                                $unsigned(rs2_dat)) begin

                                pc_next = pc_ir + B_imm12;

                                bubble = 1'b1;
                            end
                        end
                    endcase
                end

            endcase
        end
    end

    /* =====================================================
       PIPELINE REGISTERS
    ===================================================== */

    always @(posedge clk) begin

        if (rst) begin

            pc         <= 32'h00000000;
            pc_ir      <= 32'h00000000;

            regs_we3   <= 1'b0;
            ld_rd      <= 5'd0;

            is_bubble  <= 1'b0;

        end else begin

            pc <= pc_next;

            pc_ir <= pc_next - 32'd4;

            regs_we3 <= is_ld;

            ld_rd <= rd;

            is_bubble <= bubble;
        end
    end

    /* =====================================================
       REGISTER FILE
    ===================================================== */

    Registers regs (

        .clk(clk),

        .rs1(rs1),
        .rs2(rs2),

        .rd(rd),

        .rd_wd(regs_rd_wd),
        .rd_we(regs_rd_we),

        .rd1(regs_rd1),
        .rd2(regs_rd2),

        .ra3(ld_rd),
        .wd3(ram_doutA),
        .we3(regs_we3)
    );

    /* =====================================================
       RAM + UART + I2C
    ===================================================== */

    RAMIO #(
        .ADDR_WIDTH(RAM_ADDR_WIDTH),
        .DATA_FILE(RAM_FILE),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) ramio (

        .rst(rst),
        .clk(clk),

        .weA(ram_weA),
        .reA(ram_reA),

        .addrA(ram_addrA[RAM_ADDR_WIDTH+1:0]),
        .dinA(ram_dinA),
        .doutA(ram_doutA),

        .addrB(pc[RAM_ADDR_WIDTH+1:0]),
        .doutB(ir),

        .led(led),

        .uart_tx(uart_tx),
        .uart_rx(uart_rx),

        .i2c_sda(i2c_sda),
        .i2c_scl(i2c_scl)
    );

endmodule

`undef DBG
`default_nettype wire