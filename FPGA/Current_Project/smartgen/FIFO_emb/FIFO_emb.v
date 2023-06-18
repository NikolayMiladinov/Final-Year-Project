`timescale 1 ns/100 ps
// Version: v11.9 SP6 11.9.6.7


module FIFO_emb(
       DATA,
       Q,
       WE,
       RE,
       WCLOCK,
       RCLOCK,
       FULL,
       EMPTY,
       RESET
    );
input  [7:0] DATA;
output [7:0] Q;
input  WE;
input  RE;
input  WCLOCK;
input  RCLOCK;
output FULL;
output EMPTY;
input  RESET;

    wire WEBP, WRITE_FSTOP_ENABLE, WRITE_ENABLE_I, READ_ESTOP_ENABLE, 
        READ_ENABLE_I, \FULLX_I[0] , \EMPTYX_I[0] , \FULLX_I[1] , 
        \EMPTYX_I[1] , \FULLX_I[2] , \EMPTYX_I[2] , \FULLX_I[3] , 
        \EMPTYX_I[3] , \FULLX_I[4] , \EMPTYX_I[4] , \FULLX_I[5] , 
        \EMPTYX_I[5] , \FULLX_I[6] , \EMPTYX_I[6] , \FULLX_I[7] , 
        \EMPTYX_I[7] , OR2_9_Y, OR2_2_Y, OR2_0_Y, OR2_5_Y, OR2_11_Y, 
        OR2_1_Y, OR2_10_Y, OR2_7_Y, OR2_8_Y, OR2_6_Y, OR2_4_Y, OR2_3_Y, 
        VCC, GND;
    wire GND_power_net1;
    wire VCC_power_net1;
    assign GND = GND_power_net1;
    assign VCC = VCC_power_net1;
    
    OR2 OR2_EMPTY (.A(OR2_9_Y), .B(OR2_2_Y), .Y(EMPTY));
    FIFO4K18 \FIFOBLOCK[4]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[4]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[4]), .FULL(
        \FULLX_I[4] ), .AFULL(), .EMPTY(\EMPTYX_I[4] ), .AEMPTY());
    FIFO4K18 \FIFOBLOCK[5]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[5]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[5]), .FULL(
        \FULLX_I[5] ), .AFULL(), .EMPTY(\EMPTYX_I[5] ), .AEMPTY());
    NAND2A WRITE_AND (.A(WEBP), .B(WRITE_FSTOP_ENABLE), .Y(
        WRITE_ENABLE_I));
    OR2 OR2_FULL (.A(OR2_10_Y), .B(OR2_7_Y), .Y(FULL));
    OR2 OR2_5 (.A(\EMPTYX_I[2] ), .B(\EMPTYX_I[3] ), .Y(OR2_5_Y));
    OR2 OR2_3 (.A(\FULLX_I[6] ), .B(\FULLX_I[7] ), .Y(OR2_3_Y));
    FIFO4K18 \FIFOBLOCK[2]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[2]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[2]), .FULL(
        \FULLX_I[2] ), .AFULL(), .EMPTY(\EMPTYX_I[2] ), .AEMPTY());
    OR2 OR2_4 (.A(\FULLX_I[4] ), .B(\FULLX_I[5] ), .Y(OR2_4_Y));
    NAND2 READ_ESTOP_GATE (.A(EMPTY), .B(VCC), .Y(READ_ESTOP_ENABLE));
    OR2 OR2_9 (.A(OR2_0_Y), .B(OR2_5_Y), .Y(OR2_9_Y));
    OR2 OR2_6 (.A(\FULLX_I[2] ), .B(\FULLX_I[3] ), .Y(OR2_6_Y));
    NAND2 WRITE_FSTOP_GATE (.A(FULL), .B(VCC), .Y(WRITE_FSTOP_ENABLE));
    OR2 OR2_1 (.A(\EMPTYX_I[6] ), .B(\EMPTYX_I[7] ), .Y(OR2_1_Y));
    OR2 OR2_8 (.A(\FULLX_I[0] ), .B(\FULLX_I[1] ), .Y(OR2_8_Y));
    OR2 OR2_7 (.A(OR2_4_Y), .B(OR2_3_Y), .Y(OR2_7_Y));
    FIFO4K18 \FIFOBLOCK[7]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[7]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[7]), .FULL(
        \FULLX_I[7] ), .AFULL(), .EMPTY(\EMPTYX_I[7] ), .AEMPTY());
    AND2 READ_AND (.A(RE), .B(READ_ESTOP_ENABLE), .Y(READ_ENABLE_I));
    OR2 OR2_10 (.A(OR2_8_Y), .B(OR2_6_Y), .Y(OR2_10_Y));
    FIFO4K18 \FIFOBLOCK[0]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[0]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[0]), .FULL(
        \FULLX_I[0] ), .AFULL(), .EMPTY(\EMPTYX_I[0] ), .AEMPTY());
    FIFO4K18 \FIFOBLOCK[3]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[3]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[3]), .FULL(
        \FULLX_I[3] ), .AFULL(), .EMPTY(\EMPTYX_I[3] ), .AEMPTY());
    FIFO4K18 \FIFOBLOCK[6]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[6]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[6]), .FULL(
        \FULLX_I[6] ), .AFULL(), .EMPTY(\EMPTYX_I[6] ), .AEMPTY());
    OR2 OR2_2 (.A(OR2_11_Y), .B(OR2_1_Y), .Y(OR2_2_Y));
    FIFO4K18 \FIFOBLOCK[1]  (.AEVAL11(GND), .AEVAL10(GND), .AEVAL9(GND)
        , .AEVAL8(GND), .AEVAL7(GND), .AEVAL6(GND), .AEVAL5(GND), 
        .AEVAL4(GND), .AEVAL3(GND), .AEVAL2(GND), .AEVAL1(GND), 
        .AEVAL0(GND), .AFVAL11(GND), .AFVAL10(GND), .AFVAL9(GND), 
        .AFVAL8(GND), .AFVAL7(GND), .AFVAL6(GND), .AFVAL5(GND), 
        .AFVAL4(GND), .AFVAL3(GND), .AFVAL2(GND), .AFVAL1(GND), 
        .AFVAL0(GND), .WD17(GND), .WD16(GND), .WD15(GND), .WD14(GND), 
        .WD13(GND), .WD12(GND), .WD11(GND), .WD10(GND), .WD9(GND), 
        .WD8(GND), .WD7(GND), .WD6(GND), .WD5(GND), .WD4(GND), .WD3(
        GND), .WD2(GND), .WD1(GND), .WD0(DATA[1]), .WW0(GND), .WW1(GND)
        , .WW2(GND), .RW0(GND), .RW1(GND), .RW2(GND), .RPIPE(VCC), 
        .WEN(WRITE_ENABLE_I), .REN(READ_ENABLE_I), .WBLK(GND), .RBLK(
        GND), .WCLK(WCLOCK), .RCLK(RCLOCK), .RESET(RESET), .ESTOP(VCC), 
        .FSTOP(VCC), .RD17(), .RD16(), .RD15(), .RD14(), .RD13(), 
        .RD12(), .RD11(), .RD10(), .RD9(), .RD8(), .RD7(), .RD6(), 
        .RD5(), .RD4(), .RD3(), .RD2(), .RD1(), .RD0(Q[1]), .FULL(
        \FULLX_I[1] ), .AFULL(), .EMPTY(\EMPTYX_I[1] ), .AEMPTY());
    OR2 OR2_0 (.A(\EMPTYX_I[0] ), .B(\EMPTYX_I[1] ), .Y(OR2_0_Y));
    OR2 OR2_11 (.A(\EMPTYX_I[4] ), .B(\EMPTYX_I[5] ), .Y(OR2_11_Y));
    INV WEBUBBLEA (.A(WE), .Y(WEBP));
    GND GND_power_inst1 (.Y(GND_power_net1));
    VCC VCC_power_inst1 (.Y(VCC_power_net1));
    
endmodule

// _Disclaimer: Please leave the following comments in the file, they are for internal purposes only._


// _GEN_File_Contents_

// Version:11.9.6.7
// ACTGENU_CALL:1
// BATCH:T
// FAM:PA3LCLP
// OUTFORMAT:Verilog
// LPMTYPE:LPM_FIFO
// LPM_HINT:NONE
// INSERT_PAD:NO
// INSERT_IOREG:NO
// GEN_BHV_VHDL_VAL:F
// GEN_BHV_VERILOG_VAL:F
// MGNTIMER:F
// MGNCMPL:T
// DESDIR:C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project/smartgen\FIFO_emb
// GEN_BEHV_MODULE:F
// SMARTGEN_DIE:UM4X4M1NLPLV
// SMARTGEN_PACKAGE:vq100
// AGENIII_IS_SUBPROJECT_LIBERO:T
// WWIDTH:8
// RWIDTH:8
// WDEPTH:4096
// RDEPTH:4096
// WE_POLARITY:1
// RE_POLARITY:1
// RCLK_EDGE:RISE
// WCLK_EDGE:RISE
// PMODE1:1
// FLAGS:NOFLAGS
// AFVAL:2
// AEVAL:1
// ESTOP:NO
// FSTOP:NO
// DATA_IN_PN:DATA
// DATA_OUT_PN:Q
// WE_PN:WE
// RE_PN:RE
// WCLOCK_PN:WCLOCK
// RCLOCK_PN:RCLOCK
// ACLR_PN:RESET
// FF_PN:FULL
// EF_PN:EMPTY
// AF_PN:AFULL
// AE_PN:AEMPTY
// AF_PORT_PN:AFVAL
// AE_PORT_PN:AEVAL
// RESET_POLARITY:0

// _End_Comments_

