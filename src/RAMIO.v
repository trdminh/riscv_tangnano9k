//
// interface to RAM, UART, LEDs and I2C
//

`default_nettype none
//`define DBG

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
    parameter ADDR_I2C_SUBADDR  = TOP_ADDR - 5
) (
    input wire rst,

    // ---------------------------------------------------------------------
    // Port A : Data Memory
    // ---------------------------------------------------------------------
    input  wire                    clk,
    input  wire [1:0]              weA,
    input  wire [2:0]              reA,
    input  wire [ADDR_WIDTH+1:0]   addrA,
    input  wire [DATA_WIDTH-1:0]   dinA,
    output reg  [DATA_WIDTH-1:0]   doutA,

    // ---------------------------------------------------------------------
    // Port B : Instruction Memory
    // ---------------------------------------------------------------------
    input  wire [ADDR_WIDTH+1:0]   addrB,
    output wire [DATA_WIDTH-1:0]   doutB,

    // ---------------------------------------------------------------------
    // LEDs
    // ---------------------------------------------------------------------
    output reg  [5:0] led,

    // ---------------------------------------------------------------------
    // UART
    // ---------------------------------------------------------------------
    output wire uart_tx,
    input  wire uart_rx,

    // ---------------------------------------------------------------------
    // I2C
    // ---------------------------------------------------------------------
    inout  wire i2c_sda,
    inout  wire i2c_scl
);

  // =========================================================================
  // RAM Signals
  // =========================================================================

  reg  [ADDR_WIDTH-1:0] ram_addrA;
  reg  [DATA_WIDTH-1:0] ram_dinA;
  wire [DATA_WIDTH-1:0] ram_doutA;
  reg  [3:0]            ram_weA;

  // =========================================================================
  // UART Signals
  // =========================================================================

  reg  [7:0] uarttx_data;
  reg        uarttx_go;
  wire       uarttx_bsy;

  wire       uartrx_dr;
  wire [7:0] uartrx_data;

  reg        uartrx_go;
  reg  [7:0] uartrx_data_read;

  // =========================================================================
  // I2C Registers
  // =========================================================================

  reg  [7:0]  i2c_data_reg;
  reg  [6:0]  i2c_slave_reg;
  reg         i2c_read_en;
  reg         i2c_start_en;

  reg  [15:0] i2c_subaddr_reg;
  reg         i2c_subaddr_len;

  reg  [7:0]  i2c_rx_latch;

  wire        i2c_busy;
  wire        i2c_nack;
  wire [7:0]  i2c_data_out;
  wire        i2c_valid_out;
  wire        i2c_req_data_chunk;

  reg         i2c_busy_d;
  wire        i2c_done_pulse;

  assign i2c_done_pulse = i2c_busy_d & ~i2c_busy;

  // =========================================================================
  // RAM Write Decode
  // =========================================================================

  reg [1:0] addr_lower_w;

  always @(*) begin

    ram_addrA    = addrA >> 2;
    addr_lower_w = addrA[1:0];

    ram_weA  = 4'b0000;
    ram_dinA = 32'h0;

    if (
        addrA != ADDR_LEDS        &&
        addrA != ADDR_UART_OUT    &&
        addrA != ADDR_UART_IN     &&
        addrA != ADDR_I2C_DATA    &&
        addrA != ADDR_I2C_CTRL    &&
        addrA != ADDR_I2C_SUBADDR
    ) begin

      case (weA)

        // ---------------------------------------------------------------
        // BYTE
        // ---------------------------------------------------------------
        2'b01: begin

          case (addr_lower_w)

            2'b00: begin
              ram_weA       = 4'b0001;
              ram_dinA[7:0] = dinA[7:0];
            end

            2'b01: begin
              ram_weA        = 4'b0010;
              ram_dinA[15:8] = dinA[7:0];
            end

            2'b10: begin
              ram_weA         = 4'b0100;
              ram_dinA[23:16] = dinA[7:0];
            end

            2'b11: begin
              ram_weA         = 4'b1000;
              ram_dinA[31:24] = dinA[7:0];
            end

          endcase
        end

        // ---------------------------------------------------------------
        // HALF WORD
        // ---------------------------------------------------------------
        2'b10: begin

          case (addr_lower_w)

            2'b00: begin
              ram_weA        = 4'b0011;
              ram_dinA[15:0] = dinA[15:0];
            end

            2'b10: begin
              ram_weA         = 4'b1100;
              ram_dinA[31:16] = dinA[15:0];
            end

            default: ;

          endcase
        end

        // ---------------------------------------------------------------
        // WORD
        // ---------------------------------------------------------------
        2'b11: begin
          ram_weA  = 4'b1111;
          ram_dinA = dinA;
        end

        default: ;

      endcase
    end
  end

  // =========================================================================
  // Read Pipeline Registers
  // =========================================================================

  reg [ADDR_WIDTH+1:0] addrA_prev;
  reg [2:0]            reA_prev;

  // =========================================================================
  // Read Decode
  // =========================================================================

  always @(*) begin

    doutA = 32'h0;

    // ---------------------------------------------------------------------
    // UART OUT
    // ---------------------------------------------------------------------
    if (addrA_prev == ADDR_UART_OUT && reA_prev == 3'b001) begin

      doutA = {{24{1'b0}}, uarttx_data};

    // ---------------------------------------------------------------------
    // UART IN
    // ---------------------------------------------------------------------
    end else if (addrA_prev == ADDR_UART_IN && reA_prev == 3'b001) begin

      doutA = {{24{1'b0}}, uartrx_data_read};

    // ---------------------------------------------------------------------
    // I2C DATA
    // ---------------------------------------------------------------------
    end else if (addrA_prev == ADDR_I2C_DATA && reA_prev == 3'b001) begin

      doutA = {{24{1'b0}}, i2c_rx_latch};

    // ---------------------------------------------------------------------
    // I2C CTRL
    // bit[1] = nack
    // bit[0] = busy
    // ---------------------------------------------------------------------
    end else if (addrA_prev == ADDR_I2C_CTRL && reA_prev == 3'b001) begin

      doutA = {{30{1'b0}}, i2c_nack, i2c_busy};

    // ---------------------------------------------------------------------
    // I2C SUBADDR
    // ---------------------------------------------------------------------
    end else if (addrA_prev == ADDR_I2C_SUBADDR && reA_prev == 3'b111) begin

      doutA = {
        15'b0,
        i2c_subaddr_len,
        i2c_subaddr_reg
      };

    // ---------------------------------------------------------------------
    // NORMAL RAM
    // ---------------------------------------------------------------------
    end else begin

      casex (reA_prev)

        // ---------------------------------------------------------------
        // BYTE
        // ---------------------------------------------------------------
        3'bx01: begin

          case (addrA_prev[1:0])

            2'b00:
              doutA = reA_prev[2]
                    ? {{24{ram_doutA[7]}}, ram_doutA[7:0]}
                    : {{24{1'b0}}, ram_doutA[7:0]};

            2'b01:
              doutA = reA_prev[2]
                    ? {{24{ram_doutA[15]}}, ram_doutA[15:8]}
                    : {{24{1'b0}}, ram_doutA[15:8]};

            2'b10:
              doutA = reA_prev[2]
                    ? {{24{ram_doutA[23]}}, ram_doutA[23:16]}
                    : {{24{1'b0}}, ram_doutA[23:16]};

            2'b11:
              doutA = reA_prev[2]
                    ? {{24{ram_doutA[31]}}, ram_doutA[31:24]}
                    : {{24{1'b0}}, ram_doutA[31:24]};

          endcase
        end

        // ---------------------------------------------------------------
        // HALF WORD
        // ---------------------------------------------------------------
        3'bx10: begin

          case (addrA_prev[1:0])

            2'b00:
              doutA = reA_prev[2]
                    ? {{16{ram_doutA[15]}}, ram_doutA[15:0]}
                    : {{16{1'b0}}, ram_doutA[15:0]};

            2'b10:
              doutA = reA_prev[2]
                    ? {{16{ram_doutA[31]}}, ram_doutA[31:16]}
                    : {{16{1'b0}}, ram_doutA[31:16]};

            default:
              doutA = 32'h0;

          endcase
        end

        // ---------------------------------------------------------------
        // WORD
        // ---------------------------------------------------------------
        3'b111: begin
          doutA = ram_doutA;
        end

        default: begin
          doutA = 32'h0;
        end

      endcase
    end
  end

  // =========================================================================
  // Sequential Logic
  // =========================================================================

  always @(posedge clk) begin

    if (rst) begin

      led              <= 6'b111111;

      uarttx_data      <= 0;
      uarttx_go        <= 0;

      uartrx_go        <= 1;
      uartrx_data_read <= 0;

      i2c_data_reg     <= 0;
      i2c_slave_reg    <= 7'h76;
      i2c_read_en      <= 0;
      i2c_start_en     <= 0;

      i2c_subaddr_reg  <= 0;
      i2c_subaddr_len  <= 0;

      i2c_rx_latch     <= 0;

      addrA_prev       <= 0;
      reA_prev         <= 0;

      i2c_busy_d       <= 0;

    end else begin

      // -------------------------------------------------------------------
      // Pipeline RAM read address
      // -------------------------------------------------------------------
      addrA_prev <= addrA;
      reA_prev   <= reA;

      // -------------------------------------------------------------------
      // Track I2C busy edge
      // -------------------------------------------------------------------
      i2c_busy_d <= i2c_busy;

      // -------------------------------------------------------------------
      // Clear I2C start pulse
      // -------------------------------------------------------------------
      i2c_start_en <= 1'b0;

      // -------------------------------------------------------------------
      // Latch received I2C byte
      // -------------------------------------------------------------------
      if (i2c_valid_out) begin
        i2c_rx_latch <= i2c_data_out;
      end

      // -------------------------------------------------------------------
      // I2C DATA
      // -------------------------------------------------------------------
      if (addrA == ADDR_I2C_DATA && weA == 2'b01) begin
        i2c_data_reg <= dinA[7:0];
      end

      // -------------------------------------------------------------------
      // I2C CTRL
      // [8:2] slave address
      // [1]   read enable
      // [0]   start
      // -------------------------------------------------------------------
      if (addrA == ADDR_I2C_CTRL && weA != 2'b00) begin

        i2c_slave_reg <= dinA[8:2];
        i2c_read_en   <= dinA[1];

        if (dinA[0]) begin
          i2c_start_en <= 1'b1;
        end
      end

      // -------------------------------------------------------------------
      // I2C SUBADDR
      // bit[16] = subaddr length
      // -------------------------------------------------------------------
      if (addrA == ADDR_I2C_SUBADDR && weA != 2'b00) begin

        i2c_subaddr_reg <= dinA[15:0];
        i2c_subaddr_len <= dinA[16];

      end

      // -------------------------------------------------------------------
      // LEDs
      // -------------------------------------------------------------------
      led[5] <= uart_tx;
      led[4] <= uart_rx;

      if (addrA == ADDR_LEDS && weA == 2'b01) begin
        led[3:0] <= dinA[3:0];
      end

      // -------------------------------------------------------------------
      // UART TX
      // -------------------------------------------------------------------
      if (addrA == ADDR_UART_OUT && weA == 2'b01) begin

        uarttx_data <= dinA[7:0];
        uarttx_go   <= 1'b1;

      end

      if (!uarttx_bsy && uarttx_go) begin

        uarttx_go   <= 1'b0;
        uarttx_data <= 0;

      end

      // -------------------------------------------------------------------
      // UART RX
      // -------------------------------------------------------------------
      if (addrA_prev == ADDR_UART_IN && reA_prev == 3'b001) begin
        uartrx_data_read <= 0;
      end

      if (uartrx_dr && uartrx_go) begin

        uartrx_data_read <= uartrx_data;
        uartrx_go        <= 0;

      end

      if (!uartrx_go) begin
        uartrx_go <= 1;
      end

    end
  end

  // =========================================================================
  // RAM
  // =========================================================================

  RAM #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_FILE (DATA_FILE)
  ) ram (

      .clk   (clk),

      .weA   (ram_weA),
      .addrA (ram_addrA),
      .dinA  (ram_dinA),
      .doutA (ram_doutA),

      .addrB (addrB[ADDR_WIDTH+1:2]),
      .doutB (doutB)
  );

  // =========================================================================
  // UART TX
  // =========================================================================

  UartTx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) uarttx (

      .rst  (rst),
      .clk  (clk),

      .data (uarttx_data),
      .go   (uarttx_go),

      .tx   (uart_tx),
      .bsy  (uarttx_bsy)
  );

  // =========================================================================
  // UART RX
  // =========================================================================

  UartRx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) uartrx (

      .rst  (rst),
      .clk  (clk),

      .rx   (uart_rx),
      .go   (uartrx_go),

      .data (uartrx_data),
      .dr   (uartrx_dr)
  );

  // =========================================================================
  // I2C MASTER
  // =========================================================================

  I2C i2c_inst (

      .i_clk           (clk),
      .reset_n         (~rst),

      .i_addr_w_rw     ({i2c_slave_reg, i2c_read_en}),

      .i_sub_addr      (i2c_subaddr_reg),
      .i_sub_len       (i2c_subaddr_len),

      .i_byte_len      (24'd1),

      .i_data_write    (i2c_data_reg),

      .req_trans       (i2c_start_en),

      .data_out        (i2c_data_out),
      .valid_out       (i2c_valid_out),

      .scl_o           (i2c_scl),
      .sda_o           (i2c_sda),

      .req_data_chunk  (i2c_req_data_chunk),

      .busy            (i2c_busy),

      .nack            (i2c_nack)
  );

endmodule

`undef DBG
`default_nettype wire