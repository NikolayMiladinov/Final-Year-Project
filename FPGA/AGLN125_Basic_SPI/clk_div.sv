module clk_div #(
    parameter div = 4
) (
    input clk_in,
    input rst_n,
    output reg clk_out
);

reg [$clog2(div)-1:0] clk_count;

always @(posedge clk_in, negedge rst_n) begin
    if(~rst_n) begin
        clk_count<='b0;
        clk_out<='b0;
    end
    else if(clk_count==(div/2-1)) begin
        clk_count<='b0;
        clk_out<=~clk_out;
    end else begin
        clk_count<=clk_count + 'b1;
    end
end
    
endmodule