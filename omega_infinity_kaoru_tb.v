// =====================================================================
// Testbench -- OMEGA INFINITY KAORU programmable Circuit-SAT stage
// Programs the example instance of Fig. 1:
//   F(v) = (v1 AND NOT v2) OR (v2 XOR v3)
// then applies GRID tap states and checks SAT/UNSAT decisions.
// =====================================================================
`timescale 1ns/1ps

module omega_infinity_kaoru_tb;

    localparam integer N  = 64;   // Boolean inputs (GRID taps)
    localparam integer G  = 8;    // gates available in this instance
    localparam integer GW = 3;
    localparam integer IW = 9;

    // Node indices of gate outputs in the instance being programmed
    localparam integer G0 = 64;   // N + 0 : NOT v2
    localparam integer G1 = 65;   // N + 1 : v1 AND G0
    localparam integer G2 = 66;   // N + 2 : v2 XOR v3
    localparam integer G3 = 67;   // N + 3 : G1 OR G2 (circuit output)

    reg             clk = 0, rst_n;
    reg  [N-1:0]    grid_taps = {N{1'b0}};
    reg             grid_stable = 0;
    reg             prog_en = 0;
    reg  [IW-1:0]   prog_addr = 0;
    reg  [GW-1:0]   prog_op = 0;
    reg  [IW-1:0]   prog_a = 0, prog_b = 0, prog_out = 0;
    reg             prog_out_we = 0;
    wire            sat, unsat, done;
    wire [N-1:0]    assignment;

    omega_infinity_kaoru #(.N(N), .G(G), .GW(GW), .IW(IW)) dut (
        .clk(clk), .rst_n(rst_n),
        .grid_taps(grid_taps), .grid_stable(grid_stable),
        .prog_en(prog_en), .prog_addr(prog_addr), .prog_op(prog_op),
        .prog_a(prog_a), .prog_b(prog_b),
        .prog_out(prog_out), .prog_out_we(prog_out_we),
        .sat(sat), .unsat(unsat), .done(done), .assignment(assignment)
    );

    always #5 clk = ~clk;

    // Program one gate: index, opcode, operandA, operandB
    task prog_gate(input [IW-1:0] idx, input [GW-1:0] op,
                   input [IW-1:0] a, input [IW-1:0] b);
        begin
            @(negedge clk);
            prog_en = 1; prog_addr = idx; prog_op = op; prog_a = a; prog_b = b;
        end
    endtask

    // Apply a GRID conduction state and report the decision
    task apply_grid(input [2:0] v321);
        begin
            @(negedge clk);
            prog_en = 0;
            grid_taps = {{(N-3){1'b0}}, v321};
            grid_stable = 1;
            @(posedge clk); #1;
            $display("v3v2v1=%b -> F=%b  SAT=%b UNSAT=%b DONE=%b",
                     v321, dut.node[G3], sat, unsat, done);
            @(negedge clk) grid_stable = 0;
        end
    endtask

    integer errors = 0;
    integer i;
    // Truth table for F=(v1 & ~v2) | (v2 ^ v3), tt[k] = F(v3v2v1 = k)
    // k=0..7 : 0,1,1,1,1,1,0,0
    reg tt [0:7];

    initial begin
        tt[0]=0; tt[1]=1; tt[2]=1; tt[3]=1;
        tt[4]=1; tt[5]=1; tt[6]=0; tt[7]=0;

        // explicit reset pulse (generates the negedge the DUT needs)
        rst_n = 1; #1; rst_n = 0;
        repeat (2) @(negedge clk); rst_n = 1;

        // program F(v) = (v1 AND NOT v2) OR (v2 XOR v3)
        prog_gate(0, 3'd6, 9'd1, 9'd0);    // G0 = NOT v2 (tap index 1)
        prog_gate(1, 3'd0, 9'd0, G0[8:0]); // G1 = v1 AND G0
        prog_gate(2, 3'd2, 9'd1, 9'd2);    // G2 = v2 XOR v3
        prog_gate(3, 3'd1, G1[8:0], G2[8:0]); // G3 = G1 OR G2
        @(negedge clk);
        prog_en = 1; prog_out = 9'd3; prog_out_we = 1;  // output = gate index 3 (node N+3)
        @(negedge clk); prog_en = 0; prog_out_we = 0;

        // sweep all 8 conduction states of the GRID
        for (i = 0; i < 8; i = i + 1) begin
            apply_grid(i[2:0]);
            if (sat !== tt[i]) errors = errors + 1;
        end

        if (errors == 0) $display("TEST PASSED: all 8 GRID states decided correctly");
        else             $display("TEST FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
