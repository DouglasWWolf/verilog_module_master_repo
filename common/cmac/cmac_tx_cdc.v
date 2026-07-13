//=============================================================================
//                    ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 07-Jul-26  DWW    1  Initial
//=============================================================================

/*
    This performs the CDC for a TX stream to a CMAC:

    Input -> Slice --> CDC FIFO --> Packet FIFO --> Slice --> Output
*/


module cmac_tx_cdc # (parameter DW = 512, HAS_TKEEP = 0)
(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sys_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET resetn" *)
    input   sys_clk,
    input   resetn,

    // Input stream
    input [DW-1:0]     s_axis_tdata,
    input [(DW/8)-1:0] s_axis_tkeep,
    input              s_axis_tlast, 
    input              s_axis_tvalid,
    output             s_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 cmac_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis" *)
    input   cmac_clk,

    // Output stream
    output[DW-1:0]     m_axis_tdata,
    output[(DW/8)-1:0] m_axis_tkeep,
    output             m_axis_tlast, 
    output             m_axis_tvalid,
    input              m_axis_tready
);

// The number of bytes in tdata
localparam DB = DW/8;

// The "resetn" signal, synchronized to "cmac_clk"
wire cmac_resetn;

// Wires between modules
wire [DW-1:0] slice0_tdata , cdc_tdata , packet_tdata ;
wire [DB-1:0] slice0_tkeep , cdc_tkeep , packet_tkeep ;
wire          slice0_tlast , cdc_tlast , packet_tlast ;
wire          slice0_tvalid, cdc_tvalid, packet_tvalid;
wire          slice0_tready, cdc_tready, packet_tready;


//=============================================================================
// AXI stream register slice on the input
//=============================================================================
axis_slice #
(
    .DATA_WIDTH     (DW),
    .LAST_ENABLE    (1),
    .USER_ENABLE    (0),
    .USER_WIDTH     (1)
)
tx_slice_0
(
    .clk          (sys_clk),
    .rst          (~resetn),

    .s_axis_tdata (s_axis_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? s_axis_tkeep : -1),
    .s_axis_tlast (s_axis_tlast ),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tuser (0),
    .s_axis_tid   (0),
    .s_axis_tdest (0),

    .m_axis_tdata (slice0_tdata ),
    .m_axis_tkeep (slice0_tkeep ),
    .m_axis_tlast (slice0_tlast ),
    .m_axis_tvalid(slice0_tvalid),
    .m_axis_tready(slice0_tready),
    .m_axis_tuser (0),
    .m_axis_tid   (0),
    .m_axis_tdest (0)
);
//=============================================================================






//=============================================================================
// This is the clock-crossing FIFO
//=============================================================================
xpm_fifo_axis #
(
   .TDATA_WIDTH     (DW),
   .FIFO_DEPTH      (16),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("independent_clock")
)
i_cdc_fifo
(
    // Clock and reset
    .s_aclk   (sys_clk ),
    .m_aclk   (cmac_clk),
    .s_aresetn(resetn  ),

    // The input bus of the FIFO
    .s_axis_tdata (slice0_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? slice0_tkeep : -1),
    .s_axis_tlast (slice0_tlast ),
    .s_axis_tvalid(slice0_tvalid),
    .s_axis_tready(slice0_tready),

    // The output bus of the FIFO
    .m_axis_tdata (cdc_tdata ),
    .m_axis_tkeep (cdc_tkeep ),
    .m_axis_tlast (cdc_tlast ),
    .m_axis_tvalid(cdc_tvalid),
    .m_axis_tready(cdc_tready),

    // Unused input stream signals
    .s_axis_tuser(),
    .s_axis_tdest(),
    .s_axis_tid  (),
    .s_axis_tstrb(),

    // Unused output stream signals
    .m_axis_tuser(),
    .m_axis_tdest(),
    .m_axis_tid  (),
    .m_axis_tstrb(),

    // Other unused signals
    .almost_empty_axis (),
    .almost_full_axis  (),
    .dbiterr_axis      (),
    .prog_empty_axis   (),
    .prog_full_axis    (),
    .rd_data_count_axis(),
    .sbiterr_axis      (),
    .wr_data_count_axis(),
    .injectdbiterr_axis(),
    .injectsbiterr_axis()
);
//=============================================================================



//=============================================================================
// This is the packetizing FIFO
//=============================================================================
xpm_fifo_axis #
(
   .TDATA_WIDTH     (DW),
   .FIFO_DEPTH      (512),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("true"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
i_packet_fifo
(
    // Clock and reset
    .s_aclk   (cmac_clk   ),
    .m_aclk   (cmac_clk   ),
    .s_aresetn(cmac_resetn),

    // The input bus of the FIFO
    .s_axis_tdata (cdc_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? cdc_tkeep : -1),
    .s_axis_tlast (cdc_tlast ),
    .s_axis_tvalid(cdc_tvalid),
    .s_axis_tready(cdc_tready),

    // The output bus of the FIFO
    .m_axis_tdata (packet_tdata ),
    .m_axis_tkeep (packet_tkeep ),
    .m_axis_tlast (packet_tlast ),
    .m_axis_tvalid(packet_tvalid),
    .m_axis_tready(packet_tready),

    // Unused input stream signals
    .s_axis_tuser(),
    .s_axis_tdest(),
    .s_axis_tid  (),
    .s_axis_tstrb(),

    // Unused output stream signals
    .m_axis_tuser(),
    .m_axis_tdest(),
    .m_axis_tid  (),
    .m_axis_tstrb(),

    // Other unused signals
    .almost_empty_axis (),
    .almost_full_axis  (),
    .dbiterr_axis      (),
    .prog_empty_axis   (),
    .prog_full_axis    (),
    .rd_data_count_axis(),
    .sbiterr_axis      (),
    .wr_data_count_axis(),
    .injectdbiterr_axis(),
    .injectsbiterr_axis()
);
//=============================================================================


//=============================================================================
// AXI stream register slice between the packetizing FIFO and the output
//=============================================================================
axis_slice #
(
    .DATA_WIDTH     (DW),
    .LAST_ENABLE    (1),
    .USER_ENABLE    (0),
    .USER_WIDTH     (1)
)
tx_slice_1
(
    .clk          (cmac_clk),
    .rst          (~cmac_resetn),

    .s_axis_tdata (packet_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? packet_tkeep : -1),
    .s_axis_tlast (packet_tlast ),
    .s_axis_tvalid(packet_tvalid),
    .s_axis_tready(packet_tready),
    .s_axis_tuser (0),
    .s_axis_tid   (0),
    .s_axis_tdest (0),

    .m_axis_tdata (m_axis_tdata ),
    .m_axis_tkeep (m_axis_tkeep ),
    .m_axis_tlast (m_axis_tlast ),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tuser (0),
    .m_axis_tid   (0),
    .m_axis_tdest (0)
);
//=============================================================================





//=============================================================================
// Create a reset signal that's synchronized to cmac_clk
//=============================================================================
xpm_cdc_async_rst #
(
    .DEST_SYNC_FF(4), .RST_ACTIVE_HIGH(0)
)
i_sync_resetn
(
    .src_arst    (resetn),
    .dest_clk    (cmac_clk),
    .dest_arst   (cmac_resetn)
);
//=============================================================================



endmodule
