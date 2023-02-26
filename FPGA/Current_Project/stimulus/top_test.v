`timescale 1ns / 100ps

module top_test();

parameter MAIN_CLK_DELAY = 10;
logic SYSCLK = 1'b0;
logic SW1 = 1'b1;
logic rst_n = 1'b1;
logic MOSI, SPI_CLK, FPGA_CLK, SPI_READY;

always #(MAIN_CLK_DELAY) SYSCLK = ~SYSCLK;

top top_0(
    // Inputs
    .CLKA(SYSCLK),
    .pb_sw1(SW1),
    .rst_n(rst_n),
    // Outputs
    .MOSI_PIN2(MOSI),
    .SPI_CLK_PIN3(SPI_CLK),
    .FPGA_CLK_PIN4(FPGA_CLK),
    .SPI_READY_PIN5(SPI_READY)
);

initial begin

#10
rst_n = 1'b0;
#200
rst_n = 1'b1;
#200
SW1 = 1'b0;
#400
SW1 = 1'b1;
@(posedge SPI_READY);
SW1 = 1'b0;
#400
SW1 = 1'b1;
@(posedge SPI_READY);
#10000
$stop;

end

endmodule