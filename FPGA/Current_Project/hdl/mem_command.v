`include "command_vars.v"
`timescale 1ns / 100ps



module mem_command #(
    parameter SPI_MODE          = 3,
    parameter CLKS_PER_HALF_BIT = 2,
    parameter MAX_BYTES_PER_CS  = 5000,
    parameter MAX_WAIT_CYCLES   = 1000,
    parameter BAUD_VAL          = 1,
    parameter BAUD_VAL_FRACTION = 0
) (
    // Control/Data Signals,
    input           i_Rst_L,            // FPGA Reset
    input           i_Clk,              // FPGA Clock
    
    // command specific inputs
    input [7:0]     i_Command,          // command type
    input           i_CM_DV,               // pulse i_CM_DV when all inputs are valid
    input [23:0]    i_Addr_Data,        // data is always LSB byte if there is data

    output          o_CM_Ready,         // high when ready to receive next command

    // SPI Interface
    output o_SPI_Clk,
    input  i_SPI_MISO,
    output o_SPI_MOSI,
    output o_SPI_CS_n,

    // Pins for returning feature data
    output [7:0]    o_RX_Feature_Byte,
    output          o_RX_Feature_DV,

    // UART Interface
    input  i_UART_RX,
    output o_UART_TX,

    // FIFO pins for testing, to be deleted
    input [7:0]     i_fifo_save_data_in,
    input           i_fifo_save_we,
    output [11:0]   o_fifo_save_count,

    output [7:0]    o_fifo_send_data_out,
    input           i_fifo_send_re,
    output          o_fifo_send_empty
);

    // Master Specific Inputs
    logic [7:0]   r_Master_TX_Byte = 0;
    logic         r_Master_TX_DV = 1'b0;

    // Master Specific Outputs
    logic        w_Master_TX_Ready;
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] w_Master_RX_Count;
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_TX_Count;
    logic        w_Master_RX_DV;
    logic [7:0]  w_Master_RX_Byte;

    //FIFO for saving incoming UART data
    logic [7:0]  fifo_save_data_in;
    logic [7:0]  fifo_save_data_out;
    logic        fifo_save_we, fifo_save_re;
    logic [1:0]  fifo_save_re_delayed;
    logic        fifo_save_full, fifo_save_empty;
    logic [11:0] fifo_save_count;

    // For testing, to be deleted
    assign fifo_save_data_in = i_fifo_save_data_in;
    assign fifo_save_we      = i_fifo_save_we;
    assign o_fifo_save_count = fifo_save_count;

    //FIFO for saving incoming UART data
    logic [7:0] fifo_send_data_in;
    logic [7:0] fifo_send_data_out;
    logic       fifo_send_we, fifo_send_re;
    logic       fifo_send_full, fifo_send_empty;
    logic [8:0] fifo_send_count;

    // UART Inputs
    logic [7:0] r_UART_Data_In;
    logic       r_UART_OEN;
    logic       r_UART_WEN;

    // UART Outputs
    logic [7:0] w_UART_Data_Out;
    logic       w_UART_Framing_Err;
    logic       w_UART_Overflow;
    logic       w_UART_RX_Ready;
    logic       w_UART_TX_Ready;

    // For testing, to be deleted
    assign o_fifo_send_data_out = fifo_send_data_out;
    assign fifo_send_re      = i_fifo_send_re;
    assign o_fifo_send_empty = fifo_send_empty;

    // State machine for module
    logic [1:0] r_SM_COM;
    localparam  IDLE        = 2'b00;
    localparam  BUSY    = 2'b01;

    typedef struct {
        SPI_Command command;
        logic [$clog2(MAX_BYTES_PER_CS+1)-1:0]  num_bytes;
        logic                                   save_miso;
        logic [23:0]                            addr_data; // all commands have at most 24bits of address+data, except page program
        logic [2:0]                             miso_byte_num;
        logic [$clog2(MAX_WAIT_CYCLES+1)-1:0]   wait_cycles;
        logic [7:0]                             prog_data;
    } my_command_t;

    my_command_t current_command;   // Stores current command


    logic [1:0] r_SM_UART_TEST = 2'b00;
    localparam GET_DATA = 2'b00;
    localparam WRITE_DATA = 2'b01;
    localparam TRANSFER = 2'b10;

    // Register data into FIFO_SAVE
    always @(posedge i_Clk or negedge i_Rst_L) begin
        if (~i_Rst_L) begin
            r_SM_UART_TEST  <= GET_DATA;
            r_UART_Data_In  <= 'b0;
            r_UART_WEN      <= 1'b1;
            fifo_save_re    <= 1'b0;
        end
        case (r_SM_UART_TEST)
            GET_DATA: begin
                
                if(fifo_save_count>'d120 & w_UART_TX_Ready) begin
                    fifo_save_re <= 1'b1;
                    r_SM_UART_TEST <= WRITE_DATA;
                end else begin
                    fifo_save_re <= 1'b0;
                end
            end
            WRITE_DATA: begin
                fifo_save_re <= 1'b0;
                if(fifo_save_re_delayed[1] & w_UART_TX_Ready) begin
                    r_UART_Data_In <= fifo_save_data_out;
                    r_UART_WEN <= 1'b0;
                    r_SM_UART_TEST <= TRANSFER;
                end
            end
            TRANSFER: begin
                r_UART_WEN <= 1'b1;
                if(w_UART_TX_Ready) r_SM_UART_TEST <= GET_DATA;
            end
        endcase
    end


    // Get data out of FIFO_SAVE
    always @(posedge i_Clk) begin
        // if (r_TX_Count >= 'd2 & r_TX_Count < (current_command.num_bytes -'d1) & 
        //     current_command.command == PROG_LOAD1 & ~fifo_save_empty & 
        //     r_SM_COM == BUSY & w_Master_TX_Ready & ~fifo_save_re) begin 
        //     // Enable reading during PROG_LOAD for 1 cycle after TX_DV
        //     // On the last TX_DV pulse, SM_COM becomes IDLE so reading will not happen
        //     fifo_save_re <= 1'b1;
        // end else begin
        //     fifo_save_re <= 1'b0;
        // end
        fifo_save_re_delayed[0] <= fifo_save_re;
        fifo_save_re_delayed[1] <= fifo_save_re_delayed[0];
        // if (fifo_save_re_delayed[1]) begin
        //     // Use upper bits of addr_data to store data from fifo
        //     current_command.prog_data <= fifo_save_data_out;
        // end
    end


    // Register data into FIFO_SEND
    assign fifo_send_we      = w_Master_RX_DV & w_Master_RX_Count >= (current_command.miso_byte_num - 'b1) 
                               & current_command.command == CACHE_READ & ~fifo_send_full & r_SM_COM == BUSY;

    assign fifo_send_data_in = w_Master_RX_Byte;
    

    // Getting feature data
    assign o_RX_Feature_DV   = w_Master_RX_DV & current_command.command == GET_FEATURE & w_Master_RX_Count == 'd2;
    assign o_RX_Feature_Byte = w_Master_RX_Byte;

    // Register command input
    always @(posedge i_Clk or negedge i_Rst_L) begin
        if(~i_Rst_L) begin
            current_command.command     <= NO_COMMAND;
            current_command.addr_data   <= 'b0;
        end else begin
            if(i_CM_DV) begin
                current_command.command     <= SPI_Command'(i_Command);
                current_command.addr_data   <= i_Addr_Data;
            end
        end
    end

    always @(current_command.command) begin
        case (current_command.command)
            RESET, WRITE_ENABLE, WRITE_DISABLE: begin // One byte
                current_command.save_miso       <= 1'b0;
                current_command.wait_cycles     <= 'b1;
                current_command.num_bytes       <= 'b1;
            end

            GET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MISO data
                current_command.save_miso       <= 1'b1;
                current_command.miso_byte_num   <= 'd3;
                current_command.wait_cycles     <= 'b1;
                current_command.num_bytes       <= 'd3;
            end

            SET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MOSI data
                current_command.save_miso       <= 1'b0;
                current_command.wait_cycles     <= 'b1;
                current_command.num_bytes       <= 'd3;
            end

            PAGE_READ, CACHE_REQ_PAGE, CACHE_LAST, PROG_EXEC, BLOCK_ERASE: begin // 1st byte command, bytes 2,3,4 are the address
                current_command.save_miso       <= 1'b0;
                current_command.wait_cycles     <= 'd1;
                current_command.num_bytes       <= 'd4;
            end

            CACHE_READ: begin // 1st byte command, bytes 2,3,4 are the address (3 dummy bits, 13 bit address, 8 dummy bits), every following byte is MISO data
                current_command.save_miso       <= 1'b1;
                current_command.miso_byte_num   <= 'd5;
                current_command.wait_cycles     <= 'b1;
                current_command.num_bytes       <= 'd10; // # bytes to be read from memory + 4 bytes for command and address
            end

            PROG_LOAD1: begin
                current_command.save_miso       <= 1'b0;
                current_command.wait_cycles     <= 'd1;
                current_command.num_bytes       <= 'd10; // # bytes to store in memory + 3 bytes for command and address
            end

            default: begin
                current_command.save_miso       <= 1'b0;
                current_command.miso_byte_num   <= 'd3;
                current_command.wait_cycles     <= 'b1;
                current_command.num_bytes       <= 'd1;
            end
        endcase
    end


    // Load data to SPI_master
    always @(posedge i_Clk or negedge i_Rst_L) begin
        if(~i_Rst_L) begin
            r_Master_TX_DV  <= 1'b0;
            r_TX_Count      <= 'b0;
            r_SM_COM        <= IDLE;
        end else begin 
            if(w_Master_TX_Ready) begin // When SPI_Master is ready and there are more bytes to be transmitted
                case (r_SM_COM)
                    IDLE: begin
                        if (r_TX_Count == 'b0 & i_CM_DV) begin // Use RX_Count to determine what goes into TX_Byte
                            r_Master_TX_DV   <= 1'b1;
                            r_Master_TX_Byte <= i_Command;
                            r_SM_COM         <= BUSY;
                            r_TX_Count <= 'b1;
                        end
                    end
                    BUSY: begin
                        if (r_TX_Count < current_command.num_bytes) begin

                            case (current_command.command)
                                GET_FEATURE, SET_FEATURE: begin
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= current_command.addr_data[15:8];

                                    else if (r_TX_Count == 'd2) begin
                                        if(current_command.command[5]) r_Master_TX_Byte <= current_command.addr_data[7:0];
                                        else r_Master_TX_Byte <= 'b0;
                                    end
                                end

                                CACHE_READ: begin
                                    if (r_TX_Count == 'd1)  r_Master_TX_Byte <= {3'b0, current_command.addr_data[12:8]};

                                    else if (r_TX_Count == 'd2) r_Master_TX_Byte <= current_command.addr_data[7:0];

                                    else if (r_TX_Count == 'd3) r_Master_TX_Byte <= 'b0;
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
                            
                            r_Master_TX_DV      <= 1'b1;
                            r_TX_Count <= r_TX_Count + 'b1;

                            if (r_TX_Count == (current_command.num_bytes - 'b1)) begin
                                r_TX_Count <= 'b0;
                                r_SM_COM   <= IDLE;
                            end
                        end 
                    end
                endcase
            end else begin
                r_Master_TX_DV  <= 1'b0;
            end
        end
    end


    // Assign ready state of module
    assign o_CM_Ready = o_SPI_CS_n & w_Master_TX_Ready & ~i_CM_DV;


    // Instantiate FIFO for saving incoming UART data
    FIFO_INPUT_SAVE FIFO_SAVE(
        .DATA(fifo_save_data_in),
        .Q(fifo_save_data_out),
        .WE(fifo_save_we),
        .RE(fifo_save_re),
        .CLK(i_Clk),
        .FULL(fifo_save_full),
        .EMPTY(fifo_save_empty),
        .RESET(i_Rst_L),
        .RDCNT(fifo_save_count)
    );


    // Instantiate FIFO for saving incoming MISO data
    FIFO_OUTPUT_SEND FIFO_SEND(
        .DATA(fifo_send_data_in),
        .Q(fifo_send_data_out),
        .WE(fifo_send_we),
        .RE(fifo_send_re),
        .CLK(i_Clk),
        .FULL(fifo_send_full),
        .EMPTY(fifo_send_empty),
        .RESET(i_Rst_L),
        .RDCNT(fifo_send_count)
    );


    // Instantiate SPI
    SPI_Master_With_Single_CS 
    #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),
    .MAX_CS_INACTIVE_CLKS(MAX_WAIT_CYCLES)) SPI_CS_Master
    (
    // Control/Data Signals,
    .i_Rst_L(i_Rst_L),     // FPGA Reset
    .i_Clk(i_Clk),       // FPGA Clock

    // TX (MOSI) Signals
    .i_TX_Count(current_command.num_bytes),   // # bytes per CS low
    .i_TX_Byte(r_Master_TX_Byte),     // Byte to transmit on MOSI
    .i_TX_DV(r_Master_TX_DV),         // Data Valid Pulse with i_TX_Byte
    .i_CS_INACTIVE_CLKS(current_command.wait_cycles),
    .o_TX_Ready(w_Master_TX_Ready),   // Transmit Ready for Byte

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
        .BAUD_VAL(BAUD_VAL),    // Determines baud rate
        .BAUD_VAL_FRACTION(BAUD_VAL_FRACTION), // Additional precision for baud rate, increments of 0.125 for baud val
        .BIT8(1'b1),            // Always transmit 8 data bits
        .CLK(i_Clk),
        .CSN(1'b0),             // Chip select can be zero
        .DATA_IN(r_UART_Data_In), // Data to be transmitted
        .ODD_N_EVEN(1'b0),      // No parity bit
        .OEN(r_UART_OEN),       // Notify UART Data_Out has been read
        .PARITY_EN(1'b0),       // No parity bit
        .RESET_N(i_Rst_L),      
        .RX(i_UART_RX),         // Receive line
        .WEN(r_UART_WEN),       // Enable writing to internal TX register 
        // Outputs
        .DATA_OUT(w_UART_Data_Out), // Data to be transmitted
        .FRAMING_ERR(w_UART_Framing_Err), // Error if no stop bit is detected
        .OVERFLOW(w_UART_Overflow), // Error if too many bits are detected
        .PARITY_ERR(),              
        .RXRDY(w_UART_RX_Ready),    // High when data is available to be read
        .TX(o_UART_TX),             // Transmit line
        .TXRDY(w_UART_TX_Ready)     // Low when transmit buffer is full
    ); 
    
endmodule