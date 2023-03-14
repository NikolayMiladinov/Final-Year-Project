`include "command_vars.v"
`timescale 1ns / 100ps

module top(
    input CLKA,
    input pb_sw1,
    input pb_sw2,
    input rst_n,

    // SPI PINS
    output MEM_VCC,
    output SPI_CLK,
    output SPI_MOSI,
    input  SPI_MISO,
    output SPI_CS_n,

    // UART PINS
    input  UART_RX,
    output UART_TX,

    // SPI Test pins
    output TEST_MOSI,
    output TEST_CLK,
    output TEST_MISO,
    output TEST_CS_n,
    output TEST_VCC,

    // Other test pins
    output FPGA_CLK,
    output MEM_CM_READY
  );

  parameter SPI_MODE = 3; // CPOL = 1, CPHA = 1
  parameter CLKS_PER_HALF_BIT = 2;  // divide by 4
  parameter CLK_DIV_PARAM = 10;
  parameter MAX_BYTES_PER_CS = 5000;
  parameter MAX_WAIT_CYCLES = 1000;
  parameter BAUD_VAL = 1;
  parameter BAUD_VAL_FRACTION = 0;

  // Control signals
  logic CLK1;
  logic r_Mem_Power;

  // SPI pins
  logic int_SPI_CLK;
  logic int_SPI_CS_n;
  logic int_SPI_MOSI;

  assign MEM_VCC = r_Mem_Power;
  assign SPI_CLK = MEM_VCC & int_SPI_CLK;
  assign SPI_CS_n = MEM_VCC & int_SPI_CS_n;
  assign SPI_MOSI = MEM_VCC & int_SPI_MOSI;

  // Memory controller inputs/outputs
  SPI_Command  r_Command;
  logic        r_Master_CM_DV;
  logic [23:0] r_Addr_Data = 24'b0;  
  logic        w_Master_CM_Ready;
  logic [7:0]  w_RX_Feature_Byte, r_RX_Feature_Byte;
  logic        w_RX_Feature_DV;

  // FIFO pins for testing, to be deleted
  logic [7:0]  w_fifo_save_data_in;
  logic        r_fifo_save_we = 1'b0;
  logic [11:0] w_fifo_save_count;

  logic [7:0]  w_fifo_send_data_out;
  logic        w_fifo_send_empty;
  logic        r_fifo_send_re = 1'b0;

  // State machine
  logic [2:0]  fifo_SM_PROG;
  localparam WRITING = 3'b0;
  localparam LOAD = 3'b1;
  localparam WAIT = 3'b10;
  localparam SAVE = 3'b11;
  localparam p_CACHE_READ = 3'b100;
  localparam RECEIVING = 3'b101;
  localparam EVAL = 3'b110;

  // Assign output pins
  assign TEST_VCC     = MEM_VCC;
  assign TEST_MOSI    = SPI_MOSI;
  assign TEST_CLK     = SPI_CLK;
  assign TEST_CS_n    = SPI_CS_n;
  assign TEST_MISO    = SPI_MISO;
  assign FPGA_CLK     = CLK1;
  assign MEM_CM_READY = w_Master_CM_Ready;


  // Divide clock by CLK_DIV_PARAM
  clk_div #(.div(CLK_DIV_PARAM)) clk_div_1M (
    .clk_in(CLKA),
    .clk_out(CLK1),
    .rst_n(rst_n)
  );

  // Instantiate UUT
  mem_command #(.SPI_MODE(SPI_MODE),.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),.MAX_WAIT_CYCLES(MAX_WAIT_CYCLES),
    .BAUD_VAL(BAUD_VAL),.BAUD_VAL_FRACTION(BAUD_VAL_FRACTION)) 
  MEM_COMMAND_CONTROLLER (
    // Control/Data Signals,
    .i_Rst_L(rst_n),            // FPGA Reset
    .i_Clk(CLK1),              // FPGA Clock
    
    // command specific inputs
    .i_Command(r_Command),          // command type
    .i_CM_DV(r_Master_CM_DV),               // pulse i_DV when all inputs are valid
    .i_Addr_Data(r_Addr_Data),        // data is always LSB byte if there is data
    .o_CM_Ready(w_Master_CM_Ready),         // high when ready to receive next command

    // SPI Interface
    .o_SPI_Clk(int_SPI_CLK),
    .i_SPI_MISO(SPI_MISO),
    .o_SPI_MOSI(int_SPI_MOSI),
    .o_SPI_CS_n(int_SPI_CS_n),

    // Pins for returning feature data
    .o_RX_Feature_Byte(w_RX_Feature_Byte),
    .o_RX_Feature_DV(w_RX_Feature_DV),

    // UART Interface
    .i_UART_RX(UART_RX),
    .o_UART_TX(UART_TX),

    // FIFO pins for testing
    .i_fifo_save_data_in(w_fifo_save_data_in),
    .i_fifo_save_we(r_fifo_save_we),
    .o_fifo_save_count(w_fifo_save_count),

    .o_fifo_send_data_out(w_fifo_send_data_out),
    .i_fifo_send_re(r_fifo_send_re),
    .o_fifo_send_empty(w_fifo_send_empty)
  );

  // Testing sequence for SPI -> on push of button 1, transmit a byte
  // always @(posedge CLK1) begin
  //   if(pb_sw1==1'b0 && w_Master_CM_Ready==1'b1) begin
  //     r_Command         <= WRITE_ENABLE;
  //     r_Addr_Data[15:8] <= 8'h95;
  //     r_Master_CM_DV    <= 1'b1;
  //   end else begin
  //     r_Master_CM_DV    <= 1'b0;
  //   end
  // end

  always @(posedge CLK1 or negedge rst_n) begin
    if (~rst_n) begin
      r_Mem_Power <= 1'b0;
    end
    else if(~pb_sw1) begin
      r_Mem_Power <= 1'b1;
    end
  end

  assign w_fifo_save_data_in = w_fifo_save_count[7:0];

  always @(posedge CLK1 or negedge rst_n) begin
    if (~rst_n) begin
      fifo_SM_PROG <= WRITING;
    end else begin
      case (fifo_SM_PROG)
        WRITING: begin
          if(w_fifo_save_count >= 'd128) begin
            // fifo_SM_PROG    <= LOAD;
            if (~pb_sw2) begin
              fifo_SM_PROG    <= WAIT;
            end
            r_fifo_save_we  <= 1'b0;
          end else begin
            if (~r_fifo_save_we) begin
              r_fifo_save_we      <= 1'b1;
              // w_fifo_save_data_in <= w_fifo_save_count[7:0];
            end else begin
              r_fifo_save_we  <= 1'b0;
            end
          end
        end
        LOAD: begin
          r_Master_CM_DV  <= 1'b0;
          r_fifo_save_we  <= 1'b0;
          if (w_Master_CM_Ready) begin
            r_Command         <= PROG_LOAD1;
            r_Addr_Data[12:0] <= 'h034;
            r_Master_CM_DV    <= 1'b1;
            fifo_SM_PROG      <= WAIT;
          end
        end
        WAIT: begin
          if (w_Master_CM_Ready) begin
            r_Command         <= GET_FEATURE;
            r_Addr_Data[15:8] <= 8'hC0;
            r_Master_CM_DV    <= 1'b1;
          end else begin
            r_Master_CM_DV    <= 1'b0;
          end
          if (w_RX_Feature_DV) begin
            r_RX_Feature_Byte <= w_RX_Feature_Byte;
            // Do some processing and either stay in wait or move to next state
          end
        end 
        p_CACHE_READ: begin
          if (w_Master_CM_Ready) begin
            r_Command         <= CACHE_READ;
            r_Addr_Data[12:0] <= 'h834;
            r_Master_CM_DV    <= 1'b1;
            fifo_SM_PROG      <= RECEIVING;
          end else begin
            r_Master_CM_DV    <= 1'b0;
          end
        end
        RECEIVING: begin
          if (w_Master_CM_Ready) begin
            fifo_SM_PROG      <= EVAL;
          end else begin
            r_Master_CM_DV    <= 1'b0;
          end
        end
        EVAL: begin
          if(~w_fifo_send_empty) begin
            r_fifo_send_re <= 1'b1;
          end else begin
            r_fifo_send_re <= 1'b0;
          end
        end
      endcase
    end
  end

endmodule