//=============================================================================
//                  ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changess
//=============================================================================
// 05-Jun-24  DWW     1  Initial creation
//
// 19-Mar-25  DWW     2  The first AW request of a frame will now hold AWVALID
//                       high until the PCIe bridge acknowledges via AWREADY
//=============================================================================

/* 

   This module takes as its primary input two streams: one of frame-data and
   one of meta-data.

   There are two host-RAM buffers for frame-data, two host-RAM buffers for 
   meta-data, and a host-RAM buffer for two side-by-side frame-counters.

   Frame-data is "ping-ponged" between the two frame-data buffers, 16K at
   a time.   After a frame is written, the meta-data is written, with identical
   copies being written to each meta-data buffer in host-RAM.   After meta-data
   has been written, the frame-counter is written.

   It is assumed that the M_AXI output of this module will feed a PCIe bus.  
   There has intentionally been no attempt made to enforce any PCIe write-
   transaction ordering.   The "reader" of the data we write will be monitoring
   the frame-counter, and when it detects an increment, it will pause for a
   brief moment to ensure that the entire frame-data and meta-data has finished
   writing to host-RAM.   By making no attempt to enforce PCIe write-ordering, 
   we avail ourselves of the maximum possible PCIe bandwidth.

*/

module ldp_manager # (parameter DW=512, AW=64)
(
    input   clk, resetn,

    // This is the size of a data-frame, in bytes
    input[31:0]     FRAME_SIZE,
    
    // The base address and size of the two frame-data buffers in host-RAM
    input[63:0]     FD0_RING_ADDR, FD1_RING_ADDR,
    input[63:0]     FD_RING_SIZE,


    // The base address and size of the two meta-data buffers in host-RAM
    input[63:0]     MD0_RING_ADDR, MD1_RING_ADDR,
    input[63:0]     MD_RING_SIZE,

    // The address of the frame-counter in host-RAM
    input[63:0]     FC_ADDR,

    // An input stream of frame-data
    input[DW-1:0]   axis_fd_tdata,
    input           axis_fd_tvalid,
    output reg      axis_fd_tready,

    // An input stream of meta-data
    input[DW-1:0]   axis_md_tdata,
    input           axis_md_tvalid,
    output          axis_md_tready,

    // The highest and lowest number of clock cycles to emit an entire frame
    output reg[31:0] max_frame_cycles, min_frame_cycles,

    // This will be high on the first data-cycle of every data-frame
    output start_of_frame,

    //==================  This is an AXI4-master interface  ===================

    // "Specify write address"              -- Master --    -- Slave --
    output reg [AW-1:0]                     M_AXI_AWADDR,
    output reg                              M_AXI_AWVALID,
    output reg [7:0]                        M_AXI_AWLEN,
    output     [2:0]                        M_AXI_AWSIZE,
    output     [3:0]                        M_AXI_AWID,
    output     [1:0]                        M_AXI_AWBURST,
    output                                  M_AXI_AWLOCK,
    output     [3:0]                        M_AXI_AWCACHE,
    output     [3:0]                        M_AXI_AWQOS,
    output     [2:0]                        M_AXI_AWPROT,
    input                                                   M_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output reg [DW-1:0]                     M_AXI_WDATA,
    output reg [(DW/8)-1:0]                 M_AXI_WSTRB,
    output reg                              M_AXI_WVALID,
    output reg                              M_AXI_WLAST,
    input                                                   M_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              M_AXI_BRESP,
    input                                                   M_AXI_BVALID,
    output                                  M_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output     [AW-1:0]                     M_AXI_ARADDR,
    output                                  M_AXI_ARVALID,
    output     [2:0]                        M_AXI_ARPROT,
    output                                  M_AXI_ARLOCK,
    output     [3:0]                        M_AXI_ARID,
    output     [2:0]                        M_AXI_ARSIZE,
    output     [7:0]                        M_AXI_ARLEN,
    output     [1:0]                        M_AXI_ARBURST,
    output     [3:0]                        M_AXI_ARCACHE,
    output     [3:0]                        M_AXI_ARQOS,
    input                                                   M_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input[DW-1:0]                                           M_AXI_RDATA,
    input                                                   M_AXI_RVALID,
    input[1:0]                                              M_AXI_RRESP,
    input                                                   M_AXI_RLAST,
    output                                  M_AXI_RREADY
    //==========================================================================

);

