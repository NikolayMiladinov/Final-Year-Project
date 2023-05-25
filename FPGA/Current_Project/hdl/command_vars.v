parameter SIM_TEST = 0;


localparam [7:0]  RESET             = 8'hFF;
localparam [7:0]  GET_FEATURE       = 8'h0F;
localparam [7:0]  SET_FEATURE       = 8'h1F;
localparam [7:0]  READ_ID           = 8'h9F;
localparam [7:0]  PAGE_READ         = 8'h13;
localparam [7:0]  CACHE_REQ_PAGE    = 8'h30;
localparam [7:0]  CACHE_LAST        = 8'h3F;
localparam [7:0]  CACHE_READ        = 8'h03;
localparam [7:0]  CACHE_2           = 8'h3B;
localparam [7:0]  CACHE_4           = 8'h6B;
localparam [7:0]  CACHE_DUAL        = 8'hBB;
localparam [7:0]  CACHE_QUAD        = 8'hEB;
localparam [7:0]  WRITE_ENABLE      = 8'h06;
localparam [7:0]  WRITE_DISABLE     = 8'h04;
localparam [7:0]  BLOCK_ERASE       = 8'hD8;
localparam [7:0]  PROG_EXEC         = 8'h10;
localparam [7:0]  PROG_LOAD1        = 8'h02;
localparam [7:0]  PROG_LOAD2        = 8'hA2;
localparam [7:0]  PROG_LOAD2_RAND   = 8'h44;
localparam [7:0]  PROG_LOAD4        = 8'h32;
localparam [7:0]  PROG_LOAD1_RAND   = 8'h84;
localparam [7:0]  PROG_LOAD4_RAND   = 8'h34;
localparam [7:0]  PROTECT           = 8'h2C;
localparam [7:0]  NO_COMMAND        = 8'h0;

localparam FIFO_IDLE            = 3'b000;
localparam FIFO_UART_RECEIVE    = 3'b001;
localparam FIFO_UART_SEND       = 3'b010;
localparam FIFO_MEM_SEND        = 3'b011;
localparam FIFO_MEM_RECEIVE     = 3'b100;
localparam FIFO_COMPRESS        = 3'b101;
localparam FIFO_WAIT_MEM_PWRUP  = 3'b110;

// Timings:
// Power-up: Chip selection not allowed until Vcc_min = 1.7V is reached
// Read time: 25us(no ECC), 90us(typ, ECC), 178us(max, ECC)
// Program page: 200us(typ, no ECC), 240us(typ, ECC), 600us(max)
// Read cache random, RCBSY: 5us(no ECC), 90us(typ, ECC), 170us(max, ECC)
// Power-on reset time: 2ms
// Reset time for read, prog & erase operation: 30/35/525us (no ECC), 140/145/635us(ECC, CONTI_RD)
// CS non-active hold time: 3ns
// CS active setup time (after CS goes low, time before 1st posedge of SCK): 4.5ns
// Command deselect time (time between posedge and negedge of CS): 50ns

// typedef enum logic [7:0] { 
//     RESET = 8'hFF, GET_FEATURE = 8'h0F, SET_FEATURE = 8'h1F,
//     READ_ID = 8'h9F, PAGE_READ = 8'h13, CACHE_REQ_PAGE = 8'h30,
//     CACHE_LAST = 8'h3F, CACHE_READ = 8'h03, CACHE_2 = 8'h3B,
//     CACHE_4 = 8'h6B, CACHE_DUAL = 8'hBB, CACHE_QUAD = 8'hEB,
//     WRITE_ENABLE = 8'h06, WRITE_DISABLE = 8'h04, BLOCK_ERASE = 8'hD8,
//     PROG_EXEC = 8'h10, PROG_LOAD1 = 8'h02, PROG_LOAD2 = 8'hA2,
//     PROG_LOAD2_RAND = 8'h44, PROG_LOAD4 = 8'h32, PROG_LOAD1_RAND = 8'h84,
//     PROG_LOAD4_RAND = 8'h34, PROTECT = 8'h2C, NO_COMMAND = 8'h0   
// } SPI_Command;