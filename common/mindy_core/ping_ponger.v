//=============================================================================
//                     ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 15-Feb-24  DWW     1  Initial creation
//=============================================================================

/*
    The packetizes an incoming data-stream, and writes groups of packets to the
    output streams in a ping-pong fashion
*/


module ping_ponger
(
    input clk, resetn,

    //=========================================================================
    // Input stream of frame data
    //=========================================================================
    input[511:0]   AXIS_IN_TDATA,
    input          AXIS_IN_TVALID,
    output         AXIS_IN_TREADY,
    //=========================================================================

    //=========================================================================
    // Two output data streams to carry frame data
    //=========================================================================
    output[511:0]   AXIS_OUT0_TDATA,    AXIS_OUT1_TDATA,
    output          AXIS_OUT0_TLAST,    AXIS_OUT1_TLAST,
    output          AXIS_OUT0_TVALID,   AXIS_OUT1_TVALID,
    input           AXIS_OUT0_TREADY,   AXIS_OUT1_TREADY,
    //=========================================================================

    // The outgoing packet size, in bytes
    input [15:0] PACKET_SIZE,

    // The number of packets in a ping-pong group
    input [31:0] PACKETS_PER_GROUP
);  


// Number of data-cycles that comprise an outgoing packet
wire[7:0] cycles_per_packet = PACKET_SIZE / 64;

// The current data-cycle number being output.  Runs from 1 to "cycles_per_packet"
reg[7:0] data_cycle_count;

// This is asserted on the last clock cycle of every outgoing packet
wire last_cycle = (data_cycle_count == cycles_per_packet);

// This selects which output stream we're writing to
reg output_select;

// The output TDATA is driven directly from the input stream
assign AXIS_OUT0_TDATA = (output_select == 0) ? AXIS_IN_TDATA : 0;
assign AXIS_OUT1_TDATA = (output_select == 1) ? AXIS_IN_TDATA : 0;

// The output TVALID is driven by the input TVALID, gated by "output_select"
assign AXIS_OUT0_TVALID = AXIS_IN_TVALID & (output_select == 0);
assign AXIS_OUT1_TVALID = AXIS_IN_TVALID & (output_select == 1);

// The output TLAST signals are asserted on the last cycle of every packet
assign AXIS_OUT0_TLAST = last_cycle & AXIS_OUT0_TVALID;
assign AXIS_OUT1_TLAST = last_cycle & AXIS_OUT1_TVALID;

// The TREADY signal on the input stream is driven by one of the output streams
assign AXIS_IN_TREADY = (output_select == 0) ? AXIS_OUT0_TREADY : AXIS_OUT1_TREADY;

// Create some convenient shortcuts to the output TVALID, TLAST, and TREADY
wire axis_out_tvalid = (output_select == 0) ? AXIS_OUT0_TVALID : AXIS_OUT1_TVALID;
wire axis_out_tlast  = (output_select == 0) ? AXIS_OUT0_TLAST  : AXIS_OUT1_TLAST;
wire axis_out_tready = (output_select == 0) ? AXIS_OUT0_TREADY : AXIS_OUT1_TREADY;

//=============================================================================
// This block watches for the handshake on the last data-cycle of outgoing
// packets.  Every "PACKETS_PER_GROUP" packets, it switches the "output_select"
// register from 0 to 1 (or vice-versa)
//=============================================================================
reg[15:0] packet_counter;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        packet_counter <= 1;
        output_select  <= 0;
    end
    
    else if (axis_out_tvalid & axis_out_tready & axis_out_tlast) begin
        if (packet_counter < PACKETS_PER_GROUP)
            packet_counter <= packet_counter + 1;
        else begin
            packet_counter <= 1;
            output_select  <= ~output_select;
        end
    end

end
//=============================================================================


//=============================================================================
// This block counts data-cycles on the output stream to ensure that TLAST
// is asserted on the last data-cycle of every outgoing packet
//=============================================================================
always @(posedge clk) begin

    // If we're in reset, clear the data-cycle count to 1
    if (resetn == 0) begin
        data_cycle_count <= 1;
    
    // Otherwise, we're not in reset, so...
    end else begin

        // If a data-cycle was just transferred from input to output,
        // count the number of data-cycles that have gone out in this
        // packet
        if (axis_out_tvalid & axis_out_tready) begin
            if (data_cycle_count < cycles_per_packet)            
                data_cycle_count <= data_cycle_count + 1;
            else
                data_cycle_count <= 1;
        end
    end
end
//=============================================================================


endmodule