// Each burst of frame-data we write has this many bytes
localparam BYTES_PER_FD_BURST = 4096;

// Each burst of meta-data we write has this many bytes
localparam BYTES_PER_MD_BURST = 128;

// We write bursts to fd_ring_0 or fd_ring_1 in groups of N
localparam BURSTS_PER_GROUP = 4;

// The number of data-data cycles in an AXI write-burst
localparam FD_BEATS_PER_BURST = BYTES_PER_FD_BURST / (DW/8);
localparam MD_BEATS_PER_BURST = BYTES_PER_MD_BURST / (DW/8);

// The address in host-RAM where the next burst of frame-data will be written
reg[63:0] fd0_address, fd1_address;

// This is the number of data-cycles in a single data-frame
wire[31:0] FD_CYCLES_PER_FRAME = FRAME_SIZE / (DW/8);

// The number of write-bursts for frame data in a single frame
wire[31:0] FD_BURSTS_PER_FRAME = FRAME_SIZE / (BYTES_PER_FD_BURST);

// Meta-data, stored and waiting to be transmitted
reg [DW-1:0] metadata[0:1];

// The state of the state machine that drives the W-channel of M_AXI
reg[2:0]   wsm_state;
localparam WSM_RESET             = 0;
localparam WSM_WAIT_FIRST_FD     = 1;
localparam WSM_WAIT_REMAINING_FD = 2;
localparam WSM_WRITE_MD00        = 3;
localparam WSM_WRITE_MD01        = 4;
localparam WSM_WRITE_MD10        = 5;
localparam WSM_WRITE_MD11        = 6;
localparam WSM_WRITE_FC          = 7;


// The state of the state-machine that controls the AW-channel of M_AXI
reg[2:0]   awsm_state;
localparam AWSM_EMIT_FIRST_FD_REQ  = 0;
localparam AWSM_EMIT_FD_WRITE_REQS = 1;
localparam AWSM_EMIT_MD_WRITE_REQ0 = 2;
localparam AWSM_EMIT_MD_WRITE_REQ1 = 3;
localparam AWSM_EMIT_FC_WRITE_REQ  = 4;

// This is 1-based beat number of a write-burst
reg[7:0] beat;

// This counts the number of times we have emitted the AW-request for
// the first burst of a new frame
reg [31:0] aw_frames;

// This is true when the AW state-machine is generating frame-data write requests
reg awsm_fd_write;

// This is true when the first data-cycle of a frame has arrived
assign start_of_frame = (resetn == 1) & (wsm_state == WSM_WAIT_FIRST_FD) & M_AXI_WVALID; 

// This is true when the first data-cycle of a frame has been acknowledged
wire first_handshake_of_frame = start_of_frame & M_AXI_WREADY;

// This is 1-based frame-counter
reg [31:0] frame_counter_reg;
wire[31:0] frame_counter = frame_counter_reg + start_of_frame;

// We're ready for write-acknowledgements any time we're not in reset
assign M_AXI_BREADY = (resetn == 1);

// The AR and A channels of M_AXI are unused
assign M_AXI_ARVALID = 0;
assign M_AXI_ARADDR  = 0;
assign M_AXI_ARPROT  = 0;
assign M_AXI_ARLOCK  = 0;
assign M_AXI_ARID    = 0;
assign M_AXI_ARSIZE  = 0;
assign M_AXI_ARLEN   = 0;
assign M_AXI_ARBURST = 0;
assign M_AXI_ARCACHE = 0;
assign M_AXI_ARQOS   = 0;
assign M_AXI_RREADY  = 0;


