//=============================================================================
//                        ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 29-Aug-24  DWW     1  Initial creation
//
// 01-Sep-24  DWW     2  Registered the "monitor" input stream to ease
//                       timing-closure.
//
// 17-Oct-24  DWW     3  Changed the packet counters from 32-bits to 64-bits
//=============================================================================

/*

   This module is intended to monitor the "axis_tx" input of a CMAC and
   count packets by packet size. 

*/

module ns_txpkt_counter # (parameter DW=512)
(
    input clk,
    
    // This can be asynchronous to clk.   This module will sync it.
    input aresetn,

    // The AXI stream that we're monitoring
    (* X_INTERFACE_MODE = "monitor" *)
    input[DW-1:0]   monitor_tdata,
    input[DW/8-1:0] monitor_tkeep,
    input           monitor_tlast,
    input           monitor_tvalid,
    input           monitor_tready,

    // Number of frame-data packets
    output reg[63:0] fd_packets,
    
    // Number of meta-data packet
    output reg[63:0] md_packets,

    // Number of frame-counter packets
    output reg[63:0] fc_packets,
    
    // Number of unrecognized packets
    output reg[63:0] other_packets
);

// The lengths of the packets we care about
localparam FRAME_DATA_LEN = 4096 + 64;
localparam META_DATA_LEN  =  128 + 64;
localparam FRAME_CTR_LEN  =    4 + 64;

// This is the "aresetn" signal after being synchronized to "clk"
wire resetn;

// Part of the input AXI stream is registered
reg           reg_tlast;
reg           reg_tvalid;
reg           reg_tready;

// We also register the number of 1 bits in tkeep
reg[15:0]     reg_tkeep_count;

//=============================================================================
// one_bits() - This function counts the '1' bits in a field
//=============================================================================
integer i;
function[15:0] one_bits(input[(DW/8)-1:0] field);
begin
    one_bits = 0;
    for (i=0; i<(DW/8); i=i+1) one_bits = one_bits + field[i];
end
endfunction

//=============================================================================


//=============================================================================
// Register the input stream
//=============================================================================
always @(posedge clk) begin

    if (resetn == 0) begin
        reg_tlast       <= 0;
        reg_tvalid      <= 0;
        reg_tready      <= 0;
        reg_tkeep_count <= 0;
    end

    else begin
        reg_tlast       <= monitor_tlast;
        reg_tvalid      <= monitor_tvalid;
        reg_tready      <= monitor_tready;
        reg_tkeep_count <= one_bits(monitor_tkeep);
    end

end
//=============================================================================


//=============================================================================
// synchronize the 'aresetn' signal to 'resetn'
//=============================================================================
xpm_cdc_async_rst #
(
    .DEST_SYNC_FF(4),
    .INIT_SYNC_FF(0),
    .RST_ACTIVE_HIGH(0)
)
xpm_cdc_async_rst_inst
(
    .src_arst (aresetn),
    .dest_clk (clk    ),
    .dest_arst(resetn )
);
//=============================================================================


// Total length of the packet except for the cycle with TLAST asserted
reg[15:0] partial_length;

// This tracks the length of the packet as we see each data-cycle
wire[15:0] packet_length = partial_length + reg_tkeep_count;


//=============================================================================
//  This accumulates the packet length and, on the last data-cycle of the
//  packet, increments one of the packet counters
//=============================================================================
always @(posedge clk) begin

    // If reset is asserted...
    if (resetn == 0) begin
        fd_packets     <= 0;
        md_packets     <= 0;
        fc_packets     <= 0;
        other_packets  <= 0;
        partial_length <= 0;
    end

    // Otherwise: is this a data handshake?
    else if (reg_tvalid & reg_tready) begin

        // If this is the last data-cycle of the packet...
        if (reg_tlast) begin
            
            // Increment the appropriate counter
            if (packet_length == FRAME_DATA_LEN)
                fd_packets <= fd_packets + 1;
            
            else if (packet_length == META_DATA_LEN)
                md_packets <= md_packets + 1;
            
            else if (packet_length == FRAME_CTR_LEN)
                fc_packets <= fc_packets + 1;
            
            else
                other_packets <= other_packets + 1;
            
            // And reset this for the next packet
            partial_length <= 0;
        
        // Otherwise, this was not the last data-cycle of the packet...
        end else
            partial_length <= packet_length;
    end

end
//=============================================================================


endmodule