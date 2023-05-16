`include "command_vars.v"
`timescale 1ns / 100ps

module mem_command #(
    parameter SPI_MODE          = 3,    // Mode 3: CPOL = 1, CPHA = 1; clock is high during deselect
    parameter CLKS_PER_HALF_BIT = 4,    // SPI_CLK_FREQ = CLK_FREQ/(2xCLKS_PER_HALF_BIT)
    parameter MAX_BYTES_PER_CS  = 5000, // Maximum number of bytes per transaction with memory chip
    parameter MAX_WAIT_CYCLES   = 30, // Maximum number of wait cycles after deasserting (active low) CS
    parameter BAUD_VAL          = 1,    // Baud rate = clk_freq / ((1 + BAUD_VAL)x16)
    parameter BAUD_VAL_FRACTION = 0     // Adds increment of 0.125 to BAUD_VAL (3 -> +0.375)
) (
    // Control/Data Signals,
    input           i_Rst_L,            // FPGA Reset
    input           i_Clk,              // FPGA Clock
    input           i_SPI_en,           // Enable for SPI
    input           i_UART_en,          // Enable for UART
    
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
    input  [2:0]    i_fifo_sm,          // Fifo states: UART send/receive, SPI(MEM) send/receive
    output [12:0]   o_fifo_count,       // Fifo count: from read perspective
    output [12:0]   o_transfer_size,    // Size of UART transfer (when all data is saved in FIFO, its count should be = to transfer size)
    output          o_transfer_size_DV  // Data valid pulse that indicates when transfer_size has changed and is valid
); /* synthesis syn_noprune=1 */;

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
    logic        r_transfer_size_DV;
    logic [12:0] r_UART_count;          // Counts the number of bytes sent through UART
    logic [7:0]  r_UART_command;        // 1st byte in UART transaction is always the command
    // h21 = ! character
    localparam DATA_TRANSFER   = 8'h21; // Data transfer command is followed by 2 bytes indicating the size of transfer, followed by the data

    // UART Inputs
    logic [7:0] r_UART_Data_In;         // Byte to be sent through UART
    logic       r_UART_OEN;             // Active low read enable, assert low when reading from buffer
    logic       r_UART_WEN;             // Active low write enable, assert low when data is to be transmitted
    logic [12:0]w_UART_BAUD_VAL;
    logic [2:0] w_UART_BAUD_VAL_FRACTION;
    logic       w_PARITY_ERR;

    assign w_UART_BAUD_VAL = BAUD_VAL;
    assign w_UART_BAUD_VAL_FRACTION = BAUD_VAL_FRACTION;

    // UART Outputs
    logic [7:0] w_UART_Data_Out;        // Data coming out of UART
    logic       w_UART_Framing_Err;     // Framing error, high indicates a missing stop bit, cleared by asserting OEN low
    logic       w_UART_Overflow;        // When high indicates an overflow in data received
    logic       w_UART_RX_Ready;        // When high indicates data is available in receive buffer
    logic       w_UART_TX_Ready;        // When low indicates transmit buffer cannot store more data
    logic       r_UART_RX_Ready_prv;    // Used for logic

    // State machine for transmitting SPI command
    logic       r_SM_COM;
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
    assign o_fifo_count = w_fifo_count; // Top level needs to know the FIFO count and data transfer size
    assign o_transfer_size = r_TRANSFER_SIZE;
    assign o_transfer_size_DV = r_transfer_size_DV;

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
            w_fifo_count_prev   <= 'd1000; // Testing only

        end else begin
            // default assignments
            r_fifo_re           <= 1'b0;
            r_fifo_we           <= 1'b0;
            r_UART_OEN          <= 1'b1;
            r_UART_WEN          <= 1'b1;
            r_transfer_size_DV  <= 1'b0;
            
            // Cannot receive data from both UART and SPI because there is only 1 FIFO, hence the need for these states
            case (i_fifo_sm)

                FIFO_IDLE: begin
                    // For testing purposes
                    if (SIM_TEST == 1) begin
                        if (w_fifo_count == 'b0 && w_fifo_count_prev != 'b0) begin
                            r_fifo_data_in   <= 'b1; // Save RX byte received from SPI
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end else if (w_fifo_count != w_fifo_count_prev && w_fifo_count < 'd20) begin
                            r_fifo_data_in   <= w_fifo_count +'b1; // Save RX byte received from SPI
                            r_fifo_we        <= 1'b1; // Write enable for FIFO
                            w_fifo_count_prev<= w_fifo_count;
                        end
                    end
                end

                // Receiving data from UART
                FIFO_UART_RECEIVE: begin
                    // w_UART_RX_Ready signals there is data in receive buffer
                    // OEN signals the byte has been read, but has one cycle delay
                    // Hence to not register the same byte more than once, use the additional delayed OEN
                    if (w_UART_RX_Ready && ~r_UART_RX_Ready_prv) begin
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
                        // CAREFUL: if Transfer size was 0, then the count would reset after 3rd byte is processed because new transfer size is not yet saved
                        if (r_TRANSFER_SIZE == 'b0) begin
                            
                        end else if (r_UART_command == DATA_TRANSFER && r_UART_count == (r_TRANSFER_SIZE + 'd2)) begin
                            r_UART_count <= 'b0;
                        end //else r_UART_count <= r_UART_count + 'b1;
                    end else if (r_UART_RX_Ready_prv && ~w_UART_RX_Ready) begin
                        r_UART_RX_Ready_prv <= 1'b0;
                    end else if (r_UART_RX_Ready_prv && w_UART_RX_Ready) begin
                        r_UART_OEN          <= 1'b0;
                    end
                end 

                // Sending data through UART
                FIFO_UART_SEND: begin
                    case (r_SM_SEND)
                        SEND_IDLE: begin
                            // Send data when UART is ready until fifo is empty
                            if (w_fifo_count>'d0 && w_UART_TX_Ready && ~w_fifo_empty) begin
                                r_SM_SEND       <= WRITE_DATA;
                                r_fifo_re       <= 1'b1; // Cleared on next cycle by default assignment
                            end
                        end
                        WRITE_DATA: begin
                            // Send data through UART when fifo_out is valid (2 cycles after RE is HIGH)
                            if(r_fifo_re_delay[1] && w_UART_TX_Ready) begin
                                r_UART_Data_In  <= w_fifo_data_out; // Register the data coming out of FIFO
                                r_UART_WEN      <= 1'b0;            // Signal to UART to read the data
                                r_SM_SEND       <= SEND_IDLE;
                            end else if (~w_UART_TX_Ready) begin
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
                            if(r_TX_Count < 'd3 || current_command.command != PROG_LOAD1) r_SM_SEND <= SEND_IDLE; // For safety, if by mistake in this state, go to idle and wait
                            else if(r_fifo_re_delay[1]) begin
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
            RESET, WRITE_ENABLE, WRITE_DISABLE: begin // One byte
                current_command.num_bytes       <= 'b1;
            end

            GET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MISO data
                current_command.num_bytes       <= 'd3;
            end

            SET_FEATURE: begin // 1st byte command, 2nd byte address, 3rd byte MOSI data
                current_command.num_bytes       <= 'd3;
            end

            PAGE_READ, CACHE_REQ_PAGE, CACHE_LAST, PROG_EXEC, BLOCK_ERASE: begin // 1st byte command, bytes 2,3,4 are the address
                current_command.num_bytes       <= 'd4;
            end

            CACHE_READ: begin // 1st byte command, bytes 2,3,4 are the column address (3 dummy bits, 13 bit address, 8 dummy bits), every following byte is MISO data
                current_command.num_bytes       <= r_TRANSFER_SIZE + 'd4; // # bytes to be read from memory + 4 bytes for command and address
            end

            PROG_LOAD1: begin // 1st byte command, bytes 2,3 are the column address (3 dummy bits, 13 bit address), every following byte is MOSI data
                current_command.num_bytes       <= r_TRANSFER_SIZE + 'd3; // # bytes to store in memory + 3 bytes for command and address
            end

            default: begin
                current_command.wait_cycles     <= 'b1; // Min wait time between commands is 50ns (1 clock cycle at 20 MHz)
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
            r_SM_COM         <= IDLE;
            r_Master_TX_Byte <= 'b0;
        end else begin 
            // Default assignment
            r_Master_TX_DV  <= 1'b0;

            if(w_Master_TX_Ready) begin // When SPI_Master is ready and there are more bytes to be transmitted
                case (r_SM_COM)
                    IDLE: begin
                        // Start SPI when there is a valid command (only pulsed when the ready signal is high)
                        if (r_TX_Count == 'b0 && i_CM_DV) begin // Use RX_Count to determine what goes into TX_Byte
                            r_Master_TX_DV   <= 1'b1;           // Single clock data valid pulse
                            r_Master_TX_Byte <= i_Command;      // Does not use current_command.command as it has 1 cycle delay
                            r_SM_COM         <= BUSY;
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
                                        // If it's set feature, MOSI data is send, if it's get feature, MOSI is 0 and data is MISO
                                        if(current_command.command[5]) r_Master_TX_Byte <= current_command.addr_data[7:0];
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
                                r_SM_COM    <= IDLE;
                            end
                        end else begin
                            r_TX_Count  <= 'b0;
                            r_SM_COM    <= IDLE;
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


    // Instantiate SPI
    SPI_Master_With_Single_CS 
    #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),
    .MAX_CS_INACTIVE_CLKS(MAX_WAIT_CYCLES)) SPI_CS_Master
    (
    // Control/Data Signals,
    .i_Rst_L(i_Rst_L),              // FPGA Reset
    .i_Clk(i_Clk & i_SPI_en),       // FPGA Clock
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
        .CLK(i_Clk & i_UART_en),
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