//==============================================================================
// Whenever "first_handshake_of_frame" strobes high, this state machine will 
// read in two data-cycle of metadata and store them in metadata[0] and
// metadata[1].
//==============================================================================
reg [1:0] rmd_state;
assign    axis_md_tready = (resetn == 1) & (rmd_state != 0);
//------------------------------------------------------------------------------
always @(posedge clk) begin
    
    if (resetn == 0) begin
        metadata[0]    <= 0;
        metadata[1]    <= 0;
        rmd_state      <= 0;
    end 
    
    else case (rmd_state)

        0:  if (first_handshake_of_frame) begin
                rmd_state <= 1;
            end

        1:  if (axis_md_tready & axis_md_tvalid) begin
                metadata[0] <= axis_md_tdata;
                rmd_state   <= 2;
            end

        2:  if (axis_md_tready & axis_md_tvalid) begin
                metadata[1] <= axis_md_tdata;
                rmd_state   <= 0;
            end

    endcase

end
//==============================================================================




//==============================================================================
// Computes the next offset for a frame-data buffer taking into account the need
// to wrap back to 0
//==============================================================================
function [63:0] next_fd_offset
(
    input[63:0] current_offset,
    input[63:0] buffer_size    
);
begin
    next_fd_offset = current_offset + BYTES_PER_FD_BURST;
    if (next_fd_offset >= buffer_size) next_fd_offset = 0;
end
endfunction
//==============================================================================


//==============================================================================
// Computes the next offset for a meta-data buffer taking into account the need
// to wrap back to 0
//==============================================================================
function [63:0] next_md_offset
(
    input[63:0] current_offset,
    input[63:0] buffer_size
);
begin
    next_md_offset = current_offset + BYTES_PER_MD_BURST;
    if (next_md_offset >= buffer_size) next_md_offset = 0;
end
endfunction
//==============================================================================




//==============================================================================
// This block determines when the frame-data pointer will be incremented to the
// next address.  This happens every time we see a valid AW-handshake while
// we are emitting frame-data write-requests
//==============================================================================
wire inc_fd_pointer = (resetn == 1)
                    & awsm_fd_write
                    & M_AXI_AWVALID
                    & M_AXI_AWREADY;
//==============================================================================


//==============================================================================
// We will increment the meta-data pointer every time we write the frame-counter
//==============================================================================
wire inc_md_pointer = (resetn == 1)
                    & (awsm_state == AWSM_EMIT_FC_WRITE_REQ)
                    & M_AXI_AWVALID
                    & M_AXI_AWREADY;
//==============================================================================
 

//==============================================================================
// This block keeps track of the address in host-RAM where we will write the
// next burst of frame-data.
//
// We alternate writing frame-data between the ring buffers.   The first N
// bursts are written to frame-data-ring0, then next N bursts are written to
// frame-data-ring1, the next N bursts are written to frame-data-ring0, etc.
//
// The address where frame-data should be written in stored in "fd<n>_address"
//==============================================================================
// The offset (from the ring-buffer base address) of the next place we will
// write frame data
reg[63:0] next_fd0_offs, next_fd1_offs;

// Counts from 1 to BURSTS_PER_GROUP * 2, then repeats
reg[15:0] group_counter;

