
//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 25-Jul-23  DWW  1000  Initial creation
//
// 12-Jan-24  DWW  1001  Changed name to RDMX
//
// 05-Nov-24  DWW  1002  Added "user-field" to the RDMX header
//
// 26-Mar-25  DWW  1003  Fixed AXIS_TX_TKEEP width from "DW" to "DW/8"
//====================================================================================
/*

    This module formats an AXI stream as a UDP packet.  It does this by buffering up
    an incoming packet (in a FIFO) while it counts the number of bytes in the
    packet.  Once the incoming packet has arrived, the packet-length is written into
    its own FIFO.

    The thread that reads those two FIFOs builds a valid RDMX header header then
    outputs the RDMX header (in its own data-cycle) followed by the packet data.

    <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
    <> An RDMX header is:                                                           <>
    <>     An ordinary 42-byte ethernet/IP/UDP header                               <>
    <>     A  2-byte magic number (0x0122)
    <>     A  8-byte target address                                                 <>
    <>     12 bytes of reserved data, always 0                                      <>
    <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

    The incoming AXIS_DATA data should be byte packed; only the last beat (the beat with
    AXIS_DATA_TLAST asserted) may have a TKEEP bits set to 0.
    
    Notable busses:

        AXIS_DATA feeds the input of the packet-data FIFO
        AXIS_PLEN feeds the input of the packet-length FIFO
        AXIS_ADDR feeds the input of the target-address FIFO

        fpdout is the output of the packet-data FIFO
        fplout is the output of the packet-length FIFO
        ftaout is the output of the target-address FIFO

*/
module rdmx_xmit_be # 
(
    // This can be either "common_clock" or "independent clock".   Use
    // "independent clock" if the two clock inputs are not being fed 
    // from the same clock source!
    parameter FIFO_CLOCK_MODE = "independent_clock",

    // This is the width of the incoming and outgoing data bus in bits
    parameter DW = 512,

    // Width of an AXI address in bits
    parameter AW = 64,

    // Width of the "User field" in the RDMX header, in bits
    parameter UW = 32,

    // Last octet of the source MAC address
    parameter[ 7:0] SRC_MAC = 2,    
    
    // The source IP address
    parameter[ 7:0] SRC_IP0 = 10,
    parameter[ 7:0] SRC_IP1 = 1,
    parameter[ 7:0] SRC_IP2 = 1,
    parameter[ 7:0] SRC_IP3 = 2,

    // The destiniation IP address
    parameter[ 7:0] DST_IP0 = 10,
    parameter[ 7:0] DST_IP1 = 1,
    parameter[ 7:0] DST_IP2 = 1,
    parameter[ 7:0] DST_IP3 = 255,
    
    // The source UDP ports
    parameter[15:0] SOURCE_PORT = 1000,
       
    // The destination port on the remote server.  
    // << THIS MUST MATCH "REMOTE_SERVER_PORT" in rdmx_pkt_filter.v >>>
    parameter[15:0] REMOTE_SERVER_PORT = 32002,

    // This must be at least as large as the number of the smallest packets that
    // can fit into the data FIFO.   Min is 16.  
    parameter MAX_PACKET_COUNT = 256,

    // This should be at minimum MAX_PACKET_COUNT * # of data-cycles in the smallest
    // incoming packet.  This number must be large enough to accomodate the number of
    // data cycles in the largest incoming packet.
    parameter DATA_FIFO_DEPTH = 256

    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
    //>> DATA_FIFO_DEPTH / MAX_PACKET_COUNT = # of cycles in the smallest incoming data packet
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
) 
(
    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 src_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF AXIS_PLEN:AXIS_ADDR:AXIS_DATA, ASSOCIATED_RESET src_resetn" *)
    input src_clk,
    input src_resetn,


    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 dst_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF AXIS_TX" *)
    input dst_clk,
    
    //==========================================================================
    //             Packet-length input stream, synchronous to src_clk
    //==========================================================================
    input  [15:0] AXIS_PLEN_TDATA,
    input         AXIS_PLEN_TVALID,
    output        AXIS_PLEN_TREADY,
    //==========================================================================

    //==========================================================================
    //           Target address input stream, synchronous to src_clk
    //==========================================================================
    input  [(UW+AW)-1:0] AXIS_ADDR_TDATA,
    input                AXIS_ADDR_TVALID,
    output               AXIS_ADDR_TREADY,
    //==========================================================================


    //==========================================================================
    //              Packet-data input stream, synchronous to src_clk
    //==========================================================================
    input  [DW-1:0] AXIS_DATA_TDATA,
    input           AXIS_DATA_TLAST,
    input           AXIS_DATA_TVALID,
    output          AXIS_DATA_TREADY,
    //==========================================================================


    //==========================================================================
    //     Outgoing UDP/RDMX packet, synchronous to dst_clk
    //==========================================================================
    output [DW-1:0]   AXIS_TX_TDATA,
    output [DW/8-1:0] AXIS_TX_TKEEP,
    output            AXIS_TX_TLAST,
    output            AXIS_TX_TVALID,
    input             AXIS_TX_TREADY,
    //==========================================================================

    // This is high whenever AXIS_DATA is trying to write to a full FIFO
    output packet_data_fifo_full
);

