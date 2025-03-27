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
// 19-Feb-24  DWW  1002  Split front-end from back-end and added mixed clocks
//
// 04-May-24  DWW  1003  Fixed bug in rdmx_xmit_fe.v that would very occassionally
//                       attempt to write to the address FIFO before it was ready to
//                       receive data.   Added "addr_fifo_debug" for future 
//                       experiments
//
// 05-Nov-24  DWW  1004  Removed obsolete signal "addr_fifo_debug"
//                       Now stamping frame-number into the packet header
//
// 26-Mar-24  DWW  1005  Added missing port S_AXI_ARSIZE
//====================================================================================

/*

    This module formats an AXI write-burst as a UDP packet.  It does this by buffering
    up an incoming packet (in a FIFO) while it counts the number of bytes in the
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

    The incoming S_AXI_WDATA data should be byte packed; only the last beat (the
    beat with S_AXI_WLAST asserted) may have a S_AXI_WSTRB bits set to 0.

*/

module rdmx_xmit #
(
    // This width of the incoming and outgoing data bus in bits
    parameter DW = 512,

    // Width of an AXI address in bits
    parameter AW = 64,

    // The AWUSER field is used to keep track of the frame number
    parameter UW = 32,

    // This can be either "common_clock" or "independent clock".   Use
    // "independent clock" if the two clock inputs are not being fed 
    // from the same clock source!
    parameter FIFO_CLOCK_MODE = "independent_clock",

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
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET src_resetn" *)
    input src_clk,
    input src_resetn,

    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 dst_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF AXIS_TX" *)
    input dst_clk,
  
   //=================  This is the main AXI4-slave interface  ================
    
    // "Specify write address"              -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_AWADDR,
    input[UW-1:0]                           S_AXI_AWUSER,
    input                                   S_AXI_AWVALID,
    input[3:0]                              S_AXI_AWID,
    input[7:0]                              S_AXI_AWLEN,
    input[2:0]                              S_AXI_AWSIZE,
    input[1:0]                              S_AXI_AWBURST,
    input                                   S_AXI_AWLOCK,
    input[3:0]                              S_AXI_AWCACHE,
    input[3:0]                              S_AXI_AWQOS,
    input[2:0]                              S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input[DW-1:0]                           S_AXI_WDATA,
    input[DW/8-1:0]                         S_AXI_WSTRB,
    input                                   S_AXI_WVALID,
    input                                   S_AXI_WLAST,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_ARADDR,
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,
    input                                   S_AXI_ARLOCK,
    input[3:0]                              S_AXI_ARID,
    input[7:0]                              S_AXI_ARLEN,
    input[2:0]                              S_AXI_ARSIZE,
    input[1:0]                              S_AXI_ARBURST,
    input[3:0]                              S_AXI_ARCACHE,
    input[3:0]                              S_AXI_ARQOS,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY,
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

// Wires to connect the packet-length stream
wire [15:0]           AXIS_PLEN_TDATA;
wire                  AXIS_PLEN_TVALID;
wire                  AXIS_PLEN_TREADY;

// Wires to connect the user-data/target-address stream
wire [(UW+AW)-1:0]    AXIS_ADDR_TDATA;
wire                  AXIS_ADDR_TVALID;
wire                  AXIS_ADDR_TREADY;

// Wires to connect the data stream
wire [DW-1:0]         AXIS_DATA_TDATA;
wire                  AXIS_DATA_TLAST;
wire                  AXIS_DATA_TVALID;
wire                  AXIS_DATA_TREADY;

rdmx_xmit_fe #
(
    .DW(DW),
    .AW(AW),
    .UW(UW)
)
front_end
(
    .clk    (src_clk),
    .resetn (src_resetn),
    
    .S_AXI_AWADDR   (S_AXI_AWADDR ),                  
    .S_AXI_AWUSER   (S_AXI_AWUSER ),
    .S_AXI_AWVALID  (S_AXI_AWVALID),   
    .S_AXI_AWID     (S_AXI_AWID   ),
    .S_AXI_AWLEN    (S_AXI_AWLEN  ),   
    .S_AXI_AWSIZE   (S_AXI_AWSIZE ), 
    .S_AXI_AWBURST  (S_AXI_AWBURST),
    .S_AXI_AWLOCK   (S_AXI_AWLOCK ),       
    .S_AXI_AWCACHE  (S_AXI_AWCACHE),         
    .S_AXI_AWQOS    (S_AXI_AWQOS  ),       
    .S_AXI_AWPROT   (S_AXI_AWPROT ),
    .S_AXI_AWREADY  (S_AXI_AWREADY),
    .S_AXI_WDATA    (S_AXI_WDATA  ),
    .S_AXI_WSTRB    (S_AXI_WSTRB  ),
    .S_AXI_WVALID   (S_AXI_WVALID ),
    .S_AXI_WLAST    (S_AXI_WLAST  ),
    .S_AXI_WREADY   (S_AXI_WREADY ),
    .S_AXI_BRESP    (S_AXI_BRESP  ),
    .S_AXI_BVALID   (S_AXI_BVALID ),
    .S_AXI_BREADY   (S_AXI_BREADY ),
    .S_AXI_ARADDR   (S_AXI_ARADDR ),
    .S_AXI_ARVALID  (S_AXI_ARVALID),
    .S_AXI_ARPROT   (S_AXI_ARPROT ),
    .S_AXI_ARLOCK   (S_AXI_ARLOCK ),
    .S_AXI_ARID     (S_AXI_ARID   ),
    .S_AXI_ARLEN    (S_AXI_ARLEN  ),
    .S_AXI_ARSIZE   (S_AXI_ARSIZE ),
    .S_AXI_ARBURST  (S_AXI_ARBURST),
    .S_AXI_ARCACHE  (S_AXI_ARCACHE),
    .S_AXI_ARQOS    (S_AXI_ARQOS  ),
    .S_AXI_ARREADY  (S_AXI_ARREADY),
    .S_AXI_RDATA    (S_AXI_RDATA  ),
    .S_AXI_RVALID   (S_AXI_RVALID ),
    .S_AXI_RRESP    (S_AXI_RRESP  ),
    .S_AXI_RLAST    (S_AXI_RLAST  ),
    .S_AXI_RREADY   (S_AXI_RREADY ),

    .AXIS_PLEN_TDATA    (AXIS_PLEN_TDATA ),
    .AXIS_PLEN_TVALID   (AXIS_PLEN_TVALID),
    .AXIS_PLEN_TREADY   (AXIS_PLEN_TREADY),
    
    .AXIS_ADDR_TDATA    (AXIS_ADDR_TDATA ),
    .AXIS_ADDR_TVALID   (AXIS_ADDR_TVALID),
    .AXIS_ADDR_TREADY   (AXIS_ADDR_TREADY),
    
    .AXIS_DATA_TDATA    (AXIS_DATA_TDATA ),
    .AXIS_DATA_TLAST    (AXIS_DATA_TLAST ),
    .AXIS_DATA_TVALID   (AXIS_DATA_TVALID),
    .AXIS_DATA_TREADY   (AXIS_DATA_TREADY)
);


rdmx_xmit_be #
(
    .DW                 (DW                ),
    .AW                 (AW                ),
    .UW                 (UW                ),
    .FIFO_CLOCK_MODE    (FIFO_CLOCK_MODE   ),
    .SRC_MAC            (SRC_MAC           ),
    .SRC_IP0            (SRC_IP0           ),
    .SRC_IP1            (SRC_IP1           ),
    .SRC_IP2            (SRC_IP2           ),
    .SRC_IP3            (SRC_IP3           ),
    .DST_IP0            (DST_IP0           ),
    .DST_IP1            (DST_IP1           ),
    .DST_IP2            (DST_IP2           ),
    .DST_IP3            (DST_IP3           ),
    .SOURCE_PORT        (SOURCE_PORT       ),
    .REMOTE_SERVER_PORT (REMOTE_SERVER_PORT),
    .MAX_PACKET_COUNT   (MAX_PACKET_COUNT  ),
    .DATA_FIFO_DEPTH    (DATA_FIFO_DEPTH   )
)
back_end
(
    .src_clk            (src_clk),
    .src_resetn         (src_resetn),
    .dst_clk            (dst_clk),

    .AXIS_PLEN_TDATA    (AXIS_PLEN_TDATA ),
    .AXIS_PLEN_TVALID   (AXIS_PLEN_TVALID),
    .AXIS_PLEN_TREADY   (AXIS_PLEN_TREADY),
    
    .AXIS_ADDR_TDATA    (AXIS_ADDR_TDATA ),
    .AXIS_ADDR_TVALID   (AXIS_ADDR_TVALID),
    .AXIS_ADDR_TREADY   (AXIS_ADDR_TREADY),
    
    .AXIS_DATA_TDATA    (AXIS_DATA_TDATA ),
    .AXIS_DATA_TLAST    (AXIS_DATA_TLAST ),
    .AXIS_DATA_TVALID   (AXIS_DATA_TVALID),
    .AXIS_DATA_TREADY   (AXIS_DATA_TREADY),
    
    .AXIS_TX_TDATA      (AXIS_TX_TDATA   ),
    .AXIS_TX_TKEEP      (AXIS_TX_TKEEP   ),
    .AXIS_TX_TLAST      (AXIS_TX_TLAST   ),
    .AXIS_TX_TVALID     (AXIS_TX_TVALID  ),
    .AXIS_TX_TREADY     (AXIS_TX_TREADY  ),

    .packet_data_fifo_full(packet_data_fifo_full)
);

endmodule


