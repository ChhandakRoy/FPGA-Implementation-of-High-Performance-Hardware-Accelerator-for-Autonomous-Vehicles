`timescale 1ns / 1ps 
  
module CTP 
#(
parameter width                     =8,                          // Pixel size
parameter M                         =128,                         //Length of Image
parameter N                         =64,                         //Width of Image
parameter C                         =64,                         //Input Channels
parameter FW                        =8                           //Fractional Width
)
(
input clk,reset,
output reg STAGE1,STAGE2,STAGE3,STAGE4,
output reg [7:0]S4_CHANNEL_STATUS
);

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  S T A G E   1  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


//`````````````````````````````````````````````````````````````` LOCAL PARAMETERS ````````````````````````````````````````````````````````````````````````//

localparam max_knl_addr_pw           =C*(C>>2)-1;                                   //Last address of last kernel of PW row in Bram2
localparam Addr_update_latency_pw    =((N+63)>>6)-1;                                //determines the no. of cycle after which BRAM address must be updated
localparam m                         =M<<1;                                         // BRAM1 address updation
localparam PW_BARM1_ADDR_BITS        =logb2(M*2*C);
localparam PW_BARM3_ADDR_BITS        =logb2((M*C)>>2);
localparam PW_BARM2_KNL_ADDR_BITS    =logb2(max_knl_addr_pw + 1);                   //Address bits of BRAM2 
localparam latency2                  =((N+63)>>6);                                  //Latency after which address must be updated after one set of row address is finished
localparam Cby2                      =C>>1;
localparam NCby64                    =(N*C)>>6;
localparam T1_MAX                    =(N <= 64) ? (C >> 1) : ((latency2*C) >> 1  ); // No of cycles required to produce one row in PW CONV
localparam cycle_pw                  =(N+63)>>6;
localparam MAX_ADDR_BRAM3            =M*(C>>2)-1;
localparam LAST_ADDR_OF_ROW_ARRIVAL  =T1_MAX-cycle_pw-5;
localparam PW_ACCUM_W = 2*width + logb2(C) + 1;  
localparam signed [width-1:0] MAX = (1 <<< (width-1)) - 1;      // MAXIMUM value in case of overflow
localparam signed [width-1:0] MIN = -(1 <<< (width-1));        // MINIMUM value in case of overflow
//````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````//

reg PW_ACTIVE_STATUS;

(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul1 [N-1:0];
(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul2 [N-1:0];
 reg signed [width-1:0]              pixa [N-1:0];
 reg signed [width-1:0]              pixb [N-1:0];
 reg signed [width-1:0]              knl_pw1 [1:0];
 reg signed [PW_ACCUM_W-1:0]         load_pw1 [N-1:0];
 reg [8:0]                           i1,i2,k1,k2;
 reg [7:0]                           pw_op_row_status;           // keeps count of the no of pw output rows that has been completed, max=256 rows
 reg [7:0]                           pw_op_channel_status;       // keeps count of the no of pw output channels that has been completed, max=256 channels
 reg [15:0]                          pw_knl_addr1;                // produces addresses of BRAM2 and loads appropriate kernel values
 reg [3:0]                           count_up1;
//````````````````````````````````````````````````````````````````````````` BRAM INSTANTIATION ``````````````````````````````````````````````````````````````````````````````````````````
//---------------------------------------------------------- BRAM1 : For storing Input image matrix for PWConv ----------------------------------------------------------------------
reg [PW_BARM1_ADDR_BITS-1:0] addr1a,addr1b;
reg [N*width-1:0] data_in1a,data_in1b;
wire[N*width-1:0] data_out1a,data_out1b;
reg en1a,en1b,wen1a,wen1b;

blk_mem_gen_0 BRAM1_pix_pw (.clka(clk), .ena(en1a), .wea(wen1a), .addra(addr1a), .dina(data_in1a), .douta(data_out1a), .clkb(clk), .enb(en1b), .web(wen1b), .addrb(addr1b), .dinb(data_in1b), .doutb(data_out1b));

//-------------------------------------------------------- BRAM 2 : For storing Input Kernel values for PWConv ----------------------------------------------------------------------------
reg [PW_BARM2_KNL_ADDR_BITS-1:0] addr2a,addr2b;
wire signed [width-1:0] data_out2a,data_out2b;
reg en2a,en2b,wen2a,wen2b;

blk_mem_gen_1 BRAM2_knl_pw (.clka(clk), .ena(en2a), .wea(wen2a), .addra(addr2a), .dina({width{1'b0}}), .douta(data_out2a), .clkb(clk), .enb(en2b), .web(wen2b), .addrb(addr2b), .dinb({width{1'b0}}), .doutb(data_out2b));

//------------------------------------------------------- BRAM 3x & BRAM 3y : For storing PWConv Output image matrix --------------------------------------------------------------------------------
reg [PW_BARM3_ADDR_BITS-1:0] addr3xa,addr3xb,addr3ya,addr3yb;
reg [N*width-1:0] data_in3xa,data_in3xb,data_in3ya,data_in3yb;
wire[N*width-1:0] data_out3xa,data_out3xb,data_out3ya,data_out3yb;
reg en3xa,en3xb,wen3xa,wen3xb,en3ya,en3yb,wen3ya,wen3yb;

 blk_mem_gen_2 BRAM3x_pw_output1 (.clka(clk), .ena(en3xa), .wea(wen3xa), .addra(addr3xa), .dina(data_in3xa), .douta(data_out3xa), .clkb(clk), .enb(en3xb), .web(wen3xb), .addrb(addr3xb), .dinb(data_in3xb), .doutb(data_out3xb));
 
 blk_mem_gen_2 BRAM3y_pw_output2 (.clka(clk), .ena(en3ya), .wea(wen3ya), .addra(addr3ya), .dina(data_in3ya), .douta(data_out3ya), .clkb(clk), .enb(en3yb), .web(wen3yb), .addrb(addr3yb), .dinb(data_in3yb), .doutb(data_out3yb));
 
//----------------------------------------------------------- MODULE INSTANTAITION: LATENCY TRACKER ----------------------------------------------------------------------------
reg valid_in1,valid_in2,valid_in3,valid_in4,valid_in5;
wire valid_out1,valid_out2,valid_out3,valid_out4,valid_out5;

(* dont_touch = "true" *)Latency_tracker1 #(.LATENCY(Addr_update_latency_pw),.N(N)) lat1_bram_pw (.clk(clk),.rst(reset),.valid_in(valid_in1),.valid_out(valid_out1));   //For PW BRAM address updation

(* dont_touch = "true" *)Latency_tracker2 #(.LATENCY(2)) lat2_pix (.clk(clk),.rst(reset),.valid_in(valid_in3),.valid_out(valid_out3));

(* dont_touch = "true" *)Latency_tracker2 #(.LATENCY(3)) lat3_mul (.clk(clk),.rst(reset),.valid_in(valid_in4),.valid_out(valid_out4));

(* dont_touch = "true" *)Latency_tracker2 #(.LATENCY(4)) lat4_load_pw (.clk(clk),.rst(reset),.valid_in(valid_in5),.valid_out(valid_out5));

integer   n,x,y,z,w1,w2;
(* keep = "true" *) reg [7:0] t1_load_pw;
(* keep = "true" *) reg [7:0] next_row;       



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  S T A G E   2  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


//````````````````````````````````````````````````````````` S T A G E  2( BLOCK 1A ): GLOBAL AVERAGE POOLING ````````````````````````````````````````````````````````````````````````````````

// ------------------------------------------------------- LOCAL PARAMETERS -------------------------------------------------------------------------------
localparam cycle_gap= N >> 4;                                   // Determines how much cycle needed to complete accumulating one row of Pw conv.
localparam Total_pix = M*N;
localparam GAP_shift_coeff =logb2(M*N);                        // Final division coeffient
localparam OP_CHANNELS = C >> 2;
//------------------------------------------------------------------------------------------------------------------------------------------------
reg [width*N-1:0] load_GAP;                             // It will Load the cuurently calculate row of PW conv.
reg [7:0] count1_gap,j_gap;
reg valid_gap,start_gap,GAP_done;
integer i_gap;
 reg [8:0] row_accumulated_gap,channel_accumulated_gap;

 reg signed [width +logb2(Total_pix) : 0]Sum_GAP;                // Goes on Accumulating and storing all rows in a channel
 reg signed [width-1:0]GAP;                                      //For storing final accumulated result of a whole channel
 reg GAP_STATUS;
//-------------------------------------------- MODULE INSTANTIATIONS -----------------------------------------------------------------------------
reg En_AP1;
(* keep = "true" *)reg[16*width-1:0]Vector_AP1; (* keep = "true" *) wire signed [width+3:0] out_AP1;

(* dont_touch = "true" *) ADDER_16pix #(.PW(width)) AP1 (.clk(clk), .rst(reset), .en(En_AP1), .Vector(Vector_AP1), .out(out_AP1));   //Produce PW+4 bits output

reg valid_in_GAP; wire valid_out_GAP;

Latency_tracker2 #(.LATENCY(4)) lat6_dwr6_mac (.clk(clk),.rst(reset),.valid_in(valid_in_GAP),.valid_out(valid_out_GAP));   
     
//--------------------------------------------------------------------------------------------------------------------------------------------------


//`````````````````````````````````````````````````````````````````````````` STAGE 2(BLOCK 1B) : DEPTHWISE DILATED CONVOLUTION R=6 ```````````````````````````````````````````````

//----------------------------------------------------------------------- lOCAL PARAMETERS ------------------------------------------------------------------------------

localparam r1                       =6;
localparam r3                       =18;
localparam r4                       =36;
localparam r1b                      =12;

localparam r4b                      =72;
localparam kr1                      =13;                            // Kr for size of kernels for various r

localparam kr4                      =73;
//--------------- The MAX address of 6x for storing calculatd rows after (DW+ap)------------
localparam ROW_LOADER_COEFF_R1      =M-3*r1-1;

localparam ROW_LOADER_COEFF_R3      =M-3*r3-1;
localparam ROW_LOADER_COEFF_R4      =M-3*r4-1;
//-------------------------------------------------------------------------------------------
localparam WR_PTR_MAX_BLK_R1         =N-2*r1-4;


localparam WR_PTR_MAX_BLK_R4         =N-2*r4-4;
//-------------------------------------------------------------------------------------------
localparam MAX_CYC_DWR6             =((N-12)>>2)-1;                     // To keep a check of total cycles reqd to complete one row
localparam SHIFT_DWR6_COEFF         =4*width;                       // Determines how much unit the packed buffers must be shifted for convolving next set of 4 columns
localparam BRAM4_KNL_ADDR_BITS      = logb2((C>>1));
localparam BRAM5_BN_CONST_WIDTH     = 2*(width+FW);
localparam Const_Cby4               =(C>>2);
localparam addr3_r6_MAX             = M-1-r1;
//------------------------------------------------------------------------------------------------------------------------------------------------------------------------

 reg [width*N-1:0] Buffer1a,Buffer1b,Buffer1c ;                     // These are Paked Buffer araays for storing 3 dilated rows, accesing by shifting Right
 reg [width*N-1:0] Cache1a,Cache1b ;                               // These will hold 2 next set of rows to be laoded into buffers so that direct Bram fetching is avoided.
 reg [1:0] count1_dw1;
reg  Load_Buffer1,Load_Cache1,valid1_dw1,valid2_dw1,valid3_dw1,valid4_dw1,valid5_dw1,valid6_dw1,first_rep_write1;
integer x1,x2,x3;
reg Start_DW_r6;                                                // Signal to start DW conv r=6, after GAP comletes for one channel            

//-----------------------------------------------------------------------

reg  Enable_MAC1, REPLICATE_LAST_ROWS_BLK1,BLK1_STATUS;
reg  valid2_dwr6,first_write_dwr6,valid_next0_dw1,first_read_dwr6,first_read2_dw1;                                                       // For Loading DWR6 output in BRAM6
reg valid_next1_dw1,valid_next2_dw1,valid_next3_dw1,valid0_dw1,valid03_dw1;    // For Loading cache from BRAM3
 reg [7:0] max_cyc1,wr_ptr1,k3,k4,dwr6_op_row,dwr6_op_channel,count2_dw1;
 wire signed [width:0] SUM1,SUM2,SUM3,SUM4;
 wire signed [width-1:0] ACC1,ACC2,ACC3,ACC4;
 reg [PW_BARM3_ADDR_BITS-1:0] temp_addr1;      // For Storing previous value of addr3b while using it for laoding cache
reg LOAD_CACHE_FROM_BRAM1,SWAP_N_LOAD1,LOAD_BUFFER_FROM_Cache1,DWR6_STATUS;
integer x4,x5,x6,x7,x8;
reg [11:0] next_addr_dw1;

assign SUM1 = ACC1 + GAP;
assign SUM2 = ACC2 + GAP;
assign SUM3 = ACC3 + GAP;
assign SUM4 = ACC4 + GAP;

//----------------------------------------------------------------------- BRAM INSTNATIATION FOR DW R6 + R18 KERNELS AND BN CONSTANTS ------------------------------------------------------------

reg  [BRAM4_KNL_ADDR_BITS-1:0] addr4xa,addr5xa;
wire [9*width-1:0] data_out4xa;
wire [BRAM5_BN_CONST_WIDTH-1:0] data_out5xa;
reg  en4xa,wen4xa,en5xa,wen5xa;

// ``````````````````````````````````````````````````````````````````````` KERNEL'S BRAM4 ````````````````````````````````````````````````````````````````````````````````````````````````````````
blk_mem_gen_3 BRAM4x_dw_r6_r18_knl (.clka(clk), .ena(en4xa), .wea(wen4xa), .addra(addr4xa), .dina({9*width{1'b0}}), .douta(data_out4xa), .clkb(clk), .enb(1'b0), .web(1'b0), .addrb(0), .dinb({9*width{1'b0}}), .doutb());

