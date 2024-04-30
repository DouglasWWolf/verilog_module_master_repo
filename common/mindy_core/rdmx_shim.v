

//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 29-Feb-24  DWW     2  Fixed bug with the meta-data registers being too small
//====================================================================================


/*
     This module reads packets from the input stream and:

     (1) Outputs them on the M_AXI memory-mapped AXI interface
     (2) After outputting a full frame, it outputs 128-byte "meta-data"
     (3) It then outputs a 4-byte "frame_count"

     When writing frame data, the addresses they are written to are in a circular ring
     buffer.   Meta-data are written to a separate ring buffer.

*/

module rdmx_shim #
(
    parameter DATA_WBITS = 512
)
(
    input clk, resetn,

    // Size of an outgoing packet (sans header), in bytes
    input[15:0] PACKET_SIZE,

    // Size of a single-phase (i.e., 2 semiphases) sensor-data frame, in bytes
    input[31:0] FRAME_SIZE,

    // Geometry of the frame-data ring buffer
    input[63:0] FD_RING_ADDR, FD_RING_SIZE,

    // Geometry of the meta-command ring buffer
    input[63:0] MD_RING_ADDR, MD_RING_SIZE,

    // The remote address where the frame-counter should be stored
    input[63:0] FC_ADDR,

    //====================   The frame data input stream   =====================
    input [DATA_WBITS-1:0] AXIS_FD_TDATA,
    input                  AXIS_FD_TVALID,
    input                  AXIS_FD_TLAST,
    output                 AXIS_FD_TREADY,
    //==========================================================================


    //======================  The metadata input stream  =======================
    input[DATA_WBITS-1:0]  AXIS_MD_TDATA,
    input                  AXIS_MD_TVALID,
    output                 AXIS_MD_TREADY,
    //==========================================================================

    //=================   This is the AXI4 output interface   ==================

    // "Specify write address"              -- Master --    -- Slave --
    output reg [63:0]                        M_AXI_AWADDR,
    output reg [7:0]                         M_AXI_AWLEN,
    output     [2:0]                         M_AXI_AWSIZE,
    output     [3:0]                         M_AXI_AWID,
    output     [1:0]                         M_AXI_AWBURST,
    output                                   M_AXI_AWLOCK,
    output     [3:0]                         M_AXI_AWCACHE,
    output     [3:0]                         M_AXI_AWQOS,
    output     [2:0]                         M_AXI_AWPROT,
    output reg                               M_AXI_AWVALID,
    input                                                   M_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output reg[DATA_WBITS-1:0]              M_AXI_WDATA,
    output reg[(DATA_WBITS/8)-1:0]          M_AXI_WSTRB,
    output reg                              M_AXI_WVALID,
    output reg                              M_AXI_WLAST,
    input                                                   M_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              M_AXI_BRESP,
    input                                                   M_AXI_BVALID,
    output                                  M_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output[63:0]                            M_AXI_ARADDR,
    output                                  M_AXI_ARVALID,
    output[2:0]                             M_AXI_ARPROT,
    output                                  M_AXI_ARLOCK,
    output[3:0]                             M_AXI_ARID,
    output[7:0]                             M_AXI_ARLEN,
    output[1:0]                             M_AXI_ARBURST,
    output[3:0]                             M_AXI_ARCACHE,
    output[3:0]                             M_AXI_ARQOS,
    input                                                   M_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input[DATA_WBITS-1:0]                                   M_AXI_RDATA,
    input                                                   M_AXI_RVALID,
    input[1:0]                                              M_AXI_RRESP,
    input                                                   M_AXI_RLAST,
    output                                  M_AXI_RREADY,
    //==========================================================================

    // These are for debugging with an ILA
    output reg[31:0] frame_count,
    output           eof
);

// The width of a meta-data in bytes
localparam METADATA_WIDTH = 128;

