//=============================================================================
//                    ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 07-Jul-26  DWW    1  Initial
//=============================================================================

/*
    This performs the CDC for an RX stream from a CMAC:

    CMAC_RX --> register slice --> CDC FIFO --> Output
*/


module cmac_rx_cdc # (parameter DW = 512, HAS_TKEEP = 0)
(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 cmac_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis" *)
    input   cmac_clk,

    // Input stream
    input [DW-1:0]     s_axis_tdata,
    input [(DW/8)-1:0] s_axis_tkeep,
    input              s_axis_tuser,
    input              s_axis_tlast, 
    input              s_axis_tvalid,
    output             s_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sys_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET resetn" *)
    input   sys_clk,
    input   resetn,

    // Output stream
    output[DW-1:0]     m_axis_tdata,
    output[(DW/8)-1:0] m_axis_tkeep,
    output             m_axis_tuser,
    output             m_axis_tlast, 
    output             m_axis_tvalid,
    input              m_axis_tready
);

// The number of bytes in tdata
localparam DB = DW/8;

// The "resetn" signal, synchronized to "cmac_clk"
wire cmac_resetn;

// Wires between modules
wire [DW-1:0] slice_tdata , cdc_tdata ;
wire [DB-1:0] slice_tkeep , cdc_tkeep ;
wire          slice_tlast , cdc_tlast ;
wire          slice_tuser , cdc_tuser ;
wire          slice_tvalid, cdc_tvalid;
wire          slice_tready, cdc_tready;

// Connect the output of the CDC FIFO to the output bus
assign m_axis_tdata  = cdc_tdata ;
assign m_axis_tkeep  = HAS_TKEEP ? cdc_tkeep : -1;
assign m_axis_tuser  = cdc_tuser ;
assign m_axis_tlast  = cdc_tlast ;
assign m_axis_tvalid = cdc_tvalid;
assign cdc_tready = m_axis_tready;


//=============================================================================
// AXI stream register slice on the input
//=============================================================================
axis_slice #
(
    .DATA_WIDTH     (DW),
    .LAST_ENABLE    (1),
    .USER_ENABLE    (1),
    .USER_WIDTH     (1)
)
rx_slice
(
    .clk          (cmac_clk),
    .rst          (~cmac_resetn),

    .s_axis_tdata (s_axis_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? s_axis_tkeep : -1),
    .s_axis_tlast (s_axis_tlast ),
    .s_axis_tuser (s_axis_tuser ),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tid   (0),
    .s_axis_tdest (0),

    .m_axis_tdata (slice_tdata ),
    .m_axis_tkeep (slice_tkeep ),
    .m_axis_tlast (slice_tlast ),
    .m_axis_tuser (slice_tuser ),
    .m_axis_tvalid(slice_tvalid),
    .m_axis_tready(slice_tready),
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
   .TUSER_WIDTH     (1),
   .FIFO_DEPTH      (16),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("independent_clock")
)
i_cdc_fifo
(
    // Clock and reset
    .s_aclk   (cmac_clk   ),
    .m_aclk   (sys_clk    ),
    .s_aresetn(cmac_resetn),

    // The input bus of the FIFO
    .s_axis_tdata (slice_tdata ),
    .s_axis_tkeep (HAS_TKEEP ? slice_tkeep : -1),
    .s_axis_tuser (slice_tuser ),
    .s_axis_tlast (slice_tlast ),
    .s_axis_tvalid(slice_tvalid),
    .s_axis_tready(slice_tready),

    // The output bus of the FIFO
    .m_axis_tdata (cdc_tdata ),
    .m_axis_tkeep (cdc_tkeep ),
    .m_axis_tuser (cdc_tuser ),
    .m_axis_tlast (cdc_tlast ),
    .m_axis_tvalid(cdc_tvalid),
    .m_axis_tready(cdc_tready),

    // Unused input stream signals
    .s_axis_tdest(),
    .s_axis_tid  (),
    .s_axis_tstrb(),

    // Unused output stream signals
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
