///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <Name>
//
// File: top.v
// File history:
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//
// Description: 
//
// <Description here>
//
// Targeted device: <Family::IGLOO> <Die::AGL250V2> <Package::100 VQFP>
// Author: <Name>
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 

`timescale 1ns / 100ps

module top(
input wire CLKA,
input wire pb_sw1,
input wire rst_n,
output MOSI_PIN2,
output SPI_CLK_PIN3,
output FPGA_CLK_PIN4
);
  
  parameter SPI_MODE = 3; // CPOL = 1, CPHA = 1
  parameter CLKS_PER_HALF_BIT = 2;  // divide by 4
  parameter CLK_DIV_PARAM = 20;

  //reg r_Rst_L     = 1'b1;  
  //wire CLKA;
  wire CLK1;
  wire w_SPI_Clk;
  wire w_SPI_MOSI;
  wire w_SPI_CS_n;

  // Master Specific
  reg [7:0] r_Master_TX_Byte = 0;
  reg r_Master_TX_DV = 1'b0;
  wire w_Master_TX_Ready;
  wire r_Master_RX_DV;
  wire [7:0] r_Master_RX_Byte;

  //assign led1 = w_SPI_MOSI;
  assign MOSI_PIN2 = w_SPI_MOSI;
  assign SPI_CLK_PIN3 = w_SPI_Clk;
  assign FPGA_CLK_PIN4 = CLK1;


  //Divide clock by 20
  clk_div #(.div(CLK_DIV_PARAM)) clk_div_1M(
    .clk_in(CLKA),
    .clk_out(CLK1),
    .rst_n(rst_n)
  );

  // Instantiate UUT
  spi_master 
  #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) spi_master_inst
  (
   // Control/Data Signals,
   .i_Rst_L(rst_n),     // FPGA Reset
   .i_Clk(CLK1),         // FPGA Clock
   
   // TX (MOSI) Signals
   .i_TX_Byte(r_Master_TX_Byte),     // Byte to transmit on MOSI
   .i_TX_DV(r_Master_TX_DV),         // Data Valid Pulse with i_TX_Byte
   .o_TX_Ready(w_Master_TX_Ready),   // Transmit Ready for Byte
   
   // RX (MISO) Signals
   .o_RX_DV(r_Master_RX_DV),       // Data Valid pulse (1 clock cycle)
   .o_RX_Byte(r_Master_RX_Byte),   // Byte received on MISO

   // SPI Interface
   .o_SPI_Clk(w_SPI_Clk),
   .i_SPI_MISO(w_SPI_MOSI),
   .o_SPI_MOSI(w_SPI_MOSI),
   .o_SPI_CS_n(w_SPI_CS_n)
   );

   //clocking module



always @(posedge CLK1) begin
    if(pb_sw1==1'b0 && w_Master_TX_Ready==1'b1) begin
        r_Master_TX_Byte <= 8'h55;
        r_Master_TX_DV   <= 1'b1;
    end else begin
        r_Master_TX_DV   <= 1'b0;
    end
end


endmodule