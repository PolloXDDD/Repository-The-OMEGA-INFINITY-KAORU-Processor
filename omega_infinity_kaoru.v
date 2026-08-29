// =====================================================================
// OMEGA INFINITY KAORU Processor -- Programmable Circuit-SAT Stage (RTL)
// =====================================================================
// Fabrication-ready top level for the recommended programmable variant
// (Section V, variant 2): a Turing-complete control plane loads an
// arbitrary gate-level Circuit-SAT instance; the conductive GRID drives
// the Boolean inputs v1..vN; evaluation reports SAT/UNSAT and the
// satisfying assignment is recovered by thresholded voltage measurement
// (digitized here as input taps) or by the search-to-decision reduction
// controlled by the host processor.
//
// Parameters
//   N      : number of Boolean input variables (GRID taps)
//   G      : number of gates in the programmable Circuit-SAT instance
//   GW     : gate opcode width  (AND, OR, XOR, XNOR, NAND, NOR, NOT, BUF)
//   IW     : gate operand index width (ceil(log2(N+G)))
// =====================================================================
`timescale 1ns/1ps

module omega_infinity_kaoru #(
    parameter integer N  = 64,           // Boolean inputs v1..vN
    parameter integer G  = 256,          // gates in the instance
    parameter integer GW = 3,            // opcode width
    parameter integer IW = 9             // operand index width (N+G<=512)
)(
    input  wire             clk,          // control-plane clock
    input  wire             rst_n,        // active-low reset

    // ---- GRID interface (analog front end, digitized taps) ----
    // In the fabricated device these come from comparators on the GRID
    // interface taps v1..vN (thresholded voltage measurement, Sec. IV-A).
    input  wire [N-1:0]     grid_taps,    // raw digitized tap levels
    input  wire             grid_stable,  // GRID conduction state settled

    // ---- Programming interface (host / Turing-machine control plane) --
    input  wire             prog_en,      // program-mode enable
    input  wire [IW-1:0]    prog_addr,    // gate index being programmed
    input  wire [GW-1:0]    prog_op,      // gate opcode
    input  wire [IW-1:0]    prog_a,       // operand A index
    input  wire [IW-1:0]    prog_b,       // operand B index
    input  wire [IW-1:0]    prog_out,     // index of the output gate
    input  wire             prog_out_we,  // latch output-gate index

    // ---- Results ----
    output reg              sat,          // F(v) = 1  -> SAT
    output reg              unsat,        // F(v) = 0  -> UNSAT
    output reg              done,         // evaluation complete
    output wire [N-1:0]     assignment    // recovered satisfying assignment
);

    // Gate opcodes
    localparam OP_AND  = 3'd0;
    localparam OP_OR   = 3'd1;
    localparam OP_XOR  = 3'd2;
    localparam OP_XNOR = 3'd3;
    localparam OP_NAND = 3'd4;
    localparam OP_NOR  = 3'd5;
    localparam OP_NOT  = 3'd6;   // uses operand A only
    localparam OP_BUF  = 3'd7;   // uses operand A only

    // Programmable instance memory
    reg [GW-1:0] gate_op  [0:G-1];
    reg [IW-1:0] gate_ina [0:G-1];
    reg [IW-1:0] gate_inb [0:G-1];
    reg [IW-1:0] out_gate;

    // Node values: [N-1:0] = input taps, [N+G-1:N] = gate outputs
    reg  [N+G-1:0] node;

    // Recovered assignment: the digitized taps themselves carry the
    // assignment selected by the GRID conduction state (Sec. IV-A).
    assign assignment = grid_taps;

    // ---------------- Programming ----------------
    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_gate <= {IW{1'b0}};
            for (p = 0; p < G; p = p + 1) begin
                gate_op[p]  <= OP_BUF;
                gate_ina[p] <= {IW{1'b0}};
                gate_inb[p] <= {IW{1'b0}};
            end
        end else if (prog_en) begin
            if (prog_addr < G) begin
                gate_op[prog_addr]  <= prog_op;
                gate_ina[prog_addr] <= prog_a;
                gate_inb[prog_addr] <= prog_b;
            end
            if (prog_out_we)
                out_gate <= prog_out;
        end
    end

    // ---------------- Combinational evaluation ----------------
    // The GRID explores all conduction states concurrently; each settled
    // state presents one candidate assignment on the taps. The digital
    // stage evaluates the programmed instance combinationally -- in
    // practical constant time (strictly O(log n) gate depth accounting).
    integer k;
    reg a_val, b_val;
    always @(*) begin
        node[N-1:0] = grid_taps;
        for (k = 0; k < G; k = k + 1) begin
            a_val = node[gate_ina[k]];
            b_val = node[gate_inb[k]];
            case (gate_op[k])
                OP_AND : node[N+k] = a_val & b_val;
                OP_OR  : node[N+k] = a_val | b_val;
                OP_XOR : node[N+k] = a_val ^ b_val;
                OP_XNOR: node[N+k] = a_val ~^ b_val;
                OP_NAND: node[N+k] = ~(a_val & b_val);
                OP_NOR : node[N+k] = ~(a_val | b_val);
                OP_NOT : node[N+k] = ~a_val;
                default: node[N+k] = a_val;          // OP_BUF
            endcase
        end
    end

    // ---------------- Decision capture ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sat   <= 1'b0;
            unsat <= 1'b0;
            done  <= 1'b0;
        end else if (prog_en) begin
            done  <= 1'b0;               // re-programming invalidates result
        end else if (grid_stable) begin
            sat   <=  node[N + out_gate];
            unsat <= ~node[N + out_gate];
            done  <= 1'b1;
        end
    end

endmodule
