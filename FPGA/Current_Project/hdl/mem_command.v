`include "command_vars.v"
`timescale 1ns / 100ps

module mem_command #(
    parameter SPI_MODE          = 3,    // Mode 3: CPOL = 1, CPHA = 1; clock is high during deselect
    parameter CLKS_PER_HALF_BIT = 4,    // SPI_CLK_FREQ = CLK_FREQ/(2xCLKS_PER_HALF_BIT)
    parameter MAX_BYTES_PER_CS  = 5000, // Maximum number of bytes per transaction with memory chip
    parameter MAX_WAIT_CYCLES   = 200, // Maximum number of wait cycles after deasserting (active low) CS
    parameter BAUD_VAL          = 1,    // Baud rate = clk_freq / ((1 + BAUD_VAL)x16)
    parameter BAUD_VAL_FRACTION = 0     // Adds increment of 0.125 to BAUD_VAL (3 -> +0.375)
) (
    // Control/Data Signals,
    input           i_Rst_L,            // FPGA Reset
    input           i_Clk,              // FPGA Clock
    
    // command specific inputs
    input [7:0]     i_Command,          // command type
    input           i_CM_DV,            // pulse i_CM_DV when all inputs are valid
    input [23:0]    i_Addr_Data,        // data is always LSB byte if there is data

    output          o_CM_Ready,         // high when ready to receive next command

    // SPI Interface
    output o_SPI_Clk,
    input  i_SPI_MISO,
    output o_SPI_MOSI,
    output o_SPI_CS_n,

    // Pins for returning feature data
    output [7:0]    o_RX_Feature_Byte,  // wire to w_Master_RX_Byte, the byte last received by SPI
    output          o_RX_Feature_DV,    // data valid pulse when the feature byte should be read

    // UART Interface
    input  i_UART_RX,
    output o_UART_TX,

    // FIFO state
    input           i_tr_size_DV,
    input  [2:0]    i_fifo_sm,          // Fifo states: UART send/receive, SPI(MEM) send/receive
    output          o_send_sm,          // Top lvl does not change state during a read from FIFO
    output          o_UART_RX_Ready,    // Signal to top level that there is UART data to be processed
    output [12:0]   o_fifo_count,       // Fifo count: from read perspective
    output [12:0]   o_transfer_size,    // Size of UART transfer (when all data is saved in FIFO, its count should be = to transfer size)
    output          o_transfer_size_DV, // Data valid pulse that indicates when transfer_size has changed and is valid
    output          o_compress_done
); /* synthesis syn_noprune=1 */;

    localparam [$clog2(MAX_WAIT_CYCLES)-1:0] TIMER_1_25MS_COUNT = (CLK_DIV_BYPASS == 2) ? ((NORM_CLK_FREQ > PLL_FREQ) ? 25000/CLK_PLL_DIV : 25000*CLK_PLL_MULT) : 25000/CLK_DIV_PARAM; // 1.25ms in number of cycles (normal clk frequency is 20MHz)
    localparam [$clog2(MAX_WAIT_CYCLES)-1:0] TIMER_0_5MS_COUNT  = (CLK_DIV_BYPASS == 2) ? ((NORM_CLK_FREQ > PLL_FREQ) ? 10000/CLK_PLL_DIV : 10000*CLK_PLL_MULT) : 10000/CLK_DIV_PARAM; // 0.5ms in number of cycles (normal clk frequency is 20MHz)
    localparam [$clog2(MAX_WAIT_CYCLES)-1:0] TIMER_0_24MS_COUNT = (CLK_DIV_BYPASS == 2) ? ((NORM_CLK_FREQ > PLL_FREQ) ? 4800/CLK_PLL_DIV : 4800*CLK_PLL_MULT) : 4800/CLK_DIV_PARAM; // 0.24ms in number of cycles (normal clk frequency is 20MHz)
    localparam [$clog2(MAX_WAIT_CYCLES)-1:0] TIMER_0_08MS_COUNT = (CLK_DIV_BYPASS == 2) ? ((NORM_CLK_FREQ > PLL_FREQ) ? 1600/CLK_PLL_DIV : 1600*CLK_PLL_MULT) : 1600/CLK_DIV_PARAM; // 0.08ms in number of cycles (normal clk frequency is 20MHz)

    // Master Specific Inputs
    logic [7:0]   r_Master_TX_Byte;     // Byte to be transmitted
    logic         r_Master_TX_DV;       // Data valid pulse telling the SPI module to read the TX_Byte register

    // Master Specific Outputs
    logic        w_Master_TX_Ready;     // Indicates if SPI module is ready or busy
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] w_Master_RX_Count; // SPI module counts the number of bytes received in a single transaction (during CS low)
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_TX_Count;  // Counts the number of byter that were transmitted, incremented right after a data valid transmit pulse
    logic        w_Master_RX_DV;        // Data valid pulse indicating RX_Byte is valid and can be read
    logic [7:0]  w_Master_RX_Byte;      // Byte received from SPI

    //FIFO for saving incoming UART data
    logic [7:0]  r_fifo_data_in;        // Data to be saved in FIFO
    logic [7:0]  w_fifo_data_out;       // Data coming out of FIFO
    logic        r_fifo_we;             // Write enable of FIFO
    logic        r_fifo_re;             // Read enable of FIFO (has 2 cycle delay)
    logic [1:0]  r_fifo_re_delay;       // Delayed read enable, used for logic
    logic        w_fifo_full, w_fifo_empty;   // Full and empty flags for FIFO
    logic [12:0] w_fifo_count;          // Number of bytes in FIFO from read perspective

    logic [12:0] r_TRANSFER_SIZE;       // UART sends how much the transfer size will be and sets this variable
    logic        r_transfer_size_DV;    // after compression the transfer size changes
    logic [12:0] r_UART_count;          // Counts the number of bytes sent through UART
    logic [7:0]  r_UART_command;        // 1st byte in UART transaction is always the command
    // h21 = ! character
    localparam DATA_TRANSFER   = 8'h21; // Data transfer command is followed by 2 bytes indicating the size of transfer, followed by the data

    // UART Inputs
    logic [7:0] r_UART_Data_In;         // Byte to be sent through UART
    logic       r_UART_OEN;             // Active low read enable, assert low when reading from buffer
    logic       r_UART_WEN;             // Active low write enable, assert low when data is to be transmitted
    logic [12:0]w_UART_BAUD_VAL;        // Baud rate = clk_freq / ((1 + BAUD_VAL)x16)
    logic [2:0] w_UART_BAUD_VAL_FRACTION; // Adds increment of 0.125 to BAUD_VAL (3 -> +0.375)
    logic       w_PARITY_ERR;           // Not used

    assign w_UART_BAUD_VAL = BAUD_VAL;
    assign w_UART_BAUD_VAL_FRACTION = BAUD_VAL_FRACTION;

    // UART Outputs
    logic [7:0] w_UART_Data_Out;        // Data coming out of UART
    logic       w_UART_Framing_Err;     // Framing error, high indicates a missing stop bit, cleared by asserting OEN low
    logic       w_UART_Overflow;        // When high indicates an overflow in data received
    logic       w_UART_RX_Ready;        // When high indicates data is available in receive buffer
    logic       w_UART_TX_Ready;        // When low indicates transmit buffer cannot store more data
    logic       r_UART_RX_Ready_prv;    // Used for logic
    logic       r_UART_TX_Ready_prv;    // Used for logic

    // Compression variables
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_comp_count; // Counts how many bytes are left for compression
    logic [2:0] r_count_mod8;               // Counts to 8 for each byte in a block
    logic signed [7:0] w_fifo_out_signed;   // signed version of FIFO output
    logic signed [7:0] w_delta_byte;        // current byte - previous one <=> x_i - x_{i-1}
    logic [7:0] w_zigzag_byte;              // zigzag encoded version of delta byte
    logic signed [7:0] r_prev_data_byte;    // the previous byte (just a 1-cycle delayed version of FIFO output)
    logic [7:0] r_block_arr [0:7];          // buffer for all zigzag encoded bytes in a block
    // 7 and 8 bitwidth are both treated as 7 (0 to 8 has 9 values, but 3-bit reg has 7)
    logic [2:0] w_pack_bit_width;           // = 7 - min(leading zeros in block)
    logic [2:0] r_pack_bit_width;           // same as above but is registered at the correct time because the wire constantly changes
    logic [2:0] r_bytes_to_pack;            // tracks how bytes are left in the packed block
    logic [47:0]w_packed_bits;              // wires the packed bytes
    logic       r_data_compr_true;          // goes high when all the data has been compressed

    // Assign compression wires
    assign w_fifo_out_signed = w_fifo_data_out[7:0]; // signed version of FIFO output
    assign w_delta_byte     = w_fifo_out_signed - r_prev_data_byte;
    assign w_zigzag_byte    = w_delta_byte[7] ? (((~w_delta_byte)+1'b1)<<1) - 1'b1 : w_delta_byte<<1;

    // Checks from MSB to LSB for a 1 to decide how many bits are necessary to represent the bytes in the block
    assign w_pack_bit_width = (r_block_arr[0][7] | r_block_arr[1][7] | r_block_arr[2][7] | r_block_arr[3][7] |
                               r_block_arr[4][7] | r_block_arr[5][7] | r_block_arr[6][7] | r_block_arr[7][7] | 
                               r_block_arr[0][6] | r_block_arr[1][6] | r_block_arr[2][6] | r_block_arr[3][6] |
                               r_block_arr[4][6] | r_block_arr[5][6] | r_block_arr[6][6] | r_block_arr[7][6]) ? 'd7 : 
                              (r_block_arr[0][5] | r_block_arr[1][5] | r_block_arr[2][5] | r_block_arr[3][5] |
                               r_block_arr[4][5] | r_block_arr[5][5] | r_block_arr[6][5] | r_block_arr[7][5]) ? 'd6 : 
                              (r_block_arr[0][4] | r_block_arr[1][4] | r_block_arr[2][4] | r_block_arr[3][4] |
                               r_block_arr[4][4] | r_block_arr[5][4] | r_block_arr[6][4] | r_block_arr[7][4]) ? 'd5 : 
                              (r_block_arr[0][3] | r_block_arr[1][3] | r_block_arr[2][3] | r_block_arr[3][3] |
                               r_block_arr[4][3] | r_block_arr[5][3] | r_block_arr[6][3] | r_block_arr[7][3]) ? 'd4 : 
                              (r_block_arr[0][2] | r_block_arr[1][2] | r_block_arr[2][2] | r_block_arr[3][2] |
                               r_block_arr[4][2] | r_block_arr[5][2] | r_block_arr[6][2] | r_block_arr[7][2]) ? 'd3 : 
                              (r_block_arr[0][1] | r_block_arr[1][1] | r_block_arr[2][1] | r_block_arr[3][1] |
                               r_block_arr[4][1] | r_block_arr[5][1] | r_block_arr[6][1] | r_block_arr[7][1]) ? 'd2 : 
                              (r_block_arr[0][0] | r_block_arr[1][0] | r_block_arr[2][0] | r_block_arr[3][0] |
                               r_block_arr[4][0] | r_block_arr[5][0] | r_block_arr[6][0] | r_block_arr[7][0]) ? 'd1 : 'd0;

    // The bit width for each byte is known from pack_bit_width
    // Therefore, the bits can be packed correspondingly
    // Since Verilog does not allow run-time calculation of indexing a register/wire,
    // the packed bytes must be wired depending on the pack_bit_width
    // 0 wdith does not pack any bytes and for width of 7, the bytes can just be taken from the block array to minimise logic
    assign w_packed_bits    =   r_pack_bit_width=='d6 ? {r_block_arr[0][5:0],r_block_arr[1][5:0],r_block_arr[2][5:0],
                                                         r_block_arr[3][5:0],r_block_arr[4][5:0],r_block_arr[5][5:0],
                                                         r_block_arr[6][5:0],r_block_arr[7][5:0]} : 
                           r_pack_bit_width=='d5 ? {8'b0,r_block_arr[0][4:0],r_block_arr[1][4:0],r_block_arr[2][4:0],
                                                         r_block_arr[3][4:0],r_block_arr[4][4:0],r_block_arr[5][4:0],
                                                         r_block_arr[6][4:0],r_block_arr[7][4:0]} : 
                          r_pack_bit_width=='d4 ? {16'b0,r_block_arr[0][3:0],r_block_arr[1][3:0],r_block_arr[2][3:0],
                                                         r_block_arr[3][3:0],r_block_arr[4][3:0],r_block_arr[5][3:0],
                                                         r_block_arr[6][3:0],r_block_arr[7][3:0]} : 
                          r_pack_bit_width=='d3 ? {24'b0,r_block_arr[0][2:0],r_block_arr[1][2:0],r_block_arr[2][2:0],
                                                         r_block_arr[3][2:0],r_block_arr[4][2:0],r_block_arr[5][2:0],
                                                         r_block_arr[6][2:0],r_block_arr[7][2:0]} : 
                          r_pack_bit_width=='d2 ? {32'b0,r_block_arr[0][1:0],r_block_arr[1][1:0],r_block_arr[2][1:0],
                                                         r_block_arr[3][1:0],r_block_arr[4][1:0],r_block_arr[5][1:0],
                                                         r_block_arr[6][1:0],r_block_arr[7][1:0]} : 
                          r_pack_bit_width=='d1 ? {40'b0,r_block_arr[0][0],r_block_arr[1][0],r_block_arr[2][0],
                                                         r_block_arr[3][0],r_block_arr[4][0],r_block_arr[5][0],
                                                         r_block_arr[6][0],r_block_arr[7][0]} : 48'b0;


    
    // State machine for compression
    logic [1:0] r_SM_COMPRESS;
    localparam  COMPRESS_INITIAL = 2'b0; // initial state of compression, necessary to reset some variables
    localparam  GET_BYTES   = 2'b1; // here bytes are read from FIFO and written to FIFO at the same time
    localparam  WAIT_BYTES  = 2'd2; // this stage waits for any bytes left from the previous stage because FIFO output has 2 cycle delay
    localparam  PACK_BYTES  = 2'd3; // unused for now, but could be used for sequential checking of the width and packing

    // State machine for transmitting SPI command
    logic       r_SM_MEM_COMMAND;
    localparam  IDLE        = 1'b0;
    localparam  BUSY        = 1'b1;

    // State machine for sending data from FIFO to SPI/UART
    logic      r_SM_SEND;
    localparam SEND_IDLE    = 1'b0;
    localparam WRITE_DATA   = 1'b1;

    typedef struct {
        logic [7:0]                               command; // stores the current command that is/was transmitted
        logic [$clog2(MAX_BYTES_PER_CS+1)-1:0]  num_bytes; // Number of bytes that will be transmitted
        logic [23:0]                            addr_data /* synthesis syn_preserve=1 syn_noprune=1 */; // all commands have at most 24bits of address+data, except page program
        logic [$clog2(MAX_WAIT_CYCLES)-1:0]   wait_cycles /* synthesis syn_preserve=1 syn_noprune=1 syn_keep=1 */; // How many cycles to wait after CS goes HIGH
        logic [7:0]                             prog_data; // Data to be saved in memory chip from FIFO during PROG_LOAD command
    } my_command_t;

    my_command_t current_command;   // Stores current command

    // Assign outputs
    assign o_send_sm = r_SM_SEND;
    assign o_compress_done = r_data_compr_true;
    assign o_fifo_count = w_fifo_count; // Top level needs to know the FIFO count and data transfer size
    assign o_transfer_size = r_TRANSFER_SIZE;
    assign o_transfer_size_DV = r_transfer_size_DV;
    assign o_UART_RX_Ready = w_UART_RX_Ready;

    // Getting feature data
    // Feature data is available on 3rd byte received during a GET_FEATURE command
    assign o_RX_Feature_DV   = w_Master_RX_DV & (current_command.command == GET_FEATURE) & w_Master_RX_Count == 'd2;
    assign o_RX_Feature_Byte = w_Master_RX_Byte; // o_RX_Feature_DV signals when this is valid, so no further logic is needed

    // Assign ready state of module
    // The command data valid pulse immediately puts it into busy state
    // When this DV pulse occurs, the transmit data valid pulse goes high, which immediately puts SPI module into busy state
    // Hence, w_Master_TX_Ready goes low and on next cycle o_SPI_CS_n goes low
    // When SPI module is ready and chip select goes high, then the module is ready to transmit the next command
    assign o_CM_Ready = o_SPI_CS_n & w_Master_TX_Ready & ~i_CM_DV;
    logic [12:0] w_fifo_count_prev; // for testing
    integer i;

    always @(posedge i_Clk or negedge i_Rst_L) begin
        // Reset data transfer registers and states
        if (~i_Rst_L) begin
            r_SM_SEND           <= SEND_IDLE;
            r_UART_Data_In      <= 'b0;
            r_fifo_data_in      <= 'b0;
            r_fifo_re           <= 1'b0;
            r_fifo_re_delay     <= 'b0;
            r_fifo_we           <= 1'b0;
            r_UART_WEN          <= 1'b1;
            r_UART_OEN          <= 1'b1;
            r_TRANSFER_SIZE     <= 'd2048;
            r_UART_count        <= 'b0;
            r_UART_command      <= 'b0;
            r_transfer_size_DV  <= 1'b0;
            r_UART_RX_Ready_prv <= 1'b0;
            r_UART_TX_Ready_prv <= 1'b0;
            w_fifo_count_prev   <= 'd1000; // Testing only

            r_SM_COMPRESS       <= 'b0;
            r_count_mod8        <= 'b0;
            r_comp_count        <= 'b0;
            r_prev_data_byte    <= 'b0;
            r_bytes_to_pack     <= 'b0;
            r_pack_bit_width    <= 'b0;
            r_data_compr_true   <= 'b0;
            for (i = 0; i<8; i=i+1) begin
                r_block_arr[i]  <= 'b0;
            end

        end else begin
            // default assignments
            r_fifo_re           <= 1'b0;
            r_fifo_we           <= 1'b0;
            r_UART_OEN          <= 1'b1;
            r_UART_WEN          <= 1'b1;
            r_transfer_size_DV  <= 1'b0; 
            // after every compression, update the transfer count
            // important that this data valid signal is only 1 cycle 
            // and is a couple cycles after the compression finishes because the FIFO count has a delay
            if(i_tr_size_DV) begin
                r_TRANSFER_SIZE     <= w_fifo_count;
                r_transfer_size_DV  <= 1'b1;
            end
            
            // Cannot receive data from both UART and SPI because there is only 1 FIFO, hence the need for these states
            case (i_fifo_sm)
                FIFO_IDLE: begin
                    // For testing purposes, not synthesized when SIM_TEST = 0
                    if (SIM_TEST == 1) begin
                        if (w_fifo_count == 'b0 && w_fifo_count_prev != 'b0) begin
                            r_fifo_data_in   <= 'd254; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        // end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count < 'd30) begin
                        //     r_fifo_data_in   <= r_fifo_data_in +'b1; 
                        //     r_fifo_we        <= 1'b1; // Write enable for FIFO
                        //     w_fifo_count_prev<= w_fifo_count;
                        // end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count >= 'd30 && w_fifo_count < 'd60) begin
                        //     r_fifo_data_in   <= r_fifo_data_in -'b1; 
                        //     r_fifo_we        <= 1'b1; // Write enable for FIFO
                        //     w_fifo_count_prev<= w_fifo_count;
                        // end
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd0) begin
                            r_fifo_data_in   <= 'd254; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd1) begin
                            r_fifo_data_in   <= 'd253; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd2) begin
                            r_fifo_data_in   <= 'd252; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd3) begin
                            r_fifo_data_in   <= 'd248; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd4) begin
                            r_fifo_data_in   <= 'd244; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd5) begin
                            r_fifo_data_in   <= 'd240; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd6) begin
                            r_fifo_data_in   <= 'd238; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count == 'd7) begin
                            r_fifo_data_in   <= 'd235; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count < 'd24) begin
                            r_fifo_data_in   <= r_fifo_data_in +'b1; 
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end 
                    end
                end
                

                // Handle the compression
                FIFO_COMPRESS: begin
                    case (r_SM_COMPRESS)
                        COMPRESS_INITIAL: begin
                            if (~r_data_compr_true) begin // only start compression if it wasn't done yet
                                // reset necessary variables and start compression
                                r_SM_COMPRESS       <= GET_BYTES;
                                r_count_mod8        <= 'b0;
                                r_comp_count        <= w_fifo_count; // FIFO count indicates how many bytes need to be compressed
                                r_prev_data_byte    <= 'b0; // important for first delta encoding
                                r_bytes_to_pack     <= 'b0;
                                r_pack_bit_width    <= 'b0;
                            end
                        end
                        GET_BYTES: begin
                            if (r_comp_count > 'b0) begin // If there are more bytes to compress, read from FIFO
                                r_fifo_re       <= 1'b1;
                                r_comp_count    <= r_comp_count - 1'b1;
                                r_count_mod8    <= r_count_mod8 + 1'b1; // once it reaches 7, it stops to process the block
                            end

                            // Move to waiting for the bytes that are yet to come out of the FIFO
                            // Also move to waiting when all the bytes have been read
                            // Do not change state until all bytes the packed bytes have been saved in the FIFO
                            if (((r_count_mod8 == 'd7 && r_fifo_re == 1'b1) || (r_comp_count <= 'b1)) && r_bytes_to_pack == r_pack_bit_width) begin
                                r_SM_COMPRESS   <= WAIT_BYTES;
                            end

                            // Register what comes out of the FIFO
                            if(r_fifo_re_delay[1] == 1'b1 && r_comp_count!='b0)begin
                                r_block_arr[r_count_mod8 - 'd3] <= w_zigzag_byte; // r_count_mod8 is 2 cycles ahead and starts from 1
                            end else if (r_fifo_re_delay[1] == 1'b1) begin // special case where count is 0 and previous packed bytes are still not saved
                                // When count reaches 0, it might be on any byte in a block of 8
                                // Then r_fifo_re becomes 0 (stop reading from FIFO)
                                // In the next two cycles this will be reflected in r_fifo_re_delay[1:0]
                                // Example: count reaches 0 and there are 5 bytes left that need to packed in a block of typically 8
                                // on that cycle FIFO read is still 1 and the 3rd byte comes out of FIFO (r_block_arr[2]) => 5 - 3
                                // on next cycle FIFO read becomes 1 and the 4th byte needs to come out ...
                                r_block_arr[(r_count_mod8-'d1)-r_fifo_re_delay[0]-r_fifo_re] <= w_zigzag_byte;
                            end

                            // save the packed byte in FIFO
                            // Since reading from the FIFO has 2 cycle delay, the first 2 or more bytes will already be packed 
                            // special case when pack width is 7 because 8 bytes need to be packed
                            if (r_fifo_we && r_pack_bit_width != 'b0 && ((r_bytes_to_pack < r_pack_bit_width) || (r_pack_bit_width=='d7 && r_bytes_to_pack <= r_pack_bit_width))) begin
                                r_fifo_we       <= 1'b1;
                                r_bytes_to_pack <= r_bytes_to_pack + 1'b1; // tracks which byte from the packed array (48-bit wire) should be saved
                                if (r_pack_bit_width<'d7) begin
                                    r_fifo_data_in  <= w_packed_bits[((r_pack_bit_width - r_bytes_to_pack - 1'b1)*8)+:8];
                                end else begin
                                    r_fifo_data_in  <= r_block_arr[r_bytes_to_pack];
                                end
                            end

                            // When done compressing the last bytes, go to initial state and signal that compression is done
                            if (r_comp_count == 'b0 && r_count_mod8 == 'd0 && r_bytes_to_pack == r_pack_bit_width) begin
                                r_SM_COMPRESS       <= COMPRESS_INITIAL;
                                r_data_compr_true   <= 1'b1;
                            end
                        end 
                        
                        WAIT_BYTES: begin
                            // Register the delayed FIFO outputs
                            // if(r_fifo_re_delay[1] == 1'b1 && r_count_mod8 == 'd0)begin
                            //     r_block_arr[7-r_fifo_re_delay[0]-r_fifo_re] <= w_zigzag_byte;
                            // end else if (r_fifo_re_delay[1] == 1'b1) begin // special case where last block is incomplete
                            //     r_block_arr[(r_count_mod8-'d1)-r_fifo_re_delay[0]-r_fifo_re] <= w_zigzag_byte;
                            // end
                            if(r_fifo_re_delay[1] == 1'b1)begin
                                r_block_arr[(r_count_mod8-'d1)-r_fifo_re_delay[0]-r_fifo_re] <= w_zigzag_byte;
                            end

                            // Once done registering the FIFO outputs in the block,
                            // a wire calculates the pack_bit_width and it is saved in a register
                            // since the the reading and writing to the FIFO is done simultaneously,
                            // the register makes sure the width does not change
                            if (~r_fifo_re_delay[1] && r_count_mod8 == 'd0) begin
                                r_bytes_to_pack <= 'b0;
                                r_pack_bit_width<= w_pack_bit_width;
                                // Save the header (bit width in the FIFO)
                                // Currently the block is 1-dimensional so there are 5 padded zeros
                                // Having 2, 4, 5, 7 and 8 dimensions will save some space since less padding will be needed
                                r_fifo_we       <= 1'b1;
                                r_fifo_data_in  <= {5'b0, w_pack_bit_width};
                                r_SM_COMPRESS  <= GET_BYTES;
                            end

                            // When the count is 0 and less than 8 bytes remain to be packed, fill the rest of the block with the last zigzag encoded value
                            if(r_count_mod8!='d0 && ~r_fifo_re_delay[1]) begin
                                r_block_arr[r_count_mod8] <= r_block_arr[r_count_mod8-1'b1];
                                r_count_mod8 <= r_count_mod8 + 1'b1;
                            end
                        end

                        // PACK_BYTES: begin
                            
                        // end
                    endcase

                    // This can be changed to where the FIFO output is saved
                    // When the FIFO output does not change, 'previous' byte will be the same as the current one
                    // However, for the current implementation, this does not affect anything
                    r_prev_data_byte    <= w_fifo_data_out;
                end

                // Receiving data from UART
                FIFO_UART_RECEIVE: begin
                    // w_UART_RX_Ready signals there is data in receive buffer
                    // OEN signals the byte has been read, but has one cycle delay
                    // Hence to not register the same byte more than once, use the additional delayed OEN
                    if (w_UART_RX_Ready && ~r_UART_RX_Ready_prv) begin // the _prv register makes sure this is entered only once (RX_READY has a delay to it)
                        r_UART_RX_Ready_prv <= 1'b1; // w_UART_RX_Ready is high
                        r_UART_OEN          <= 1'b0; // Clears UART receive buffer and tells it that data was read

                        // Decide what to do with received UART byte
                        if(r_UART_count == 'b0) r_UART_command  <= w_UART_Data_Out; // First byte of UART transaction is always the command
                        else begin
                            case (r_UART_command)
                                // Command for transferring data: 1st byte is command, 2nd & 3rd bytes are for the number of data bytes to be transferred
                                DATA_TRANSFER: begin
                                    if (r_UART_count == 'd1) r_TRANSFER_SIZE[12:8]   <= w_UART_Data_Out[4:0]; // Second byte of UART transaction is the MSB of the size
                                    else if (r_UART_count == 'd2) begin
                                        r_TRANSFER_SIZE[7:0]    <= w_UART_Data_Out; // First byte of UART transaction is the LSB of the size
                                        r_transfer_size_DV      <= 1'b1;
                                    end else begin
                                        r_fifo_data_in    <= w_UART_Data_Out; // After data size is sent, bytes after that are data bytes
                                        r_fifo_we         <= 1'b1; // Write enable for FIFO
                                    end
                                end 
                            endcase
                        end

                        // After byte is processed, increment UART_count or reset it
                        r_UART_count <= r_UART_count + 'b1;
                        // CAREFUL: transfer size of 0 causes issues
                        // if Transfer size was 0, then the count would reset after 3rd byte is processed because new transfer size is not yet save
                        if (r_TRANSFER_SIZE != 'b0 && r_UART_command == DATA_TRANSFER && r_UART_count == (r_TRANSFER_SIZE + 'd2)) begin
                            r_UART_count <= 'b0;
                        end //else r_UART_count <= r_UART_count + 'b1;
                    end else if (r_UART_RX_Ready_prv && ~w_UART_RX_Ready) begin
                        r_UART_RX_Ready_prv <= 1'b0;
                    end else if (r_UART_RX_Ready_prv && w_UART_RX_Ready) begin
                        r_UART_OEN          <= 1'b0; // Hold the clear signal until w_UART_RX_Ready goes low
                    end
                end 

                // Sending data through UART
                FIFO_UART_SEND: begin
                    r_UART_count <= 'b0;
                    case (r_SM_SEND)
                        SEND_IDLE: begin
                            // Send data when UART is ready until fifo is empty
                            if (w_fifo_count>'d0 && w_UART_TX_Ready && ~w_fifo_empty && ~r_UART_TX_Ready_prv) begin // the _prv register makes sure this is entered only once (TX_READY has a delay to it)
                                r_SM_SEND       <= WRITE_DATA;
                                r_fifo_re       <= 1'b1; // Cleared on next cycle by default assignment
                                r_UART_TX_Ready_prv <= 1'b1;
                            end else if(r_UART_TX_Ready_prv && ~w_UART_TX_Ready) begin
                                r_UART_TX_Ready_prv <= 1'b0;
                            end
                        end
                        WRITE_DATA: begin
                            // Send data through UART when fifo_out is valid (2 cycles after RE is HIGH)
                            if(r_fifo_re_delay[1] && w_UART_TX_Ready) begin
                                r_UART_Data_In  <= w_fifo_data_out; // Register the data coming out of FIFO
                                r_UART_WEN      <= 1'b0;            // Signal to UART to read the data
                                r_SM_SEND       <= SEND_IDLE;
                            end else if (~w_UART_TX_Ready || (~r_fifo_re_delay[1] && ~r_fifo_re_delay[0] && ~r_fifo_re)) begin // Read hasn't begun, so -> send_idle
                                r_SM_SEND       <= SEND_IDLE;       // For safety if for some reason UART is not ready, go to idle and wait until it is ready
                            end
                        end
                    endcase
                end 

                // Receive data from memory/SPI
                FIFO_MEM_RECEIVE: begin
                    // CAREFULL: currently only command that receives data from mem chip is cache read
                    // During cache read, bytes 4 and after are for data, RX data valid pulse indicates when to save the data
                    if (w_Master_RX_DV && w_Master_RX_Count >= 'd4 && current_command.command == CACHE_READ && ~w_fifo_full) begin
                        r_fifo_data_in   <= w_Master_RX_Byte; // Save RX byte received from SPI
                        r_fifo_we        <= 1'b1; // Write enable for FIFO
                    end
                end 

                // Send data to memory/SPI
                FIFO_MEM_SEND: begin
                    case (r_SM_SEND)
                        SEND_IDLE: begin
                            // Begin sending data when SPI is ready (TX_DV is asserted only when SPI is ready, once per byte), there is data in FIFO and there are still bytes to be transmitted
                            // current_command.num_bytes is affected by r_TRANSFER_SIZE
                            // This begins on 3rd byte of cache read to prepare the data before next TX_DV pulse (works because SPI clock is at least 2x slower and needs to transmit 8 bits)
                            if (current_command.command == PROG_LOAD1 && r_TX_Count >= 'd3 && r_TX_Count < current_command.num_bytes && r_Master_TX_DV && ~w_fifo_empty) begin
                                r_SM_SEND       <= WRITE_DATA;
                                r_fifo_re       <= 1'b1;
                            end
                        end
                        WRITE_DATA: begin
                            // Send data through SPI when fifo_out is valid (2 cycles after RE is HIGH)
                            if(r_TX_Count < 'd3 || current_command.command != PROG_LOAD1 || (~r_fifo_re_delay[1] && ~r_fifo_re_delay[0] && ~r_fifo_re)) begin
                                r_SM_SEND <= SEND_IDLE; // For safety, if by mistake in this state, go to idle and wait
                            end else if(r_fifo_re_delay[1]) begin
                                current_command.prog_data   <= w_fifo_data_out; // Register the data coming out of FIFO
                                r_SM_SEND                   <= SEND_IDLE;
                            end
                        end
                    endcase
                end 
            endcase

            // Shift registers for delay
            r_fifo_re_delay[0]  <= r_fifo_re;
            r_fifo_re_delay[1]  <= r_fifo_re_delay[0];
        end
    end


    // Register/process command input
    always @(posedge i_Clk or negedge i_Rst_L) begin
        // Reset command inputs which are registered
        if(~i_Rst_L) begin
            current_command.command     <= NO_COMMAND;
            current_command.addr_data   <= 'b0;
        end else begin
            // Single clock cycle data valid pulse, save command and address internally
            if(i_CM_DV) begin
                current_command.command     <= i_Command;
                current_command.addr_data   <= i_Addr_Data;
            end
        end
    end

    // Whenever the command changes, change the number of bytes for that transaction
    always @(current_command.command or r_TRANSFER_SIZE) begin
        case (current_command.command)
            RESET: begin
                current_command.num_bytes       <= 'b1;
                // After power-up, the reset command is issued and it takes a max of 1.25ms for the chip to complete the command
                // Therefore, need to wait 1.25ms after issuing the command -> wait_cycles = 1.25ms * clk_freq
                current_command.wait_cycles     <= TIMER_1_25MS_COUNT;
            end
            WRITE_ENABLE, WRITE_DISABLE: begin // One byte
                current_command.num_bytes       <= 'b1;
                current_command.wait_cycles     <= 'd2;
            end

            GET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MISO data
                current_command.num_bytes       <= 'd3;
                current_command.wait_cycles     <= 'd2;
            end

            SET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MOSI data
                current_command.num_bytes       <= 'd3;
                current_command.wait_cycles     <= 'd2;
            end

            BLOCK_ERASE: begin // 1st byte command, bytes 2,3,4 are the address
                current_command.num_bytes       <= 'd4;
                current_command.wait_cycles     <= TIMER_0_5MS_COUNT;
            end

            PROG_EXEC: begin // 1st byte command, bytes 2,3,4 are the address
                current_command.num_bytes       <= 'd4;
                current_command.wait_cycles     <= TIMER_0_24MS_COUNT;
            end

            PAGE_READ, CACHE_REQ_PAGE, CACHE_LAST: begin // 1st byte command, bytes 2,3,4 are the address
                current_command.num_bytes       <= 'd4;
                current_command.wait_cycles     <= TIMER_0_08MS_COUNT;
            end

            CACHE_READ: begin // 1st byte command, bytes 2,3,4 are the column address (3 dummy bits, 13 bit address, 8 dummy bits), every following byte is MISO data
                current_command.num_bytes       <= r_TRANSFER_SIZE + 'd4; // # bytes to be read from memory + 4 bytes for command and address
                current_command.wait_cycles     <= 'd2;
            end

            PROG_LOAD1: begin // 1st byte command, bytes 2,3 are the column address (3 dummy bits, 13 bit address), every following byte is MOSI data
                current_command.num_bytes       <= r_TRANSFER_SIZE + 'd3; // # bytes to store in memory + 3 bytes for command and address
                current_command.wait_cycles     <= 'd2;
            end

            default: begin
                current_command.wait_cycles     <= 'd2; // Min wait time between commands is 50ns (1 clock cycle at 20 MHz)
                current_command.num_bytes       <= 'd1;
            end
        endcase
    end


    // Load data to SPI_master depending on command type
    always @(posedge i_Clk or negedge i_Rst_L) begin
        // Reset registers for SPI logic
        if(~i_Rst_L) begin
            r_Master_TX_DV   <= 1'b0;
            r_TX_Count       <= 'b0;
            r_SM_MEM_COMMAND         <= IDLE;
            r_Master_TX_Byte <= 'b0;
        end else begin 
            // Default assignment
            r_Master_TX_DV  <= 1'b0;

            if(w_Master_TX_Ready) begin // When SPI_Master is ready and there are more bytes to be transmitted
                case (r_SM_MEM_COMMAND)
                    IDLE: begin
                        // Start SPI when there is a valid command (only pulsed when the ready signal is high)
                        if (r_TX_Count == 'b0 && i_CM_DV) begin // Use RX_Count to determine what goes into TX_Byte
                            r_Master_TX_DV   <= 1'b1;           // Single clock data valid pulse
                            r_Master_TX_Byte <= i_Command;      // Does not use current_command.command as it has 1 cycle delay
                            r_SM_MEM_COMMAND         <= BUSY;
                            r_TX_Count       <= 'b1;            // Count was 0, increment to 1
                        end
                    end
                    // During IDLE, the command type and its parameters are saved in the struct current_command
                    BUSY: begin
                        if (r_TX_Count < current_command.num_bytes) begin // Check that there are more bytes to be transmitted
                            
                            // Decides what to send depending on command type and number of bytes transmitted
                            // Previous always block has description of commands and their bytes
                            case (current_command.command)
                                GET_FEATURE, SET_FEATURE: begin
                                    // Feature address is save in bits 15-8, check top-level to confirm
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= current_command.addr_data[15:8];

                                    else if (r_TX_Count == 'd2) begin
                                        // If it's set feature, MOSI data is send, if it's get feature, MOSI is 0 and data is on MISO
                                        if(current_command.command[4]) r_Master_TX_Byte <= current_command.addr_data[7:0];
                                        else r_Master_TX_Byte <= 'b0;
                                    end
                                end

                                CACHE_READ: begin
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= {3'b0, current_command.addr_data[12:8]};

                                    else if (r_TX_Count == 'd2) r_Master_TX_Byte <= current_command.addr_data[7:0];

                                    else if (r_TX_Count == 'd3) r_Master_TX_Byte <= 'b0; // Dummy bytes
                                end

                                PAGE_READ, CACHE_REQ_PAGE, BLOCK_ERASE, PROG_EXEC: begin
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= current_command.addr_data[23:16];

                                    else if (r_TX_Count == 'd2) r_Master_TX_Byte <= current_command.addr_data[15:8];
                                    
                                    else if (r_TX_Count == 'd3) r_Master_TX_Byte <= current_command.addr_data[7:0];
                                end

                                PROG_LOAD1: begin
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= {3'b0, current_command.addr_data[12:8]};

                                    else if (r_TX_Count == 'd2) r_Master_TX_Byte <= current_command.addr_data[7:0];

                                    else if (r_TX_Count > 'd2) r_Master_TX_Byte <= current_command.prog_data;
                                end

                                default: r_Master_TX_Byte <= 'b0;
                            endcase
                            
                            r_Master_TX_DV  <= 1'b1; // Pulse data valid
                            r_TX_Count      <= r_TX_Count + 'b1; // Increment count by 1
                            
                            // When count reaches the number of bytes to be transmitted, reset the count and go to idle to wait for next command
                            if (r_TX_Count == (current_command.num_bytes - 'b1)) begin
                                r_TX_Count  <= 'b0;
                                r_SM_MEM_COMMAND    <= IDLE;
                            end
                        end else begin
                            r_TX_Count  <= 'b0;
                            r_SM_MEM_COMMAND    <= IDLE;
                        end
                    end
                endcase
            end
        end
    end


    // Instantiate FIFO for saving incoming UART data
    FIFO_INPUT_SAVE fifo_(
        .DATA(r_fifo_data_in),  // Data to be saved in the FIFO
        .Q(w_fifo_data_out),    // Data coming out of FIFO
        .WE(r_fifo_we),         // Write enable of FIFO (no delay)
        .RE(r_fifo_re),         // Read enable of FIFO (essentially has 2 cycle delay)
        .CLK(i_Clk),            // FIFO clock
        .FULL(w_fifo_full),     // FIFO is full flag
        .EMPTY(w_fifo_empty),   // FIFO is empty flag
        .RESET(i_Rst_L),        // FIFO reset
        .RDCNT(w_fifo_count)    // Number of bytes in FIFO, from read perspective
    );

    // FIFO_emb fifo__(
    //     .DATA(r_fifo_data_in),  // Data to be saved in the FIFO
    //     .Q(w_fifo_data_out),    // Data coming out of FIFO
    //     .WE(r_fifo_we),         // Write enable of FIFO (no delay)
    //     .RE(r_fifo_re),         // Read enable of FIFO (essentially has 2 cycle delay)
    //     .WCLOCK(i_Clk),            // FIFO clock
    //     .RCLOCK(i_Clk),
    //     .FULL(w_fifo_full),     // FIFO is full flag
    //     .EMPTY(w_fifo_empty),   // FIFO is empty flag
    //     .RESET(i_Rst_L)        // FIFO reset
    // );


    // Instantiate SPI
    SPI_Master_With_Single_CS 
    #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),
    .MAX_CS_INACTIVE_CLKS(MAX_WAIT_CYCLES)) SPI_CS_Master
    (
    // Control/Data Signals,
    .i_Rst_L(i_Rst_L),              // FPGA Reset
    .i_Clk(i_Clk),                  // FPGA Clock
    // TX (MOSI) Signals
    .i_TX_Count(current_command.num_bytes), // Number of bytes per CS low
    .i_TX_Byte(r_Master_TX_Byte),   // Byte to transmit on MOSI
    .i_TX_DV(r_Master_TX_DV),       // Data Valid Pulse with i_TX_Byte
    .i_CS_INACTIVE_CLKS(current_command.wait_cycles),
    .o_TX_Ready(w_Master_TX_Ready), // Transmit Ready for Byte
    // RX (MISO) Signals
    .o_RX_Count(w_Master_RX_Count), // Index RX byte
    .o_RX_DV(w_Master_RX_DV),       // Data Valid pulse (1 clock cycle)
    .o_RX_Byte(w_Master_RX_Byte),   // Byte received on MISO
    // SPI Interface
    .o_SPI_Clk(o_SPI_Clk),
    .i_SPI_MISO(i_SPI_MISO),
    .o_SPI_MOSI(o_SPI_MOSI),
    .o_SPI_CS_n(o_SPI_CS_n)
    );


    // Instantiate UART
    UART_CORE UART_Master(
        // Inputs
        .BAUD_VAL(w_UART_BAUD_VAL),        // Determines baud rate
        .BAUD_VAL_FRACTION(w_UART_BAUD_VAL_FRACTION), // Additional precision for baud rate, increments of 0.125 for baud val
        .BIT8(1'b1),                // Always transmit 8 data bits
        .CLK(i_Clk),
        .CSN(1'b0),                 // Chip select can be zero
        .DATA_IN(r_UART_Data_In),   // Data to be transmitted
        .ODD_N_EVEN(1'b0),          // No parity bit
        .OEN(r_UART_OEN),           // Notify UART Data_Out has been read
        .PARITY_EN(1'b0),           // No parity bit
        .RESET_N(i_Rst_L),      
        .RX(i_UART_RX),             // Receive line
        .WEN(r_UART_WEN),           // Enable writing to internal TX register 
        // Outputs
        .DATA_OUT(w_UART_Data_Out), // Data received
        .FRAMING_ERR(w_UART_Framing_Err), // Error if no stop bit is detected
        .OVERFLOW(w_UART_Overflow), // Error if too many bits are detected
        .PARITY_ERR(w_PARITY_ERR),              
        .RXRDY(w_UART_RX_Ready),    // High when data is available to be read
        .TX(o_UART_TX),             // Transmit line
        .TXRDY(w_UART_TX_Ready)     // Low when transmit buffer is full
    ); 
    
endmodule