// anding a packet length with this mask will give the the remainder
// of "payload_length / width-of-the-data-bus-in-bytes"
localparam REMAINDER_MASK = (1 << $clog2(DW/8)) - 1;

//=============================================================================
// This synchronizes src_resetn to dst_clk, resulting in dst_resetn
//=============================================================================
wire dst_resetn;
xpm_cdc_async_rst #
(
    .DEST_SYNC_FF(4),
    .INIT_SYNC_FF(0),
    .RST_ACTIVE_HIGH(0)
)
reset_synchronizer
(
    .src_arst (src_resetn),    
    .dest_arst(dst_resetn), 
    .dest_clk (dst_clk   )   
);
//=============================================================================
 

//==================  The output of the packet-data FIFO  ==================
wire[DW-1:0] fpdout_tdata;
wire         fpdout_tvalid;
wire         fpdout_tlast;
wire         fpdout_tready;
//==========================================================================


//=============  This is the output of the packet-length FIFO  =============
reg [15:0] fplout_tdata_latched;
wire[15:0] fplout_tdata;
wire       fplout_tvalid;
wire       fplout_tready;
//==========================================================================


// This is the length of the payload data as reported by AXIS_PLEN
wire[15:0] payload_length = (fplout_tvalid & fplout_tready) ? fplout_tdata : fplout_tdata_latched;


//============  This is the output of the target-address FIFO  =============
reg [(UW+AW)-1:0] ftaout_tdata_latched;
wire[(UW+AW)-1:0] ftaout_tdata;
wire              ftaout_tvalid;
reg               ftaout_tready;
//==========================================================================


// The length (in bytes) of a standard header for an IP packet
localparam IP_HDR_LEN = 20;

// The length (in bytes) of a standard header for a UDP packet
localparam UDP_HDR_LEN = 8;

// The total number of bytes in the RDMX header, including reserved space
localparam RDMX_HDR_LEN = 22;

// This is the state of the primary state machine
reg[1:0] fsm_state;

