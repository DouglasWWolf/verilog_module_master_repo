//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 12-Jun-26  DWW     1  Initial creation
//
// 23-Jun-26  DWW     2  Fixed a bug in the reset logic that cause "occupancy"
//                       to not be reset properly
//====================================================================================

/*
    A very simple FIFO
*/

module ldp_fstat_fifo # (parameter WIDTH=1, parameter DEPTH=16)
(
    input   clk,
    input   resetn,

    input  [WIDTH-1:0] data_in,
    output [WIDTH-1:0] data_out,

    // Valid and ready for the input side
    input   in_valid,
    output  in_ready,

    // Valid and ready for the output side
    output  out_valid,
    input   out_ready
);

// How many items are currently in the FIFO?
reg[$clog2(DEPTH):0] occupancy;

// The index of the next items to be input and output
reg[$clog2(DEPTH):0] in_idx, out_idx;

// The FIFO itself
reg[WIDTH-1:0] fifo [0:DEPTH-1];

// We're ready to receive data when there is room to store it
assign in_ready = (occupancy < DEPTH || out_ready);

// We're ready to output data when there is data in the FIFO
assign out_valid = (occupancy != 0);

// "data_out" always holds the next item to come out of the FIFO
assign data_out = (occupancy == 0) ? 0 : fifo[out_idx];

// Handshakes for both the input and output side
wire hsk_in  = in_ready  & in_valid;
wire hsk_out = out_ready & out_valid;

//=============================================================================
// Basic FIFO management
//=============================================================================
always @(posedge clk) begin

    if (resetn == 0) begin
        in_idx    <= 0;
        out_idx   <= 0;
        occupancy <= 0;
    end

    else begin

        // Handle an incoming handshake
        if (hsk_in) begin
            fifo[in_idx] <= data_in;
            in_idx       <= (in_idx == DEPTH-1) ? 0 : in_idx + 1;
        end

        // Handle an outgoing handshake
        if (hsk_out) begin
            out_idx <= (out_idx == DEPTH-1) ? 0 : out_idx + 1;
        end

        // Keep track of how many items are in the FIFO
        occupancy <= occupancy + hsk_in - hsk_out;
        
    end
end
//=============================================================================


endmodule