`include "command_vars.v"
`timescale 1ns / 100ps

module top(
    input CLKA,
    input pb_sw1,
    input pb_sw2,
    input rst_n,

    // SPI PINS
    output MEM_VCC,
    output SPI_CLK,
    output SPI_MOSI,
    input  SPI_MISO,
    output SPI_CS_n,

    // UART PINS
    input  UART_RX,
    output UART_TX,

    // SPI and UART Test pins
    output TEST_MOSI,
    output TEST_CLK,
    output TEST_MISO,
    output TEST_CS_n,
    output TEST_VCC,
    output TEST_RX,
    output TEST_TX,

    // Other test pins
    output FPGA_CLK,
    output MEM_CM_READY,
    output FIFO_STATE0,
    output FIFO_STATE1
  ); /* synthesis syn_noprune=1 */

  parameter SPI_MODE = 3;           // Mode 3: CPOL = 1, CPHA = 1; clock is high during deselect
  parameter CLKS_PER_HALF_BIT = 2;  // SPI_CLK_FREQ = CLK_FREQ/(CLKS_PER_HALF_BIT)
  parameter CLK_DIV_PARAM = 10;     // Divide CLK freq by that number
  parameter MAX_BYTES_PER_CS = 5000;// Maximum number of bytes per transaction with memory chip
  parameter MAX_WAIT_CYCLES = 30; // Maximum number of wait cycles after deasserting (active low) CS
  parameter BAUD_VAL = 12;          // Baud rate = clk_freq / ((1 + BAUD_VAL)x16)
  parameter BAUD_VAL_FRACTION = 0;  // Adds increment of 0.125 to BAUD_VAL (3 -> +0.375)

  // Page address that will be used to store data from UART to memory, no specific reason for this exact address
  // First couple pages are used for OTP, parameters page and Unique page
  parameter PAGE_ADDRESS = 24'h000120; // 4th block, 32nd page
  parameter BLOCK_LOCK_ADDRESS = 8'hA0; 
  parameter CONF_ADDRESS = 8'hB0; 
  parameter STATUS_ADDRESS = 8'hC0;
  parameter DIE_SEL_ADDRESS = 8'hD0;

  // Control signals
  logic CLK_tick;               // Internal clock after dividing the 20 MHz input clock (CLKA)
  logic r_Mem_Power; // VCC line and all other SPI lines are low when r_Mem_Power is low
  logic r_SPI_en;    // Enables or disables the clock inside SPI module
  logic r_UART_en;   // Enables or disables the clock inside UART module

  // SPI pins
  logic int_SPI_CLK;  // Internal SPI_CLK that connects to SPI module
  logic int_SPI_CS_n; // Internal SPI_CS_n that connects to SPI module
  logic int_SPI_MOSI; // Internal SPI_MOSI that connects to SPI module

  // SPI pins with power control; important that CS_n rises and falls with VCC of memory chip
  assign MEM_VCC  = r_Mem_Power;
  assign SPI_CLK  = r_Mem_Power & int_SPI_CLK;
  assign SPI_CS_n = r_Mem_Power & int_SPI_CS_n;
  assign SPI_MOSI = r_Mem_Power & int_SPI_MOSI;

  // Memory controller inputs/outputs
  logic [7:0]  r_Command;       // Command for the memory chip
  logic [7:0]  r_Command_prev /* synthesis syn_preserve=1 syn_noprune=1 */;  // Basically same as r_Command but GET_FEATURE does not change this variable; used for logic
  logic        r_Master_CM_DV;  // Data valid signal for command and beginning of transaction

  // Some commands require an address, which varies in length, but max length is 24 bits (3 bytes)
  // Always the LSBs are used if address is only 1/2 bytes
  // GET_FEATURE/SET_FEATURE require 1 byte address
  // CACHE_READ (+ other types of cache read), PROG_LOAD have a 2 byte address (3 dummy bits, followed by 13-bit column address)
  // Column address indicates from which byte the operation on the specific page should begin (i.e. to change/read only last 10 bytes of a page)
  // However, reading/writing part of a page should not decrease the time to save/read the page
  logic [23:0] r_Addr_Data /* synthesis syn_preserve=1 syn_noprune=1 */; 
  logic        w_Master_CM_Ready; // Indicates that the SPI is ready for the next command when high, busy when low
  logic [7:0]  w_RX_Feature_Byte, r_RX_Feature_Byte /* synthesis syn_preserve=1 syn_noprune=1 */; // wire that connects to mem_command module and internal register to save the feature byte
  logic        w_RX_Feature_DV; // Data valid for when to save the feature byte to the internal register

  // FIFO controls
  logic [12:0] w_fifo_count;    // indicates the number of bytes in FIFO from read perspective
  logic [12:0] r_TRANSFER_SIZE; // indicates the number of data bytes, changed by UART message, internal register
  logic [12:0] w_transfer_size; // indicates the number of data bytes, changed by UART message
  logic        w_transfer_size_DV; // Data valid pulse to save data on w_transfer_size

  // State machine for top-level control
  // States are: UART send/receive, SPI(MEM) send/receive, Compress
  // Variable is controlled only in this module, but mem_command can read the state the fifo is in to decide when to save/read info
  // States are in the included file command_vars
  logic [2:0]  r_fifo_sm;

  // State machine for writing/reading from memory chip
  // Used for doing the correct command sequence when reading/storing data in the memory chip
  logic [2:0]  r_SEND_sm;
  localparam SEND_CHECK = 3'b000;
  localparam SEND_CHECK_EVAL = 3'b001;
  localparam SEND_WRITE_DISABLE = 3'b010;
  localparam SEND_WRITE_ENABLE = 3'b011;
  localparam SEND_PROG_EXEC = 3'b100;
  localparam SEND_PROG_LOAD = 3'b101;
  localparam RESET_MEM = 3'b110;

  logic [2:0]  r_RECEIVE_sm;
  localparam RECEIVE_CHECK = 3'b000;
  localparam RECEIVE_CHECK_EVAL = 3'b001;
  localparam RECEIVE_WRITE_DISABLE = 3'b010;
  localparam RECEIVE_PAGE_READ = 3'b011;
  localparam RECEIVE_CACHE_READ = 3'b100;

  // Assign output pins
  assign TEST_VCC     = r_Mem_Power;
  assign TEST_MOSI    = SPI_MOSI;
  assign TEST_CLK     = SPI_CLK;
  assign TEST_CS_n    = SPI_CS_n;
  assign TEST_MISO    = SPI_MISO;
  assign FPGA_CLK     = CLK_tick;
  assign MEM_CM_READY = r_Mem_Power; // changed for testing
  assign TEST_RX      = UART_RX;
  assign TEST_TX      = w_fifo_count[0];
  assign FIFO_STATE0   = SPI_MISO;
  assign FIFO_STATE1   = SPI_MOSI;


  // Divide clock by CLK_DIV_PARAM
  // Outputs a clock tick, which is inputted into every always block
  clk_div #(.div(CLK_DIV_PARAM)) clk_div_1M (
    .clk_in(CLKA),
    .clk_tick(CLK_tick),
    .rst_n(rst_n)
  );

  // Instantiate UUT
  mem_command #(.SPI_MODE(SPI_MODE),.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),.MAX_WAIT_CYCLES(MAX_WAIT_CYCLES),
    .BAUD_VAL(BAUD_VAL),.BAUD_VAL_FRACTION(BAUD_VAL_FRACTION)) 
  MEM_COMMAND_CONTROLLER (
    // Control/Data Signals,
    .i_Rst_L(rst_n),            // FPGA Reset
    .i_Clk(CLKA),               // FPGA Clock
    .i_Clk_tick(CLK_tick),      // Clock tick
    .i_SPI_en(r_SPI_en),        // SPI Enable
    .i_UART_en(r_UART_en),      // UART Enable
    
    // command specific inputs
    .i_Command(r_Command),          
    .i_CM_DV(r_Master_CM_DV),       
    .i_Addr_Data(r_Addr_Data),
    .o_CM_Ready(w_Master_CM_Ready),

    // SPI Interface
    .o_SPI_Clk(int_SPI_CLK),
    .i_SPI_MISO(SPI_MISO),
    .o_SPI_MOSI(int_SPI_MOSI),
    .o_SPI_CS_n(int_SPI_CS_n),

    // Pins for returning feature data
    .o_RX_Feature_Byte(w_RX_Feature_Byte),
    .o_RX_Feature_DV(w_RX_Feature_DV),

    // UART Interface
    .i_UART_RX(UART_RX),
    .o_UART_TX(UART_TX),

    // FIFO state
    .i_fifo_sm(r_fifo_sm),
    .o_fifo_count(w_fifo_count),
    .o_transfer_size(w_transfer_size),
    .o_transfer_size_DV(w_transfer_size_DV)
  );


  always @(posedge CLKA or negedge rst_n) begin
    // Reset condition
    if (~rst_n) begin
      r_fifo_sm         <= FIFO_IDLE;
      r_SEND_sm         <= RESET_MEM;
      r_RECEIVE_sm      <= RECEIVE_CHECK;
      r_Addr_Data       <= 24'b0;
      r_Master_CM_DV    <= 1'b0;
      r_Command         <= NO_COMMAND;
      r_Command_prev    <= NO_COMMAND;
      r_SPI_en          <= 1'b0;
      r_UART_en         <= 1'b0;
      r_Mem_Power       <= 1'b0;
      r_RX_Feature_Byte <= 8'b0;
      r_TRANSFER_SIZE   <= 'd2048; // default transfer size, half a page, same in mem_command
    end else if(CLK_tick) begin
      // Transfer size wire will change during a UART message before it is the final value
      if (w_transfer_size_DV) begin
        r_TRANSFER_SIZE <= w_transfer_size;
      end

      // SPI/UART are enabled/disabled depending on state
      // Cannot receive data from both UART and SPI because there is only 1 FIFO, hence the need for these states
      // TO DO: add a state that performs checks/changes upon power-up of memory chip

      case (r_fifo_sm)

        // Idle state, push button 1 changes state to receiving data from UART
        FIFO_IDLE: begin
          // Disable both SPI and UART to save power
          r_SPI_en          <= 1'b0;
          r_UART_en         <= 1'b0;
          r_Mem_Power       <= 1'b0;

          // Change state when push button 1 is pressed
          if (~pb_sw1) begin
            if (SIM_TEST == 1) r_fifo_sm <= FIFO_MEM_SEND; // for testing
            else r_fifo_sm <= FIFO_UART_RECEIVE;
            
            r_UART_en       <= 1'b1;
            r_SPI_en       <= 1'b1;
            r_Mem_Power     <= 1'b1;
          end
        end 

        // Receive data from UART
        FIFO_UART_RECEIVE: begin
          // Disable SPI
          // r_SPI_en          <= 1'b0;
          // r_Mem_Power       <= 1'b0; // changed for testing

          // Enable UART if disabled
          if (~r_UART_en) begin
            r_UART_en       <= 1'b1;
          end else begin
            // Go to next state when the FIFO has the correct amount of bytes stored
            // CAREFULL: if FIFO was not emptied before this state, this logic does not work
            // Could be fixed by saving the beginning count when entering the state
            if (w_fifo_count >= r_TRANSFER_SIZE) begin
              r_fifo_sm     <= FIFO_MEM_SEND;
              r_SPI_en      <= 1'b1;
            end
          end
        end 

        // Send the data in FIFO through UART
        FIFO_UART_SEND: begin
          // Disable SPI
          // r_SPI_en          <= 1'b0;
          // r_Mem_Power       <= 1'b0; // changed for testing

          // Enable UART if previously disabled
          if (~r_UART_en) begin
            r_UART_en       <= 1'b1;
          end else begin
            // Change state when FIFO is emptied, when all data has been sent
            if (w_fifo_count == 'd0) begin
              r_fifo_sm     <= FIFO_IDLE;
            end
          end
        end 

        // Read data from memory chip
        // Check status of chip -> page read -> wait until chip is not busy -> cache read
        // Currently this reads a specific page with previously specified address
        FIFO_MEM_RECEIVE: begin
          // Disable UART
          r_UART_en         <= 1'b0;
          r_Master_CM_DV    <= 1'b0;
          // Enable SPI and turn on memory chip
          // CAREFULL: increasing clock frequency might preemptively send commands to the chip before VCC has reached threshold voltage
          if(~r_Mem_Power || ~r_SPI_en) begin
            r_Mem_Power     <= 1'b1;
            r_SPI_en        <= 1'b1;
          end else begin
            // Decided to use states to create the sequential logic for the whole read sequence
            case (r_RECEIVE_sm)

              // This state issues the GET_FEATURE command, then moves to checking the data that is received from the chip
              RECEIVE_CHECK: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= GET_FEATURE;
                  r_Addr_Data[15:8] <= STATUS_ADDRESS; // Address for getting the status of the chip
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_RECEIVE_sm      <= RECEIVE_CHECK_EVAL;
                end
              end

              // Check the data received from GET_FEATURE command
              RECEIVE_CHECK_EVAL: begin
                if (w_RX_Feature_DV) begin

                  r_RX_Feature_Byte <= w_RX_Feature_Byte; // Save the byte from GET_FEATURE command to internal register

                  // Status Feature Byte: 0 -> Operation in Progress (1 when busy), 1 -> Write enable (should be 0)
                  // 2 -> Erase fail, 3 -> Program (Write) fail, 4-6 -> ECC registers, 7 -> Cache read busy (CRBSY)
                  if(w_RX_Feature_Byte[0] || w_RX_Feature_Byte[7]) r_RECEIVE_sm <= RECEIVE_CHECK; // If chip is busy, poll GET_FEATURE until it isn't 
                  else if(w_RX_Feature_Byte[1]) r_RECEIVE_sm <= RECEIVE_WRITE_DISABLE; // Write enable should be 0 in read mode, disable if high
                  else begin
                    // If chip is not busy and is in correct state, decide what to do next

                    // If the page or cache has not been read, then it is the beginning of the sequence and page read must be done
                    if(~(r_Command_prev == PAGE_READ || r_Command_prev == CACHE_READ)) r_RECEIVE_sm <= RECEIVE_PAGE_READ;
                    // If page has been read (save to mem chip cache), the do a cache read
                    if(r_Command_prev == PAGE_READ) r_RECEIVE_sm <= RECEIVE_CACHE_READ;
                    // If cache read has been done, then data has been transferred and FIFO can move to next state (UART_SEND)
                    else if(r_Command_prev == CACHE_READ && w_fifo_count >= r_TRANSFER_SIZE) begin
                      r_RECEIVE_sm  <= RECEIVE_CHECK; // Reset this state machine, so that it always starts with checking the status
                      r_fifo_sm     <= FIFO_UART_SEND;
                      r_UART_en     <= 1'b1;
                    end
                    
                  end
                end
              end

              // Write disable command, check status after
              RECEIVE_WRITE_DISABLE: begin
                if (w_Master_CM_Ready) begin // If SPI is ready for another command
                  r_Command         <= WRITE_DISABLE;
                  r_Command_prev    <= WRITE_DISABLE;
                  r_Master_CM_DV    <= 1'b1; // Issues a data valid pulse (should be 1 clock cycle)
                  r_RECEIVE_sm      <= RECEIVE_CHECK;
                end
              end

              // Cache read command, check status after
              RECEIVE_CACHE_READ: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= CACHE_READ;
                  r_Command_prev    <= CACHE_READ;
                  r_Addr_Data[12:0] <= 'b0;   // CACHE_READ requires a 13-bit column addres, putting 0 means it will save data in the page from 0th byte
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                end
                else if(w_Master_CM_Ready && r_Command_prev == CACHE_READ) begin
                  r_RECEIVE_sm      <= RECEIVE_CHECK;
                end
              end

              // Page read command (saves page data to cache of mem chip), check status after
              RECEIVE_PAGE_READ: begin
                if (w_Master_CM_Ready) begin // If SPI is ready for another command
                  r_Command         <= PAGE_READ;
                  r_Command_prev    <= PAGE_READ;
                  r_Addr_Data[23:0] <= PAGE_ADDRESS; // Assign the correct page address to read data from memory chip
                  r_Master_CM_DV    <= 1'b1; // Issues a data valid pulse (should be 1 clock cycle)
                  r_RECEIVE_sm      <= RECEIVE_CHECK;
                end
              end
            endcase
          end
        end

        // Send data in FIFO to memory chip
        // Check status of chip -> write enable -> program load -> check status -> program execute -> wait until chip is not busy by checking status
        FIFO_MEM_SEND: begin
          // Disable UART
          r_UART_en       <= 1'b0;
          r_Master_CM_DV  <= 1'b0;
          // Enable SPI and turn on memory chip
          // CAREFULL: increasing clock frequency might preemptively send commands to the chip before VCC has reached threshold voltage
          if(~r_Mem_Power || ~r_SPI_en) begin
            r_Mem_Power   <= 1'b1;
            r_SPI_en      <= 1'b1;
          end else begin
            // Decided to use states to create the sequential logic for the whole read sequence
            case (r_SEND_sm)

              // Issue a reset command at the begginning, then use get feature to check when the reset is finished (OIP bit is high during reset)
              RESET_MEM: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= RESET;
                  r_Command_prev    <= RESET;
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK; // TO DO: check if ECC is enabled/disabled and use set_feature if needed to change it
                end
              end

              // This state issues the GET_FEATURE command, then moves to checking the data that is received from the chip
              SEND_CHECK: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= GET_FEATURE;
                  r_Addr_Data[15:8] <= STATUS_ADDRESS; // Address for getting the status of the chip
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK_EVAL;
                end
              end

              // Check the data received from GET_FEATURE command
              SEND_CHECK_EVAL: begin
                if (w_RX_Feature_DV) begin

                  r_RX_Feature_Byte <= w_RX_Feature_Byte; // Save the byte from GET_FEATURE command to internal register

                  // Feature Byte: 0 -> Operation in Progress (1 when busy), 1 -> Write enable (should be 1)
                  // 2 -> Erase fail, 3 -> Program (Write) fail, 4-6 -> ECC registers, 7 -> Cache read busy (CRBSY)
                  if(w_RX_Feature_Byte[0]) r_SEND_sm <= SEND_CHECK; // If chip is busy, poll GET_FEATURE until it isn't
                  else if(~w_RX_Feature_Byte[1] && r_Command_prev == WRITE_DISABLE && w_fifo_count == 'b0) begin
                    r_SEND_sm       <= SEND_CHECK;        // Reset state so it always begins with a status check
                    r_fifo_sm       <= FIFO_MEM_RECEIVE;  // Move to next state
                  end
                  else if(~w_RX_Feature_Byte[1]) r_SEND_sm <= SEND_WRITE_ENABLE; // Write enable should be high before writing to the chip
                  else if(w_RX_Feature_Byte[1] && r_Command_prev == WRITE_DISABLE) r_SEND_sm <= SEND_WRITE_DISABLE; // If write disable unsuccessful, try again
                  else if(w_RX_Feature_Byte[3])  r_SEND_sm <= RESET_MEM; // This clears the prog fail status
                  else begin
                    
                    // If chip is in the correct status, decide what to do next
                    // CAREFULL: currently all data in FIFO is transferred to the chip
                    // Checks whether sequence has begun, if not then begin sequence by doing prog load
                    if(~(r_Command_prev == PROG_LOAD1 || r_Command_prev == PROG_EXEC || r_Command_prev == WRITE_DISABLE)) r_SEND_sm <= SEND_PROG_LOAD;
                    // If data is loaded onto chip, perform program execute
                    else if(w_fifo_count == 'b0 && r_Command_prev == PROG_LOAD1) r_SEND_sm     <= SEND_PROG_EXEC;
                    // If the last command for writing to chip, program execute, has been done, perform write disable
                    else if(w_fifo_count == 'b0 && r_Command_prev == PROG_EXEC) r_SEND_sm <= SEND_WRITE_DISABLE;
                    else r_SEND_sm <= SEND_CHECK;

                  end
                end
              end

              // Write enable command, check status after
              SEND_WRITE_ENABLE: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= WRITE_ENABLE;
                  r_Command_prev    <= WRITE_ENABLE;
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                end
              end

              // Write disable command, check status after
              SEND_WRITE_DISABLE: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= WRITE_DISABLE;
                  r_Command_prev    <= WRITE_DISABLE;
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                end
              end

              // Program load command, where data is transferred from FIFO to memory chip, check status after
              SEND_PROG_LOAD: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= PROG_LOAD1;
                  r_Command_prev    <= PROG_LOAD1;
                  r_Addr_Data[12:0] <= 'b0;   // PROG_LOAD requires a 13-bit column addres, putting 0 means it will save data in the page from 0th byte
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                end
              end

              // Program execute command, where data is transferred from memory cache to page, check status after
              SEND_PROG_EXEC: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= PROG_EXEC;
                  r_Command_prev    <= PROG_EXEC;
                  r_Addr_Data[23:0] <= PAGE_ADDRESS; // Assign the correct page address to store data in memory chip
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                end
              end
            endcase
          end
        end 
      endcase
    end
  end

endmodule