
//=============================================================================
//                 ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 23-Mar-25  DWW     1  Initial creation
//=============================================================================

/*

    This module works in two distinct modes:

    If "MARK_ONLY_MODE" is 0:
        Bad packets will be dropped    

    If "MARK_ONLY_MODE" is 1:
        Bad packets will be output, with TUSER=1 on every cycle

*/

module bad_packet_filter #
(
    parameter DW             = 512,
    parameter FIFO_DEPTH     = 256,
    parameter MARK_ONLY_MODE = 0
)
(
    input clk, resetn,

    // Strobes high for one cycle to signal a bad packet
    output bad_packet_strb,

    // Input stream
    input[DW-1:0]      AXIS_IN_TDATA,
    input[(DW/8)-1:0]  AXIS_IN_TKEEP,
    input              AXIS_IN_TUSER,
    input              AXIS_IN_TLAST,
    input              AXIS_IN_TVALID,
    output             AXIS_IN_TREADY,    

    // Output stream
    output[DW-1:0]     AXIS_OUT_TDATA,
    output[(DW/8)-1:0] AXIS_OUT_TKEEP,
    output             AXIS_OUT_TLAST,
    output             AXIS_OUT_TUSER,
    output             AXIS_OUT_TVALID,
    input              AXIS_OUT_TREADY    
);

// This is the TVALID output from the output side of the packet-data FIFO
wire pdf_out_tvalid;

// Entries get added to the "end of packet" FIFO on the last cycle of each incoming packet
wire feop_in_tvalid = AXIS_IN_TVALID & AXIS_IN_TREADY & AXIS_IN_TLAST;

// This is TVALID from the output side of the "end of packet" FIFO
wire feop_out_tvalid;

// This is the TREADY input to the output side of "end of packet" FIFO.  Every 
// time this cycles high, it will cause the "end of packet" FIFO to advance to 
// the next entry
wire feop_out_tready = pdf_out_tvalid & AXIS_OUT_TREADY & AXIS_OUT_TLAST;

// This strobes high for a single cycle anytime we encounter a bad packet
assign bad_packet_strb = AXIS_IN_TVALID & AXIS_IN_TREADY & AXIS_IN_TLAST & AXIS_IN_TUSER;

// We can output data if this packet is good or if we're in "mark only mode"
wire output_enable = (AXIS_OUT_TUSER == 0) | (MARK_ONLY_MODE == 1);

// We output data on the output bus whenever it's available from the FIFO
assign AXIS_OUT_TVALID = (output_enable & feop_out_tvalid);

//====================================================================================
// This FIFO holds the incoming packet data
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (FIFO_DEPTH),   // DECIMAL
   .TDATA_WIDTH     (DW),           // DECIMAL
   .FIFO_MEMORY_TYPE("auto"    ),   // String
   .PACKET_FIFO     ("false"   ),   // String
   .USE_ADV_FEATURES("0000"    )    // String
)
packet_data_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),                       
   .m_aclk   (clk   ),             
   .s_aresetn(resetn),

    // The input of this FIFO is driven directly by AXIS_IN
   .s_axis_tdata (AXIS_IN_TDATA ),  /* Input  */
   .s_axis_tkeep (AXIS_IN_TKEEP ),  /* Input  */
   .s_axis_tlast (AXIS_IN_TLAST ),  /* Input  */
   .s_axis_tvalid(AXIS_IN_TVALID),  /* Input  */
   .s_axis_tready(AXIS_IN_TREADY),  /* Output */

    // The output of this FIFO (mostly) drives AXIS_OUT
   .m_axis_tdata (AXIS_OUT_TDATA ), /* Output */     
   .m_axis_tkeep (AXIS_OUT_TKEEP ), /* Output */
   .m_axis_tlast (AXIS_OUT_TLAST ), /* Output */         
   .m_axis_tvalid(pdf_out_tvalid ), /* Output */       
   .m_axis_tready(feop_out_tvalid & AXIS_OUT_TREADY), /* Input  */

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
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
// This FIFO holds the incoming "end of packet" indicators
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (FIFO_DEPTH),   // DECIMAL
   .TDATA_WIDTH     (8         ),   // DECIMAL
   .FIFO_MEMORY_TYPE("auto"    ),   // String
   .PACKET_FIFO     ("false"   ),   // String
   .USE_ADV_FEATURES("0000"    )    // String
)
eop_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),                       
   .m_aclk   (clk   ),             
   .s_aresetn(resetn),

    // The input of this FIFO is active once per packet
   .s_axis_tdata (AXIS_IN_TUSER ), 
   .s_axis_tvalid(feop_in_tvalid),
   .s_axis_tready(              ),

    // This FIFO outputs one entry per packet
   .m_axis_tdata (AXIS_OUT_TUSER),
   .m_axis_tvalid(feop_out_tvalid),
   .m_axis_tready(feop_out_tready),

    // Unused input stream signals
   .s_axis_tlast(),
   .s_axis_tkeep(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tlast(),         
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


endmodule