// Compute the number of data-cycles in an outgoing packet
wire[7:0] cycles_per_packet = PACKET_SIZE / (DATA_WBITS/8);

// Offset where we'll write the next frame-data 
reg [63:0] fd_ptr;
wire[63:0] next_fd_ptr = fd_ptr + PACKET_SIZE;   

// Offset where we'll write the next meta-data
reg [63:0] md_ptr;
wire[63:0] next_md_ptr = md_ptr + METADATA_WIDTH;

// When writing data-bursts to the output interface, this is the current beat
reg[8:0] beat;

// This will be high when outputting the first beat of a burst 
wire first_beat = (M_AXI_WVALID & M_AXI_WREADY & (beat == 0));

// States of our main finite-state-machine
reg[2:0]   fsm_state;
localparam FSM_RESET       = 0;
localparam FSM_START       = 1;
localparam FSM_XFER_PACKET = 2;
localparam FSM_OUTPUT_MD1  = 3;
localparam FSM_OUTPUT_MD2  = 4;
localparam FSM_OUTPUT_FC   = 5;

// 128 bytes of metadata
reg[DATA_WBITS-1:0] metadata[0:1];

// Create a byte-swapped version of the data on the input stream
//wire[DATA_WBITS-1:0] AXIS_FD_tdata_swapped;
//byte_swap#(DATA_WBITS) bs2(.I(AXIS_FD_TDATA), .O(AXIS_FD_tdata_swapped));

//=============================================================================
// This block computes the number of outgoing packets per data-frame
//
// One instance of this module (rdmx_shim) will only see half of the packets
// for a data-frame.  The other half of the packets are being sent to the
// other instance of rdmx_shim.
//=============================================================================
reg [31:0] packets_per_frame;
wire[31:0] packets_per_half_frame = packets_per_frame / 2;
always @* begin
    case (PACKET_SIZE)
          64:   packets_per_frame = FRAME_SIZE /   64;
         128:   packets_per_frame = FRAME_SIZE /  128;
         256:   packets_per_frame = FRAME_SIZE /  256;
         512:   packets_per_frame = FRAME_SIZE /  512;
        1024:   packets_per_frame = FRAME_SIZE / 1024;
        2048:   packets_per_frame = FRAME_SIZE / 2048;
        4096:   packets_per_frame = FRAME_SIZE / 4096;
        8192:   packets_per_frame = FRAME_SIZE / 8192;
     default:   packets_per_frame = 1;
    endcase
end
//=============================================================================

//=============================================================================
// This block reads in two data-cycles of metadata
//=============================================================================
reg[1:0] mdsm_state;
reg      fetch_metadata;

// We're ready to receive metadata in states 0 and 1
assign AXIS_MD_TREADY = (resetn == 1 && mdsm_state < 2);
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        mdsm_state <= 0;
    end else case(mdsm_state)
        
        // Wait for the arrival of the first data-cycle of metadata.
        // When it arrives, store it in metadata[0]
        0:  if (AXIS_MD_TVALID & AXIS_MD_TREADY) begin
                metadata[0] <= AXIS_MD_TDATA;
                mdsm_state  <= 1;
            end

        // Wait for the arrival of the second data-cycle of metadata
        // When it arrives, store it in metadata[1]
        1:  if (AXIS_MD_TVALID & AXIS_MD_TREADY) begin
                metadata[1] <= AXIS_MD_TDATA;
                mdsm_state  <= 2;
            end

        // Wait for permission to read the next 2 cycles of metadata
        2:  if (fetch_metadata) mdsm_state <= 0;

    endcase
end
//=============================================================================


//-----------------------------------------------------------------------------
// This block determines the output_mode by looking at the state of the
// main state machine
//-----------------------------------------------------------------------------