//```````````````````````````````````````````````````````````````````````` BN CONSTANTS BRAM5 ````````````````````````````````````````````````````````````````````````````````````````````````````
blk_mem_gen_4 BRAM5x_dw_r6_r18_BN (.clka(clk), .ena(en5xa), .wea(wen5xa), .addra(addr5xa), .dina({BRAM5_BN_CONST_WIDTH{1'b0}}), .douta(data_out5xa), .clkb(clk), .enb(1'b0), .web(1'b0), .addrb(0), .dinb({BRAM5_BN_CONST_WIDTH{1'b0}}), .doutb());


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ MODULE INSTANTIATION ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC1 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC1), .A0(Buffer1a[width-1:0]), .A1(Buffer1a[7*width-1:6*width]), .A2(Buffer1a[13*width-1:12*width]), .A3(Buffer1b[width-1:0]), .A4(Buffer1b[7*width-1:6*width]), .A5(Buffer1b[13*width-1:12*width]), .A6(Buffer1c[width-1:0]), .A7(Buffer1c[7*width-1:6*width]), .A8(Buffer1c[13*width-1:12*width]), .K0(data_out4xa[9*width-1:8*width]), .K1(data_out4xa[8*width-1:7*width]), .K2(data_out4xa[7*width-1:6*width]), .K3(data_out4xa[6*width-1:5*width]), .K4(data_out4xa[5*width-1:4*width]), .K5(data_out4xa[4*width-1:3*width]), .K6(data_out4xa[3*width-1:2*width]), .K7(data_out4xa[2*width-1:width]), .K8(data_out4xa[width-1:0]), .A(data_out5xa[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5xa[width+FW-1:0]), .Result(ACC1));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC2 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC1), .A0(Buffer1a[2*width-1:width]), .A1(Buffer1a[8*width-1:7*width]), .A2(Buffer1a[14*width-1:13*width]), .A3(Buffer1b[2*width-1:width]), .A4(Buffer1b[8*width-1:7*width]), .A5(Buffer1b[14*width-1:13*width]), .A6(Buffer1c[2*width-1:width]), .A7(Buffer1c[8*width-1:7*width]), .A8(Buffer1c[14*width-1:13*width]), .K0(data_out4xa[9*width-1:8*width]), .K1(data_out4xa[8*width-1:7*width]), .K2(data_out4xa[7*width-1:6*width]), .K3(data_out4xa[6*width-1:5*width]), .K4(data_out4xa[5*width-1:4*width]), .K5(data_out4xa[4*width-1:3*width]), .K6(data_out4xa[3*width-1:2*width]), .K7(data_out4xa[2*width-1:width]), .K8(data_out4xa[width-1:0]), .A(data_out5xa[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5xa[width+FW-1:0]), .Result(ACC2));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC3 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC1), .A0(Buffer1a[3*width-1:2*width]), .A1(Buffer1a[9*width-1:8*width]), .A2(Buffer1a[15*width-1:14*width]), .A3(Buffer1b[3*width-1:2*width]), .A4(Buffer1b[9*width-1:8*width]), .A5(Buffer1b[15*width-1:14*width]), .A6(Buffer1c[3*width-1:2*width]), .A7(Buffer1c[9*width-1:8*width]), .A8(Buffer1c[15*width-1:14*width]), .K0(data_out4xa[9*width-1:8*width]), .K1(data_out4xa[8*width-1:7*width]), .K2(data_out4xa[7*width-1:6*width]), .K3(data_out4xa[6*width-1:5*width]), .K4(data_out4xa[5*width-1:4*width]), .K5(data_out4xa[4*width-1:3*width]), .K6(data_out4xa[3*width-1:2*width]), .K7(data_out4xa[2*width-1:width]), .K8(data_out4xa[width-1:0]), .A(data_out5xa[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5xa[width+FW-1:0]), .Result(ACC3));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC4 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC1), .A0(Buffer1a[4*width-1:3*width]), .A1(Buffer1a[10*width-1:9*width]), .A2(Buffer1a[16*width-1:15*width]), .A3(Buffer1b[4*width-1:3*width]), .A4(Buffer1b[10*width-1:9*width]), .A5(Buffer1b[16*width-1:15*width]), .A6(Buffer1c[4*width-1:3*width]), .A7(Buffer1c[10*width-1:9*width]), .A8(Buffer1c[16*width-1:15*width]), .K0(data_out4xa[9*width-1:8*width]), .K1(data_out4xa[8*width-1:7*width]), .K2(data_out4xa[7*width-1:6*width]), .K3(data_out4xa[6*width-1:5*width]), .K4(data_out4xa[5*width-1:4*width]), .K5(data_out4xa[4*width-1:3*width]), .K6(data_out4xa[3*width-1:2*width]), .K7(data_out4xa[2*width-1:width]), .K8(data_out4xa[width-1:0]), .A(data_out5xa[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5xa[width+FW-1:0]), .Result(ACC4));

reg valid_in1_dwr6;wire valid_out1_dwr6;

(* dont_touch = "true" *) Latency_tracker2 #(.LATENCY(7)) MAC_latency (.clk(clk),.rst(reset),.valid_in(valid_in1_dwr6),.valid_out(valid_out1_dwr6));              // MAC LATENCY -1

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////




//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ STAGE 2( BLOCK 2A) :AVERAGE POOLING 16X16 S=8 + DW R=12 CONV STARTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//------------------------------------------------------------ LOCAL PARAMETERS --------------------------------------------------------------------------

localparam PTR_MAX_AP16 = ((N-16)/8);
localparam AP16_WIDTH = (width+8)*(PTR_MAX_AP16+1) ;
localparam COL_AP16 = ((N-16)/8)+1;
localparam ROW_AP16 = ((M-16)/16)+1;
localparam AP16_BUFF_SHIFT = 16*width;

//--------------------------------------------------------------------------------------------------------------------------------------------------------
reg signed [width-1:0] MEM_AP16 [ROW_AP16-1:0] [COL_AP16-1:0];
reg [N*width-1:0] Vec_ap16;                 // Full row will be copied from Load_pw
reg [AP16_WIDTH-1:0] Load_AP16;
reg [6:0] ptr1,ptr2,ap16_row,ap16_channel;
reg [4:0] Win16;
reg Start_AP16,valid_in1_ap16,En_AP16,valid_AP16,Load_ap16_row,clip_ap16_pix,AP16_STATUS;
wire valid_out1_ap16;
wire signed [width+3:0] Add1,Add2;
integer j1,j2;

//------------------------------------------------------------------ MODULE INSTANTIATION -----------------------------------------------------------------

(* dont_touch = "true" *) ADDER_16pix #(.PW(width)) AP16_1 (.clk(clk), .rst(reset), .en(En_AP16), .Vector(Vec_ap16[16*width-1:0]), .out(Add1));   //Produce PW+4 bits output

(* dont_touch = "true" *) ADDER_16pix #(.PW(width)) AP16_2 (.clk(clk), .rst(reset), .en(En_AP16), .Vector(Vec_ap16[24*width-1:8*width]), .out(Add2));   //Produce PW+4 bits output

Latency_tracker2 #(.LATENCY(4)) Adder_latency (.clk(clk),.rst(reset),.valid_in(valid_in1_ap16),.valid_out(valid_out1_ap16));              

//------------------------------------------------------------------------------------------------------------------------------------------------------




//------------------------------------------------------------- S T A G E  2 ( BLOCK 2B ) : DEPTHWISE DILATED CONVOLUTION, R=12-----------------------------------------------------------------------------------

//------------------------------------------------------------- LAOCAL PARAMETERS --------------------------------------------------------------------------------------
localparam r2                       =12;
localparam r2b                      =24;
localparam kr2                      =25;
localparam ROW_LOADER_COEFF_R2      =M-3*r2-1;
localparam WR_PTR_MAX_BLK_R2         =N-2*r2-4;
localparam MAX_CYC_DWR12            =((N-24)>>2)-1;                     // To keep a check of total cycles reqd to complete one row
localparam SHIFT_DWR12_COEFF        =4*width;                       // Determines how much unit the packed buffers must be shifted for convolving next set of 4 columns
localparam addr3_r12_MAX            =M-1-r2;
// ----------------------------------------------------------------------------------------------------------------------------------------------------------------------


    
reg [width*N-1:0] Buffer2a,Buffer2b,Buffer2c ;                     // These are Paked Buffer araays for storing 3 dilated rows, accesing by shifting Right
reg [width*N-1:0] Cache2a,Cache2b ;                               // These will hold 2 next set of rows to be laoded into buffers so that direct Bram fetching is avoided.
reg [1:0] count1_dw2;
reg  Load_Buffer2,Load_Cache2,valid1_dw2,valid2_dw2,valid3_dw2,valid4_dw2,valid5_dw2,valid6_dw2;
integer y1,y2,y3,y4,y5,y6,y7,y8;

reg Start_DW_r12;                                                // Signal to start DW conv r=12, after PW comletes one channel            
//-----------------------------------------------------------------------

reg  Enable_MAC2, REPLICATE_LAST_ROWS_BLK2,BLK2_STATUS;
reg  valid2_DWR12,first_write_DWR12,valid_next0_dw2,first_read_DWR12,first_rep_write2;                     // For Loading DWR12 output in BRAM6

reg valid_next1_dw2,valid_next2_dw2,valid_next3_dw2,valid0_dw2,valid03_dw2;    // For Loading cache from BRAM3
reg [7:0] max_cyc2,wr_ptr2,l3,l4,DWR12_op_row,DWR12_op_channel,count2_dw2;

wire signed [width:0] SUM5,SUM6,SUM7,SUM8;
wire signed [width-1:0] ACC5,ACC6,ACC7,ACC8;

reg [PW_BARM3_ADDR_BITS-1:0] temp_addr2;      // For Storing previous value of addr3b while using it for laoding cache
reg LOAD_CACHE_FROM_BRAM2,SWAP_N_LOAD2,LOAD_BUFFER_FROM_Cache2,DWR12_STATUS;
reg [width-1:0] AP2A,AP2B,AP2C,AP2D;
reg [11:0]next_addr_dw2;

assign SUM5 = ACC5 + AP2A;
assign SUM6 = ACC6 + AP2B;
assign SUM7 = ACC7 + AP2C;
assign SUM8 = ACC8 + AP2D;

//----------------------------------------------------------------------- BRAM INSTNATIATION FOR DW R6 + R18 KERNELS AND BN CONSTANTS ------------------------------------------------------------

reg  [BRAM4_KNL_ADDR_BITS-1:0] addr4ya,addr5ya;
wire [9*width-1:0] data_out4ya;
wire [BRAM5_BN_CONST_WIDTH-1:0] data_out5ya;
reg  en4ya,wen4ya,en5ya,wen5ya;

// ``````````````````````````````````````````````````````````````````````` KERNEL'S BRAM4 ````````````````````````````````````````````````````````````````````````````````````````````````````````
blk_mem_gen_3 BRAM4y_dw_r12_r36_knl (.clka(clk), .ena(en4ya), .wea(wen4ya), .addra(addr4ya), .dina({9*width{1'b0}}), .douta(data_out4ya), .clkb(clk), .enb(1'b0), .web(1'b0), .addrb(0), .dinb({9*width{1'b0}}), .doutb());

//```````````````````````````````````````````````````````````````````````` BN CONSTANTS BRAM5 ````````````````````````````````````````````````````````````````````````````````````````````````````
blk_mem_gen_4 BRAM5y_dw_r12_r36_BN (.clka(clk), .ena(en5ya), .wea(wen5ya), .addra(addr5ya), .dina({BRAM5_BN_CONST_WIDTH{1'b0}}), .douta(data_out5ya), .clkb(clk), .enb(1'b0), .web(1'b0), .addrb(0), .dinb({BRAM5_BN_CONST_WIDTH{1'b0}}), .doutb());



//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ MODULE INSTANTIATION ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC5 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC2), .A0(Buffer2a[width-1:0]), .A1(Buffer2a[7*width-1:6*width]), .A2(Buffer2a[13*width-1:12*width]), .A3(Buffer2b[width-1:0]), .A4(Buffer2b[7*width-1:6*width]), .A5(Buffer2b[13*width-1:12*width]), .A6(Buffer2c[width-1:0]), .A7(Buffer2c[7*width-1:6*width]), .A8(Buffer2c[13*width-1:12*width]), .K0(data_out4ya[9*width-1:8*width]), .K1(data_out4ya[8*width-1:7*width]), .K2(data_out4ya[7*width-1:6*width]), .K3(data_out4ya[6*width-1:5*width]), .K4(data_out4ya[5*width-1:4*width]), .K5(data_out4ya[4*width-1:3*width]), .K6(data_out4ya[3*width-1:2*width]), .K7(data_out4ya[2*width-1:width]), .K8(data_out4ya[width-1:0]), .A(data_out5ya[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5ya[width+FW-1:0]), .Result(ACC5));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC6 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC2), .A0(Buffer2a[2*width-1:width]), .A1(Buffer2a[8*width-1:7*width]), .A2(Buffer2a[14*width-1:13*width]), .A3(Buffer2b[2*width-1:width]), .A4(Buffer2b[8*width-1:7*width]), .A5(Buffer2b[14*width-1:13*width]), .A6(Buffer2c[2*width-1:width]), .A7(Buffer2c[8*width-1:7*width]), .A8(Buffer2c[14*width-1:13*width]), .K0(data_out4ya[9*width-1:8*width]), .K1(data_out4ya[8*width-1:7*width]), .K2(data_out4ya[7*width-1:6*width]), .K3(data_out4ya[6*width-1:5*width]), .K4(data_out4ya[5*width-1:4*width]), .K5(data_out4ya[4*width-1:3*width]), .K6(data_out4ya[3*width-1:2*width]), .K7(data_out4ya[2*width-1:width]), .K8(data_out4ya[width-1:0]), .A(data_out5ya[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5ya[width+FW-1:0]), .Result(ACC6));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC7 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC2), .A0(Buffer2a[3*width-1:2*width]), .A1(Buffer2a[9*width-1:8*width]), .A2(Buffer2a[15*width-1:14*width]), .A3(Buffer2b[3*width-1:2*width]), .A4(Buffer2b[9*width-1:8*width]), .A5(Buffer2b[15*width-1:14*width]), .A6(Buffer2c[3*width-1:2*width]), .A7(Buffer2c[9*width-1:8*width]), .A8(Buffer2c[15*width-1:14*width]), .K0(data_out4ya[9*width-1:8*width]), .K1(data_out4ya[8*width-1:7*width]), .K2(data_out4ya[7*width-1:6*width]), .K3(data_out4ya[6*width-1:5*width]), .K4(data_out4ya[5*width-1:4*width]), .K5(data_out4ya[4*width-1:3*width]), .K6(data_out4ya[3*width-1:2*width]), .K7(data_out4ya[2*width-1:width]), .K8(data_out4ya[width-1:0]), .A(data_out5ya[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5ya[width+FW-1:0]), .Result(ACC7));

(* dont_touch = "true" *) Hybrid_MAC #(.PW(width),.FW(FW)) Hybrid_MAC8 (.clk(clk), .reset(reset), .Enable_MAC(Enable_MAC2), .A0(Buffer2a[4*width-1:3*width]), .A1(Buffer2a[10*width-1:9*width]), .A2(Buffer2a[16*width-1:15*width]), .A3(Buffer2b[4*width-1:3*width]), .A4(Buffer2b[10*width-1:9*width]), .A5(Buffer2b[16*width-1:15*width]), .A6(Buffer2c[4*width-1:3*width]), .A7(Buffer2c[10*width-1:9*width]), .A8(Buffer2c[16*width-1:15*width]), .K0(data_out4ya[9*width-1:8*width]), .K1(data_out4ya[8*width-1:7*width]), .K2(data_out4ya[7*width-1:6*width]), .K3(data_out4ya[6*width-1:5*width]), .K4(data_out4ya[5*width-1:4*width]), .K5(data_out4ya[4*width-1:3*width]), .K6(data_out4ya[3*width-1:2*width]), .K7(data_out4ya[2*width-1:width]), .K8(data_out4ya[width-1:0]), .A(data_out5ya[BRAM5_BN_CONST_WIDTH-1:width+FW]), .B(data_out5ya[width+FW-1:0]), .Result(ACC8));

