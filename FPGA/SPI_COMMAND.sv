typedef enum logic[7:0] { 
    RESET = 'hFF, GET_FEATURE = 'h0F, SET_FEATURE = 'h1F,
    READ_ID = 'h9F, PAGE_READ = 'h13, CACHE_READ = 'h30,
    CACHE_LAST = 'h3F, CACHE_1 = 'h03, CACHE_2 = 'h3B,
    CACHE_4 = 'h6B, CACHE_DUAL = 'hBB, CACHE_QUAD = 'hEB,
    WRITE_ENABLE = 'h06, WRITE_DISABLE = 'h04, BLOCK_ERASE = 'hD8,
    PROG_EXEC = 'h10, PROG_LOAD1 = 'h02, PROG_LOAD2 = 'hA2,
    PROG_LOAD2_RAND = 'h44, PROG_LOAD4 = 'h32, PROG_LOAD1_RAND = 'h84,
    PROG_LOAD4_RAND = 'h34, PROTECT = 'h2C    
    } SPI_COMMAND;

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

parameter MAX_BYTES_PER_CS = 5000;
parameter MAX_WAIT_TIME = 1000;

// command, num_bytes, save_miso, miso_byte_num, wait_time

typedef struct {
    SPI_COMMAND command;
    logic [$clog2(MAX_BYTES_PER_CS+1)-1:0] num_bytes;
    logic save_miso;
    logic miso_byte_num;
    logic [$clog2(MAX_WAIT_TIME+1)-1:0] wait_time;
} my_command_t;