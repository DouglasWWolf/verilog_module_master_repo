//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 15-Feb-24  DWW     1  Initial creation
//=============================================================================

/*
    As of this writing, this module doesn't do much: the stream carrying in
    frame data connects directly to the output stream and the stream carrying
    in meta-data connects to a pair of FIFO's that each output identical
    copies of that data.

    Potential enhancements in the future:

    (1) Put a FIFO between the input and the output on the frame-data stream.
        This could be useful if it's common for us to have upstream modules
        that need to be able to send us data faster than we can get rid of 
        it.
*/


module mindy_if #
(
    parameter DATA_WBITS   = 512,
    parameter MD_FIFO_TYPE = "distributed"
)
(
    input clk, resetn,

    //==========================================================================
    //                   Input stream of frame data 
    //==========================================================================
    input  [DATA_WBITS-1:0] AXIS_FD_IN_TDATA,
    input                   AXIS_FD_IN_TVALID,
    output                  AXIS_FD_IN_TREADY,
    //==========================================================================


    //==========================================================================
    //                   Input stream of meta-data
    //==========================================================================
    input  [DATA_WBITS-1:0] AXIS_MD_IN_TDATA,
    input                   AXIS_MD_IN_TVALID,
    output                  AXIS_MD_IN_TREADY,
    //==========================================================================

    //==========================================================================
    // Meta-data gets emitted on both of these streams simultaneously
    //==========================================================================
    output [DATA_WBITS-1:0] AXIS_MD0_OUT_TDATA,    AXIS_MD1_OUT_TDATA,
    output                  AXIS_MD0_OUT_TVALID,   AXIS_MD1_OUT_TVALID,
    input                   AXIS_MD0_OUT_TREADY,   AXIS_MD1_OUT_TREADY,
    //==========================================================================


    //==========================================================================
    // Frame-data gets emitted on this stream
    //==========================================================================
    output [DATA_WBITS-1:0] AXIS_FD_OUT_TDATA,
    output                  AXIS_FD_OUT_TVALID,
    input                   AXIS_FD_OUT_TREADY
    //==========================================================================
);  


// Frame data passes straight through to the output stream. 
assign AXIS_FD_OUT_TDATA  = AXIS_FD_IN_TDATA;
assign AXIS_FD_OUT_TVALID = AXIS_FD_IN_TVALID;
assign AXIS_FD_IN_TREADY  = AXIS_FD_OUT_TREADY;


// The "tready" signals from the two meta-data FIFOs
wire fifo_md0_in_tready, fifo_md1_in_tready;

// We can accept incoming meta-data when both FIFOs are ready
assign AXIS_MD_IN_TREADY = fifo_md0_in_tready & fifo_md1_in_tready;

// This is asserted during a valid handshake on the metadata input stream
wire md_in_handshake = AXIS_MD_IN_TREADY & AXIS_MD_IN_TVALID;

//=============================================================================
// This FIFO holds outgoing meta-data
//=============================================================================
xpm_fifo_axis #
(
    .CLOCKING_MODE      ("common_clock"),
    .PACKET_FIFO        ("false"),
    .FIFO_DEPTH         (16),
    .TDATA_WIDTH        (DATA_WBITS),
    .TUSER_WIDTH        (1),
    .FIFO_MEMORY_TYPE   (MD_FIFO_TYPE),
    .USE_ADV_FEATURES   ("0000")
)
md0_fifo
(
    // Clock and reset
   .s_aclk          (clk   ),
   .m_aclk          (clk   ),
   .s_aresetn       (resetn),

    // The input bus to the FIFO
   .s_axis_tdata    (AXIS_MD_IN_TDATA  ),
   .s_axis_tvalid   (md_in_handshake   ),
   .s_axis_tready   (fifo_md0_in_tready),
   .s_axis_tuser    (                  ),
   .s_axis_tkeep    (                  ),
   .s_axis_tlast    (                  ),


    // The output bus of the FIFO
   .m_axis_tdata    (AXIS_MD0_OUT_TDATA ),
   .m_axis_tvalid   (AXIS_MD0_OUT_TVALID),
   .m_axis_tready   (AXIS_MD0_OUT_TREADY),
   .m_axis_tuser    (                   ),
   .m_axis_tkeep    (                   ),
   .m_axis_tlast    (                   ),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),

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
// This FIFO holds outgoing meta-data
//=============================================================================
xpm_fifo_axis #
(
    .CLOCKING_MODE      ("common_clock"),
    .PACKET_FIFO        ("false"),
    .FIFO_DEPTH         (16),
    .TDATA_WIDTH        (DATA_WBITS),
    .TUSER_WIDTH        (1),
    .FIFO_MEMORY_TYPE   (MD_FIFO_TYPE),
    .USE_ADV_FEATURES   ("0000")
)
md1_fifo
(
    // Clock and reset
   .s_aclk          (clk   ),
   .m_aclk          (clk   ),
   .s_aresetn       (resetn),

    // The input bus to the FIFO
   .s_axis_tdata    (AXIS_MD_IN_TDATA  ),
   .s_axis_tvalid   (md_in_handshake   ),
   .s_axis_tready   (fifo_md1_in_tready),
   .s_axis_tuser    (                  ),
   .s_axis_tkeep    (                  ),
   .s_axis_tlast    (                  ),

    // The output bus of the FIFO
   .m_axis_tdata    (AXIS_MD1_OUT_TDATA ),
   .m_axis_tvalid   (AXIS_MD1_OUT_TVALID),
   .m_axis_tready   (AXIS_MD1_OUT_TREADY),
   .m_axis_tuser    (                   ),
   .m_axis_tkeep    (                   ),
   .m_axis_tlast    (                   ),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),

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

 

endmodule
