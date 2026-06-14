//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 12-Jun-26  DWW     1  Initial creation
//====================================================================================

/*
    This module serves as a buffer for incoming frame-data and meta-data.  It is aware
    of how many data-cycles are in a frame, and it will always output an entire frame
    of data, *EVEN IF THE BUFFER OVERFLOWS*.  In the case where the frame buffer
    overflows, "dummy" data is output in order to pad the output data to the length of
    a full frame.

    If a frame is damaged via the dropping of data, "dropped_frame_stb" will strobe
    high for one cycle.  When this happens "dropped_frame_number" contains the frame
    number of the damaged frame.

    This module also has a secondary output stream called "axis_ferr".  One 
    entry is written to the "axis_ferr" stream for every frame that arrives
    at the input.  If the axis_ferr data is non-zero it means that the frame
    is damaged.
*/

module ldp_buffer #
(
    parameter DW=512,
    parameter DATA_FIFO_DEPTH = 16,
    parameter SUPPORT_FIFO_DEPTH = 16
)
(
   
    input   clk,
    input   resetn,
    
    // The frame-data input stream
    input[DW-1:0]       axis_fd_in_tdata,
    input               axis_fd_in_tvalid,    

    // This is for debugging only, leave disconnected during normal use
    output              axis_fd_in_tready, 

    // The frame-data output stream
    output reg [DW-1:0] axis_fd_out_tdata,
    output reg          axis_fd_out_tvalid,
    input               axis_fd_out_tready,

    // The meta-data input stream
    input[DW-1:0]       axis_md_in_tdata,
    input               axis_md_in_tvalid,    
    output              axis_md_in_tready,

    // The meta-data output stream
    output[DW-1:0]      axis_md_out_tdata,
    output              axis_md_out_tvalid,
    input               axis_md_out_tready,

    // This output stream carries a flag that says whether
    // the current frame is valid or not. 
    output[7:0]         axis_ferr_tdata,  // (0 = Valid frame, 1 = damaged frame)
    output              axis_ferr_tvalid,
    input               axis_ferr_tready,

    // Number of bytes in a frame
    input[31:0] frame_size,

    // When a frame has one or more cycles dropped, this strobes high
    output reg dropped_frame_stb,
    
    // When "dropped_frame_stb" strobes high, this is the frame number
    output reg[31:0] dropped_frame_number,

    // If this strobes high, the output stream was completely unable
    // to keep up with the required bandwidth
    output fatal_overflow_stb,

    // This is strictly a debugging aid and is not typically 
    // used in a deployed design.  This is asserted any time
    // data arriving on the input will be discarded instead
    // of being recorded in the data-fifo
    output  discard_input 
);

// This will be repeated across "axis_stream_tdata" when dummy-data
// cycles are written.   In little-endian, this is 0xDEAD
localparam[15:0] DUMMY_WORD = 16'hADDE;

// This is the number of data-cycles in a single data-frame
wire[31:0] CYCLES_PER_FRAME = frame_size / 64;

// This is the data-cycle number of the last data-cycle in a frame
wire[31:0] LAST_FRAME_CYCLE = CYCLES_PER_FRAME - 1;

// When this is asserted, the remaining cycles of the frame will not
// be written into the data_fifo
reg abort_frame_input;

// As data gets written to the FIFO, we assocate a frame-number with it
reg[31:0] inp_frame_number;

// If we ever drop a data-cycle during a frame because the FIFO was full,
// we will not write any data to the FIFO for the rest of the frame. 
wire fd_fifo_in_tvalid = axis_fd_in_tvalid && !abort_frame_input;

// In the data_fifo, the TUSER data is the frame number
wire[7:0] fd_fifo_in_tuser = inp_frame_number[7:0];

// The data_fifo asserts this when it's ready for incoming data
wire fd_fifo_in_tready;

// Assign this sigal strictly for the sake of debugging with an ILA
assign axis_fd_in_tready = fd_fifo_in_tready;

// The number of input data-cycles that we've seen in this frame.  This includes
// both cycles that were written into the data_fifo and cycles that were dropped
// because the data_fifo was full
reg[31:0] frame_cycles_in;

// Entries in the "drop" FIFO indicate frame numbers that had
// dropped data-cycles
wire[7:0] drop_fifo_in_tdata = inp_frame_number[7:0]; 
reg       drop_fifo_in_tvalid; 
wire      drop_fifo_in_tready;

// The output side of the "drop" FIFO
wire[7:0] drop_fifo_out_tdata;
wire      drop_fifo_out_tvalid;
reg       drop_fifo_out_tready;

// When this strobes high, an entry is written into the frame-status FIFO
reg frame_status;
reg frame_status_stb;

