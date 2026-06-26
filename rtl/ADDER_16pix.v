`timescale 1ns / 1ps

module ADDER_16pix
 #( parameter PW = 16)
(
    input                          clk,
    input                          rst,
    input                          en,
    input signed [16*PW-1:0]       Vector,
    output reg signed [PW+3:0]     out                      //Produces UNCLIPPED pixels
);

    localparam SUMW = PW + 4;

   

    localparam signed [SUMW-1:0] MAX_VAL = (1 <<< (PW-1)) - 1;

    localparam signed [SUMW-1:0] MIN_VAL = -(1 <<< (PW-1));

    wire signed [PW-1:0] p0;
    wire signed [PW-1:0] p1;
    wire signed [PW-1:0] p2;
    wire signed [PW-1:0] p3;
    wire signed [PW-1:0] p4;
    wire signed [PW-1:0] p5;
    wire signed [PW-1:0] p6;
    wire signed [PW-1:0] p7;
    wire signed [PW-1:0] p8;
    wire signed [PW-1:0] p9;
    wire signed [PW-1:0] p10;
    wire signed [PW-1:0] p11;
    wire signed [PW-1:0] p12;
    wire signed [PW-1:0] p13;
    wire signed [PW-1:0] p14;
    wire signed [PW-1:0] p15;
    
    // stage-1 : 16 -> 8
    (* keep = "true" *) reg signed [PW:0] s1_0,s1_1,s1_2,s1_3;
    (* keep = "true" *) reg signed [PW:0] s1_4,s1_5,s1_6,s1_7;

    // stage-2 : 8 -> 4
    (* keep = "true" *) reg signed [PW+1:0] s2_0,s2_1,s2_2,s2_3;

    // stage-3 : 4 -> 2
    (* keep = "true" *) reg signed [PW+2:0] s3_0,s3_1;

    

    assign p0  = Vector[(0 *PW) +: PW];
    assign p1  = Vector[(1 *PW) +: PW];
    assign p2  = Vector[(2 *PW) +: PW];
    assign p3  = Vector[(3 *PW) +: PW];
    assign p4  = Vector[(4 *PW) +: PW];
    assign p5  = Vector[(5 *PW) +: PW];
    assign p6  = Vector[(6 *PW) +: PW];
    assign p7  = Vector[(7 *PW) +: PW];
    assign p8  = Vector[(8 *PW) +: PW];
    assign p9  = Vector[(9 *PW) +: PW];
    assign p10 = Vector[(10*PW) +: PW];
    assign p11 = Vector[(11*PW) +: PW];
    assign p12 = Vector[(12*PW) +: PW];
    assign p13 = Vector[(13*PW) +: PW];
    assign p14 = Vector[(14*PW) +: PW];
    assign p15 = Vector[(15*PW) +: PW];

   
   
   
   
    always @(posedge clk)
    begin

        if(rst)
        begin

            s1_0 <= 0;  s1_1 <= 0;
            s1_2 <= 0;  s1_3 <= 0;
            s1_4 <= 0;  s1_5 <= 0;
            s1_6 <= 0;  s1_7 <= 0;

            s2_0 <= 0;  s2_1 <= 0;
            s2_2 <= 0;  s2_3 <= 0;

            s3_0 <= 0;  s3_1 <= 0;

            out <= 0;

        end
        else if(en)
        begin
       
            // ====================================================
            // Stage-1
            // ====================================================

            s1_0 <= p0  + p1;
            s1_1 <= p2  + p3;
            s1_2 <= p4  + p5;
            s1_3 <= p6  + p7;
            s1_4 <= p8  + p9;
            s1_5 <= p10 + p11;
            s1_6 <= p12 + p13;
            s1_7 <= p14 + p15;

            // ====================================================
            // Stage-2
            // ====================================================

            s2_0 <= s1_0 + s1_1;
            s2_1 <= s1_2 + s1_3;
            s2_2 <= s1_4 + s1_5;
            s2_3 <= s1_6 + s1_7;

            // ====================================================
            // Stage-3
            // ====================================================

            s3_0 <= s2_0 + s2_1;
            s3_1 <= s2_2 + s2_3;

            // ====================================================
            // Stage-4
            // ====================================================

            out<= s3_0 + s3_1;

      
        end
    end

endmodule