//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 07-Jun-25  DWW     1  First official version
//====================================================================================

/*
    This simulates a PCI bridge or block RAM or any generic AXI4 read/write device
*/


module sim_pcie # (parameter DW=512, parameter AW=64, IW=4)
(
    input   clk, resetn,

    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_AWADDR,
    input                                   S_AXI_AWVALID,
    input     [7:0]                         S_AXI_AWLEN,
    input     [2:0]                         S_AXI_AWSIZE,
    input     [IW-1:0]                      S_AXI_AWID,
    input     [1:0]                         S_AXI_AWBURST,
    input                                   S_AXI_AWLOCK,
    input     [3:0]                         S_AXI_AWCACHE,
    input     [3:0]                         S_AXI_AWQOS,
    input     [2:0]                         S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S_AXI_WDATA,
    input     [(DW/8)-1:0]                  S_AXI_WSTRB,
    input                                   S_AXI_WVALID,
    input                                   S_AXI_WLAST,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output[IW-1:0]                                          S_AXI_BID,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_ARADDR,
    input                                   S_AXI_ARVALID,
    input     [2:0]                         S_AXI_ARPROT,
    input                                   S_AXI_ARLOCK,
    input     [IW-1:0]                      S_AXI_ARID,
    input     [7:0]                         S_AXI_ARLEN,
    input     [1:0]                         S_AXI_ARBURST,
    input     [3:0]                         S_AXI_ARCACHE,
    input     [3:0]                         S_AXI_ARQOS,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_AXI_RDATA,
    output[IW-1:0]                                          S_AXI_RID,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY
    //==========================================================================

);

// Output side of the AR-fifo
wire[AW-1:0] s_axi_araddr;
wire[IW-1:0] s_axi_arid;
wire[7:0]    s_axi_arlen;
wire         s_axi_arvalid;
wire         s_axi_arready;

// Output side of the AW-fifo
wire[IW-1:0] s_axi_awid;
wire         s_axi_awvalid;
wire         s_axi_awready;

assign S_AXI_AWREADY = s_axi_awready;
assign S_AXI_WREADY  = (resetn == 1);

reg[31:0] packets_rcvd, packets_ackd;

// Count the number of packets received on the W-channel
always @(posedge clk) begin
    if (resetn == 0)
        packets_rcvd <= 0;
    else if (S_AXI_WVALID & S_AXI_WREADY & S_AXI_WLAST)
        packets_rcvd <= packets_rcvd + 1;
end


// Count the number of packets we've acknowledge on the B-channel
always @(posedge clk) begin
    if (resetn == 0) 
        packets_ackd <= 0;
    else if (S_AXI_BVALID & S_AXI_BREADY)
        packets_ackd <= packets_ackd + 1;
end

// We'll respond with a B-channel ID that matches the AWID value 
// from the most recent outstanding write-request
assign S_AXI_BID = s_axi_awid;

// BVALID is asserted when we have an unacknowledged packet and
// we have a BID (from the FIFO) to acknowledge it with.
assign S_AXI_BVALID = (packets_rcvd != packets_ackd) & (s_axi_awvalid);


//=============================================================================
// State machine runs the AR channel
//=============================================================================
reg    rsm_state;
assign s_axi_arready = (resetn == 1) & (rsm_state == 0);
reg[7:0] cycles_per_burst;
reg[8:0] beat;
reg[63:0] read_addr;
reg[IW-1:0] arid;

assign S_AXI_RLAST  = (beat == cycles_per_burst);
assign S_AXI_RRESP  = 0;
assign S_AXI_RDATA  = {(DW/64){read_addr}};
assign S_AXI_RID    = arid;
assign S_AXI_RVALID = (resetn == 1) & (rsm_state == 1);
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0)
        rsm_state <= 0;
    else case(rsm_state)

        // Wait for something to arrive on the AR-channel
        0:  if (s_axi_arvalid & s_axi_arready) begin
                beat             <= 0;
                arid             <= s_axi_arid;
                cycles_per_burst <= s_axi_arlen;
                read_addr        <= s_axi_araddr;
                rsm_state        <= 1;
            end

        // Send out response data on the R-channel
        1:  if (S_AXI_RREADY & S_AXI_RVALID) begin
                beat      <= beat + 1;
                read_addr <= read_addr + (DW/8);
                if (S_AXI_RLAST) rsm_state <= 0;
            end

    endcase

end
//=============================================================================

//=============================================================================
// Holds read-requests from the AR-channel.  TDATA holds the address of the
// read request, and TUSER holds "{ARID, ARLEN}"
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (16),
   .TDATA_WIDTH     (AW),
   .TUSER_WIDTH     (IW+8),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CDC_SYNC_STAGES (2),
   .CLOCKING_MODE   ("common_clock")
)
ar_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus to the FIFO comes straight from the AR-channel
   .s_axis_tdata (S_AXI_ARADDR ),
   .s_axis_tvalid(S_AXI_ARVALID),
   .s_axis_tuser ({S_AXI_ARID,S_AXI_ARLEN}),
   .s_axis_tready(S_AXI_ARREADY),

    // The output bus of the FIFO
   .m_axis_tdata (s_axi_araddr),
   .m_axis_tvalid(s_axi_arvalid),
   .m_axis_tuser ({s_axi_arid, s_axi_arlen}),
   .m_axis_tready(s_axi_arready),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tkeep(),
   .s_axis_tlast(),

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
// Holds one AWID value for every write-request from the AW-channel.  We 
// will send out a B-channel using these entries for the BID values
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (16),
   .TDATA_WIDTH     (8),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CDC_SYNC_STAGES (2),
   .CLOCKING_MODE   ("common_clock")
)
aw_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus to the FIFO comes straight from the AW-channel
   .s_axis_tdata (S_AXI_AWID   ),
   .s_axis_tvalid(S_AXI_AWVALID),
   .s_axis_tready(S_AXI_AWREADY),

    // The output bus of the FIFO
   .m_axis_tdata (s_axi_awid   ),
   .m_axis_tvalid(s_axi_awvalid),
   .m_axis_tready(S_AXI_BVALID & S_AXI_BREADY),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tkeep(),
   .s_axis_tlast(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tkeep(),
   .m_axis_tlast(),
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
//=============================================================================







endmodule
