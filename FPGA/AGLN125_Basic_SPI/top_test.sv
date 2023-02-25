`timescale 1ns / 100ps

module top_test();

parameter MAIN_CLK_DELAY = 10;
logic SYSCLK = 1'b0;
logic SW1 = 1'b1;
logic rst_n = 1'b1;
logic MOSI, SPI_CLK, FPGA_CLK;

always #(MAIN_CLK_DELAY) SYSCLK = ~SYSCLK;

top top_0(
    // Inputs
    .CLKA(SYSCLK),
    .pb_sw1(SW1),
    .rst_n(rst_n),
    // Outputs
    .MOSI_PIN2(MOSI),
    .SPI_CLK_PIN3(SPI_CLK),
    .FPGA_CLK_PIN4(FPGA_CLK)
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
#10000
$stop;

end

endmodule