// Determine whether we're writing to frame-data-ring0, or frame-data-ring1
wire      group_select = (group_counter > BURSTS_PER_GROUP);
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    // If reset is asserted...
    if (resetn == 0) begin
        group_counter <= 1;
        next_fd0_offs <= next_fd_offset(0, FD_RING_SIZE);
        next_fd1_offs <= next_fd_offset(0, FD_RING_SIZE);
        fd0_address   <= FD0_RING_ADDR;
        fd1_address   <= FD1_RING_ADDR;
    end

    // If we've been told to increment the frame-data pointer....
    else if (inc_fd_pointer) begin

        // "group-select" determines which pointer we increment
        if (group_select == 0) begin
            fd0_address   <= FD0_RING_ADDR + next_fd0_offs;
            next_fd0_offs <= next_fd_offset(next_fd0_offs, FD_RING_SIZE);
        end else begin
            fd1_address   <= FD1_RING_ADDR + next_fd1_offs;
            next_fd1_offs <= next_fd_offset(next_fd1_offs, FD_RING_SIZE);
        end


        // Any time we bump the frame-data address, incr the group-counter.
        // This allows us to keep track of whether the next "pointer incr"
        // will be for frame-data-ring0, or frame-data-ring1
        if (group_counter == 2 * BURSTS_PER_GROUP)
            group_counter <= 1;
        else
            group_counter <= group_counter + 1;

    end
end
//==============================================================================



//==============================================================================
// This block keeps track of the address in host-RAM where we will write the
// next burst of meta.  Note that we write two copies of meta-data into two
// distinct ring-buffers
//
// The address where frame-data should be written in stored in "md0_address"
// and "md1_address"
//==============================================================================
// The offset (from the ring-buffer base address) of the next place we will
// write meta-data
reg[63:0] next_md_offs;

// The addresses of the two metadata buffers in host RAM
reg[63:0] md0_address, md1_address;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    // If reset is asserted...
    if (resetn == 0) begin
        next_md_offs <= next_md_offset(0, MD_RING_SIZE);
        md0_address  <= MD0_RING_ADDR;
        md1_address  <= MD1_RING_ADDR;
    end

    // If we've been told to increment the meta-data pointer....
    else if (inc_md_pointer) begin
        md0_address  <= MD0_RING_ADDR + next_md_offs;
        md1_address  <= MD1_RING_ADDR + next_md_offs;
        next_md_offs <= next_md_offset(next_md_offs, MD_RING_SIZE);
    end
end
//==============================================================================



//==============================================================================
// This controls the AW-channel of the M_AXI master interface
//==============================================================================
always @* begin

    if (resetn == 0) begin
        awsm_fd_write = 0;
        M_AXI_AWADDR  = 0;
        M_AXI_AWLEN   = 0;
        M_AXI_AWVALID = 0;

    end else case (awsm_state) 

        // Are we emitting the first write-request for frame-data?
        AWSM_EMIT_FIRST_FD_REQ:
            begin
                awsm_fd_write = 1;
                M_AXI_AWADDR  = (group_select == 0) ? fd0_address : fd1_address;
                M_AXI_AWLEN   = FD_BEATS_PER_BURST - 1;
                M_AXI_AWVALID = (aw_frames != frame_counter);
            end

        // Are we emitting a write-request for subsequent frame-data?
        AWSM_EMIT_FD_WRITE_REQS:
            begin
                awsm_fd_write = 1;
                M_AXI_AWADDR  = (group_select == 0) ? fd0_address : fd1_address;
                M_AXI_AWLEN   = FD_BEATS_PER_BURST - 1;
                M_AXI_AWVALID = 1;
            end
        
        // Are we emiting a write-request for the 1st copy of metadata?
        AWSM_EMIT_MD_WRITE_REQ0:
            begin
                awsm_fd_write = 0;
                M_AXI_AWADDR  = md0_address;
                M_AXI_AWLEN   = MD_BEATS_PER_BURST - 1;
                M_AXI_AWVALID = 1;
            end

        // Are we emiting a write-request for the 2nd copy of metadata?
        AWSM_EMIT_MD_WRITE_REQ1:
            begin
                awsm_fd_write = 0;
                M_AXI_AWADDR  = md1_address;
                M_AXI_AWLEN   = MD_BEATS_PER_BURST - 1;
                M_AXI_AWVALID = 1;
            end

        // Are we emitting a write-request for the frame-counters?
        AWSM_EMIT_FC_WRITE_REQ:
            begin
                awsm_fd_write = 0;                
                M_AXI_AWADDR  = FC_ADDR;
                M_AXI_AWLEN   = 0;
                M_AXI_AWVALID = 1;  
            end
    
        // We'll never get here
        default:
            begin
                awsm_fd_write = 0;                
                M_AXI_AWADDR  = 0;
                M_AXI_AWLEN   = 0;
                M_AXI_AWVALID = 0;  
            end

    endcase

