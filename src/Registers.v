`default_nettype none
//`define DBG

module Registers #(
    parameter ADDR_WIDTH = 5,
    parameter WIDTH = 32
)(
    input  wire                    clk,

    /* source registers */

    input  wire [ADDR_WIDTH-1:0]  rs1,
    input  wire [ADDR_WIDTH-1:0]  rs2,

    /* destination register */

    input  wire [ADDR_WIDTH-1:0]  rd,
    input  wire [WIDTH-1:0]       rd_wd,
    input  wire                   rd_we,

    /* read outputs */

    output wire [WIDTH-1:0]       rd1,
    output wire [WIDTH-1:0]       rd2,

    /* load writeback port */

    input  wire [ADDR_WIDTH-1:0]  ra3,
    input  wire [WIDTH-1:0]       wd3,
    input  wire                   we3
);

    /* =====================================================
       REGISTER FILE
       x0-x31
    ===================================================== */

    reg [WIDTH-1:0] mem[0:(1<<ADDR_WIDTH)-1];

    /* =====================================================
       READ PORTS + FORWARDING
    ===================================================== */

    /*
        Priority:

        1. ALU writeback
        2. Load writeback
        3. Register file
    */

    assign rd1 =
        (rs1 == 0) ? {WIDTH{1'b0}} :

        /* EX/MEM forwarding */
        (rd_we && (rd == rs1) && (rd != 0)) ?
            rd_wd :

        /* MEM/WB forwarding */
        (we3 && (ra3 == rs1) && (ra3 != 0)) ?
            wd3 :

        mem[rs1];

    assign rd2 =
        (rs2 == 0) ? {WIDTH{1'b0}} :

        /* EX/MEM forwarding */
        (rd_we && (rd == rs2) && (rd != 0)) ?
            rd_wd :

        /* MEM/WB forwarding */
        (we3 && (ra3 == rs2) && (ra3 != 0)) ?
            wd3 :

        mem[rs2];

    /* =====================================================
       WRITE PORTS
    ===================================================== */

    always @(posedge clk) begin

`ifdef DBG
        $display(
            "%0t REG rs1=%0d rs2=%0d rd=%0d",
            $time,
            rs1,
            rs2,
            rd
        );
`endif

        /*
            Port 3:
            load writeback

            Example:
            lw x1, 0(x2)
        */

        if (we3 && (ra3 != 0)) begin
            mem[ra3] <= wd3;
        end

        /*
            Main writeback

            Example:
            addi x1, x1, 1
        */

        if (rd_we && (rd != 0)) begin
            mem[rd] <= rd_wd;
        end
    end

endmodule

`undef DBG
`default_nettype wire