// The statically declared ethernet header fields
localparam[47:0] eth_dst_mac    = {48'hFFFFFFFFFFFF};
localparam[47:0] eth_src_mac    = {40'hC400AD0000, SRC_MAC};
localparam[15:0] eth_frame_type = 16'h0800;

// The statically declared IPv4 header fields
localparam[15:0] ip4_ver_dsf    = 16'h4500;
localparam[15:0] ip4_id         = 16'hDEAD;
localparam[15:0] ip4_flags      = 16'h4000;
localparam[15:0] ip4_ttl_prot   = 16'h4011;
localparam[15:0] ip4_srcip_h    = {SRC_IP0, SRC_IP1};
localparam[15:0] ip4_srcip_l    = {SRC_IP2, SRC_IP3};
localparam[15:0] ip4_dstip_h    = {DST_IP0, DST_IP1};
localparam[15:0] ip4_dstip_l    = {DST_IP2, DST_IP3};

// The statically declared UDP header fields
localparam[15:0] udp_src_port   = SOURCE_PORT;
localparam[15:0] udp_dst_port   = REMOTE_SERVER_PORT;
localparam[15:0] udp_checksum   = 0;

// 2 bytes of magic number
localparam[15:0] rdmx_magic = 16'h0122;

// 6 bytes of reserved area in the RDMX header
localparam[6*8-1:0] rdmx_reserved = 0;

// Compute both the IPv4 packet length and UDP packet length
wire[15:0]       ip4_length     = IP_HDR_LEN + UDP_HDR_LEN + RDMX_HDR_LEN + payload_length;
wire[15:0]       udp_length     =              UDP_HDR_LEN + RDMX_HDR_LEN + payload_length;

// Compute the 32-bit version of the IPv4 header checksum
wire[31:0] ip4_cs32 = ip4_ver_dsf
                    + ip4_id
                    + ip4_flags
                    + ip4_ttl_prot
                    + ip4_srcip_h
                    + ip4_srcip_l
                    + ip4_dstip_h
                    + ip4_dstip_l
                    + ip4_length;

// Compute the 16-bit IPv4 checksum
wire[15:0] ip4_checksum = ~(ip4_cs32[15:0] + ip4_cs32[31:16]);


// This is the target address of this outgoing packet
wire[63:0] rdmx_target_addr = (ftaout_tready & ftaout_tvalid) ?
                               ftaout_tdata[63:0] : ftaout_tdata_latched[63:0];

// This is the RDMX user field of the outgoing packet
wire[31:0] rdmx_user_field  = (ftaout_tready & ftaout_tvalid) ?
                               ftaout_tdata[95:64] : ftaout_tdata_latched[95:64];


// This number increments by 1 on every packet
reg[15:0] rdmx_seq_num;

// This is the 64-byte packet header for an RDMX packet
wire[DW-1:0] pkt_header =
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
    rdmx_seq_num,
    rdmx_user_field,
    rdmx_reserved
};


// The Ethernet IP sends the bytes from least-sigificant-byte to most-significant-byte.  
// This means we need to create a little-endian (i.e., reversed) version of our packet 
// header.
wire[DW-1:0] pkt_header_le;
genvar i;
for (i=0; i<(DW/8); i=i+1) begin
    assign pkt_header_le[i*8 +:8] = pkt_header[(DW/8-1-i)*8 +:8];
end 

// Determine how many "leftover" bytes there are after dividing
// payload_length by DW (i.e., data-width)
wire[ 7:0] extra_bytes  = (payload_length & REMAINDER_MASK);

//=====================================================================================================================
// In state 1, we drive AXIS_TX with the outgoing RDMX header.
// In state 2, AXIS_TX is driven directly from the output of the packet-data FIFO.
//=====================================================================================================================
assign AXIS_TX_TDATA = (fsm_state == 1) ? pkt_header_le
                     : (fsm_state == 2) ? fpdout_tdata
                     : 0;

assign AXIS_TX_TLAST = (fsm_state == 2 & fpdout_tlast);

assign AXIS_TX_TKEEP = (AXIS_TX_TLAST & (extra_bytes != 0)) ? (1 << extra_bytes)-1 : -1;


assign AXIS_TX_TVALID = (fsm_state == 1) ? (fplout_tvalid & fplout_tready)
                      : (fsm_state == 2) ? fpdout_tvalid
                      : 0;

assign fpdout_tready  = (dst_resetn == 1) & (fsm_state == 2) & AXIS_TX_TREADY;
//=====================================================================================================================

// This goes high to indicate that the packet data FIFO is full
assign packet_data_fifo_full = AXIS_DATA_TVALID & ~AXIS_DATA_TREADY;

//=====================================================================================================================
// This state machine has 3 states:
//
//   0 = We just came out of reset.  This state initializes things.
//
//   1 = Waiting for a "packet length" to arrive on AXIS_PLEN.  When it does, the RDMX header is emitted
//       on AXIS_TX.
//
//   2 = Copying the output of the packet-data FIFO to the AXIS_TX output stream
//
//
// Since logic outside of this routine buffers up the entire packet prior to presenting us with a packet-length on
// the fplout bus, we may assume that an incoming cycle of user data (on fpdout_tdata) will be available on every
// consecutive cycle after receiving a packet-length.
//=====================================================================================================================

// We are able to receive data from AXIS_LEN in state 1 only when the TX bus is ready for us to send
assign fplout_tready = (dst_resetn == 1 & fsm_state == 1 & AXIS_TX_TREADY);

always @(posedge dst_clk) begin
    
    if (dst_resetn == 0) begin
        ftaout_tready <= 0;
        fsm_state     <= 0;
    end
    
    else case(fsm_state) 
        
        // Here we're coming out of reset
        0:  begin
                ftaout_tready <= 1;
                rdmx_seq_num  <= 1;
                fsm_state     <= 1;
            end


        // Here we're waiting for a packet-length to arrive on the fplout bus.  While
        // we're waiting, we will capture the first data-cycle of target-address FIFO
        1:  begin

                // While we're waiting for data to arrive on AXIS_PLEN, read the
                // first cycle of target-address from its FIFO. 
                //
                // The target address could arrive on the same data-cycle as the
                // packet-length, or it could arrive earlier.
                if (ftaout_tready & ftaout_tvalid) begin
                    ftaout_tdata_latched <= ftaout_tdata;
                    ftaout_tready        <= 0;                     
                end

                // If a packet-length arrives, the RDMX packet header is immediately
                // emitted, and we go to state 2 to wait for the packet to complete
                if (fplout_tready & fplout_tvalid) begin
                    fplout_tdata_latched <= fplout_tdata;
                    rdmx_seq_num         <= rdmx_seq_num + 1;
                    fsm_state            <= 2;
                end
            end


        // When we receive the last data-cycle of the packet, go back to state 1
        2:  if (fpdout_tvalid & fpdout_tready & fpdout_tlast) begin
                ftaout_tready <= 1;
                fsm_state     <= 1;
            end
        
    endcase
end
//=====================================================================================================================




//====================================================================================
// This FIFO holds the incoming packet data
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (DATA_FIFO_DEPTH), 
   .TDATA_WIDTH     (DW),     
   .FIFO_MEMORY_TYPE("auto"),       
   .PACKET_FIFO     ("false"),      
   .USE_ADV_FEATURES("0000"),        
   .CDC_SYNC_STAGES (2),            
   .CLOCKING_MODE   (FIFO_CLOCK_MODE)

)
packet_data_fifo
(
    // Clock and reset
   .s_aclk   (src_clk   ),                       
   .m_aclk   (dst_clk   ),             
   .s_aresetn(src_resetn),

    // The input bus to the FIFO is the AXIS_DATA input stream
   .s_axis_tdata (AXIS_DATA_TDATA ),
   .s_axis_tvalid(AXIS_DATA_TVALID),
   .s_axis_tlast (AXIS_DATA_TLAST ),
   .s_axis_tready(AXIS_DATA_TREADY),

    // The output bus of the FIFO
   .m_axis_tdata (fpdout_tdata ),     
   .m_axis_tvalid(fpdout_tvalid),       
   .m_axis_tlast (fpdout_tlast ),         
   .m_axis_tready(fpdout_tready),

    // Unused input stream signals
   .s_axis_tkeep(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tkeep(),
   .m_axis_tdest(),             
   .m_axis_tid  (),               
   .m_axis_tstrb(), 
   .m_axis_tuser(),         

    // Other unused signals
   .almost_empty_axis(),
   .almost_full_axis(), 
   .dbiterr_axis(),          
   .prog_empty_axis(), 
   .prog_full_axis(), 
   .rd_data_count_axis(), 
   .sbiterr_axis(),
   .wr_data_count_axis(),
   .injectdbiterr_axis(),
   .injectsbiterr_axis()
);
//====================================================================================


//====================================================================================
// This FIFO holds the packet-length of the incoming data packets
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (MAX_PACKET_COUNT),  
   .TDATA_WIDTH     (16),               
   .FIFO_MEMORY_TYPE("auto"),       
   .PACKET_FIFO     ("false"),      
   .USE_ADV_FEATURES("0000"),        
   .CDC_SYNC_STAGES (2),            
   .CLOCKING_MODE   (FIFO_CLOCK_MODE)
)
packet_length_fifo
(
    // Clock and reset
   .s_aclk   (src_clk   ),                       
   .m_aclk   (dst_clk   ),             
   .s_aresetn(src_resetn),

    // The input bus to the FIFO comes straight from the AXIS_PLEN input stream
   .s_axis_tdata (AXIS_PLEN_TDATA ),
   .s_axis_tvalid(AXIS_PLEN_TVALID),
   .s_axis_tready(AXIS_PLEN_TREADY),

    // The output bus of the FIFO
   .m_axis_tdata (fplout_tdata ),     
   .m_axis_tvalid(fplout_tvalid),       
   .m_axis_tready(fplout_tready),     

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),
   .s_axis_tkeep(),
   .s_axis_tlast(),

    // Unused output stream signals
   .m_axis_tdest(),             
   .m_axis_tid  (),               
   .m_axis_tstrb(), 
   .m_axis_tuser(),         
   .m_axis_tkeep(),           
   .m_axis_tlast(),         

    // Other unused signals
   .almost_empty_axis(),
   .almost_full_axis(), 
   .dbiterr_axis(),          
   .prog_empty_axis(), 
   .prog_full_axis(), 
   .rd_data_count_axis(), 
   .sbiterr_axis(),
   .wr_data_count_axis(),
   .injectdbiterr_axis(),
   .injectsbiterr_axis()
);
//====================================================================================