end


// Assign fixed values to the rest of the AW-channel ports of M_AXI
assign M_AXI_AWSIZE  = $clog2(DW/8);
assign M_AXI_AWID    = 0;
assign M_AXI_AWBURST = 1;  // This selects an incremental burst
assign M_AXI_AWLOCK  = 0;
assign M_AXI_AWCACHE = 0;
assign M_AXI_AWQOS   = 0;
assign M_AXI_AWPROT  = 0;
//==============================================================================



//==============================================================================
// This state machine issues the write-requests on the AW-channel.   
//==============================================================================
reg[31:0] aw_fd_burst;
//------------------------------------------------------------------------------
always @(posedge clk) begin

    if (resetn == 0) begin
        awsm_state  <= AWSM_EMIT_FIRST_FD_REQ;
        aw_frames   <= 0;
    end
    
    else case (awsm_state)

        // Emit the first write-request
        AWSM_EMIT_FIRST_FD_REQ:
            if (M_AXI_AWVALID & M_AXI_AWREADY) begin
                aw_frames   <= aw_frames + 1;
                aw_fd_burst <= 2;
                awsm_state  <= AWSM_EMIT_FD_WRITE_REQS;
            end
    
        // Emit as many write-request as we need for the entire data-frame
        AWSM_EMIT_FD_WRITE_REQS:
            if (M_AXI_AWVALID & M_AXI_AWREADY) begin
                if (aw_fd_burst < FD_BURSTS_PER_FRAME)
                    aw_fd_burst <= aw_fd_burst + 1;
                else
                    awsm_state <= AWSM_EMIT_MD_WRITE_REQ0;
            end
    
        // Emit the write-request for the 1st copy of meta-data
        AWSM_EMIT_MD_WRITE_REQ0:
            if (M_AXI_AWVALID & M_AXI_AWREADY)
                awsm_state <= AWSM_EMIT_MD_WRITE_REQ1;
    
        // Emit the write-request for the 2nd copy of meta-data
        AWSM_EMIT_MD_WRITE_REQ1:
            if (M_AXI_AWVALID & M_AXI_AWREADY)
                awsm_state <= AWSM_EMIT_FC_WRITE_REQ;
    
        // Emit the write-request for the frame-counter
        AWSM_EMIT_FC_WRITE_REQ:
            if (M_AXI_AWVALID & M_AXI_AWREADY) begin
                awsm_state <= AWSM_EMIT_FIRST_FD_REQ;
            end

    endcase

end
//==============================================================================



