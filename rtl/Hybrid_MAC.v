`timescale 1ns / 1ps

module Hybrid_MAC
#(parameter PW=8, FW=8)
( 
input clk,
input reset,
input Enable_MAC,                           // Enable PIN to save power
input signed [PW-1:0] A0,A1,A2,A3,A4,A5,A6,A7,A8,
input signed [PW-1:0] K0,K1,K2,K3,K4,K5,K6,K7,K8,
input signed [PW+FW-1:0] A,B,                      // BNorm Constants Q8.8 form
output reg signed [PW-1:0]Result
    );
    
    
    (* use_dsp = "yes" *)reg signed [2*PW-1:0] P1,P2,P3,P4,P5,P6,P7,P8,P9;
    (* keep = "true" *) reg signed [2*PW+1:0] S1,S2,S3;
    (* keep = "true" *) reg signed [2*PW+3:0] ACC;
    (* use_dsp = "yes" *)reg signed [3*PW+FW+3:0] ybn1;
    (* keep = "true" *) reg signed [3*PW+FW+4:0] ybn2,Temp;
    
    localparam YBN2_W = 3*PW + FW + 4;
    localparam signed [PW-1:0] MAX = (1 << (PW-1)) - 1;
    
    reg s1,s2,s3,s4,s5,s6;
    
always @(posedge clk)
begin
    if (reset)
    begin
        ACC<=0;
        S1<=0;
        S2<=0;
        S3<=0;
        Result<=0;
        ybn1<=0; ybn2<=0;
        Temp<=0;
        P1<=0;P2<=0;P3<=0;P4<=0;P5<=0;P6<=0;P7<=0;P8<=0;P9<=0;
        s1<=0;s2<=0;s3<=0;s4<=0;s5<=0;s6<=0;
    end
    if(Enable_MAC)
    begin
        P1<=A0*K0;
        P2<=A1*K1;
        P3<=A2*K2; 
        P4<=A3*K3;
        P5<=A4*K4;
        P6<=A5*K5;
        P7<=A6*K6;
        P8<=A7*K7;
        P9<=A8*K8;
        s1<=1'b1;
        
        if(s1)
        begin
            S1<=P1+P2+P3;
            S2<=P4+P5+P6;
            S3<=P7+P8+P9;
            s2<=1'b1;
        end
        
        if(s2)
        begin
            ACC<=S1+S2+S3;
            s3<=1'b1;
        end
        if(s3)
        begin
            ybn1<=(A*ACC)>>>FW;
            s4<=1'b1;
        end
        if(s4)
        begin
            ybn2<=ybn1+(B >>>FW);
            s5<=1'b1;
        end
        
        if(s5)
        begin
            Temp<=ybn2[YBN2_W] ? 0:ybn2;
            s6<=1'b1;
        end
        if(s6)
        begin
            if(Temp > MAX)
                Result <= MAX;        
            else
                Result <= Temp[PW-1:0];
        end
    end

end


endmodule
