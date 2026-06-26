`timescale 1ns / 1ps


module Latency_tracker #(
    parameter LATENCY = 0
)(
    input  wire clk,
    input  wire rst,
    input  wire valid_in,
    output wire valid_out
);

 reg [LATENCY-1:0] shift_reg;

generate

    // -------------------------
    // ZERO LATENCY
    // -------------------------
    if(LATENCY == 0)
    begin
        assign valid_out = valid_in;
    end

    // -------------------------
    // NON-ZERO LATENCY
    // -------------------------
    else
    begin

        always @(posedge clk)
        begin
            if(rst)
                shift_reg <= {LATENCY{1'b0}};
            else
                shift_reg <= {shift_reg[LATENCY-2:0], valid_in};
        end

        assign valid_out = shift_reg[LATENCY-1];

    end

endgenerate

endmodule

