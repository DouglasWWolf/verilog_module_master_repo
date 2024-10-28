//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 24-Oct-24  DWW     1  Initial creation
//=============================================================================

/*
    This manages the "tracer_value" FIFO for the "sensor_inject" module.

    The output of the FIFO directly feeds the axis_vector output stream
    but is gated by the i_RUN signal.   We can only feed or clear the FIFO
    when i_RUN is 0, and data is only output from the FIFO when i_RUN is 1
*/



module sensor_inject_ctl # (parameter FIFO_DEPTH=8192)
(
    input clk, resetn,

    // Clear the FIFO
    input            i_FIFO_CLEAR,
    input            i_FIFO_CLEAR_wstrobe,

    // Load data into the FIFO
    input[7:0]       i_FIFO_LOAD,
    input            i_FIFO_LOAD_wstrobe,

    // Start or stop the FIFO
    input            i_RUN,

    // 1 = "FIFO is ready to accept data"
    output           o_FIFO_STATUS,

    // The number of entries in the FIFO
    output reg[31:0] o_FIFO_COUNT,

    // This is the streaming output of the FIFO
    output[7:0]      axis_vector_tdata,
    output           axis_vector_tvalid,
    input            axis_vector_tready
);

// When 'clear_fifo' is asserted, we are being told to clear the FIFO
wire clear_fifo = i_FIFO_CLEAR & i_FIFO_CLEAR_wstrobe & (i_RUN == 0);

// FIFO is held in reset while this counter is non-zero
reg[7:0] fifo_reset_counter;

// FIFO is in reset when counter is non-zero, or when the module is in reset
wire fifo_resetn = ~(fifo_reset_counter > 0 || resetn == 0);

// This is a "1" when the FIFO is ready to be written to
assign o_FIFO_STATUS = (i_RUN == 0)
                     & (o_FIFO_COUNT < FIFO_DEPTH)
                     & (fifo_resetn == 1);


// The interface to the input side of the FIFO
wire[7:0] fifo_in_tdata;   // An input
wire      fifo_in_tvalid;  // An input
wire      fifo_in_tready;  // An output

// The interface to the output side of the FIFO
wire[7:0] fifo_out_tdata;   // An output
wire      fifo_out_tvalid;  // An output
wire      fifo_out_tready;  // An input

// The FIFO input is always fed from either from i_FIFO_LOAD or from the FIFO output
assign fifo_in_tdata  = (i_RUN == 0) ? i_FIFO_LOAD : fifo_out_tdata;
assign fifo_in_tvalid = (i_RUN == 0) ? i_FIFO_LOAD_wstrobe 
                                     : (axis_vector_tvalid & axis_vector_tready);

// Drive TDATA and TVALID of the output stream
assign axis_vector_tdata  = fifo_out_tdata;
assign axis_vector_tvalid = fifo_out_tvalid & i_RUN & (fifo_resetn == 1);

// TREADY to the output the FIFO comes from the output stream, gated by i_RUN
assign fifo_out_tready = axis_vector_tready & i_RUN & (fifo_resetn == 1);


//=============================================================================
// This block manages the counter that controls whether or not the FIFO is
// being held in reset
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0 || clear_fifo)
        fifo_reset_counter <= 20;
    else if (fifo_reset_counter)
        fifo_reset_counter <= fifo_reset_counter - 1;
end
//=============================================================================


//=============================================================================
// The block keeps track of the number of entries in the FIFO.  Note that
// we're only we're only truly adding entries to the FIFO when i_RUN is 0.
// When i_RUN is 1, the entries going to the FIFO are being recycled from the
// output back to the input, and therefore don't increase the number of
// entries in the FIFO.
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0 || clear_fifo)
        o_FIFO_COUNT <= 0;
    else if ((i_RUN == 0) & fifo_in_tvalid & fifo_in_tready)
        o_FIFO_COUNT <= o_FIFO_COUNT + 1;
end
//=============================================================================



//=============================================================================
// This FIFO holds a vector of 8-bit cell-values
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH(FIFO_DEPTH),        // DECIMAL
   .TDATA_WIDTH(8),                // DECIMAL
   .FIFO_MEMORY_TYPE("auto"),      // String
   .PACKET_FIFO("false"),          // String
   .USE_ADV_FEATURES("0000")       // String
)
fifo
(
    // Clock and reset
   .s_aclk   (clk        ),
   .m_aclk   (clk        ),
   .s_aresetn(fifo_resetn),

    // The input bus to the FIFO
   .s_axis_tdata (fifo_in_tdata ),
   .s_axis_tvalid(fifo_in_tvalid),
   .s_axis_tready(fifo_in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (fifo_out_tdata),
   .m_axis_tvalid(fifo_out_tvalid),
   .m_axis_tready(fifo_out_tready),

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
//=============================================================================



endmodule