reg valid_in1_DWR12; wire valid_out1_DWR12;

(* dont_touch = "true" *) Latency_tracker2 #(.LATENCY(7)) MAC_latency2 (.clk(clk),.rst(reset),.valid_in(valid_in1_DWR12),.valid_out(valid_out1_DWR12));              // MAC LATENCY -1

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

localparam S2_B1_LOAD_START_ADDR =M*C;
localparam S2_B2_LOAD_START_ADDR =5*M*C/4;
localparam S2_B1_LOAD_LAST_ADDR =(5*M*C/4);
localparam S2_B2_LOAD_LAST_ADDR =(6*M*C/4)-1;
reg STAGE2_STATUS, valid_load, START_LOAD_BRAM1,first_load;


//------------------------------------------------------------------------ S T A G E  3   ----------------------------------------------------------------------------------------------------------------------------
localparam WR_PTR_MAX_BLK_R3         =N-2*r3-4;
localparam r3b                       =36;
localparam kr3                       =37;
localparam addr3_r18_MAX             = M-1-r3;
localparam MAX_CYC_DWR18             =((N-36)>>2)-1;

reg  START_STAGE3, Start_Dwr18,first_read_dwr18, first_write_dwr18,Load_knl_dwr18,Bram1_loaded, STAGE3_STATUS;
reg [8:0] dwr18_op_channel, dwr18_op_row; 
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ S T A G E  4 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

localparam T2_MAX                    =(N <= 64) ? (C) : (latency2*C); // No of cycles required to produce one row in PW(1/2) CONV
localparam PW_BARM7_ADDR_BITS        =logb2((2*C*C));                // Depth of bram7 (knl of pw 1/2) is C*C/2
localparam max_knl_addr_pw1          =C*(C>>1)-1;
localparam max_knl_addr_pw2          =C*C -1;
localparam max_knl_addr_pw3          =3*C*(C>>1)-1;
localparam max_knl_addr_pw4          =2*C*C-1;
localparam LAST_ADDR_OF_ROW_ARRIVAL2 =T2_MAX-cycle_pw-5;
localparam pw_knl_init1              =2*C-1;
localparam pw_knl_init2              =C*(C>>1) + 2*C -1;
localparam pw_knl_init3              =C*C + 2*C -1;
localparam pw_knl_init4              =3*C*(C>>1)+ 2*C -1;
localparam Const_2C                  =2*C;

