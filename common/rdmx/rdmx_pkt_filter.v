//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 11-Nov-23  DWW     1  Initial creation
// 12-Jan-24  DWW  1001  Changed name to RDMX
//===================================================================================================

/*


    This module receives packets on an AXI-Stream bus and throws away any packet
    that isn't an RDMX packet.   Valid RDMX packets are passed on to the output.
 

*/

module rdmx_pkt_filter #
(
    parameter DATA_WBITS         = 512,
    parameter DATA_WBYTS         = (DATA_WBITS / 8),
    parameter LOCAL_SERVER_PORT  = 11111,

    // <<< This must match REMOTE_SERVER_PORT in rdmx_xmit.v !! >>>
    parameter REMOTE_SERVER_PORT = 32002    
)
(
    input wire  clk, resetn,

    //==========================================================================
    //                     AXI Stream for incoming RDMX packets
    //==========================================================================
    input[DATA_WBITS-1:0]  AXIS_IN_TDATA,
    input[DATA_WBYTS-1:0]  AXIS_IN_TKEEP,
    input                  AXIS_IN_TLAST,
    input                  AXIS_IN_TUSER,
    input                  AXIS_IN_TVALID,

    output                 AXIS_IN_TREADY,
    //==========================================================================


    //==========================================================================
    //                     AXI Stream for incoming RDMX packets
    //==========================================================================
    output[DATA_WBITS-1:0] AXIS_OUT_TDATA,
    output[DATA_WBYTS-1:0] AXIS_OUT_TKEEP,
    output                 AXIS_OUT_TLAST,
    output                 AXIS_OUT_TUSER,
    output                 AXIS_OUT_TVALID,    
    input                  AXIS_OUT_TREADY
    //==========================================================================

);

// This is the magic number for an RDMX packet
localparam RDMX_MAGIC = 16'h0122;

// The entire output stream (other than TVALID) is driven by the input stream
assign AXIS_OUT_TDATA = AXIS_IN_TDATA;
assign AXIS_OUT_TUSER = AXIS_IN_TUSER;
assign AXIS_OUT_TKEEP = AXIS_IN_TKEEP;
assign AXIS_OUT_TLAST = AXIS_IN_TLAST;
assign AXIS_IN_TREADY = AXIS_OUT_TREADY;

// The state of the input state-machine
reg[1:0] ism_state;

// These are the possible states of ism_state
localparam ISM_STARTING     = 0;
localparam ISM_WAIT_FOR_HDR = 1;
localparam ISM_XFER_PACKET  = 2;

// AXIS_IN_TDATA comes to us in little-endian order.  Create a byte-swapped version of it
// so we can easily break out the fields of the header in big-endian
wire[DATA_WBITS-1:0] AXIS_IN_TDATA_swapped;
genvar i;
for (i=0; i<DATA_WBYTS; i=i+1) begin
    assign AXIS_IN_TDATA_swapped[i*8 +:8] = AXIS_IN_TDATA[(DATA_WBYTS-1-i)*8 +:8];
end 

// These are the fields that comprise an RDMX packet header
wire[ 6 *8-1:0] eth_dst_mac, eth_src_mac;
wire[ 2 *8-1:0] eth_frame_type;
wire[ 2 *8-1:0] ip4_ver_dsf, ip4_length, ip4_id, ip4_flags, ip4_ttl_prot, ip4_checksum;
wire[ 2 *8-1:0] ip4_srcip_h, ip4_srcip_l, ip4_dstip_h, ip4_dstip_l;
wire[ 2 *8-1:0] udp_src_port, udp_dst_port, udp_length, udp_checksum;
wire[ 2 *8-1:0] rdmx_magic;
wire[ 8 *8-1:0] rdmx_target_addr;
wire[12 *8-1:0] rdmx_reserved;

// This is the 64-byte packet header for an RDMX packet.  This is an ordinary UDP packet
// with 22 bytes of RDMX header fields appended
assign
{
    // Ethernet header fields - 14 bytes
    eth_dst_mac,
    eth_src_mac,
    eth_frame_type,

    // IPv4 header fields - 20 bytes
    ip4_ver_dsf,
    ip4_length,
    ip4_id,
    ip4_flags,
    ip4_ttl_prot,
    ip4_checksum,
    ip4_srcip_h,
    ip4_srcip_l,
    ip4_dstip_h,
    ip4_dstip_l,

    // UDP header fields - 8 bytes
    udp_src_port,
    udp_dst_port,
    udp_length,
    udp_checksum,
    
    // RDMX header fields - 22 bytes
    rdmx_magic,
    rdmx_target_addr,
    rdmx_reserved

} = AXIS_IN_TDATA_swapped;

// The first cycle of a packet is considered an RDMX packet if the protocol is
// UDP (i.e., 17) and the port number is one of the RDMX UDP port numbers
wire is_rdmx_imm = (ip4_ttl_prot[7:0] == 17)
                 & (udp_dst_port      == LOCAL_SERVER_PORT || udp_dst_port == REMOTE_SERVER_PORT)
                 & (rdmx_magic        == RDMX_MAGIC);
reg  is_rdmx_reg;

// This will be high on any data-cycle of an RDMX packet
wire is_rdmx = ((ism_state == ISM_WAIT_FOR_HDR) & is_rdmx_imm)
             | ((ism_state == ISM_XFER_PACKET ) & is_rdmx_reg);

// AXIS_OUT_TVALID is gated by "is_rdmx".   When "is_rdmx" is low, TVALID can 
// never go high.
assign AXIS_OUT_TVALID = (AXIS_IN_TVALID & is_rdmx);

//====================================================================================
// The input state-machine: reads incoming packets and passes them to the output
// only if we think they are RDMX packets
//====================================================================================
always @(posedge clk) begin
    if (resetn == 0) begin
        ism_state <= ISM_STARTING;

    end else case (ism_state)

        // Here we're just coming out of reset
        ISM_STARTING: 
            begin
                ism_state <= ISM_WAIT_FOR_HDR;
            end

        // Wait for a packet header to arrive
        ISM_WAIT_FOR_HDR:
            if (AXIS_IN_TREADY & AXIS_IN_TVALID) begin
                is_rdmx_reg <= is_rdmx_imm;
                if (AXIS_IN_TLAST == 0) ism_state <= ISM_XFER_PACKET;
            end

        // Here we transfer the rest of the packet
        ISM_XFER_PACKET:
            if (AXIS_IN_TREADY & AXIS_IN_TVALID & AXIS_IN_TLAST) begin
                ism_state <= ISM_WAIT_FOR_HDR;
            end

    endcase
end
//====================================================================================


endmodule