// The frame-status FIFO drives this signal
wire frame_status_in_ready;

// The state of the input state-machine
reg ism_state;

// When this is true, we're discarding input data
assign discard_input = !fd_fifo_in_tready || abort_frame_input;

// If we one of our support FIFOs overflows, all bets are off
assign fatal_overflow_stb = (frame_status_stb    && !frame_status_in_ready)
                          | (drop_fifo_in_tvalid && !drop_fifo_in_tready  )
                          | (axis_md_in_tvalid   && !axis_md_in_tready    );

//=============================================================================
// This state machine feeds incoming data into the data-fifo, along with an
// indicator of which frame-number each data-cycle belongs to.
//
// If a data-cycle can't be written to the FIFO because the FIFO is full, the
// entire rest of the frame is dropped (i.e., not written to the FIFO), and
// an entry is written to the "drop_fifo" to indicate that the current frame
// is missing data-cycles
//
// The state-machine that reads the main FIFO will use the "drop_fifo" to
// know that it should output sufficient "dummy" data-cycles to complete
// the frame.
//=============================================================================
always @(posedge clk) begin

    // These strobes high for a single cycle at a time
    dropped_frame_stb   <= 0;
    drop_fifo_in_tvalid <= 0;
    frame_status_stb    <= 0;

    if (resetn == 0) begin
        dropped_frame_number <= 0;
        ism_state            <= 0;
    end 

    else case(ism_state)
        
        // After coming out of reset, we wait for the data_fifo
        // to become ready to accept data
        0:  if (fd_fifo_in_tready) begin
                abort_frame_input <= 0;
                frame_cycles_in   <= 0;
                inp_frame_number  <= 1;
                ism_state         <= 1;
            end


        // Every time a data-cycle arrives on the input stream...
        1:  if (axis_fd_in_tvalid) begin

                // If this is the first cycle of the frame to be dropped
                // because the FIFO is full, abort the frame and write
                // an entry in the "drop_fifo"    
                if (!fd_fifo_in_tready && !abort_frame_input) begin
                    abort_frame_input   <= 1;
                    drop_fifo_in_tvalid <= 1;
                end
         
                if (frame_cycles_in < LAST_FRAME_CYCLE)
                    frame_cycles_in <= frame_cycles_in + 1;
                else begin
                    abort_frame_input    <= 0;
                    frame_cycles_in      <= 0;
                    dropped_frame_number <= inp_frame_number;
                    dropped_frame_stb    <= discard_input;
                    frame_status         <= discard_input;
                    frame_status_stb     <= 1;
                    inp_frame_number     <= inp_frame_number + 1;
                end

            end
    endcase

end
//=============================================================================


// The output side of the data_fifo
wire[DW-1:0] fd_fifo_out_tdata;
wire[   7:0] fd_fifo_out_tuser;
wire         fd_fifo_out_tvalid;
wire         fd_fifo_out_tready;

// Number of data-cycles thus far in the output frame
reg[31:0] frame_cycles_out;

// The frame-number of the output frame being handled.  We are only using the 
// bottom 8 bits here because it allows us to keep the drop-fifo tiny.
reg[7:0] out_frame_number;

// Is the data-fifo presenting data for the current frame?
wire fd_fifo_active = (fd_fifo_out_tvalid && fd_fifo_out_tuser == out_frame_number);

// Is the drop-fifo presenting data for the current frame?
wire drop_fifo_active = (drop_fifo_out_tvalid && drop_fifo_out_tdata == out_frame_number);

//=============================================================================
// If the output side of the data-fifo is presenting valid data for the
// expected frame number, then axis_fd_out_tdata take on that value.
//
// In all other case, axis_fd_out_tdata is repetitions of DUMMY_WORD
//=============================================================================
always @* begin

    if (fd_fifo_active) begin
        axis_fd_out_tdata  = fd_fifo_out_tdata;
        axis_fd_out_tvalid = 1;
    end
    
    else if (drop_fifo_active) begin
        axis_fd_out_tdata  = {(DW/16){DUMMY_WORD}};
        axis_fd_out_tvalid = 1;        
    end

    else begin
        axis_fd_out_tdata  = 0;
        axis_fd_out_tvalid = 0;
    end

end
//=============================================================================


