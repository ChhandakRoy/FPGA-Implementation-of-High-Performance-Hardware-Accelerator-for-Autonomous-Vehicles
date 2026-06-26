module Bilinear_Interpolation 
#(
  parameter PW = 8,   // pixel width 
  parameter FW = 8    // fractional width
)
(
input  signed [PW-1:0] Qa,Qb,Qc,Qd,
input  [FW-1:0] dx,dy,
input  clk,reset,En,
output reg signed [PW-1:0] P_out
);

// -----------------------------
// Saturation limits
// -----------------------------
localparam signed [PW-1:0] MAX = (1 << (PW-1)) - 1;
localparam signed [PW-1:0] MIN = -(1 << (PW-1));

// -----------------------------
// Registers
// -----------------------------
(* keep = "true" *) reg signed [PW:0] D1,D2;
(* use_dsp = "yes" *) reg signed [FW+PW:0] M1,M2;
(* keep = "true" *) reg signed [FW+PW:0] M1_d1,M2_d2;
(* keep = "true" *) reg signed [PW+1:0] R1,R2,R1_d1,R1_d2;
reg signed [PW+2:0] D3;
(* use_dsp = "yes" *) reg signed [FW+PW+2:0] M3;
(* keep = "true" *)   reg signed [PW+3:0] P;

// delay regs
reg signed [PW-1:0] Qa_d1,Qc_d1,Qa_d2,Qc_d2;
reg [FW-1:0] dx_d1,dy_d1,dy_d2,dy_d3,dy_d4,dy_d5;

// valid pipeline
reg valid1,valid2,valid3,valid4,valid5,valid6;

// -----------------------------
always @(posedge clk)
begin
    if(reset)
    begin
        P_out<=0;
        valid1<=0; valid2<=0; valid3<=0;
        valid4<=0; valid5<=0; valid6<=0; 
    end
    else
    begin
        // ---------------- STAGE 1 ----------------
        if(En)
        begin
            D1 <= Qb - Qa;
            D2 <= Qd - Qc;

            Qa_d1 <= Qa;
            Qc_d1 <= Qc;

            dx_d1 <= dx;
            dy_d1 <= dy;

            valid1 <= 1'b1;
            
             // ---------------- STAGE 2 ----------------
            if(valid1)
            begin
                M1 <= ($signed({1'b0, dx_d1}) * D1) >>> FW;
                M2 <= ($signed({1'b0, dx_d1}) * D2) >>> FW;
        
                Qa_d2 <= Qa_d1;
                Qc_d2 <= Qc_d1;
        
                dy_d2 <= dy_d1;
        
                valid2 <= 1'b1;
            end
            // ---------------- STAGE 3 ----------------
            if(valid2)
            begin
               R1 <= $signed(Qa_d2) + $signed(M1);                              
               R2 <= $signed(Qc_d2) + $signed(M2);
        
               dy_d3 <= dy_d2;
        
               valid3 <= 1'b1;
            end
            // ---------------- STAGE 4 ----------------
            if(valid3)
            begin
                D3 <= $signed(R2) - $signed(R1);
                R1_d1 <= R1;
        
                dy_d4 <= dy_d3;
        
                valid4 <= 1'b1;
            end
            // ---------------- STAGE 5 ----------------
            if(valid4)
            begin
                M3 <= ($signed({1'b0, dy_d4}) * D3) >>> FW;
                R1_d2 <= R1_d1;
        
                valid5 <= 1'b1;
            end
            // ---------------- STAGE 6 ----------------
            if(valid5)
            begin
                P <= R1_d2 + M3;
    
                valid6 <= 1'b1;
            end
            // ---------------- OUTPUT ----------------
    
            if(valid6)
            begin
                if(P > MAX)
                    P_out <= MAX;
                else if(P < MIN)
                    P_out <= MIN;
                else
                    P_out <= P[PW-1:0];
            end
        end
       

       
    end
end

endmodule