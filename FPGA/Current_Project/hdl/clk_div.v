module clk_div #(
    parameter div = 4
) (
    input clk_in,
    input rst_n,
    output reg clk_tick
);

reg [$clog2(div)-1:0] clk_count;

always @(posedge clk_in or negedge rst_n) begin
    if(~rst_n) begin
        clk_count   <='b0;
        clk_tick    <='b0;
    end else begin
        clk_count   <= clk_count + 'b1;
        if(clk_count == (div - 1)) begin // this way clock tick frequency is clk_in/parameter
            clk_tick    <= 1'b1;
            clk_count   <= 'b0;
        end else clk_tick <= 1'b0;
    end
end
    
endmodule