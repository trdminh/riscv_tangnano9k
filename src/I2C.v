`default_nettype none

module I2C #(
    parameter CLK_FREQ = 66_000_000,
    parameter I2C_FREQ = 100_000    
) (
    input  wire       clk,        
    input  wire       rst,
    input  wire [6:0] slave_addr, 
    input  wire [7:0] data_in,    
    input  wire       start_en,   
    inout  wire       sda,
    output reg        scl,
    output reg        busy,
    output reg        done
);

   
    localparam QUARTER_PERIOD = CLK_FREQ / (I2C_FREQ * 4);

    // State Encoding
    localparam IDLE      = 4'd0;
    localparam START     = 4'd1;
    localparam ADDR      = 4'd2;
    localparam RW_BIT    = 4'd3;
    localparam ACK_ADDR  = 4'd4;
    localparam DATA      = 4'd5;
    localparam ACK_DATA  = 4'd6;
    localparam STOP      = 4'd7;

    reg [3:0]  state;
    reg [31:0] count;
    reg [2:0]  bit_idx;
    reg [7:0]  saved_addr;
    reg [7:0]  saved_data;
    
    reg sda_out;
    reg sda_en; 

    assign sda = sda_en ? sda_out : 1'bz;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            count    <= 0;
            scl      <= 1'b1;
            sda_out  <= 1'b1;
            sda_en   <= 1'b0;
            busy     <= 1'b0;
            done     <= 1'b0;
            bit_idx  <= 3'd7;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    scl  <= 1'b1;
                    sda_out <= 1'b1;
                    sda_en  <= 1'b1;
                    if (start_en) begin
                        busy       <= 1'b1;
                        saved_addr <= {slave_addr, 1'b0}; 
                        saved_data <= data_in;
                        state      <= START;
                        count      <= 0;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                START: begin
                    
                    if (count == QUARTER_PERIOD) begin
                        sda_out <= 1'b0;
                    end else if (count == QUARTER_PERIOD * 2) begin
                        scl   <= 1'b0;
                        state <= ADDR;
                        count <= 0;
                        bit_idx <= 3'd7;
                    end else begin
                        count <= count + 1;
                    end
                end

                ADDR: begin
                    sda_en <= 1'b1;
                    sda_out <= saved_addr[bit_idx]; 
                    if (count == QUARTER_PERIOD)      scl <= 1'b1;
                    else if (count == QUARTER_PERIOD * 3) scl <= 1'b0;
                    else if (count == QUARTER_PERIOD * 4) begin
                        count <= 0;
                        if (bit_idx == 0) state <= ACK_ADDR;
                        else bit_idx <= bit_idx - 1;
                    end
                    count <= count + 1;
                end

                ACK_ADDR: begin
                    sda_en <= 1'b0; 
                    if (count == QUARTER_PERIOD)      scl <= 1'b1;
                    else if (count == QUARTER_PERIOD * 3) scl <= 1'b0;
                    else if (count == QUARTER_PERIOD * 4) begin
                        count <= 0;
                        state <= DATA;
                        bit_idx <= 3'd7;
                    end
                    count <= count + 1;
                end

                DATA: begin
                    sda_en <= 1'b1;
                    sda_out <= saved_data[bit_idx];
                    if (count == QUARTER_PERIOD)      scl <= 1'b1;
                    else if (count == QUARTER_PERIOD * 3) scl <= 1'b0;
                    else if (count == QUARTER_PERIOD * 4) begin
                        count <= 0;
                        if (bit_idx == 0) state <= ACK_DATA;
                        else bit_idx <= bit_idx - 1;
                    end
                    count <= count + 1;
                end

                ACK_DATA: begin
                    sda_en <= 1'b0;
                    if (count == QUARTER_PERIOD)      scl <= 1'b1;
                    else if (count == QUARTER_PERIOD * 3) scl <= 1'b0;
                    else if (count == QUARTER_PERIOD * 4) begin
                        count <= 0;
                        state <= STOP;
                    end
                    count <= count + 1;
                end

                STOP: begin
                    sda_en <= 1'b1;
                    if (count == 0)                   sda_out <= 1'b0;
                    else if (count == QUARTER_PERIOD)      scl <= 1'b1;
                    else if (count == QUARTER_PERIOD * 2) sda_out <= 1'b1; 
                    else if (count == QUARTER_PERIOD * 4) begin
                        state <= IDLE;
                        done  <= 1'b1;
                    end
                    count <= count + 1;
                end
            endcase
        end
    end
endmodule