module sim_pcie # (parameter DW=512, parameter AW=64)
(
    input   clk, resetn,

    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_AWADDR,
    input                                   S_AXI_AWVALID,
    input     [7:0]                         S_AXI_AWLEN,
    input     [2:0]                         S_AXI_AWSIZE,
    input     [3:0]                         S_AXI_AWID,
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
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_ARADDR,
    input                                   S_AXI_ARVALID,
    input     [2:0]                         S_AXI_ARPROT,
    input                                   S_AXI_ARLOCK,
    input     [3:0]                         S_AXI_ARID,
    input     [7:0]                         S_AXI_ARLEN,
    input     [1:0]                         S_AXI_ARBURST,
    input     [3:0]                         S_AXI_ARCACHE,
    input     [3:0]                         S_AXI_ARQOS,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY
    //==========================================================================

);

// Output side of the AR-fifo
wire[AW-1:0] s_axi_araddr;
wire[7:0]    s_axi_arlen;
wire         s_axi_arvalid;
wire         s_axi_arready;


assign S_AXI_AWREADY = (resetn == 1);
assign S_AXI_WREADY  = (resetn == 1);

reg[31:0] packets_rcvd, packets_ackd;

always @(posedge clk) begin
    if (resetn == 0)
        packets_rcvd <= 0;
    else if (S_AXI_WVALID & S_AXI_WREADY & S_AXI_WLAST)
        packets_rcvd <= packets_rcvd + 1;
end


always @(posedge clk) begin
    if (resetn == 0) 
        packets_ackd <= 0;
    else if (S_AXI_BVALID & S_AXI_BREADY)
        packets_ackd <= packets_ackd + 1;
end

assign S_AXI_BVALID = (packets_rcvd != packets_ackd);



//=============================================================================
// State machine runs the AR channel
//=============================================================================
reg    rsm_state;
assign s_axi_arready = (resetn == 1) & (rsm_state == 0);
reg[7:0] cycles_per_burst;
reg[8:0] beat;
reg[63:0] read_addr;
assign S_AXI_RLAST  = (beat == cycles_per_burst);
assign S_AXI_RRESP  = 0;
assign S_AXI_RDATA  = {(DW/64){read_addr}};
assign S_AXI_RVALID = (resetn == 1) & (rsm_state == 1);
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0)
        rsm_state <= 0;
    else case(rsm_state)

        // Wait for something to arrive on the AR-channel
        0:  if (s_axi_arvalid & s_axi_arready) begin
                beat             <= 0;
                cycles_per_burst <= s_axi_arlen;
                read_addr        <= s_axi_araddr;
                rsm_state        <= 1;
            end

        1:  if (S_AXI_RREADY & S_AXI_RVALID) begin
                beat      <= beat + 1;
                read_addr <= read_addr + (DW/8);
                if (S_AXI_RLAST) rsm_state <= 0;
            end

    endcase

end
//=============================================================================


//=============================================================================
// Holds read-requests from the AR-channel
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (16),
   .TDATA_WIDTH     (AW),
   .TUSER_WIDTH     (8),
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
   .s_axis_tuser (S_AXI_ARLEN  ),
   .s_axis_tready(S_AXI_ARREADY),

    // The output bus of the FIFO
   .m_axis_tdata (s_axi_araddr),
   .m_axis_tvalid(s_axi_arvalid),
   .m_axis_tuser (s_axi_arlen),
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



endmodule