//=============================================================================
// This block writes data to the output stream.  It will always write either
// the data-cycles from the data-fifo, or dummy-data if no more data-cycles
// are available for the current frame.
//=============================================================================
always @(posedge clk) begin
    
    // This will strobe high for a single cycle at a time
    drop_fifo_out_tready <= 0;

    if (resetn == 0) begin
        out_frame_number <= 1;
        frame_cycles_out <= 0;
    end

    else if (axis_fd_out_tvalid & axis_fd_out_tready) begin

        if (frame_cycles_out < LAST_FRAME_CYCLE) begin
            frame_cycles_out <= frame_cycles_out + 1;
        end else begin
            frame_cycles_out     <= 0;
            out_frame_number     <= out_frame_number + 1;
            drop_fifo_out_tready <= drop_fifo_active;
        end
    end

end
//=============================================================================

// The output of the frame-data FIFO advances every time a handshake occurs
// on the output stream while the frame-data FIFO is presenting data
assign fd_fifo_out_tready = fd_fifo_active & axis_fd_out_tready;

//=============================================================================
// This holds our buffered frame data.  TUSER is the bottom 8 bits of the
// frame number
//=============================================================================
xpm_fifo_axis #
(
   .TDATA_WIDTH     (DW),
   .TUSER_WIDTH     (8),
   .FIFO_DEPTH      (DATA_FIFO_DEPTH),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
i_fd_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus of the FIFO
   .s_axis_tdata (axis_fd_in_tdata),
   .s_axis_tvalid(fd_fifo_in_tvalid),
   .s_axis_tuser (fd_fifo_in_tuser ),
   .s_axis_tready(fd_fifo_in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (fd_fifo_out_tdata ),
   .m_axis_tuser (fd_fifo_out_tuser ),
   .m_axis_tvalid(fd_fifo_out_tvalid),
   .m_axis_tready(fd_fifo_out_tready),

    // Unused input stream signals
   .s_axis_tkeep(),
   .s_axis_tlast(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
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
//=============================================================================



//=============================================================================
// This holds our buffered meta data.  Our capacity is 2 * SUPPORT_FIFO_DEPTH
// because every frame has 2 cycles of meta-data
//=============================================================================
xpm_fifo_axis #
(
   .TDATA_WIDTH     (DW),
   .FIFO_DEPTH      (SUPPORT_FIFO_DEPTH * 2),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
i_md_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus of the FIFO
   .s_axis_tdata (axis_md_in_tdata ),
   .s_axis_tvalid(axis_md_in_tvalid),
   .s_axis_tready(axis_md_in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (axis_md_out_tdata ),
   .m_axis_tvalid(axis_md_out_tvalid),
   .m_axis_tready(axis_md_out_tready),

    // Unused input stream signals
   .s_axis_tuser(),
   .s_axis_tkeep(),
   .s_axis_tlast(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),

    // Unused output stream signals
   .m_axis_tuser(),
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
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
//=============================================================================



//=============================================================================
// Each entry is a frame-number of a frame that has dropped-cycles.  This FIFO
// is small enough that Vivado will automatically place it in LUTRAM if there
// is LUTRAM available
//=============================================================================
xpm_fifo_axis #
(
   .TDATA_WIDTH     (8),
   .FIFO_DEPTH      (SUPPORT_FIFO_DEPTH),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
i_drop_fifo
(
    // Clock and reset
    .s_aclk   (clk   ),
    .m_aclk   (clk   ),
    .s_aresetn(resetn),

    // The input bus of the FIFO
    .s_axis_tdata (drop_fifo_in_tdata),
    .s_axis_tvalid(drop_fifo_in_tvalid),
    .s_axis_tready(drop_fifo_in_tready),

    // The output bus of the FIFO
    .m_axis_tdata (drop_fifo_out_tdata),
    .m_axis_tvalid(drop_fifo_out_tvalid),
    .m_axis_tready(drop_fifo_out_tready),    

    // Unused input stream signals
    .s_axis_tuser(),
    .s_axis_tkeep(),
    .s_axis_tlast(),
    .s_axis_tdest(),
    .s_axis_tid  (),
    .s_axis_tstrb(),

    // Unused output stream signals
    .m_axis_tuser(),
    .m_axis_tdest(),
    .m_axis_tid  (),
    .m_axis_tstrb(),
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
//=============================================================================


//=============================================================================
// This is a small, 1-bit wide FIFO.   It carries the error-status for
// each frame
//=============================================================================
ldp_fstat_fifo # (.DEPTH(SUPPORT_FIFO_DEPTH)) i_fstat_fifo 
(
    .clk        (clk),
    .resetn     (resetn),
    
    // The input side of the fifo
    .data_in    (frame_status),
    .in_valid   (frame_status_stb),
    .in_ready   (frame_status_in_ready),

    // The output side of the fifo
    .data_out   (axis_ferr_tdata[0]),
    .out_valid  (axis_ferr_tvalid),
    .out_ready  (axis_ferr_tready)
);
//=============================================================================


endmodule