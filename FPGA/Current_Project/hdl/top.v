`timescale 1ns / 100ps

module top(
input wire CLKA,
input wire pb_sw1,
input wire rst_n,
output MOSI_PIN2,
output SPI_CLK_PIN3,
output FPGA_CLK_PIN4,
output SPI_READY_PIN5
);
  
  parameter SPI_MODE = 3; // CPOL = 1, CPHA = 1
  parameter CLKS_PER_HALF_BIT = 2;  // divide by 4
  parameter CLK_DIV_PARAM = 10;
  parameter MAX_BYTES_PER_CS = 2;
  parameter CS_INACTIVE_CLKS = 5;

  // Control signals
  wire CLK1;

  // SPI Interface
  wire w_SPI_Clk;
  wire w_SPI_MOSI;
  wire w_SPI_CS_n;

  // Master Specific Inputs
  reg [7:0] r_Master_TX_Byte = 0;
  reg r_Master_TX_DV = 1'b0;
  reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_Master_TX_Count = 'd2;

  // Master Specific Outputs
  wire w_Master_TX_Ready;
  wire w_Master_RX_Count;
  wire r_Master_RX_DV;
  wire [7:0] r_Master_RX_Byte;

  // Assign output pins
  assign MOSI_PIN2 = w_SPI_MOSI;
  assign SPI_CLK_PIN3 = w_SPI_Clk;
  assign FPGA_CLK_PIN4 = CLK1;
  assign SPI_READY_PIN5 = w_Master_TX_Ready;


  // Divide clock by CLK_DIV_PARAM
  clk_div #(.div(CLK_DIV_PARAM)) clk_div_1M(
    .clk_in(CLKA),
    .clk_out(CLK1),
    .rst_n(rst_n)
  );

  // Instantiate UUT
  SPI_Master_With_Single_CS 
  #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),
    .CS_INACTIVE_CLKS(CS_INACTIVE_CLKS)) SPI_CS_Master
  (
   // Control/Data Signals,
   .i_Rst_L(rst_n),     // FPGA Reset
   .i_Clk(CLK1),         // FPGA Clock
   
   // TX (MOSI) Signals
   .i_TX_Count(r_Master_TX_Count),   // # bytes per CS low
   .i_TX_Byte(r_Master_TX_Byte),     // Byte to transmit on MOSI
   .i_TX_DV(r_Master_TX_DV),         // Data Valid Pulse with i_TX_Byte
   .o_TX_Ready(w_Master_TX_Ready),   // Transmit Ready for Byte
   
   // RX (MISO) Signals
   .o_RX_Count(w_Master_RX_Count), // Index RX byte
   .o_RX_DV(r_Master_RX_DV),       // Data Valid pulse (1 clock cycle)
   .o_RX_Byte(r_Master_RX_Byte),   // Byte received on MISO

   // SPI Interface
   .o_SPI_Clk(w_SPI_Clk),
   .i_SPI_MISO(w_SPI_MOSI),
   .o_SPI_MOSI(w_SPI_MOSI),
   .o_SPI_CS_n(w_SPI_CS_n)
   );

// Testing sequence for SPI -> on push of button 1, transmit a byte
always @(posedge CLK1) begin
    if(pb_sw1==1'b0 && w_Master_TX_Ready==1'b1) begin
        r_Master_TX_Byte <= 8'h55;
        r_Master_TX_DV   <= 1'b1;
    end else begin
        r_Master_TX_DV   <= 1'b0;
    end
end

endmodule