//==============================================================================
// This block controls the W-channel of M_AXI and axis_fd_tready
//==============================================================================
always @* begin

    if (resetn == 0) begin
        axis_fd_tready = 0;
        M_AXI_WDATA    = 0;
        M_AXI_WSTRB    = 0;
        M_AXI_WLAST    = 0;
        M_AXI_WVALID   = 0;

    end else case (wsm_state)


        // Are we writing the first cycle of data for this frame?
        WSM_WAIT_FIRST_FD:
            begin
                axis_fd_tready = M_AXI_WREADY;
                M_AXI_WDATA    = axis_fd_tdata;
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = 0;
                M_AXI_WVALID   = axis_fd_tvalid;
            end

        // Are we writing a subsequent cycle of data for this frame?
        WSM_WAIT_REMAINING_FD:
            begin
                axis_fd_tready = M_AXI_WREADY;
                M_AXI_WDATA    = axis_fd_tdata;
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = (beat == FD_BEATS_PER_BURST);
                M_AXI_WVALID   = axis_fd_tvalid;
            end            

        // Are we writing the first cycle of copy #1 of meta-data?
        WSM_WRITE_MD00:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = metadata[0];
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = 0;
                M_AXI_WVALID   = 1;
            end            

        // Are we writing the second cycle of copy #1 of meta-data?
        WSM_WRITE_MD01:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = metadata[1];
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = 1;
                M_AXI_WVALID   = 1;
            end            

        // Are we writing the first cycle of copy #2 of meta-data?
        WSM_WRITE_MD10:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = metadata[0];
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = 0;
                M_AXI_WVALID   = 1;
            end            

        // Are we writing the second cycle of copy #2 of meta-data?
        WSM_WRITE_MD11:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = metadata[1];
                M_AXI_WSTRB    = -1;
                M_AXI_WLAST    = 1;
                M_AXI_WVALID   = 1;
            end            

        // Are we writing the framer-counters?
        WSM_WRITE_FC:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = {frame_counter, frame_counter};
                M_AXI_WSTRB    = {4'b1111, 4'b1111};
                M_AXI_WLAST    = 1;
                M_AXI_WVALID   = 1;
            end      

        // Since we've handled every possible case,
        // this should never be executed
        default:
            begin
                axis_fd_tready = 0;
                M_AXI_WDATA    = 0;
                M_AXI_WSTRB    = 0;
                M_AXI_WLAST    = 0;
                M_AXI_WVALID   = 0;
            end      

    endcase

end
//==============================================================================



//==============================================================================
// This state-machine manages state transitions for controlling the W-channel
// of M_AXI
//==============================================================================
reg[31:0] w_fd_burst;
reg[31:0] elapsed;
//------------------------------------------------------------------------------
always @(posedge clk) begin

    // We're always counting elapsed cycles
    elapsed <= elapsed + 1;

    if (resetn == 0) begin
        beat              <= 0;
        w_fd_burst        <= 0;
        frame_counter_reg <= 0;
        wsm_state         <= WSM_WAIT_FIRST_FD;
        max_frame_cycles  <= 0;
        min_frame_cycles  <= -1;
    end 

    else case(wsm_state)

        // Here we're waiting for the first data-cycle of a new data frame
        WSM_WAIT_FIRST_FD:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                elapsed           <= 1;
                frame_counter_reg <= frame_counter_reg + 1;
                beat              <= 2;
                w_fd_burst        <= 1;
                wsm_state         <= WSM_WAIT_REMAINING_FD;
            end

        // Here we're waiting for all subsequent data-cycles of a data frame
        WSM_WAIT_REMAINING_FD:
            if (M_AXI_WVALID & M_AXI_WREADY) begin
                beat <= beat + 1;
                if (M_AXI_WLAST) begin
                    beat <= 1;
                    if (w_fd_burst == FD_BURSTS_PER_FRAME)
                        wsm_state  <= WSM_WRITE_MD00;
                    else
                        w_fd_burst <= w_fd_burst + 1;
                end
            end

        WSM_WRITE_MD00:
            if (M_AXI_WVALID & M_AXI_WREADY)
                wsm_state <= WSM_WRITE_MD01;

        WSM_WRITE_MD01:
            if (M_AXI_WVALID & M_AXI_WREADY)
                wsm_state <= WSM_WRITE_MD10;

        WSM_WRITE_MD10:
            if (M_AXI_WVALID & M_AXI_WREADY)
                wsm_state <= WSM_WRITE_MD11;

        WSM_WRITE_MD11:
            if (M_AXI_WVALID & M_AXI_WREADY)
                wsm_state <= WSM_WRITE_FC;

        WSM_WRITE_FC:
           if (M_AXI_WVALID & M_AXI_WREADY) begin
                if (elapsed > max_frame_cycles)
                    max_frame_cycles <= elapsed;
                if (elapsed < min_frame_cycles)
                    min_frame_cycles <= elapsed;
                wsm_state <= WSM_WAIT_FIRST_FD;
           end

    endcase

end
//==============================================================================

endmodule