// The current output mode : Frame-Data, Meta-Command, or Frame-Counter
reg[2:0]   output_mode;
localparam OM_RESET = 0;
localparam OM_FD    = 1;  /* Output Mode : Frame Data           */
localparam OM_MD1   = 2;  /* Output Mode : Meta Data, 1st half  */
localparam OM_MD2   = 3;  /* Output Mode : Meta Data, 2nd half  */
localparam OM_FC    = 4;  /* Output Mode : Frame Counter        */

always @* begin
    case (fsm_state)
        FSM_XFER_PACKET:    output_mode = OM_FD;    // Frame-data
        FSM_OUTPUT_MD1:     output_mode = OM_MD1;   // 1st half of meta-data
        FSM_OUTPUT_MD2:     output_mode = OM_MD2;   // 2nd half of meta-data
        FSM_OUTPUT_FC:      output_mode = OM_FC;    // Frame counter
        default:            output_mode = OM_RESET;
    endcase
end
//-----------------------------------------------------------------------------


//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
// 
//    This next section manages the W-channel of the M_AXI output interface
//
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

//-----------------------------------------------------------------------------
// Drive M_AXI_WDATA
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_WDATA = AXIS_FD_TDATA;
        OM_MD1  :   M_AXI_WDATA = metadata[0];
        OM_MD2  :   M_AXI_WDATA = metadata[1];
        OM_FC   :   M_AXI_WDATA = frame_count;
        default :   M_AXI_WDATA = 0;
    endcase
end
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Drive M_AXI_WLAST
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_WLAST = AXIS_FD_TLAST;
        OM_MD2  :   M_AXI_WLAST = 1;
        OM_FC   :   M_AXI_WLAST = 1;
        default :   M_AXI_WLAST = 0;
    endcase
end
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Drive M_AXI_WSTRB
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FC   :   M_AXI_WSTRB = 4'hF;
        default :   M_AXI_WSTRB = -1; 
    endcase
end
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Drive M_AXI_WVALID
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_WVALID = AXIS_FD_TVALID;
        OM_MD1  :   M_AXI_WVALID = 1;
        OM_MD2  :   M_AXI_WVALID = 1;
        OM_FC   :   M_AXI_WVALID = 1;
        default :   M_AXI_WVALID = 0;
    endcase
end
//-----------------------------------------------------------------------------


//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//
//     This next section manages the AW-channel of the M_AXI output interface
// 
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

assign M_AXI_AWID    = 0;
assign M_AXI_AWSIZE  = $clog2(DATA_WBITS/8);
assign M_AXI_AWBURST = 1;       /* Burst type = Increment */
assign M_AXI_AWLOCK  = 0;       /* Not locked             */
assign M_AXI_AWCACHE = 0;       /* No caching             */
assign M_AXI_AWPROT  = 1;       /* Privileged Access      */
assign M_AXI_AWQOS   = 0;       /* No QoS                 */


//-----------------------------------------------------------------------------
// Drive M_AXI_AWADDR
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_AWADDR = FD_RING_ADDR + fd_ptr;
        OM_MD1  :   M_AXI_AWADDR = MD_RING_ADDR + md_ptr;
        OM_MD2  :   M_AXI_AWADDR = MD_RING_ADDR + md_ptr;
        OM_FC   :   M_AXI_AWADDR = FC_ADDR;
        default :   M_AXI_AWADDR = 0;
    endcase
end
//-----------------------------------------------------------------------------



//-----------------------------------------------------------------------------
// Drive M_AXI_AWLEN
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_AWLEN = cycles_per_packet - 1;
        OM_MD1  :   M_AXI_AWLEN = 1;
        OM_MD2  :   M_AXI_AWLEN = 1;
        default :   M_AXI_AWLEN = 0;
    endcase
end
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Drive M_AXI_AWVALID - AWVALID goes active for 1 cycle when the first beat
//                       of a data burst has been accepted
//-----------------------------------------------------------------------------
always @* begin
    case (output_mode)
        OM_FD   :   M_AXI_AWVALID = first_beat;
        OM_MD1  :   M_AXI_AWVALID = first_beat;
        OM_FC   :   M_AXI_AWVALID = first_beat;
        default :   M_AXI_AWVALID = 0;
    endcase
