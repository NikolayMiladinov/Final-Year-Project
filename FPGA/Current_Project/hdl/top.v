`include "command_vars.v"
`timescale 1ns / 100ps

module top(
    input CLKA,
    // input pb_sw1,
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
    // output TEST_MOSI,
    // output TEST_CLK,
    // output TEST_MISO,
    // output TEST_CS_n,
    // output TEST_VCC,
    // output TEST_RX,
    // output TEST_TX,

    // Other test pins
    // output FPGA_CLK,
    // output MEM_CM_READY,
    output FIFO_TRIG_WR,
    // output FIFO_TRIG_RE,
    output FIFO_TRIG_DL
  ); /* synthesis syn_noprune=1 */

  // Parameters for memmory controller
  parameter SPI_MODE = 3;           // Mode 3: CPOL = 1, CPHA = 1; clock is high during deselect
  parameter CLKS_PER_HALF_BIT = 2;  // SPI_CLK_FREQ = CLK_FREQ/(CLKS_PER_HALF_BIT)
  parameter MAX_BYTES_PER_CS = 5000;// Maximum number of bytes per transaction with memory chip
  parameter MAX_WAIT_CYCLES = 25000;  // Maximum number of wait cycles after deasserting (active low) CS
  parameter BAUD_VAL = (130/CLK_DIV_PARAM) - 1; // Baud rate = clk_freq / ((1 + BAUD_VAL)x16); This achieves a 9600 baud rate
  parameter BAUD_VAL_FRACTION = 0;  // Adds increment of 0.125 to BAUD_VAL (3 -> +0.375)

  // Page address that will be used to store data from UART to memory, no specific reason for this exact address
  // First couple pages are used for OTP, parameters page and Unique page
  parameter PAGE_ADDRESS = 24'h000316;  // Page address
  parameter BLOCK_LOCK_ADDRESS = 8'hA0; // Address in GET/SET FEATURE command to access status of which blocks are locked (cannot write to these blocks)
  parameter CONF_ADDRESS = 8'hB0;       // Address in GET/SET FEATURE command to access status of the configuration (usually normal mode)
  parameter STATUS_ADDRESS = 8'hC0;     // Address in GET/SET FEATURE command to access status of the chip
  parameter DIE_SEL_ADDRESS = 8'hD0;    // Address in GET/SET FEATURE command to access information on which die is selected (2 dies total)

  // Control signals
  logic CLK1;        // Internal clock after dividing the 20 MHz input clock (CLKA); division can be bypassed as well (look at command_vars file)
  logic r_Mem_Power; // VCC line and all other SPI lines are low when r_Mem_Power is low

  // SPI pins
  logic int_SPI_CLK;  // Internal SPI_CLK that connects to SPI module
  logic int_SPI_CS_n; // Internal SPI_CS_n that connects to SPI module
  logic int_SPI_MOSI; // Internal SPI_MOSI that connects to SPI module

  // SPI pins with power control; important that CS_n rises and falls with VCC of memory chip
  assign MEM_VCC  = r_Mem_Power; 
  assign SPI_CLK  = r_Mem_Power & int_SPI_CLK;
  assign SPI_CS_n = r_Mem_Power & int_SPI_CS_n; // Should rise/fall with VCC when powering on/off
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
  logic [23:0] r_Addr_Data /* synthesis syn_preserve=1 syn_noprune=1 */; // TO DO: remove MSB 7 bits; [16:0] are only needed
  logic        w_Master_CM_Ready; // Indicates that the SPI is ready for the next command when high, busy when low
  logic [7:0]  w_RX_Feature_Byte, r_RX_Feature_Byte /* synthesis syn_preserve=1 syn_noprune=1 */; // wire that connects to mem_command module and internal register to save the feature byte
  logic        w_RX_Feature_DV; // Data valid for when to save the feature byte to the internal register

  // FIFO controls
  logic        w_UART_RX_Ready;
  logic [12:0] w_fifo_count;    // indicates the number of bytes in FIFO from read perspective
  logic [12:0] r_TRANSFER_SIZE; // indicates the number of data bytes, changed by UART message, internal register
  logic [12:0] w_transfer_size; // indicates the number of data bytes, changed by UART message
  logic        w_transfer_size_DV; // Data valid pulse to save data on w_transfer_size

  // State machine for top-level control
  // States are: UART send/receive, SPI(MEM) send/receive, Compress
  // Variable is controlled only in this module, but mem_command can read the state the fifo is in to decide when to save/read info
  // States are in the included file command_vars
  logic [2:0]  r_fifo_sm;

  logic        w_send_sm; // Two-state register in mem_command, used so that fifo state changes only when in idle state
  logic [15:0] r_Pwrup_Timer; // Counts 2ms, in the case of the max 20MHz clock, needs to count to 40 000 (2^15 = 32k    => need 16 bits)

  // State machine for writing/reading from memory chip
  // Used for doing the correct command sequence when reading/storing data in the memory chip
  logic [2:0]  r_SEND_sm;
  localparam SEND_CHECK           = 3'b000; // Initiates GET FEATURE command, address depends on previous states
  localparam SEND_CHECK_EVAL      = 3'b001; // Checks the results of GET FEATURE command
  localparam SEND_WRITE_DISABLE   = 3'b010; // WRITE DISABLE command
  localparam SEND_WRITE_ENABLE    = 3'b011; // WRITE ENABLE command
  localparam SEND_SET_FEATURE     = 3'b100; // SET FEATURE command if result of GET FEATURE is not what was expected
  localparam SEND_PROG_LOAD_EXEC  = 3'b101; // Initiates PROGRAM LOAD or EXECUTE if LOAD was done 
  localparam RESET_MEM            = 3'b110; // RESET command

  logic [2:0]  r_RECEIVE_sm;
  localparam RECEIVE_CHECK        = 3'b000;
  localparam RECEIVE_CHECK_EVAL   = 3'b001;
  localparam RECEIVE_WRITE_DISABLE = 3'b010;
  localparam RECEIVE_PAGE_READ    = 3'b011; // PAGE READ command with address specified in parameter section
  localparam RECEIVE_CACHE_READ   = 3'b100; // Initiate CACHE READ command when PAGE READ is finished (can be combined with page read state)

  // For commands that need waiting, do get_feature command twice
  logic [1:0] r_check_twice; // used to accomplish the logic in comment above

  // Assign output pins
  // assign TEST_VCC     = r_Mem_Power;
  // assign TEST_MOSI    = SPI_MOSI;
  // assign TEST_CLK     = SPI_CLK;
  // assign TEST_CS_n    = SPI_CS_n;
  // assign TEST_MISO    = SPI_MISO;
  // assign FPGA_CLK     = CLK1;
  // assign MEM_CM_READY = 1'b0; // extra pin for testing
  // assign TEST_RX      = UART_RX;
  // assign TEST_TX      = UART_TX;
  assign FIFO_TRIG_WR = ~r_fifo_sm[0]&&r_fifo_sm[1]&&r_fifo_sm[2];  // Triggers high during memory power-up
  // assign FIFO_TRIG_RE = ~r_fifo_sm[0]&~r_fifo_sm[1]&r_fifo_sm[2];     // Triggers high during a read to the memory
  assign FIFO_TRIG_DL = r_fifo_sm[0]&&r_fifo_sm[1]&&(~r_fifo_sm[2])&&(r_Command_prev == BLOCK_ERASE); // Triggers high during a block erase command


  generate
    if(CLK_DIV_BYPASS == 0) begin
      // Divide clock by CLK_DIV_PARAM
      clk_div #(.div(CLK_DIV_PARAM)) clk_div_1M (
        .clk_in(CLKA),
        .clk_out(CLK1),
        .rst_n(rst_n)
      );
    end else begin
      assign CLK1 = CLKA;
    end
  endgenerate
  

  // Instantiate UUT
  mem_command #(.SPI_MODE(SPI_MODE),.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
    .MAX_BYTES_PER_CS(MAX_BYTES_PER_CS),.MAX_WAIT_CYCLES(MAX_WAIT_CYCLES),
    .BAUD_VAL(BAUD_VAL),.BAUD_VAL_FRACTION(BAUD_VAL_FRACTION)) 
  MEM_COMMAND_CONTROLLER (
    // Control/Data Signals,
    .i_Rst_L(rst_n),            // FPGA Reset
    .i_Clk(CLK1),               // FPGA Clock
    
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
    .o_send_sm(w_send_sm),
    .o_UART_RX_Ready(w_UART_RX_Ready),
    .o_fifo_count(w_fifo_count),
    .o_transfer_size(w_transfer_size),
    .o_transfer_size_DV(w_transfer_size_DV)
  );


  always @(posedge CLK1 or negedge rst_n) begin
    // Reset condition
    if (~rst_n) begin
      r_fifo_sm         <= FIFO_IDLE;
      r_SEND_sm         <= RESET_MEM;
      r_RECEIVE_sm      <= RECEIVE_CHECK;
      r_Addr_Data       <= 24'b0;
      r_Master_CM_DV    <= 1'b0;
      r_Command         <= NO_COMMAND;
      r_Command_prev    <= NO_COMMAND;
      r_Mem_Power       <= 1'b0;
      r_RX_Feature_Byte <= 8'b0;
      r_check_twice     <= 2'b0;
      r_TRANSFER_SIZE   <= 'd2048; // default transfer size, half a page, same in mem_command
      r_Pwrup_Timer     <= 'b0;
    end else begin
      // Transfer size wire will change during a UART message before it is the final value
      if (w_transfer_size_DV) begin
        r_TRANSFER_SIZE <= w_transfer_size;
      end

      // SPI/UART are enabled/disabled depending on state
      // Cannot receive data from both UART and SPI because there is only 1 FIFO, hence the need for these states

      case (r_fifo_sm)

        // Idle state, push button 1 changes state to receiving data from UART
        FIFO_IDLE: begin
          // Power off memory chip to save power 
          r_Mem_Power       <= 1'b0;

          // Change state when push button 1 is pressed 
          // if (SIM_TEST == 1 && ~pb_sw1) r_fifo_sm <= FIFO_WAIT_MEM_PWRUP; // for testing
          // When UART data is available, start processing it
          if (w_UART_RX_Ready) r_fifo_sm <= FIFO_UART_RECEIVE;
        end 

        // Receive data from UART
        FIFO_UART_RECEIVE: begin
          // Power off memory chip to save power
          r_Mem_Power       <= 1'b0;

          // Go to next state when the FIFO has the correct amount of bytes stored
          // CAREFULL: if FIFO was not emptied before this state, this logic does not work
          // Could be fixed by saving the beginning count when entering the state
          if (w_fifo_count >= r_TRANSFER_SIZE) begin
            r_fifo_sm     <= FIFO_WAIT_MEM_PWRUP;
          end
        end 

        // Send the data in FIFO through UART
        FIFO_UART_SEND: begin
          // Power off memory chip to save power
          if(w_Master_CM_Ready) r_Mem_Power <= 1'b0; // Only power off if SPI is idle

          // Change state when FIFO is emptied, when all data has been sent
          // ~w_send_sm makes sure state does not change during a read from FIFO
          if (w_fifo_count == 'd0 && ~w_send_sm) begin
            r_fifo_sm     <= FIFO_IDLE;
          end
        end 

        // Wait 2ms after power up
        FIFO_WAIT_MEM_PWRUP: begin
          // Turn on memory chip if it was previously off
          if(~r_Mem_Power) begin
            r_Mem_Power <= 1'b1;
            // Reset timer
            r_Pwrup_Timer <= 'b0;
          end else begin
            // Begin counting
            r_Pwrup_Timer <= r_Pwrup_Timer + 'b1;
            // When counter reaches 2ms count value, reset timer and move to next state
            if(r_Pwrup_Timer >= TIMER_2MS_COUNT) begin
              r_fifo_sm     <= FIFO_MEM_SEND;
              r_Pwrup_Timer <= 'b0;
            end
          end
        end

        // Read data from memory chip
        // Check status of chip -> page read -> wait until chip is not busy -> cache read
        // Currently this reads a specific page with previously specified address
        FIFO_MEM_RECEIVE: begin
          r_Master_CM_DV    <= 1'b0;
          // Only issue commands if the chip is turned on
          if(r_Mem_Power) begin 
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

                  // Do a get feature command twice if previous command was READ
                  // Often the first get feature is not accurate
                  if(r_check_twice == 2'b0 && (r_Command_prev == CACHE_READ || r_Command_prev == PAGE_READ)) begin
                    r_RECEIVE_sm  <= RECEIVE_CHECK;
                    r_check_twice <= 2'b1;
                  end
                  else if(w_RX_Feature_Byte[0] || w_RX_Feature_Byte[7]) r_RECEIVE_sm <= RECEIVE_CHECK; // If chip is busy, poll GET_FEATURE until it isn't 
                  else if(w_RX_Feature_Byte[1]) r_RECEIVE_sm <= RECEIVE_WRITE_DISABLE; // Write enable should be 0 in read mode, disable if high
                  else begin
                    // If chip is not busy and is in correct state, decide what to do next

                    // If the page or cache has not been read, then it is the beginning of the sequence and page read must be done
                    if(~(r_Command_prev == PAGE_READ || r_Command_prev == CACHE_READ)) r_RECEIVE_sm <= RECEIVE_PAGE_READ;
                    // If page has been read (save to mem chip cache), the do a cache read
                    else if(r_Command_prev == PAGE_READ) r_RECEIVE_sm <= RECEIVE_CACHE_READ;
                    // If cache read has been done, then data has been transferred and FIFO can move to next state (UART_SEND)
                    else if(r_Command_prev == CACHE_READ && w_fifo_count >= r_TRANSFER_SIZE) begin
                      r_RECEIVE_sm  <= RECEIVE_CHECK; // Reset this state machine, so that it always starts with checking the status
                      r_fifo_sm     <= FIFO_UART_SEND;
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

              // TO DO: CACHE READ and PAGE READ states can be combined
              // Cache read command, check status after
              RECEIVE_CACHE_READ: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= CACHE_READ;
                  r_Command_prev    <= CACHE_READ;
                  r_Addr_Data[23:0] <= 'b0;   // CACHE_READ requires a 13-bit column addres, putting 0 means it will save data in the page from 0th byte
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_RECEIVE_sm      <= RECEIVE_CHECK;
                  r_check_twice     <= 2'b0;  // Reset logic to issue get feature command twice
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
                  r_check_twice     <= 2'b0; // Reset logic to issue get feature command twice
                end
              end
            endcase
          end
        end

        // Send data in FIFO to memory chip
        // Check status of chip -> write enable -> program load -> check status -> program execute -> wait until chip is not busy by checking status
        FIFO_MEM_SEND: begin
          r_Master_CM_DV  <= 1'b0;
          // Only issue commands if the chip is turned on
          if(r_Mem_Power) begin 
            // Decided to use states to create the sequential logic for the whole read sequence
            case (r_SEND_sm)

              // Issue a reset command at the begginning, then use get feature to check when the reset is finished (OIP bit is high during reset)
              RESET_MEM: begin
                if (w_Master_CM_Ready) begin        // If SPI is ready for another command
                  r_Command         <= RESET;
                  r_Command_prev    <= RESET;
                  r_Master_CM_DV    <= 1'b1;        // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                  r_check_twice     <= 2'b0;        // Reset logic to issue get feature command twice
                end
              end

              // Do a SET FEATURE command when chip is not in correct state
              // Upon power-up all block are locked, so a SET_FEATURE command is necessary
              // Address is set previously by GET FEATURE command, so not necessary to change it
              // Based on address from previous GET FEATURE command, send the correct data to change the chip's features
              SEND_SET_FEATURE: begin
                if (w_Master_CM_Ready) begin        // If SPI is ready for another command
                  r_Command         <= SET_FEATURE;
                  r_Command_prev    <= SET_FEATURE;
                  if(r_Addr_Data[15:8] == BLOCK_LOCK_ADDRESS) r_Addr_Data[7:0] <= 'b0; // unlock all blocks, so they can all be written to
                  else if(r_Addr_Data[15:8] == CONF_ADDRESS) r_Addr_Data[7:0] <= 'h10; // normal configuration with ECC enabled
                  r_Master_CM_DV    <= 1'b1;        // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;  // Make sure SET FEATURE worked, if not SET FEATURE is initiated again
                end
              end

              // This state issues the GET_FEATURE command, then moves to checking the data that is received from the chip 
              SEND_CHECK: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command           <= GET_FEATURE;

                  // Makes sure after reset status of chip is checked twice as sometimes the first check is incorrect
                  if(r_Command_prev == RESET && r_check_twice < 2'd2) r_Addr_Data[15:8] <= STATUS_ADDRESS; // Address for getting the status of the chip
                  else if((r_Command_prev == RESET && r_Addr_Data[15:8] == STATUS_ADDRESS && ~r_RX_Feature_Byte[0]) || (r_Command_prev == SET_FEATURE && r_Addr_Data[15:8] == BLOCK_LOCK_ADDRESS)) begin
                    r_Addr_Data[15:8] <= BLOCK_LOCK_ADDRESS; // Address for getting the block lock status of the chip
                    r_Command_prev    <= GET_FEATURE;
                  end else if((r_Command_prev == GET_FEATURE && r_Addr_Data[15:8] == BLOCK_LOCK_ADDRESS) || (r_Command_prev == SET_FEATURE && r_Addr_Data[15:8] == CONF_ADDRESS)) begin
                    r_Addr_Data[15:8] <= CONF_ADDRESS;       // Address for getting the configuration status of the chip
                    r_Command_prev    <= GET_FEATURE;
                  end else r_Addr_Data[15:8] <= STATUS_ADDRESS; // Address for getting the status of the chip
                  r_Master_CM_DV      <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm           <= SEND_CHECK_EVAL;
                end
              end

              // Check the data received from GET_FEATURE command
              SEND_CHECK_EVAL: begin
                if (w_RX_Feature_DV) begin
                  r_RX_Feature_Byte <= w_RX_Feature_Byte; // Save the byte from GET_FEATURE command to internal register

                  // Block Lock Byte: 0 -> nothing, 1 -> should be 0, 2 -> High block lower part, 3-6 -> Block Lock bits, 7 -> should be 0
                  
                  // Configuration Byte: 0 -> continuous read, 2-3 -> Driver strength (00 is for 100%), 4 -> ECC enable, 
                  // 5 -> LOT enable (keep at 0), 1,6,7 -> configuration bits (0 is for normal)

                  // Status Byte: 0 -> Operation in Progress (1 when busy), 1 -> Write enable (should be 1)
                  // 2 -> Erase fail, 3 -> Program (Write) fail, 4-6 -> ECC registers, 7 -> Cache read busy (CRBSY)

                  if(r_Addr_Data[15:8] == BLOCK_LOCK_ADDRESS) begin
                    if(w_RX_Feature_Byte != 'b0) r_SEND_sm <= SEND_SET_FEATURE; // unlock all blocks
                    else r_SEND_sm <= SEND_CHECK;
                  end else if (r_Addr_Data[15:8] == CONF_ADDRESS) begin
                    if(w_RX_Feature_Byte != 'h10) r_SEND_sm <= SEND_SET_FEATURE; // normal configuration, ECC enabled, 100% driver strength
                    else r_SEND_sm <= SEND_CHECK;
                  end else if(r_Addr_Data[15:8] == STATUS_ADDRESS) begin
                    // Do a get feature command twice if previous command was RESET, ERASE or PROGRAM
                    // Often the first get feature is not accurate
                    if(r_check_twice == 2'b0 && (r_Command_prev == RESET || r_Command_prev == BLOCK_ERASE || r_Command_prev == PROG_LOAD1 || r_Command_prev == PROG_EXEC)) begin
                      r_SEND_sm     <= SEND_CHECK;
                      r_check_twice <= 2'b1;
                    end else if(r_check_twice == 2'b1 && r_Command_prev == RESET) begin // Needed for checking twice the status after a reset
                      r_SEND_sm     <= SEND_CHECK;
                      r_check_twice <= 2'd2;
                    end
                    else if(w_RX_Feature_Byte[0]) r_SEND_sm <= SEND_CHECK; // If chip is busy, poll GET_FEATURE until it isn't
                    else if(w_RX_Feature_Byte[3] || w_RX_Feature_Byte[2])  r_SEND_sm <= RESET_MEM; // This clears the prog/erase fail status
                    else if(~w_RX_Feature_Byte[1] && (r_Command_prev == WRITE_DISABLE || r_Command_prev == PROG_EXEC) && w_fifo_count == 'b0) begin
                      r_SEND_sm       <= RESET_MEM;        // Reset state so it always begins with a mem reset
                      r_fifo_sm       <= FIFO_MEM_RECEIVE; // Move to next state
                    end
                    // If the last command for writing to chip, program execute, has been done, perform write disable
                    else if(w_fifo_count == 'b0 && r_Command_prev == PROG_EXEC && w_RX_Feature_Byte[1]) r_SEND_sm <= SEND_WRITE_DISABLE;
                    else if(~w_RX_Feature_Byte[1]) r_SEND_sm <= SEND_WRITE_ENABLE; // Write enable should be high before writing to the chip
                    else if(w_RX_Feature_Byte[1] && r_Command_prev == WRITE_DISABLE) r_SEND_sm <= SEND_WRITE_DISABLE; // If write disable unsuccessful, try again
                    else begin
                      // If chip is in correct status, continue with the writing sequence commands (erase -> program -> execute)
                      // Since every time the program writes to the same page, for accurate measurements the block must be erased
                      r_SEND_sm <= SEND_PROG_LOAD_EXEC;
                    end
                  end
                end
              end

              // TO DO: Write enable and disable state can be combined with some logic
              // Write enable command, check status after
              SEND_WRITE_ENABLE: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  r_Command         <= WRITE_ENABLE;
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
              // Program execute command, where data is transferred from memory cache to page, check status after
              SEND_PROG_LOAD_EXEC: begin
                if (w_Master_CM_Ready) begin  // If SPI is ready for another command
                  
                  if(r_Command_prev == PROG_LOAD1) begin
                    r_Command         <= PROG_EXEC;
                    r_Command_prev    <= PROG_EXEC;
                    r_Addr_Data[23:0] <= PAGE_ADDRESS; // Assign the correct page address to store data in memory chip
                  end else if(r_Command_prev == BLOCK_ERASE) begin
                    r_Command         <= PROG_LOAD1;
                    r_Command_prev    <= PROG_LOAD1;
                    r_Addr_Data[23:0] <= 'b0; // PROG_LOAD requires a 13-bit column addres, putting 0 means it will save data in the page from 0th byte
                  end else begin
                    r_Command         <= BLOCK_ERASE;
                    r_Command_prev    <= BLOCK_ERASE;
                    r_Addr_Data[23:0] <= {13'b0, PAGE_ADDRESS[16:6]}; // Get only the block address (bits 16-6), the rest are dummy bits (0s)
                  end
                  r_Master_CM_DV    <= 1'b1;  // Issues a data valid pulse (should be 1 clock cycle)
                  r_SEND_sm         <= SEND_CHECK;
                  r_check_twice     <= 2'b0;  // Reset logic to issue get feature command twice
                end
              end
            endcase
          end
        end 
      endcase
    end
  end

endmodule