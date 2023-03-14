`timescale 1ns / 100ps

module tb_top();

parameter MAIN_CLK_DELAY = 10;
logic SYSCLK = 1'b0;
logic SW1 = 1'b1;
logic SW2 = 1'b1;
logic rst_n = 1'b1;
logic SPI_CLK, SPI_MOSI, SPI_CS_n, MEM_VCC;
logic SPI_MISO = 1'b0;
logic UART_RX, UART_TX;
logic TEST_CLK, TEST_MOSI, TEST_MISO, TEST_CS_n;
logic FPGA_CLK, MEM_CM_READY;

always #(MAIN_CLK_DELAY) SYSCLK = ~SYSCLK;

top top_0(
    // Inputs
    .CLKA(SYSCLK),
    .pb_sw1(SW1),
    .pb_sw2(SW2),
    .rst_n(rst_n),
    // SPI
    .MEM_VCC(MEM_VCC),
    .SPI_CLK(SPI_CLK),
    .SPI_MOSI(SPI_MOSI),
    .SPI_MISO(SPI_MISO),
    .SPI_CS_n(SPI_CS_n),
    // UART 
    .UART_RX(UART_RX),
    .UART_TX(UART_TX),
    // Test pins
    .TEST_CLK(TEST_CLK),
    .TEST_MOSI(TEST_MOSI),
    .TEST_MISO(TEST_MISO),
    .TEST_CS_n(TEST_CS_n),
    .FPGA_CLK(FPGA_CLK),
    .MEM_CM_READY(MEM_CM_READY)
);

initial begin

#10
rst_n = 1'b0;
#10
rst_n = 1'b1;
#200
SW1 = 1'b0;
#400
SW1 = 1'b1;
#85000
$stop;

end

always @(negedge SPI_CLK) begin
    SPI_MISO = ~SPI_MISO;
end

endmodule