end
//-----------------------------------------------------------------------------



//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//
//                         End of AW-channel definitions
// 
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

// We're always ready to receive AXI write-acknowledgments
assign M_AXI_BREADY = 1;

//-----------------------------------------------------------------------------
// Drive the TREADY line of the input stream.  We only allow input when
// we're in frame-data mode and the output is ready to receive the data-cycle.
//-----------------------------------------------------------------------------
assign AXIS_FD_TREADY = (output_mode == OM_FD) & M_AXI_WREADY;
//-----------------------------------------------------------------------------


//=============================================================================
// This state machine manages the "fd_ptr" that specifies the offset where
// the next packet of frame data should be stored
//=============================================================================
always @(posedge clk) begin
    
    case(fsm_state)

        FSM_START:
            fd_ptr <= 0;

        FSM_XFER_PACKET:
            if (M_AXI_WVALID & M_AXI_WREADY & M_AXI_WLAST) begin
                if (next_fd_ptr < FD_RING_SIZE)
                    fd_ptr <= next_fd_ptr;
                else
                    fd_ptr <= 0;
            end

    endcase

end
//=============================================================================





//=============================================================================
// This state machine manages the "md_ptr" that specifies the offset where
// the next meta-data should be stored
//=============================================================================
always @(posedge clk) begin
    
    case(fsm_state)

        FSM_START:
            md_ptr <= 0;

        FSM_OUTPUT_MD2:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                if (next_md_ptr < MD_RING_SIZE)
                    md_ptr <= next_md_ptr;
                else
                    md_ptr <= 0;
            end

    endcase

end
//=============================================================================



//=============================================================================
// This state machine is responsible for watching packets get copied from the
// input interface to the output interface and for injecting a meta-data packet
// and a frame-count packet after every frame.
//
// Drives:
//    fsm_state (and therefore, "output_mode")
//    beat
//    packet_count
//    frame_count
//=============================================================================
reg[31:0] packet_count;


always @(posedge clk) begin

    // This strobes high for exactly 1 cycle at a time
    fetch_metadata <= 0;

    if (resetn == 0) begin
        fsm_state <= FSM_RESET;

    end else case(fsm_state)

        FSM_RESET:
            fsm_state <= FSM_START;

        FSM_START:
            begin
                beat         <= 0;
                frame_count  <= 1;
                packet_count <= 1;
                fsm_state    <= FSM_XFER_PACKET;
            end

        // Counts packets as they get output.  Once an entire frame has 
        // has been output, we move on to the next state
        FSM_XFER_PACKET:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                beat <= beat + 1;
                if (M_AXI_WLAST) begin
                    beat <= 0;
                    if (packet_count == packets_per_half_frame) begin
                        fsm_state <= FSM_OUTPUT_MD1;
                    end else
                        packet_count <= packet_count + 1;
                end
            end

        // Wait for the 1st half of the meta-data to be output
        FSM_OUTPUT_MD1:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                beat      <= 1;
                fsm_state <= FSM_OUTPUT_MD2;
            end
        
        // Wait for the 2nd half of the meta-data to be output
        FSM_OUTPUT_MD2:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                fetch_metadata <= 1;
                beat           <= 0;
                fsm_state      <= FSM_OUTPUT_FC;
            end

        // Wait for the frame-counter to be output
        FSM_OUTPUT_FC:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                frame_count  <= frame_count + 1;
                packet_count <= 1;
                fsm_state    <= FSM_XFER_PACKET;
            end

    endcase

end

// This flag is asserted for one cycle at the end of a frame and is
// useful for examining end-of-frame behavior in an ILA
assign eof = (fsm_state == FSM_OUTPUT_FC) & M_AXI_WVALID & M_AXI_WREADY;
//=============================================================================

endmodule