(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul3 [N-1:0];
(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul4 [N-1:0];

reg signed [width-1:0]                                  knl_pw2 [1:0];
reg signed [PW_ACCUM_W-1:0]                             load_pw2 [N-1:0];
reg [15:0]                                              pw_knl_addr2;         

reg signed [2*width-1:0]                                mul5 [N-1:0];
reg signed [2*width-1:0]                                mul6 [N-1:0];
reg signed [width-1:0]                                  knl_pw3 [1:0];
reg signed [PW_ACCUM_W-1:0]                             load_pw3 [N-1:0];
reg [15:0]                                              pw_knl_addr3;                

(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul7 [N-1:0];
(* use_dsp = "yes" *) reg signed [2*width-1:0]          mul8 [N-1:0];
reg signed [width-1:0]                                  knl_pw4 [1:0];
    reg signed [PW_ACCUM_W-1:0]                         load_pw4 [N-1:0];
reg [15:0]                                              pw_knl_addr4;                
       



(* keep = "true" *) reg [8:0] t2_load_pw;
reg START_STAGE4,STAGE4_STATUS;

//-------------------------------------------------------- BRAM 7 : For storing Input Kernel values for PWConv ----------------------------------------------------------------------------

reg [PW_BARM7_ADDR_BITS-1:0] addr7wa,addr7wb,addr7xa,addr7xb,addr7ya,addr7yb,addr7za,addr7zb;
wire signed [width-1:0] data_out7wa,data_out7wb,data_out7xa,data_out7xb,data_out7ya,data_out7yb,data_out7za,data_out7zb;
reg en7wa,en7wb,wen7wa,wen7wb,en7xa,en7xb,wen7xa,wen7xb,en7ya,en7yb,wen7ya,wen7yb,en7za,en7zb,wen7za,wen7zb;

blk_mem_gen_5 BRAM7w_pw2_knl (.clka(clk), .ena(en7wa), .wea(wen7wa), .addra(addr7wa), .dina(data_in7wa), .douta(data_out7wa), .clkb(clk), .enb(en7wb), .web(wen7wb), .addrb(addr7wb), .dinb(data_in7wb), .doutb(data_out7wb));
blk_mem_gen_5 BRAM7x_pw2_knl (.clka(clk), .ena(en7xa), .wea(wen7xa), .addra(addr7xa), .dina(data_in7xa), .douta(data_out7xa), .clkb(clk), .enb(en7xb), .web(wen7xb), .addrb(addr7xb), .dinb(data_in7xb), .doutb(data_out7xb));
blk_mem_gen_5 BRAM7y_pw2_knl (.clka(clk), .ena(en7ya), .wea(wen7ya), .addra(addr7ya), .dina(data_in7ya), .douta(data_out7ya), .clkb(clk), .enb(en7yb), .web(wen7yb), .addrb(addr7yb), .dinb(data_in7yb), .doutb(data_out7yb));
blk_mem_gen_5 BRAM7z_pw2_knl (.clka(clk), .ena(en7za), .wea(wen7za), .addra(addr7za), .dina(data_in7za), .douta(data_out7za), .clkb(clk), .enb(en7zb), .web(wen7zb), .addrb(addr7zb), .dinb(data_in7zb), .doutb(data_out7zb));


//----------------------------------------------------------------------- BRAM INSTNATIATION FOR STORING OUTPUT OF BLOCK 2(DW=R12 + AP16X16) + BLOCK4 (DW_R36+AP4X4)  -------------------------------------------------------------------

reg  [PW_BARM3_ADDR_BITS-1:0] addr6ya,addr6yb;
reg  [N*width-1:0] data_in6ya,data_in6yb;
wire [N*width-1:0] data_out6ya,data_out6yb;
reg  en6ya,en6yb,wen6ya,wen6yb;

 blk_mem_gen_2 BRAM6y_DW2_output (.clka(clk), .ena(en6ya), .wea(wen6ya), .addra(addr6ya), .dina(data_in6ya), .douta(data_out6ya), .clkb(clk), .enb(en6yb), .web(wen6yb), .addrb(addr6yb), .dinb(data_in6yb), .doutb(data_out6yb));

//----------------------------------------------------------------------- BRAM INSTNATIATION FOR STORING OUTPUT OF BLOCK 1(DwR=6+GAP) + BLOCK 4(DwR=18 + AP8X8)  ----------------------------------------------------------

reg  [PW_BARM3_ADDR_BITS-1:0] addr6xa,addr6xb;
reg  [N*width-1:0] data_in6xa,data_in6xb;
wire [N*width-1:0] data_out6xa,data_out6xb;
reg  en6xa,en6xb,wen6xa,wen6xb;

 blk_mem_gen_2 BRAM6x_DW1_output (.clka(clk), .ena(en6xa), .wea(wen6xa), .addra(addr6xa), .dina(data_in6xa), .douta(data_out6xa), .clkb(clk), .enb(en6xb), .web(wen6xb), .addrb(addr6xb), .dinb(data_in6xb), .doutb(data_out6xb));

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ S T A G E  1 : POINTWISE CONVOLUTION (1/4) ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 
 //------------------------- For FPGA ------------------------------------------------------------------------------
 always @(posedge clk)
 begin
    if(reset)
    begin
        STAGE1<=1'b0;STAGE2<=1'b0;STAGE3<=1'b0;STAGE4=1'b0;
        
    end
    else
    begin
        STAGE1<=PW_ACTIVE_STATUS;
        STAGE2<=DWR6_STATUS;
        STAGE3<=START_STAGE4;
        STAGE4<=STAGE4_STATUS;
    end
 end
 
 
 //------------------------------------------------------------------------------------------------------------------
 
always @(posedge clk)
begin    
    if(reset)
    begin        
        //              Status / Control Register               //
        pw_op_row_status<=8'b0;
        pw_op_channel_status<=8'b0;
        pw_knl_addr1<= C-1;
        PW_ACTIVE_STATUS<=1'b0;
        START_STAGE4<=1'b0;
        S4_CHANNEL_STATUS<=1'b0;
        valid_in1<=1'b1; 
        valid_in3<=1'b1;valid_in4<=1'b1;valid_in5<=1'b1;   // To maintain initial PIPELINE Latency (triggered only once at the start)
        next_row<=1'b0;
        i1<=0; i2<=0; k1<=0; k2<=0;
        t1_load_pw<=0;
        count_up1<=1'b0;
      //*******Initialize pw load,mul1,2,knl reg with zeros********//
        for (n = 0; n < N; n = n + 1)
        begin
            load_pw1[n] <= {PW_ACCUM_W{1'b0}}; mul1[n] <= {2*width{1'b0}}; mul2[n] <= {2*width{1'b0}};  pixa[n] <= {width{1'b0}};  pixb[n] <= {width{1'b0}};    
        end
        knl_pw1[0]<={width{1'b0}}; knl_pw1[1]<={width{1'b0}};
           
     //***********BRAM 1 for PW pixels**********//   
        en1a<=1'b1;wen1a<=1'b0; addr1a<=0;
        en1b<=1'b1;wen1b<=1'b0; addr1b<=M;
               
      //**********BRAM 2 for PW kernels********//  
        en2a<=1'b1; wen2a<=1'b0; addr2a<=0;
        en2b<=1'b1; wen2b<=1'b0; addr2b<=1; 
        
      //********** BRAM 3 for Pw output *******//
        en3xa<=1'b0; wen3xa<=1'b0; addr3xa<=-1; en3xb<=1'b0; wen3xb<=0;
        en3ya<=1'b0; wen3ya<=1'b0; addr3ya<=-1; en3yb<=1'b0; wen3yb<=0;
        
        //----------------------------------------
        STAGE3_STATUS<=1'b0;
    //-------------------------------- stage 4-----------------------------------------
        pw_knl_addr2<= pw_knl_init2; pw_knl_addr3<= pw_knl_init3; pw_knl_addr4<= pw_knl_init4;
        for (n = 0; n < N; n = n + 1)
        begin
            load_pw2[n] <= {PW_ACCUM_W{1'b0}}; mul3[n] <= {2*width{1'b0}}; mul4[n] <= {2*width{1'b0}}; 
            load_pw3[n] <= {PW_ACCUM_W{1'b0}}; mul5[n] <= {2*width{1'b0}}; mul6[n] <= {2*width{1'b0}};  
            load_pw4[n] <= {PW_ACCUM_W{1'b0}}; mul7[n] <= {2*width{1'b0}}; mul8[n] <= {2*width{1'b0}}; 
        end
        knl_pw2[0]<={width{1'b0}}; knl_pw2[1]<={width{1'b0}}; knl_pw3[0]<={width{1'b0}}; knl_pw3[1]<={width{1'b0}}; knl_pw4[0]<={width{1'b0}}; knl_pw4[1]<={width{1'b0}};
         STAGE4_STATUS<=1'b0;
         t2_load_pw<=0;
    //--------------------------------------------------------------------------------         
    end
    else if(!PW_ACTIVE_STATUS)
    begin
        if( (t1_load_pw==LAST_ADDR_OF_ROW_ARRIVAL) && (N>64))
        valid_in1<=1'b0;
        
        if(!valid_in1)
        begin
            if(count_up1 < cycle_pw)
            begin
                count_up1<=count_up1 + 1; 
            end
            else
            begin
                valid_in1<=1'b1;
                count_up1<=1'b0;
            end
        end
                
//-------------------------------------------------------------- PART 1: PW CONVOLUTION BRAM Address Updation Logic ---------------------------------------------------------------
    
        if(pw_knl_addr1 <= max_knl_addr_pw )
        begin
            if(valid_out1)
            begin
                if(pw_op_row_status <= M-1)
                begin
                    if(addr2b < pw_knl_addr1)
                    begin
                        addr1a<=addr1a + m ; addr1b<=addr1b + m ; addr2a<=addr2a + 2; addr2b<=addr2b + 2;
                    end          
                end
                             
                end
                if(t1_load_pw==T1_MAX-4)
                begin            ///////////////    Row Completion   /////////////////
                    if (pw_op_row_status != M-1) 
                    begin
                        addr2a<=pw_knl_addr1 -(C-1); addr2b<=pw_knl_addr1 - (C-2);
                        pw_op_row_status<=pw_op_row_status +1;                      // Update row completion status
                        addr1a<=pw_op_row_status + 1;addr1b<=pw_op_row_status + M + 1;    
                    end
                                    
                    else     ////////////////// Channel Completion /////////////////
                    begin
                        pw_op_channel_status<=pw_op_channel_status+1;               // Keeps Record of Pw Output Channels
                        pw_op_row_status<=0;                                        //Because now we move to next kernel which will convolve the same image matrix
                        pw_knl_addr1<=pw_knl_addr1 + C;                               // Moves to max address of the next kernel
                        addr1a<=0; addr1b<=M;
                        addr2a<=addr2a+2; addr2b<=addr2b+2;
                    end
                    en3xa<=1'b1; wen3xa<=1'b1; en3ya<=1'b1; wen3ya<=1'b1;         // Turn ON BRAM 3x and 3y for storing just completed rows
                end   
        end
        else       ////////////////////// PW CONVOLUTION Completion /////////////////////
        begin
            if(t1_load_pw==T1_MAX)
            begin
                PW_ACTIVE_STATUS<=1'b1;
                for (n = 0; n < N; n = n + 1)
                begin
                    load_pw1[n] <= {PW_ACCUM_W{1'b0}}; mul1[n] <= {2*width{1'b0}}; mul2[n] <= {2*width{1'b0}};  pixa[n] <= {width{1'b0}};  pixb[n] <= {width{1'b0}};    
                end
                knl_pw1[0]<={width{1'b0}}; knl_pw1[1]<={width{1'b0}};
                valid_in1<=1'b0; valid_in3<=1'b0; valid_in4<=1'b0; valid_in5<=1'b0;
                pw_knl_addr1<=pw_knl_init1;
                 
            end
            en2a<=1'b0;en2b<=1'b0;  //Turn OFF BRAM 2:Not to be used again
           
           
        end
            
    
//---------------------------------------------------------------------------------------------------------------------------------------------------------------   
   
 //---------------------------------------------------------------------- PART 2 : Loading pixa,pixb,knl values from BRAM 1 and BRAM2 --------------------------------------------------------------------      
      
        if(valid_out3)
        begin
            for (x = 0; x < N; x = x + 1) 
            begin
                pixa[N-1-x] <= data_out1a[x*width +: width]; pixb[N-1-x] <= data_out1b[x*width +: width];           
            end
            knl_pw1[0]<=data_out2a;  knl_pw1[1]<=data_out2b;
        end
        
//----------------------------------------------------------------------- PART 3 : Multiply and Accumulate operationS of PW ------------------------------------------------------------------
        
        
        if(valid_out4)
        begin
            if(cycle_pw == 1)    // ✅ localparam → synthesis removes dead branch entirely
            begin
                // For N≤64: fixed indices, zero mux logic generated
                for (w1 = 0; w1 < N; w1 = w1 + 1)
                begin
                    mul1[w1] <= pixa[w1] * knl_pw1[0];
                    mul2[w1] <= pixb[w1] * knl_pw1[1];
                    mul3[w1] <= pixa[w1] * knl_pw2[0];
                    mul4[w1] <= pixb[w1] * knl_pw2[1];
                    mul5[w1] <= pixa[w1] * knl_pw3[0];
                    mul6[w1] <= pixb[w1] * knl_pw3[1];
                    mul7[w1] <= pixa[w1] * knl_pw4[0];
                    mul8[w1] <= pixb[w1] * knl_pw4[1];
                end
                // No i1/k1 update needed - they're dead too
            end
            else                 // cycle_pw > 1 → only enters for N > 64
            begin
                for (w1 = 0; w1 < 64; w1 = w1 + 1)
                begin
                    mul1[i1+w1] <= pixa[i1+w1] * knl_pw1[0];
                    mul2[i1+w1] <= pixb[i1+w1] * knl_pw1[1];
                    mul3[i1+w1] <= pixa[i1+w1] * knl_pw2[0];
                    mul4[i1+w1] <= pixb[i1+w1] * knl_pw2[1];
                    mul5[i1+w1] <= pixa[i1+w1] * knl_pw3[0];
                    mul6[i1+w1] <= pixb[i1+w1] * knl_pw3[1];
                    mul7[i1+w1] <= pixa[i1+w1] * knl_pw4[0];
                    mul8[i1+w1] <= pixb[i1+w1] * knl_pw4[1];
                end
                if((k1 < cycle_pw-1) && (t2_load_pw != T2_MAX-1))
                begin
                    i1 <= i1 + 64;
                    k1 <= k1 + 1;
                end
                else
                begin
                    i1 <= 0;
                    k1 <= 0;
                end
            end 
        end
        if(valid_out5)
        begin
            if(cycle_pw == 1)
            begin
                for ( w2 = 0; w2 < 64; w2 = w2 + 1)
                begin
                    load_pw1[i2+w2]<=mul1[i2+w2] + mul2[i2+w2] + load_pw1[i2+w2];
                end
            end
            else
            begin    
                if ( (N > 64) && (k2 < (cycle_pw-1)) && (t1_load_pw!=T1_MAX))
                begin
                    i2<= i2 + 64;
                    k2<=k2+1;
                end
                else
                begin
                    i2<=0;
                    k2<=0;
                end 
            end
          t1_load_pw<=t1_load_pw+1;
        end
            /////////////////////// ////// ROW COMPLETION LOGIC ////////////////////////////////// 
                 /////////////////////////////  Store the PW output Row in Bram3 + Make Load Reg fil with 0s /////////////////////
        if(t1_load_pw==T1_MAX)
        begin
            for (y = 0; y < N; y = y + 1)
            begin
                // -------- Saturation / Clipping --------
                if(load_pw1[N-1-y] > MAX)
                begin
                    data_in3xa[y*width +: width] <= MAX;
                    data_in3ya[y*width +: width] <= MAX;
                end
                else if(load_pw1[N-1-y] < MIN)
                begin
                    data_in3xa[y*width +: width] <= MIN;
                    data_in3ya[y*width +: width] <= MIN;
                end
                else
                begin
                    data_in3xa[y*width +: width] <= load_pw1[N-1-y][width-1:0];
                    data_in3ya[y*width +: width] <= load_pw1[N-1-y][width-1:0];
                end
        
                // -------- Clear accumulator --------
                load_pw1[y] <= {PW_ACCUM_W{1'b0}};
            end
    
        // -------- Store completed row --------
            addr3xa <= addr3xa + 1;
            addr3ya <= addr3ya + 1;
    
            t1_load_pw <= 0;
        end
   end
    //----------------------------------------------------------- S T A G E 1 Completion --------------------------------------------------------------------------------------------------------
    
 //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   
  
  //----------------------------------------------------------- S T A G E   2 ( BLOCK 1A ) ------------------------------------------------------------------------------------------------  
    if(reset)
    begin
        valid_gap<=1'b0;
        Sum_GAP<=0;
        GAP<=0;
        count1_gap<=0;
        j_gap<=0;
        load_GAP<=0;
        Vector_AP1<=0;
        valid_in_GAP<=1'b0;
        row_accumulated_gap<=0;
        channel_accumulated_gap<=0;
        GAP_done<=1'b0;
        GAP_STATUS<=1'b0;
    end
    else
    begin
        if(t1_load_pw==T1_MAX)
        begin
            for(i_gap=0;i_gap<N;i_gap=i_gap+1)
            begin
            load_GAP [i_gap*width+:width] <=load_pw1 [i_gap];
            end
            valid_gap<=1'b1;
        end
        if(valid_gap)
        begin
            if(j_gap < N-16)
                j_gap<=j_gap+16;
            else
                valid_gap<=1'b0;
                
            Vector_AP1<=load_GAP [j_gap*width+:16*width];
             
            En_AP1<=1'b1;   valid_in_GAP<=1'b1;   start_gap<=1'b1;
        end
            
        if(valid_out_GAP && start_gap)
        begin
            if(count1_gap < cycle_gap)
            begin
                Sum_GAP<=Sum_GAP + out_AP1;                   // Accumulates added pixels with output of 16 pix Adder
                count1_gap<=count1_gap+1;
            end
            else                        // When 1 full row is accumulated-> reset all the reg and variables
            begin
                if( row_accumulated_gap!=M-1)
                row_accumulated_gap <= row_accumulated_gap + 1;         // keeping a count of total row accumulated
                else
                begin
                     Sum_GAP<= Sum_GAP >>> GAP_shift_coeff;
                     GAP_done<=1'b1;                                    // Signals that a channel has been accumulated
                     row_accumulated_gap<=0;
                     channel_accumulated_gap<=channel_accumulated_gap +1;   // keeping a count of total column accumulated
                end      
                j_gap<=0;
                count1_gap<=0;
                valid_in_GAP<=1'b0;
                start_gap<=1'b0;                                            // So that after a row is done we can stop execution from entering an updating count1_gap again
            end    
        end
        if(GAP_done)                                                    // Program will only enter when 1 channel has been fully accumulated and averaged
        begin
            if(Sum_GAP >= MAX)
            GAP<=MAX;
            else if (Sum_GAP < MIN)
            GAP<=MIN;
            else
            GAP<=Sum_GAP;
            
            Sum_GAP<=0;                                                 // PREPARING FOR NEXT CHANNEL ACCUMULATION
            GAP_done<=1'b0;
                
            if(channel_accumulated_gap == OP_CHANNELS)      
                GAP_STATUS<=1'b1;                     
        end
         
       
    end


//`````````````````````````````````````````````````````````````````````````` GAP COMPLETES HERE ````````````````````````````````````````````````````````````````````````````````````````
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//---------------------------------------------------------------------------- S T A G E 2( BLOCK 1B ) ---------------------------------------------------------------------------------
    if(reset)
    begin
        valid1_dw1<=1'b0;
        valid2_dw1<=1'b0;
        valid3_dw1<=1'b0;
        valid4_dw1<=1'b0;
        valid5_dw1<=1'b0;
        valid6_dw1<=1'b0;
        valid_next0_dw1<=1'b0;
        
        Load_Cache1<=1'b0;
        Load_Buffer1<=1'b0;
        Buffer1a<=0;
        Buffer1b<=0;
        Buffer1c<=0;
        Cache1a<=0;
        Cache1b<=0;
        valid0_dw1<=1'b0;
        valid03_dw1<=1'b0;
        Start_DW_r6<=1'b0;
        max_cyc1<=1'b0;
        REPLICATE_LAST_ROWS_BLK1<=1'b0; BLK1_STATUS<=1'b0;
        dwr6_op_row<=0; dwr6_op_channel<=0;
        next_addr_dw1<=0;
        
        
        count1_dw1<=0;
        count2_dw1<=0;
     
        valid_in1_dwr6<=1'b0;
        wr_ptr1<=0;
        valid2_dwr6<=1'b0;
        k3<=0;k4<=0;
        LOAD_CACHE_FROM_BRAM1<=1'b0;SWAP_N_LOAD1<=1'b0;LOAD_BUFFER_FROM_Cache1<=1'b0;
        valid_next1_dw1<=1'b0;valid_next3_dw1<=1'b0;valid_next3_dw1<=1'b0;
        Enable_MAC1<=1'b0;
        
        addr3xb<=1; 
        addr4xa<=0;
        addr5xa<=0;     
        addr6xa<=0;  wen6xa<=1'b0;  data_in6xa<=0;
        addr6xb<=0;  en6xb<=0; wen6xb<=1'b0;
        first_write_dwr6<=1'b1;        // so that 1st increment is 0 and oth row is stored at this 0th address
        first_read_dwr6<=1'b1;         // so that 1st increment is 0 and oth row is stored at this 0th address
        first_read2_dw1<=1'b1;          // To replicate M-kr first time
        
        DWR6_STATUS<=1'b0;
    end
    else if(!BLK1_STATUS)
    begin
        if(pw_op_row_status ==M-5)
        begin
            en3xb<=1'b1; wen3xb<=1'b0;                                    // Turning on Port B of BRAM 3 for reading and loading buffer   
        end
        if((pw_op_row_status ==M-4) && (t1_load_pw==T1_MAX))              // so that load_Cache1a becomes 1  for a single cycle so that we can turn it off after loading immediately
        begin    
            Load_Cache1<=1'b1;   
 //-------------------------------- LOADING KERNEL AND BN CONSTANTS IN MAC -------------------------------------------
            if(first_read_dwr6)                                         
            begin
                addr4xa<=0;
                addr5xa<=0;
                first_read_dwr6<=1'b0;
            end 
            else if(addr4xa < ((Const_Cby4)-1))
            begin
                addr4xa<=addr4xa+1;
                addr5xa<=addr5xa+1;                
            end   
 //-------------------------------------------------------------------------------------------------------------------------  
        end
        
 //--------------------------------------------------------------- PART 1: Loading of Buffers and Cache before starting (only at the start of a channel)-------------------------------- 
//--------------------------------------------------------------- Laoding Cache -------------------------------------------------------------------------------------------------------
        
        if(Load_Cache1)
        begin
            addr3xb<=addr3xb+r1;
            valid0_dw1<=1'b1;                                           //Introduce 2 latency delay for correct fetching.
            valid1_dw1<=valid0_dw1; 
        end
        if(valid1_dw1)
        begin
            for(x1=0; x1 < N; x1=x1+1)
            begin
                Cache1a[x1*width+:width] <= data_out3xb[(N-1-x1)*width+:width] ;
                valid2_dw1<=1'b1; valid1_dw1<=0; valid0_dw1<=1'b0; Load_Cache1<=1'b0; 
            end
        end
        if(valid2_dw1)
        begin
            for(x2=0; x2 < N; x2=x2+1)
            begin
                Cache1b [x2*width+:width] <= data_out3xb[(N-1-x2)*width+:width] ;
            end
            valid2_dw1<=1'b0;
            addr3xb<=next_addr_dw1;                              // becasue next 3 buffers will be laoded with ddresses(rows) 0,6,12
        end    
//----------------------------------------------------------------------------Loading Buffers --------------------------------------------------------------------------------------

        if((pw_op_row_status ==M-2) && (t1_load_pw==T1_MAX))                            // so that load_Buffer1 driven to 1  for a single cycle so that we can turn it off after loading immediately
        Load_Buffer1<=1'b1;
        
        if( Load_Buffer1)
        begin
            if(count1_dw1 < 2)
            begin
                addr3xb<=addr3xb+r1;
                count1_dw1<=count1_dw1+1;
                
                valid03_dw1<=1'b1;                      // Introduce 2 latency delay for correct fetching.
                valid3_dw1<=valid03_dw1;
            end
        end
        if(valid3_dw1)
        begin
            for(x1=0; x1 < N; x1=x1+1)
            begin
                Buffer1a [x1*width+:width] <= data_out3xb[(N-1-x1)*width+:width] ;
            end
            valid4_dw1<=1'b1; valid3_dw1<=1'b0; valid03_dw1<=1'b0;
        end
        
        if(valid4_dw1)
        begin
            for(x2=0; x2 < N; x2=x2+1)
            begin
                Buffer1b [x2*width+:width] <= data_out3xb[(N-1-x2)*width+:width] ;
               
            end
            valid5_dw1<=1'b1; valid4_dw1<=1'b0;
        end        
        if(valid5_dw1)
        begin
            for(x3=0; x3 < N; x3=x3+1)
            begin
                Buffer1c [x3*width+:width] <= data_out3xb[(N-1-x3)*width+:width] ;
            end
            Load_Buffer1<=1'b0; count1_dw1<=0;                                 // Enters only before beginning of a cycle for PRELOADING.
            valid5_dw1<=1'b0;
            
            addr3xb<=r1b + next_addr_dw1;                                        // Make addr=2r=12 bcoz next address(row) fetched after 0,6,12 will be 18, so keep it 12.
             
  //````````````````````````````````````````````````` Turning on BRAMs with KERNEL VALUES AND BN CONSTANTS IN MAC (once every channel) ````````````````````````````````````````````
            en4xa<=1'b1; wen4xa<=1'b0;
            en5xa<=1'b1; wen5xa<=1'b0; 
            
            
        end    
    
 //------------------------------------------------------------------ PART 2 : STARTING DW DIALTED CONVOLUTION AND COLLECTING PIXELS + GAP AND REPLICATING --------------------------------------------------
        if(GAP_done)
        begin
            en6xa<=1'b1;en6xb<=1'b1; wen6xb<=1'b0;
            Enable_MAC1<=1'b1; Start_DW_r6<=1'b1; valid_in1_dwr6<=1'b1;       
        end
        
        if(Start_DW_r6)
        begin
            if(max_cyc1 < MAX_CYC_DWR6)
            begin
                Buffer1a <= Buffer1a >> SHIFT_DWR6_COEFF;
                Buffer1b <= Buffer1b >> SHIFT_DWR6_COEFF;
                Buffer1c <= Buffer1c >> SHIFT_DWR6_COEFF;
            end
            if(max_cyc1 < MAX_CYC_DWR6)
                max_cyc1 <= max_cyc1 +1;
            else
                max_cyc1<=0;
            
            if(valid_out1_dwr6)
            begin   
                if(SUM1 > MAX)
                    data_in6xa [((wr_ptr1)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1)*width) +: width]<= SUM1[width-1:0];
                    
                if(SUM2 > MAX)
                    data_in6xa [((wr_ptr1+1)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+1)*width) +: width]<= SUM2[width-1:0];
                    
                if(SUM3 > MAX)
                    data_in6xa [((wr_ptr1+2)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+2)*width) +: width]<= SUM3[width-1:0];
                    
                if(SUM4 > MAX)
                    data_in6xa [((wr_ptr1+3)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+3)*width) +: width]<= SUM4[width-1:0];
                
                if(wr_ptr1 < WR_PTR_MAX_BLK_R1)
                begin    
                    wr_ptr1<=wr_ptr1+4;      
                end
                if(wr_ptr1 == WR_PTR_MAX_BLK_R1)
                begin                                      
                    wr_ptr1<=0;
                    dwr6_op_row <= dwr6_op_row + 1;
                    for(x4=N-12; x4 < N; x4=x4+1)
                    begin
                        data_in6xa [(x4*width) +: width]<=SUM4[width-1:0];      // Replicate last pixel to rest 12 columns, in the same cycle when last 4 pixels are generated
                    end
                    valid2_dwr6<=1'b1; wen6xa <= 1'b1;   // ✅ wen arrives as 1 exactly in valid2_dwr6 cycle.
                    
                    // start writing data into bram 6x
                        
                    if(first_write_dwr6)
                    begin
                        addr6xa <= next_addr_dw1;
                        first_write_dwr6 <= 1'b0;
                    end 
                         
                    else if(addr6xa <= next_addr_dw1 + ROW_LOADER_COEFF_R1)             // addr6xa<=M-3*r1-1;
                        addr6xa <= addr6xa + r1 ;
                        
                    else if(k4< r1-1)
                    begin
                        k4<=k4+1;
                        addr6xa <= next_addr_dw1+ k4+1;
                    end
                    
                    else                    //1 channel completely stored : Load last 12 rows.
                    begin
                        
                        dwr6_op_channel<= dwr6_op_channel+1;
                        next_addr_dw1<=next_addr_dw1+M;
                       
                        dwr6_op_row<=0;
                        
                        Buffer1a<=0; Buffer1b<=0; Buffer1c<=0; Cache1a<=0; Cache1b<=0;  Load_Buffer1<=1'b0; Load_Cache1<=1'b0;
                        valid2_dwr6<=1'b0; LOAD_CACHE_FROM_BRAM1<=1'b0; SWAP_N_LOAD1<=1'b0; LOAD_BUFFER_FROM_Cache1<=1'b0;
                        valid_next1_dw1<=1'b0; valid_next3_dw1<=1'b0; valid_next3_dw1<=1'b0; valid_next0_dw1<=1'b0; 
                        Start_DW_r6<=1'b0; wr_ptr1<=0; max_cyc1<=0; Enable_MAC1<=1'b0; valid_in1_dwr6<=1'b0;
                        k3<=0; k4<=0;
                        
                        //--------------------------------------------------For replication at the end of channel ----------------------------
                        REPLICATE_LAST_ROWS_BLK1<=1'b1; count2_dw1<=0;
                        first_rep_write1<=1'b1;
                        addr6xb<=M-kr1+ next_addr_dw1;        // M-13
                        
                        addr6xa<= next_addr_dw1+M-r1b;        // write from M-12 onwards
                        //--------------------------------------------------------------------------------------------------------------------------
                    end
                end    
    //------------------------------------------------------------------ PART 3 : STORNG THE DWR6 + GAP ROWS IN BRAM 6--------------------------------------------------          
                if(valid2_dwr6)
                begin
                    wen6xa      <= 1'b0;   // stop after one write
                    valid2_dwr6 <= 1'b0;
                end                  
                    
                         
            end
 
         
//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
            
//------------------------------------------------------------------------- PART 4: LAODING BUFFER AND CACHE AFTER ROW COMPLETION --------------------------------------------------
            if(max_cyc1==MAX_CYC_DWR6-3)
            begin
                if(addr3xb  <= next_addr_dw1 + addr3_r6_MAX)
                begin
                    addr3xb<=addr3xb+r1;
                    SWAP_N_LOAD1<=1'b1;
                end
                else if (k3 < r1-1)
                begin
                    addr3xb<=next_addr_dw1+k3+kr1;
                    k3<=k3+1;
                    LOAD_CACHE_FROM_BRAM1<=1'b1; valid_next0_dw1<=1'b1;
                    LOAD_BUFFER_FROM_Cache1<=1'b1;
                end
            
            end
            
            if(max_cyc1==MAX_CYC_DWR6)
            begin
                if(SWAP_N_LOAD1)
                begin
                    Buffer1a <= Buffer1b ;                              // Buffer 1b has already been right shifted to last set of 4 pixels which gets copied to Buffer 1a, that's why Buffer 1a remains 0 in sim
                    Buffer1b <= Buffer1c ; 
                    for(x5=0; x5 < N; x5=x5+1)
                    begin
                        Buffer1c [x5*width+:width] <= data_out3xb[(N-1-x5)*width+:width] ;
                    end
                    SWAP_N_LOAD1<=1'b0;
                end
                
                if(LOAD_BUFFER_FROM_Cache1)
                begin
                    Buffer1a<=Cache1a;
                    Buffer1b<=Cache1b;
                    for(x6=0; x6 < N; x6=x6+1)
                    begin
                        Buffer1c [x6*width+:width] <= data_out3xb[(N-1-x6)*width+:width] ;
                    end
                    
                    LOAD_BUFFER_FROM_Cache1<=1'b0;
                end
            
            
            end
            if(LOAD_CACHE_FROM_BRAM1 && (k3 < r1-1))                // Load only when k3<4 else that means channel is completed
            begin
                if(valid_next0_dw1)
                begin
                    temp_addr1<=addr3xb ;
                    addr3xb<= next_addr_dw1+ k3+1;
                    valid_next1_dw1<=1'b1; valid_next0_dw1<=1'b0;
                end
                if(valid_next1_dw1)
                begin
                    addr3xb<=addr3xb + r1;
                    valid_next2_dw1<=1'b1; valid_next1_dw1<=1'b0;
                end
                
                if(valid_next2_dw1)
                begin
                    for(x7=0; x7 < N; x7=x7+1)
                    begin
                        Cache1a [x7*width+:width] <= data_out3xb[(N-1-x7)*width+:width] ;
                    end
                    valid_next3_dw1<=1'b1; valid_next2_dw1<=1'b0;
                    addr3xb<=temp_addr1;              // Loading addr3b with its previous value
                end
                
                 if(valid_next3_dw1)
                begin
                    for(x8=0; x8 < N; x8=x8+1)
                    begin
                        Cache1b [x8*width+:width] <= data_out3xb[(N-1-x8)*width+:width] ;
                    end
                    LOAD_CACHE_FROM_BRAM1<=1'b0; valid_next3_dw1<=1'b0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
                end
                       
            end
                          
        end
 //-------------------------------------------------------------- PART 5: REPLICATE LAST 12 ROWS TO MATCH IMAGE SIZE after Channel Completion --------------------------------------------------
        if(REPLICATE_LAST_ROWS_BLK1)
        begin
            valid6_dw1 <= 1'b1;   // 1-cycle delay for BRAM B output
            if(valid6_dw1)
            begin
                if(first_rep_write1)
                begin
                   
                    // BRAM A sees: addr=M=2r, wen=0 this cycle (wen takes effect next)
                    data_in6xa     <= data_out6xb;  // latch row 51 data
                    wen6xa         <= 1'b1;         // arms wen (takes effect next cycle)
                    first_rep_write1<= 1'b0;
                    // next cycle: addr=52, wen=1, data=row51 → BRAM writes to 52 ✓
                end
        
                else if(addr6xa < next_addr_dw1-1)   // < 64, covers all 52-63
                begin
                    // ✅ WRITE+INCREMENT: BRAM writes to CURRENT addr this cycle
                    addr6xa <= addr6xa + 1;
                    // wen=1 stays, data_in stays (same row 51 for all replications)
                end
        
                else if(dwr6_op_channel == Const_Cby4)
                begin
                    wen6xa                   <= 1'b0;
                    BLK1_STATUS              <= 1'b1;
                    DWR6_STATUS              <= 1'b1;
                    valid6_dw1               <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK1 <= 1'b0;
                    en6xb                    <= 1'b1;
                    addr6xa                  <=0;
                end
        
                else
                begin
                    wen6xa                   <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK1 <= 1'b0;
                    valid6_dw1               <= 1'b0;
                    en6xb                    <= 1'b0;
                    first_write_dwr6         <= 1'b1;
                    addr6xa                  <= next_addr_dw1;
         
                    addr3xb <= next_addr_dw1 + 1;
                end
            end
    end 
    //----------------------------- DW R6 + GAP COMPLETES HERE-------------------------------------------
    
        
   
    end

    
    
      
    
//--------------------------------------------------------------- BLOCK 1B COMPLETION ----------------------------------------------------------------------------------------------  
 
    
//--------------------------------------------------------------- S T A G E 2 ( BLOCK 2A )------------------------------------------------------------------------------------------


    if(reset)
    begin
        Vec_ap16<=0; Load_AP16<=0;
        ptr1<=0; ptr2<=0;
        valid_in1_ap16<=0; valid_AP16<=1'b0;
        Start_AP16<=1'b0;
        Win16<=0; ap16_row<=0; ap16_channel<=0; 
        Load_ap16_row<=1'b0; clip_ap16_pix<=1'b0;
        AP16_STATUS<=1'b0;
    end
    else
    begin
        if(t1_load_pw==T1_MAX)
        begin
            for(j1=0; j1<N; j1=j1+1)
            begin
                Vec_ap16 [j1*width+:width] <=load_pw1 [j1];
            end
            valid_in1_ap16<=1'b1; valid_AP16<=1'b1;
            En_AP16<=1'b1; Start_AP16<=1'b1;
        end
        
        if(valid_AP16)
        begin
            if(ptr1 < PTR_MAX_AP16)
            begin
                Vec_ap16 <= Vec_ap16 >> AP16_BUFF_SHIFT;
                ptr1<=ptr1+2;
            end
            else
               begin
                valid_AP16<=1'b0;
                ptr1<=0;
               end
        end
       
        if(valid_out1_ap16 && Start_AP16)
        begin
            Load_AP16 [ptr2*width+:(width+8)] <= $signed (Load_AP16 [ptr2*width+:(width+8)]) + Add1; 
            Load_AP16 [(ptr2+1)*width+:(width+8)] <= $signed(Load_AP16 [(ptr2+1)*width+:(width+8)]) + Add2; 
            
            if(ptr2 < PTR_MAX_AP16)
            begin
                ptr2<=ptr2+2;
            end
            else
            begin
                Win16<=Win16+1;
                ptr2<=0;
                Start_AP16<=0; valid_in1_ap16<=1'b0;
            end
        end
       
        if(Win16==16)
       begin
           Load_AP16 <= Load_AP16 >> 8;                 // divide by 256 after pooling
           clip_ap16_pix<=1'b1; 
           Win16<=0;                // Preparing for next row
       end
       if(clip_ap16_pix)                           // Clipping the generated row
       begin
           clip_ap16_pix<=1'b0;
           for(j1=0; j1< COL_AP16; j1=j1+1)
           begin
               if($signed(Load_AP16 [j1*width+:width]) > MAX)
               begin
                   Load_AP16 [j1*width+:width]<= MAX;
               end
               if($signed(Load_AP16 [j1*width+:width]) < MIN)
               begin
                   Load_AP16 [j1*width+:width]<= MIN;
               end                    
           end
               
           Load_ap16_row<=1'b1; 
       end
           
           
       if(Load_ap16_row)                // Only executes 2 cc after a row completes
       begin
           Load_ap16_row<=1'b0;
           Load_AP16<=0;                // Clearing Accumulator after a Laoding a row
           
            for(j2=0; j2 < COL_AP16; j2=j2+1)
               begin
                   MEM_AP16[ap16_row][j2] <= Load_AP16 [j2*width+:width];
               end
           if(ap16_row != ROW_AP16-1 )
           begin  
               ap16_row<=ap16_row+1;
           end
           else                              // AVg Pool 16 over 1 channel finishes
           begin
               ap16_row<=0;                 
               ap16_channel<=ap16_channel+1;
               
           end
           if(ap16_channel==OP_CHANNELS-1)
                AP16_STATUS<=1'b1;
       end
          
    end



//-------------------------------------------------------------- BLOCK 2A COMPLETION -----------------------------------------------------------------------------------------------
 
 
//--------------------------------------------------------------  S T A G E 2 ( BLOCK 2B ) -----------------------------------------------------------------------------------------
  

    if(reset)
    begin
        valid1_dw2<=1'b0;
        valid2_dw2<=1'b0;
        valid3_dw2<=1'b0;
        valid4_dw2<=1'b0;
        valid5_dw2<=1'b0;
        valid_next0_dw2<=1'b0;
        
        Load_Cache2<=1'b0;
        Load_Buffer2<=1'b0;
        Buffer2a<=0;
        Buffer2b<=0;
        Buffer2c<=0;
        Cache2a<=0;
        Cache2b<=0;
        valid0_dw2<=1'b0;
        valid03_dw2<=1'b0;
        Start_DW_r12<=1'b0;
        max_cyc2<=0;
        REPLICATE_LAST_ROWS_BLK2<=1'b0; BLK2_STATUS<=1'b0;
        DWR12_op_row<=0; DWR12_op_channel<=0; 
        AP2A<=0;AP2B<=0; AP2C<=0; AP2D<=0;
        first_rep_write2<= 1'b0;
        count1_dw2<=0;
        count2_dw2<=0;
        valid_in1_DWR12<=1'b0;
        wr_ptr2<=0;
        valid2_DWR12<=1'b0;
        l3<=0;l4<=0;
        LOAD_CACHE_FROM_BRAM2<=1'b0;SWAP_N_LOAD2<=1'b0;LOAD_BUFFER_FROM_Cache2<=1'b0;
        valid_next1_dw2<=1'b0;valid_next3_dw2<=1'b0;valid_next3_dw2<=1'b0;
        Enable_MAC2<=1'b0;
        
        addr3yb<=1; 
        addr4ya<=0;
        addr5ya<=0;     
        addr6ya<=0; wen6ya<=1'b0;  
        addr6yb<=0;
        data_in6ya<=0;
        first_write_DWR12<=1'b1;        // so that 1st increment is 0 and oth row is stored at this 0th address
        first_read_DWR12<=1'b1;         // so that 1st increment is 0 and oth row is stored at this 0th address
        next_addr_dw2<=0;               // Initially 0, will increment by M each cahnnel
        DWR12_STATUS<=1'b0;
    end
    else if(!BLK2_STATUS)
    begin
        if(pw_op_row_status ==M-5)
        begin
            en3yb<=1'b1; wen3yb<=1'b0;                                    // Turning on Port B of BRAM 3 for reading and loading buffer   
        end
        if((pw_op_row_status ==M-4) && (t1_load_pw==T1_MAX))              // so that load_Cache2a becomes 1  for a single cycle so that we can turn it off after loading immediately
        begin    
            Load_Cache2<=1'b1;   
 //-------------------------------- LOADING KERNEL AND BN CONSTANTS IN MAC -------------------------------------------
            if(first_read_DWR12)                                         
            begin
                addr4ya<=0;
                addr5ya<=0;
                first_read_DWR12<=1'b0;
            end 
            else if(addr4ya < ((Const_Cby4)-1))
            begin
                addr4ya<=addr4ya+1;
                addr5ya<=addr5ya+1;                
            end   
 //-------------------------------------------------------------------------------------------------------------------------  
        end
        
        if(Load_Cache2)
        begin
            addr3yb<=addr3yb+r2;
            valid0_dw2<=1'b1;                                           //Introduce 2 latency delay for correct fetching.
            valid1_dw2<=valid0_dw2; 
        end
        if(valid1_dw2)
        begin
            for(y1=0; y1 < N; y1=y1+1)
            begin
                Cache2a[y1*width+:width] <= data_out3yb[(N-1-y1)*width+:width] ;
                valid2_dw2<=1'b1; valid1_dw2<=0; valid0_dw2<=1'b0; Load_Cache2<=1'b0; 
            end
        end
        if(valid2_dw2)
        begin
            for(y2=0; y2 < N; y2=y2+1)
            begin
                Cache2b [y2*width+:width] <= data_out3yb[(N-1-y2)*width+:width] ;
            end
            valid2_dw2<=1'b0;
            addr3yb<= next_addr_dw2;                              // becasue next 3 buffers will be laoded with ddresses(rows) 0,12,24
        end    
//----------------------------------------------------------------------------Loading Buffers --------------------------------------------------------------------------------------

        if((pw_op_row_status ==M-2) && (t1_load_pw==T1_MAX))                            // so that load_Buffer2 driven to 1  for a single cycle so that we can turn it off after loading immediately
        Load_Buffer2<=1'b1;
        
        if( Load_Buffer2)
        begin
            if(count1_dw2 < 2)
            begin
                addr3yb<=addr3yb+r2;
                count1_dw2<=count1_dw2+1;
                
                valid03_dw2<=1'b1;                      // Introduce 2 latency delay for correct fetching.
                valid3_dw2<=valid03_dw2;
            end
        end
        if(valid3_dw2)
        begin
            for(y1=0; y1 < N; y1=y1+1)
            begin
                Buffer2a [y1*width+:width] <= data_out3yb[(N-1-y1)*width+:width] ;
            end
            valid4_dw2<=1'b1; valid3_dw2<=1'b0; valid03_dw2<=1'b0;
        end
        
        if(valid4_dw2)
        begin
            for(y2=0; y2 < N; y2=y2+1)
            begin
                Buffer2b [y2*width+:width] <= data_out3yb[(N-1-y2)*width+:width] ;
               
            end
            valid5_dw2<=1'b1; valid4_dw2<=1'b0;
        end        
        if(valid5_dw2)
        begin
            for(y3=0; y3 < N; y3=y3+1)
            begin
                Buffer2c [y3*width+:width] <= data_out3yb[(N-1-y3)*width+:width] ;
            end
            Load_Buffer2<=1'b0; count1_dw2<=0;                                 // Enters only before beginning of a cycle for PRELOADING.
            valid5_dw2<=1'b0;
            
            addr3yb<=r2b + next_addr_dw2;                                        // Make addr=2r=12 bcoz next address(row) fetched after 0,6,12 will be 18.
             
  //````````````````````````````````````````````````` Turning on BRAMs with KERNEL VALUES AND BN CONSTANTS IN MAC (once every channel) ````````````````````````````````````````````
            en4ya<=1'b1; wen4ya<=1'b0;
            en5ya<=1'b1; wen5ya<=1'b0; 
            
            
        end    
    
 //------------------------------------------------------------------ PART 2 : STARTING DW DIALTED CONVOLUTION AND COLLECTING PIXELS AND REPLICATING --------------------------------------------------
        if(GAP_done)
        begin
            en6ya<=1'b1;
            Enable_MAC2<=1'b1; Start_DW_r12<=1'b1; valid_in1_DWR12<=1'b1;       
        end
        
        if(Start_DW_r12)
        begin
            if(max_cyc2 < MAX_CYC_DWR12)
            begin
                Buffer2a <= Buffer2a >> SHIFT_DWR12_COEFF;
                Buffer2b <= Buffer2b >> SHIFT_DWR12_COEFF;
                Buffer2c <= Buffer2c >> SHIFT_DWR12_COEFF;
            end
            if(max_cyc2 < MAX_CYC_DWR12)
                max_cyc2 <= max_cyc2 +1;
            else
                max_cyc2<=0;
            
            if(valid_out1_DWR12)
            begin   
                if(SUM5 > MAX)
                    data_in6ya [((wr_ptr2)*width) +: width]<= MAX;
                else
                    data_in6ya [((wr_ptr2)*width) +: width]<= SUM5[width-1:0];
                    
                if(SUM6 > MAX)
                    data_in6ya [((wr_ptr2+1)*width) +: width]<= MAX;
                else
                    data_in6ya [((wr_ptr2+1)*width) +: width]<= SUM6[width-1:0];
                    
                if(SUM7 > MAX)
                    data_in6ya [((wr_ptr2+2)*width) +: width]<= MAX;
                else
                    data_in6ya [((wr_ptr2+2)*width) +: width]<= SUM7[width-1:0];
                    
                if(SUM8 > MAX)
                    data_in6ya [((wr_ptr2+3)*width) +: width]<= MAX;
                else
                    data_in6ya [((wr_ptr2+3)*width) +: width]<= SUM8[width-1:0];
                
                if(wr_ptr2 < WR_PTR_MAX_BLK_R2)
                begin    
                    wr_ptr2<=wr_ptr2+4;      
                end
                if(wr_ptr2 == WR_PTR_MAX_BLK_R2)
                begin                                      
                    wr_ptr2<=0;
                    DWR12_op_row <= DWR12_op_row + 1;
                    for(y4=N-12; y4 < N; y4=y4+1)
                    begin
                        data_in6ya [(y4*width) +: width]<=SUM4[width-1:0];      // Replicate last pixel to rest 12 columns, in the same cycle when last 4 pixels are generated
                    end
                    valid2_DWR12<=1'b1; wen6ya <= 1'b1;   // ✅ wen arrives as 1 exactly in valid2_DWR12 cycle.
    //------------------------------------------------------------------ PART 3 : STORNG THE DWR12 + GAP ROWS IN BRAM 6--------------------------------------------------          
                    if(first_write_DWR12)
                    begin
                        addr6ya <= next_addr_dw2;
                        first_write_DWR12 <= 1'b0;
                    end 
                         
                    else if(addr6ya <= ROW_LOADER_COEFF_R2 + next_addr_dw2)
                        addr6ya <= addr6ya + r2;
                        
                    else if(l4< r2-1)
                    begin
                        l4<=l4+1;
                        addr6ya <= l4+ 1 + next_addr_dw2;
                    end
                    
                    else                    //1 channel completely stored : Load last 12 rows.
                    begin
                        
                        DWR12_op_channel<= DWR12_op_channel+1;
                        DWR12_op_row<=0;
                        next_addr_dw2<= next_addr_dw2 + M;
                        
                        Buffer2a<=0; Buffer2b<=0; Buffer2c<=0; Cache2a<=0; Cache2b<=0;  Load_Buffer2<=1'b0; Load_Cache2<=1'b0;
                        valid2_DWR12<=1'b1; LOAD_CACHE_FROM_BRAM2<=1'b0; SWAP_N_LOAD2<=1'b0; LOAD_BUFFER_FROM_Cache2<=1'b0;
                        valid_next1_dw2<=1'b0; valid_next3_dw2<=1'b0; valid_next3_dw2<=1'b0; valid_next0_dw2<=1'b0; count2_dw2<=0; 
                        Start_DW_r12<=1'b0; wr_ptr2<=0; max_cyc2<=0; Enable_MAC2<=1'b0; valid_in1_DWR12<=1'b0;
                        l3<=0; l4<=0; first_write_DWR12<=1'b1;
                        
                        REPLICATE_LAST_ROWS_BLK2<=1'b1; first_rep_write2<=1'b1; 
                        wen6yb<=1'b0; addr6yb<=M-kr1 + next_addr_dw2;
                        addr6ya<= M-r2b + next_addr_dw2;
                            
                    end
                   
                end
                
                if(valid2_DWR12)
                begin
                    wen6ya      <= 1'b0;   // stop after one write
                    valid2_DWR12 <= 1'b0;
                end                           
            end
 
         
//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
            
//------------------------------------------------------------------------- PART 4: LAODING BUFFER AND CACHE AFTER ROW COMPLETION --------------------------------------------------
            if(max_cyc2==MAX_CYC_DWR12-3)
            begin
                if(addr3yb <= next_addr_dw2+ addr3_r12_MAX)
                begin
                    addr3yb<=addr3yb+r2;
                    SWAP_N_LOAD2<=1'b1;
                end
                else if (l3 < r2-1)
                begin
                    addr3yb<=l3+kr2 + next_addr_dw2;
                    l3<=l3+1;
                    LOAD_CACHE_FROM_BRAM2<=1'b1; valid_next0_dw2<=1'b1;
                    LOAD_BUFFER_FROM_Cache2<=1'b1;
                end
            
            end
            
            if(max_cyc2==MAX_CYC_DWR12)
            begin
                if(SWAP_N_LOAD2)
                begin
                    Buffer2a <= Buffer2b ;
                    Buffer2b <= Buffer2c ; 
                    for(y5=0; y5 < N; y5=y5+1)
                    begin
                        Buffer2c [y5*width+:width] <= data_out3yb[(N-1-y5)*width+:width] ;
                    end
                    SWAP_N_LOAD2<=1'b0;
                end
                
                if(LOAD_BUFFER_FROM_Cache2)
                begin
                    Buffer2a<=Cache2a;
                    Buffer2b<=Cache2b;
                    for(y6=0; y6 < N; y6=y6+1)
                    begin
                        Buffer2c [y6*width+:width] <= data_out3yb[(N-1-y6)*width+:width] ;
                    end
                    
                    LOAD_BUFFER_FROM_Cache2<=1'b0;
                end
            
            
            end
            if(LOAD_CACHE_FROM_BRAM2 && (l3 < r2-1))                // Load only when l3<11 else that means channel is completed
            begin
                if(valid_next0_dw2)
                begin
                    temp_addr2<=addr3yb;
                    addr3yb<=l3+1 + next_addr_dw2;
                    valid_next1_dw2<=1'b1; valid_next0_dw2<=1'b0;
                end
                if(valid_next1_dw2)
                begin
                    addr3yb<=addr3yb+r2;
                    valid_next2_dw2<=1'b1; valid_next1_dw2<=1'b0;
                end
                
                if(valid_next2_dw2)
                begin
                    for(y7=0; y7 < N; y7=y7+1)
                    begin
                        Cache2a [y7*width+:width] <= data_out3yb[(N-1-y7)*width+:width] ;
                    end
                    valid_next3_dw2<=1'b1; valid_next2_dw2<=1'b0;
                    addr3yb<=temp_addr2;              // Loading addr3b with its previous value
                end
                
                 if(valid_next3_dw2)
                begin
                    for(y8=0; y8 < N; y8=y8+1)
                    begin
                        Cache2b [y8*width+:width] <= data_out3yb[(N-1-y8)*width+:width] ;
                    end
                    LOAD_CACHE_FROM_BRAM2<=1'b0; valid_next3_dw2<=1'b0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
                end
                
            
            
            end
            
            
            
             
        end
 //-------------------------------------------------------------- PART 5: REPLICATE LAST 24 ROWS TO MATCH IMAGE SIZE --------------------------------------------------
        if(REPLICATE_LAST_ROWS_BLK2)
        begin
            valid6_dw2 <= 1'b1;   // 1-cycle delay for BRAM B output
            if(valid6_dw2)
            begin
                if(first_rep_write2)
                begin
                    data_in6ya     <= data_out6yb;  
                    wen6ya         <= 1'b1;         // arms wen (takes effect next cycle)
                    first_rep_write2<= 1'b0;
                  
                end
        
                else if(addr6ya < next_addr_dw2-1)   // < M, covers all M-2r2 to M-1
                begin
                    // ✅ WRITE+INCREMENT: BRAM writes to CURRENT addr this cycle
                    addr6ya <= addr6ya + 1;
                    // wen=1 stays, data_in stays 
                end
        
                else if(DWR12_op_channel == Const_Cby4)
                begin
                    wen6ya                   <= 1'b0;
                    BLK2_STATUS              <= 1'b1;
                    DWR12_STATUS              <= 1'b1;
                    valid6_dw2               <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK2 <= 1'b0;
                    en6yb                    <= 1'b1;
                    addr6ya                  <=0;
                    
                end
        
                else
                begin
                    wen6ya                   <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK2 <= 1'b0;
                    valid6_dw2               <= 1'b0;
                    en6yb                    <= 1'b0;
                    first_write_DWR12         <= 1'b1;
                    addr6ya                  <= next_addr_dw2;
                    
                    addr3yb <= next_addr_dw2 + 1;
                end
            end
    end      
    
      
    end


//------------------------------------------------------------  S T A G E  2 COMPLETION ------------------------------------------------------------------------------------------------


//------------------------------------------------------------ LOADING STAGE 2 IN BRAM 1 -----------------------------------------------------------------------------------------------
     if(reset)
     begin
        STAGE2_STATUS<=1'b1;
        valid_load<=1'b0;
        START_LOAD_BRAM1<=1'b0;
        first_load<=1'b0;
        Bram1_loaded<=1'b0;
     end
     
     else if(BLK1_STATUS && STAGE2_STATUS)
     begin
         en6yb<=1'b1; wen6yb<=1'b0; addr6yb<=0; 
         en6xb<=1'b1; wen6xb<=1'b0; addr6xb<=0; 
         en1a<=1'b1; wen1a<=1'b0; en1b<=1'b1; wen1b<=1'b0;             
         addr1a<=S2_B1_LOAD_START_ADDR ;  addr1b<=S2_B2_LOAD_START_ADDR;
         valid_load<=1'b1; STAGE2_STATUS<=1'b0; first_load<=1'b1;
         
     end  
     else if(valid_load)
     begin
         START_LOAD_BRAM1<= valid_load;
         
         addr6xb<=addr6xb+1; addr6yb<=addr6yb+1;
         if(START_LOAD_BRAM1)
         begin
             if(first_load)
             begin
                 addr1a<=S2_B1_LOAD_START_ADDR;
                 addr1b<=S2_B2_LOAD_START_ADDR;
                 data_in1a<=data_out6xb;
                 data_in1b<=data_out6yb;
                 first_load<=1'b0;
             end
             else if(addr1a < S2_B1_LOAD_LAST_ADDR)
             begin
                 wen1a<=1'b1; wen1b<=1'b1;
                 data_in1a<=data_out6xb;
                 data_in1b<=data_out6yb;
                 addr1a<=addr1a+1;
                 addr1b<=addr1b+1;
             end
             else
             begin
                 addr1a<=0; addr1b<=0;
                 START_LOAD_BRAM1<=1'b0;
                 valid_load<=1'b0;
                 Bram1_loaded<=1'b1;
             end
         end
     end
 
 
 
 
 
 //----------------------------------------------------------- S T A G E  3 --------------------------------------------------------------------------------------------
    
    if(Bram1_loaded)
    begin
        valid1_dw1<=1'b0; valid2_dw1<=1'b0; valid3_dw1<=1'b0; valid4_dw1<=1'b0; valid5_dw1<=1'b0; valid6_dw1<=1'b0; valid_next0_dw1<=1'b0;
        Load_Cache1<=1'b1; Load_Buffer1<=1'b0;
        Buffer1a<=0; Buffer1b<=0;
        Buffer1c<=0; Cache1a<=0;Cache1b<=0;
        valid0_dw1<=1'b0;valid03_dw1<=1'b0;
        Start_Dwr18<=1'b0;
        max_cyc1<=0;
        REPLICATE_LAST_ROWS_BLK1<=1'b0;
        dwr6_op_row<=0; dwr6_op_channel<=0;
        next_addr_dw1<=0;
           
        count1_dw1<=0;count2_dw1<=0;
     
        valid_in1_dwr6<=1'b0;
        wr_ptr1<=0;
        valid2_dwr6<=1'b0;
        k3<=0;k4<=0;
        LOAD_CACHE_FROM_BRAM1<=1'b0;SWAP_N_LOAD1<=1'b0;LOAD_BUFFER_FROM_Cache1<=1'b0;
        valid_next1_dw1<=1'b0;valid_next3_dw1<=1'b0;valid_next3_dw1<=1'b0;
        Enable_MAC1<=1'b0;
        
        en3xb<=1'b1; wen3xb<=1'b0; addr3xb<=1; Load_knl_dwr18<=0;
        en4xa<=1'b1; wen4xa<=1'b0; en5xa<=1'b1; wen5xa<=1'b0; addr4xa<=Const_Cby4; addr5xa<=Const_Cby4;     
        en6xa<=1'b1; addr6xa<=0;  wen6xa<=1'b0;  data_in6xa<=0; first_read_dwr18<=1'b1;
        dwr18_op_channel<=0; dwr18_op_row<=0; first_write_dwr18<=1'b1;
        START_STAGE3<=1'b1; Bram1_loaded<=1'b0;
    
    end
    
 
    if(START_STAGE3)
    begin
 //-------------------------------- LOADING KERNEL AND BN CONSTANTS IN MAC -------------------------------------------
        if(first_read_dwr18)                                         
        begin
            addr4xa<=Const_Cby4;
            addr5xa<=Const_Cby4;
            first_read_dwr18<=1'b0;
        end 
        else if(Load_knl_dwr18)
        begin
            addr4xa<=addr4xa+1;
             addr5xa<=addr5xa+1;                
        end   
 //-------------------------------------------------------------------------------------------------------------------------  
        
        
 //--------------------------------------------------------------- PART 1: Loading of Buffers and Cache before starting (only at the start of a channel)-------------------------------- 
//--------------------------------------------------------------- Laoding Cache -------------------------------------------------------------------------------------------------------
        
        if(Load_Cache1)
        begin
            addr3xb<=addr3xb+r3;
            valid0_dw1<=1'b1;                                           //Introduce 2 latency delay for correct fetching.
            valid1_dw1<=valid0_dw1; 
        end
        if(valid1_dw1)
        begin
            for(x1=0; x1 < N; x1=x1+1)
            begin
                Cache1a[x1*width+:width] <= data_out3xb[(N-1-x1)*width+:width] ;
                valid2_dw1<=1'b1; valid1_dw1<=0; valid0_dw1<=1'b0; Load_Cache1<=1'b0; 
            end
        end
        if(valid2_dw1)
        begin
            for(x2=0; x2 < N; x2=x2+1)
            begin
                Cache1b [x2*width+:width] <= data_out3xb[(N-1-x2)*width+:width] ;
            end
            valid2_dw1<=1'b0;
            addr3xb<=next_addr_dw1;                              // becasue next 3 buffers will be laoded with ddresses(rows) 0,18,36
            Load_Buffer1<=1'b1;
        end    
//----------------------------------------------------------------------------Loading Buffers --------------------------------------------------------------------------------------
 
        if( Load_Buffer1)
        begin
            if(count1_dw1 < 2)
            begin
                addr3xb<=addr3xb+r3;
                count1_dw1<=count1_dw1+1;
                
                valid03_dw1<=1'b1;                      // Introduce 2 latency delay for correct fetching.
                valid3_dw1<=valid03_dw1;
            end
        end
        if(valid3_dw1)
        begin
            for(x1=0; x1 < N; x1=x1+1)
            begin
                Buffer1a [x1*width+:width] <= data_out3xb[(N-1-x1)*width+:width] ;
            end
            valid4_dw1<=1'b1; valid3_dw1<=1'b0; valid03_dw1<=1'b0;
        end
        
        if(valid4_dw1)
        begin
            for(x2=0; x2 < N; x2=x2+1)
            begin
                Buffer1b [x2*width+:width] <= data_out3xb[(N-1-x2)*width+:width] ;
               
            end
            valid5_dw1<=1'b1; valid4_dw1<=1'b0;
        end        
        if(valid5_dw1)
        begin
            for(x3=0; x3 < N; x3=x3+1)
            begin
                Buffer1c [x3*width+:width] <= data_out3xb[(N-1-x3)*width+:width] ;
            end
            Load_Buffer1<=1'b0; count1_dw1<=0;                                 // Enters only before beginning of a cycle for PRELOADING.
            valid5_dw1<=1'b0;
            
            addr3xb<=r3b + next_addr_dw1;                                        // Make addr=2r=36 bcoz next address(row) fetched after 0,18,36 will be 54, so keep it 12.
             
  //````````````````````````````````````````````````` Turning on BRAMs with KERNEL VALUES AND BN CONSTANTS IN MAC (once every channel) ````````````````````````````````````````````
            en4xa<=1'b1; wen4xa<=1'b0;
            en5xa<=1'b1; wen5xa<=1'b0; 
            
            Start_Dwr18<=1'b1; Enable_MAC1<=1'b1; valid_in1_dwr6<=1'b1;
            
        end    
    
        
        if(Start_Dwr18)
        begin
            if(max_cyc1 < MAX_CYC_DWR18)
            begin
                Buffer1a <= Buffer1a >> SHIFT_DWR6_COEFF;
                Buffer1b <= Buffer1b >> SHIFT_DWR6_COEFF;
                Buffer1c <= Buffer1c >> SHIFT_DWR6_COEFF;
            end
            if(max_cyc1 < MAX_CYC_DWR18)
                max_cyc1 <= max_cyc1 +1;
            else
                max_cyc1<=0;
            
            if(valid_out1_dwr6)
            begin   
                if(ACC1 > MAX)
                    data_in6xa [((wr_ptr1)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1)*width) +: width]<= ACC1[width-1:0];
                    
                if(SUM2 > MAX)
                    data_in6xa [((wr_ptr1+1)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+1)*width) +: width]<= ACC2[width-1:0];
                    
                if(ACC3 > MAX)
                    data_in6xa [((wr_ptr1+2)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+2)*width) +: width]<= ACC3[width-1:0];
                    
                if(ACC4 > MAX)
                    data_in6xa [((wr_ptr1+3)*width) +: width]<= MAX;
                else
                    data_in6xa [((wr_ptr1+3)*width) +: width]<= ACC4[width-1:0];
                
                if(wr_ptr1 < WR_PTR_MAX_BLK_R3)
                begin    
                    wr_ptr1<=wr_ptr1+4;      
                end
                if(wr_ptr1 == WR_PTR_MAX_BLK_R3)
                begin                                      
                    wr_ptr1<=0;
                    dwr18_op_row <= dwr18_op_row + 1;
                    
                    for(x4=N-12; x4 < N; x4=x4+1)
                    begin
                        data_in6xa [(x4*width) +: width]<=ACC4[width-1:0];      // Replicate last pixel to rest 12 columns, in the same cycle when last 4 pixels are generated
                    end
                    valid2_dwr6<=1'b1; wen6xa <= 1'b1;   // ✅ wen arrives as 1 exactly in valid2_dwr6 cycle.
                    
                    // start writing data into bram 6x
                        
                    if(first_write_dwr18)
                    begin
                        addr6xa <= next_addr_dw1;
                        first_write_dwr18 <= 1'b0;
                    end 
                         
                    else if(addr6xa <= next_addr_dw1 + ROW_LOADER_COEFF_R3)             // addr6xa<=M-3*r3-1;
                        addr6xa <= addr6xa + r3 ;
                        
                    else if(k4< r3-1)
                    begin
                        k4<=k4+1;
                        addr6xa <= next_addr_dw1+ k4+1;
                    end
                    
                    else                    //1 channel completely stored : Load last 12 rows.
                    begin
                        
                        dwr18_op_channel<= dwr18_op_channel+1;
                        next_addr_dw1<=next_addr_dw1+M;
                       
                        dwr18_op_row<=0;
                        
                        Buffer1a<=0; Buffer1b<=0; Buffer1c<=0; Cache1a<=0; Cache1b<=0;  Load_Buffer1<=1'b0; Load_Cache1<=1'b0;
                        valid2_dwr6<=1'b0; LOAD_CACHE_FROM_BRAM1<=1'b0; SWAP_N_LOAD1<=1'b0; LOAD_BUFFER_FROM_Cache1<=1'b0;
                        valid_next1_dw1<=1'b0; valid_next3_dw1<=1'b0; valid_next3_dw1<=1'b0; valid_next0_dw1<=1'b0; 
                        Start_Dwr18<=1'b0; wr_ptr1<=0; max_cyc1<=0; Enable_MAC1<=1'b0; valid_in1_dwr6<=1'b0;
                        k3<=0; k4<=0;
                        
                        //--------------------------------------------------For replication at the end of channel ----------------------------
                        REPLICATE_LAST_ROWS_BLK1<=1'b1; count2_dw1<=0;
                        first_rep_write1<=1'b1;
                        
                        addr6xb<=M-kr3+ next_addr_dw1;        // M-37
                        addr6xa<= next_addr_dw1+M-r3b;        // write from M-36 onwards
                        //--------------------------------------------------------------------------------------------------------------------------
                    end
                end    
    //------------------------------------------------------------------ PART 3 : STORNG THE DWR18 IN BRAM 6--------------------------------------------------          
                if(valid2_dwr6)
                begin
                    wen6xa      <= 1'b0;   // stop after one write
                    valid2_dwr6 <= 1'b0;
                end                  
                    
                         
            end
        
//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
            
//------------------------------------------------------------------------- PART 4: LAODING BUFFER AND CACHE AFTER ROW COMPLETION --------------------------------------------------
            if(max_cyc1==MAX_CYC_DWR18-3)
            begin
                if(addr3xb  <= next_addr_dw1 + addr3_r18_MAX)
                begin
                    addr3xb<=addr3xb+r3;
                    SWAP_N_LOAD1<=1'b1;
                end
                else if (k3 < r3-1)
                begin
                    addr3xb<=next_addr_dw1+k3+kr3;
                    k3<=k3+1;
                    LOAD_CACHE_FROM_BRAM1<=1'b1; valid_next0_dw1<=1'b1;
                    LOAD_BUFFER_FROM_Cache1<=1'b1;
                end
            
            end
            
            if(max_cyc1==MAX_CYC_DWR18)
            begin
                if(SWAP_N_LOAD1)
                begin
                    Buffer1a <= Buffer1b ;
                    Buffer1b <= Buffer1c ; 
                    for(x5=0; x5 < N; x5=x5+1)
                    begin
                        Buffer1c [x5*width+:width] <= data_out3xb[(N-1-x5)*width+:width] ;
                    end
                    SWAP_N_LOAD1<=1'b0;
                end
                
                if(LOAD_BUFFER_FROM_Cache1)
                begin
                    Buffer1a<=Cache1a;
                    Buffer1b<=Cache1b;
                    for(x6=0; x6 < N; x6=x6+1)
                    begin
                        Buffer1c [x6*width+:width] <= data_out3xb[(N-1-x6)*width+:width] ;
                    end
                    
                    LOAD_BUFFER_FROM_Cache1<=1'b0;
                end
            
            
            end
            if(LOAD_CACHE_FROM_BRAM1 && (k3 < r3-1))                // Load only when k3<4 else that means channel is completed
            begin
                if(valid_next0_dw1)
                begin
                    temp_addr1<=addr3xb ;
                    addr3xb<= next_addr_dw1+ k3+1;
                    valid_next1_dw1<=1'b1; valid_next0_dw1<=1'b0;
                end
                if(valid_next1_dw1)
                begin
                    addr3xb<=addr3xb + r3;
                    valid_next2_dw1<=1'b1; valid_next1_dw1<=1'b0;
                end
                
                if(valid_next2_dw1)
                begin
                    for(x7=0; x7 < N; x7=x7+1)
                    begin
                        Cache1a [x7*width+:width] <= data_out3xb[(N-1-x7)*width+:width] ;
                    end
                    valid_next3_dw1<=1'b1; valid_next2_dw1<=1'b0;
                    addr3xb<=temp_addr1;              // Loading addr3b with its previous value
                end
                
                 if(valid_next3_dw1)
                begin
                    for(x8=0; x8 < N; x8=x8+1)
                    begin
                        Cache1b [x8*width+:width] <= data_out3xb[(N-1-x8)*width+:width] ;
                    end
                    LOAD_CACHE_FROM_BRAM1<=1'b0; valid_next3_dw1<=1'b0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
                end
                       
            end
                          
        end
 //-------------------------------------------------------------- PART 5: REPLICATE LAST 36 ROWS TO MATCH IMAGE SIZE after Channel Completion --------------------------------------------------
        if(REPLICATE_LAST_ROWS_BLK1)
        begin
            valid6_dw1 <= 1'b1;   // 1-cycle delay for BRAM B output
            if(valid6_dw1)
            begin
                if(first_rep_write1)
                begin
                   
                    // BRAM A sees: addr=M=2r, wen=0 this cycle (wen takes effect next)
                    data_in6xa     <= data_out6xb;  // latch row 51 data
                    wen6xa         <= 1'b1;         // arms wen (takes effect next cycle)
                    first_rep_write1<= 1'b0;
                    
                end
        
                else if(addr6xa < next_addr_dw1-1)   
                begin
                    
                    addr6xa <= addr6xa + 1;
                end
        
                else if(dwr18_op_channel == Const_Cby4)
                begin
                    wen6xa                   <= 1'b0;
                    BLK1_STATUS              <= 1'b1;
                    DWR6_STATUS              <= 1'b1;
                    valid6_dw1               <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK1 <= 1'b0;
                    en6xb                    <= 1'b1;
                    addr6xa                  <=0;
                    STAGE3_STATUS            <=1'b1;
                end
        
                else
                begin
                    wen6xa                   <= 1'b0;
                    REPLICATE_LAST_ROWS_BLK1 <= 1'b0;
                    valid6_dw1               <= 1'b0;
                    en6xb                    <= 1'b0;
                    first_write_dwr18        <= 1'b1;
                    addr6xa                  <= next_addr_dw1;
                    
                    Load_knl_dwr18           <=1'b1;
                    Load_Cache1              <=1'b1;
         
                    addr3xb <= next_addr_dw1 + 1;
                end
            end
    end 
    
    end
    
        
   


 
 
 
 //----------------------------------------------------------- S T A G E  4 : POINTWISE CONVOLUTION  (1/2)  ------------------------------------------------------------------------------------
        if(STAGE3_STATUS)
        begin
            pw_knl_addr1<= pw_knl_init1;
            pw_op_row_status<=0; pw_op_channel_status<=0; i1<=0; i2<=0; k1<=0; k2<=0;
            
            STAGE3_STATUS<=1'b0;
  
            valid_in1<=1'b1; valid_in3<=1'b1;valid_in4<=1'b1;valid_in5<=1'b1;   // To maintain initial PIPELINE Latency (triggered only once at the start)
            next_row<=1'b0;
            i1<=0; i2<=0; k1<=0; k2<=0;
            t2_load_pw<=0;
            count_up1<=1'b0;
          //*******Initialize pw load,mul1,2,knl reg with zeros********//
            for (n = 0; n < N; n = n + 1)
            begin
                load_pw1[n] <= {PW_ACCUM_W{1'b0}}; mul1[n] <= {2*width{1'b0}}; mul2[n] <= {2*width{1'b0}};  pixa[n] <= {width{1'b0}};  pixb[n] <= {width{1'b0}};    
            end
            knl_pw1[0]<={width{1'b0}}; knl_pw1[1]<={width{1'b0}};
               
         //***********BRAM 1 for PW pixels**********//   
            en1a<=1'b1;wen1a<=1'b0; addr1a<=0;
            en1b<=1'b1;wen1b<=1'b0; addr1b<=M;
                   
          //**********BRAM 7 for PW kernels********//  
            en7wa<=1'b1; wen7wa<=1'b0; addr7wa<=0; en7wb<=1'b1; wen7wb<=1'b0; addr7wb<=1; 
            en7xa<=1'b1; wen7xa<=1'b0; addr7xa<=0; en7xb<=1'b1; wen7xb<=1'b0; addr7xb<=1; 
            en7ya<=1'b1; wen7ya<=1'b0; addr7ya<=0; en7yb<=1'b1; wen7yb<=1'b0; addr7yb<=1; 
            en7za<=1'b1; wen7za<=1'b0; addr7za<=0; en7zb<=1'b1; wen7zb<=1'b0; addr7zb<=1; 
            
          //********** BRAM 3 for Pw output *******//
            en3xa<=1'b0; wen3xa<=1'b1; addr3xa<=-1; 
            en3ya<=1'b0; wen3ya<=1'b1; addr3ya<=-1; 
           
         //********** BRAM 6 for Pw output *******//
            en6xa<=1'b0; wen6xa<=1'b1; addr6xa<=-1;
            en6ya<=1'b0; wen6ya<=1'b1; addr6ya<=-1; 
            
                
        
        
            START_STAGE4<=1'b1;
        end
        
        
        
        
        if(START_STAGE4)
        begin
            if( (t2_load_pw==LAST_ADDR_OF_ROW_ARRIVAL2) && (N>64))
                valid_in1<=1'b0;
            
            if(!valid_in1)
            begin
                if(count_up1 < cycle_pw)
                begin
                    count_up1<=count_up1 + 1; 
                end
                else
                begin
                    valid_in1<=1'b1;
                    count_up1<=1'b0;
                end
            end
                    
//-------------------------------------------------------------- PART 1: PW CONVOLUTION BRAM Address Updation Logic ---------------------------------------------------------------
    
            if(pw_knl_addr1 <= max_knl_addr_pw1 )
            begin
                if(valid_out1)
                begin
                    if(pw_op_row_status <= M-1)
                    begin
                        if(addr7wb < pw_knl_addr1)
                        begin
                            addr1a<=addr1a + m ; addr1b<=addr1b + m ;       // Fetching input rows
                            
                            // Fetching kernels
                            addr7wa<=addr7wa + 2; addr7wb<=addr7wb + 2;
                            addr7xa<=addr7xa + 2; addr7xb<=addr7xb + 2;
                            addr7ya<=addr7ya + 2; addr7yb<=addr7yb + 2;
                            addr7za<=addr7za + 2; addr7zb<=addr7zb + 2;
                        end          
                    end
                                 
                    end
                    if(t2_load_pw==T2_MAX-4)
                    begin            ///////////////    Row Completion   /////////////////
                        if (pw_op_row_status != M-1) 
                        begin
                            addr7wa<=pw_knl_addr1 -(Const_2C-1); addr7wb<=pw_knl_addr1 - (Const_2C-2);            
                            addr7xa<=pw_knl_addr2 -(Const_2C-1); addr7xb<=pw_knl_addr2 - (Const_2C-2);
                            addr7ya<=pw_knl_addr3 -(Const_2C-1); addr7yb<=pw_knl_addr3 - (Const_2C-2);
                            addr7za<=pw_knl_addr4 -(Const_2C-1); addr7zb<=pw_knl_addr4 - (Const_2C-2);
                            
                            
                            pw_op_row_status<=pw_op_row_status +1;                      // Update row completion status
                            addr1a<=pw_op_row_status + 1;addr1b<=pw_op_row_status + M + 1;    
                            
                            S4_CHANNEL_STATUS<=S4_CHANNEL_STATUS+4;                 // For FPGA
                        end
                                        
                        else     ////////////////// Channel Completion /////////////////
                        begin
                            pw_op_channel_status<=pw_op_channel_status+4;               // Keeps Record of Pw Output Channels
                            pw_op_row_status<=0;                                        //Because now we move to next kernel which will convolve the same image matrix
                           
                            pw_knl_addr1<=pw_knl_addr1 + Const_2C;                               // Moves to max address of the next kernel
                            pw_knl_addr2<=pw_knl_addr2 + Const_2C;
                            pw_knl_addr3<=pw_knl_addr3 + Const_2C;
                            pw_knl_addr4<=pw_knl_addr4 + Const_2C;
                            
                            
                            addr1a<=0; addr1b<=M;
                            
                            addr7wa<=addr7wa+2; addr7wb<=addr7wb+2;
                            addr7xa<=addr7xa+2; addr7xb<=addr7xb+2;
                            addr7ya<=addr7ya+2; addr7yb<=addr7yb+2;
                            addr7za<=addr7za+2; addr7zb<=addr7zb+2;
                        end
                       
                    end   
            end
            else       ////////////////////// PW (1/2) CONVOLUTION Completion /////////////////////
            begin
                if(t2_load_pw==T2_MAX)
                begin
                    STAGE4_STATUS<=1'b1;
                    
                end
             
               
            end
            
    
//---------------------------------------------------------------------------------------------------------------------------------------------------------------   
   
 //---------------------------------------------------------------------- PART 2 : Loading pixels and knl values from BRAM 1 and BRAM7 in all 4 arrays parallely --------------------------------------------------------------------      
      
        if(valid_out3)
        begin
            for (x = 0; x < N; x = x + 1) 
            begin
                pixa[N-1-x] <= data_out1a[x*width +: width];  pixb[N-1-x] <= data_out1b[x*width +: width];       
            end
            
            knl_pw1[0]<=data_out7wa;  knl_pw1[1]<=data_out7wb;
            knl_pw2[0]<=data_out7xa;  knl_pw2[1]<=data_out7xb;
            knl_pw3[0]<=data_out7ya;  knl_pw3[1]<=data_out7yb;
            knl_pw4[0]<=data_out7za;  knl_pw4[1]<=data_out7zb;
        end
        
//----------------------------------------------------------------------- PART 3 : Multiply and Accumulate operationS for all 4 Channels parallelly ------------------------------------------------------------------
        
        
        if(valid_out4)
        begin
            if(cycle_pw==1)
            begin
             for ( w1 = 0; w1 < 64; w1 = w1 + 1)
                begin
                    mul1[w1] <= pixa[w1] * knl_pw1[0];
                    mul2[w1] <= pixb[w1] * knl_pw1[1];
                    
                    mul3[w1] <= pixa[w1] * knl_pw2[0];
                    mul4[w1] <= pixb[w1] * knl_pw2[1];
                    
                    mul5[w1] <= pixa[w1] * knl_pw3[0];
                    mul6[w1] <= pixb[w1] * knl_pw3[1];
                    
                    mul7[w1] <= pixa[w1] * knl_pw4[0];
                    mul8[w1] <= pixb[w1] * knl_pw4[1];
            
                end
            end
            else
            begin
                for ( w1 = 0; w1 < 64; w1 = w1 + 1)
                begin
                    mul1[i1+w1] <= pixa[i1+w1] * knl_pw1[0];
                    mul2[i1+w1] <= pixb[i1+w1] * knl_pw1[1];
                    
                    mul3[i1+w1] <= pixa[i1+w1] * knl_pw2[0];
                    mul4[i1+w1] <= pixb[i1+w1] * knl_pw2[1];
                    
                    mul5[i1+w1] <= pixa[i1+w1] * knl_pw3[0];
                    mul6[i1+w1] <= pixb[i1+w1] * knl_pw3[1];
                    
                    mul7[i1+w1] <= pixa[i1+w1] * knl_pw4[0];
                    mul8[i1+w1] <= pixb[i1+w1] * knl_pw4[1];
                end
                    
                if ( (N > 64) && (k1 < (cycle_pw-1)) && (t2_load_pw!=T2_MAX-1))
                begin
                    i1<= i1 + 64;
                    k1<=k1+1;
                end
                else
                begin
                    i1<=0;
                    k1<=0;
                end 
            end
        end
        if(valid_out5)
        begin
            if(cycle_pw==1)
            begin
                for ( w2 = 0; w2 < 64; w2 = w2 + 1)
                begin
                    
                    load_pw1[w2]<=mul1[w2] + mul2[w2] + load_pw1[w2];
                    load_pw2[w2]<=mul3[w2] + mul4[w2] + load_pw2[w2];
                    load_pw3[w2]<=mul5[w2] + mul6[w2] + load_pw3[w2];
                    load_pw4[w2]<=mul7[w2] + mul8[w2] + load_pw4[w2];
                    
                end
            end
            else
            begin
                for ( w2 = 0; w2 < 64; w2 = w2 + 1)
                begin
                    
                    load_pw1[i2+w2]<=mul1[i2+w2] + mul2[i2+w2] + load_pw1[i2+w2];
                    load_pw2[i2+w2]<=mul3[i2+w2] + mul4[i2+w2] + load_pw2[i2+w2];
                    load_pw3[i2+w2]<=mul5[i2+w2] + mul6[i2+w2] + load_pw3[i2+w2];
                    load_pw4[i2+w2]<=mul7[i2+w2] + mul8[i2+w2] + load_pw4[i2+w2];
                    
                end
                  
                if ( (N > 64) && (k2 < (cycle_pw-1)) && (t2_load_pw!=T2_MAX))
                begin
                    i2<= i2 + 64;
                     k2<=k2+1;
                end
                else
                begin
                    i2<=0;
                    k2<=0;
                end 
            end
            t2_load_pw<=t2_load_pw+1; 
        end
            /////////////////////// ////// ROW COMPLETION LOGIC ////////////////////////////////// 
                 /////////////////////////////  Store the PW output Row in Bram3 + Make Load Reg fil with 0s /////////////////////
        if(t2_load_pw==T2_MAX)
        begin
            for (y = 0; y < N; y = y + 1)
            begin
                // -------- Saturation / Clipping  for all 4 load_pw and storing--------
                if(load_pw1[N-1-y] > MAX)
                begin
                    data_in3xa[y*width +: width] <= MAX;
                end
                else if(load_pw1[N-1-y] < MIN)
                begin
                    data_in3xa[y*width +: width] <= MIN;
                end
                else
                begin
                    data_in3xa[y*width +: width] <= load_pw1[N-1-y][width-1:0];
                end
                
                
                if(load_pw2[N-1-y] > MAX)
                begin
                    data_in3ya[y*width +: width] <= MAX;
                end
                else if(load_pw2[N-1-y] < MIN)
                begin 
                    data_in3ya[y*width +: width] <= MIN;
                end
                else
                begin
                    data_in3ya[y*width +: width] <= load_pw2[N-1-y][width-1:0];
                end
                
                
                if(load_pw3[N-1-y] > MAX)
                begin
                    data_in6xa[y*width +: width] <= MAX;
                end
                else if(load_pw3[N-1-y] < MIN)
                begin
                    data_in6xa[y*width +: width] <= MIN;  
                end
                else
                begin
                    data_in6xa[y*width +: width] <= load_pw3[N-1-y][width-1:0];
                end
                
                
                if(load_pw4[N-1-y] > MAX)
                begin
                   
                    data_in6ya[y*width +: width] <= MAX;
                end
                else if(load_pw4[N-1-y] < MIN)
                begin     
                    data_in6ya[y*width +: width] <= MIN;
                end
                else
                begin
                    data_in6ya[y*width +: width] <= load_pw4[N-1-y][width-1:0];
                end
                
                // -------- Clear all 4 accumulator parallely --------
                load_pw1[y] <= {PW_ACCUM_W{1'b0}};
                load_pw2[y] <= {PW_ACCUM_W{1'b0}};
                load_pw3[y] <= {PW_ACCUM_W{1'b0}};
                load_pw4[y] <= {PW_ACCUM_W{1'b0}};
            end
    
        // -------- Store completed row in 4 BRAMS --------
            addr3xa <= addr3xa + 1;
            addr3ya <= addr3ya + 1;
            addr6xa <= addr6xa + 1;
            addr6ya <= addr6ya + 1;
    
            t2_load_pw <= 0;
        end    
        
        
        end    
    
    
    
    
    
  
  //--------------------------------------------------------- S T A G E 4 Completion---------------------------------------------------------------------------------------------------------
  
  
  
   



end  // end of global always









function integer logb2;
    input integer value;
    integer i;
    begin
        value = value - 1;
        for (i = 0; value > 0; i = i + 1)
            value = value >> 1;
        logb2 = i;
    end
endfunction

endmodule