//====================================================================================
// This FIFO holds the user-field and target-address of the incoming data packets
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (MAX_PACKET_COUNT),   
   .TDATA_WIDTH     (UW+AW),        
   .FIFO_MEMORY_TYPE("auto"),       
   .PACKET_FIFO     ("false"),      
   .USE_ADV_FEATURES("0000"),        
   .CDC_SYNC_STAGES (2),            
   .CLOCKING_MODE   (FIFO_CLOCK_MODE)
)
rdmx_addr_fifo
(
    // Clock and reset
   .s_aclk   (src_clk   ),                       
   .m_aclk   (dst_clk   ),             
   .s_aresetn(src_resetn),

    // The input of this FIFO comes from the AXIS_ADDR stream
   .s_axis_tdata (AXIS_ADDR_TDATA ),
   .s_axis_tvalid(AXIS_ADDR_TVALID),
   .s_axis_tready(AXIS_ADDR_TREADY),

    // The output bus of the FIFO
   .m_axis_tdata (ftaout_tdata ),     
   .m_axis_tvalid(ftaout_tvalid),       
   .m_axis_tready(ftaout_tready),     

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),
   .s_axis_tkeep(),
   .s_axis_tlast(),

    // Unused output stream signals
   .m_axis_tdest(),             
   .m_axis_tid  (),               
   .m_axis_tstrb(), 
   .m_axis_tuser(),         
   .m_axis_tkeep(),           
   .m_axis_tlast(),         

    // Other unused signals
   .almost_empty_axis(),
   .almost_full_axis(), 
   .dbiterr_axis(),          
   .prog_empty_axis(), 
   .prog_full_axis(), 
   .rd_data_count_axis(), 
   .sbiterr_axis(),
   .wr_data_count_axis(),
   .injectdbiterr_axis(),
   .injectsbiterr_axis()
);
//====================================================================================

endmodule