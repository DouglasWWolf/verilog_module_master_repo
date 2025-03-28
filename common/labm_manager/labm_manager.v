//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 27-Mar-25  DWW     1  Initial creation
//====================================================================================

/*
    labm_manager - Laguna ABM manager

    This module listens for read-requests on S_AXI, and translates them into a pair
    of read-requests on M_AXI, with the two requests accessing two different buffers
    in host RAM.   The resulting data returned from those two requests is bitwise OR'd
    together as it is handed off to the R-channel of the S_AXI interface.

    When data arrives on the R-channel of M_AXI, it is funnelled into one of two FIFOs.
    The output of those FIFOs is what drives the R-channel of the S_AXI interface.

*/


module labm_manager # (parameter DW=32, AW=20, FIFO_DEPTH=256)
(
    input   clk, resetn,

    // The host-RAM addresses of the two ABMs that we'll fetch
    input[63:0] abm0_addr, abm1_addr,

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
    input     [2:0]                         S_AXI_ARSIZE,
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
    input                                   S_AXI_RREADY,
    //==========================================================================



    //==================  This is an AXI4-master interface  ===================

    // "Specify write address"              -- Master --    -- Slave --
    output     [63:0]                       M_AXI_AWADDR,
    output                                  M_AXI_AWVALID,
    output     [7:0]                        M_AXI_AWLEN,
    output     [2:0]                        M_AXI_AWSIZE,
    output     [3:0]                        M_AXI_AWID,
    output     [1:0]                        M_AXI_AWBURST,
    output                                  M_AXI_AWLOCK,
    output     [3:0]                        M_AXI_AWCACHE,
    output     [3:0]                        M_AXI_AWQOS,
    output     [2:0]                        M_AXI_AWPROT,
    input                                                   M_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     M_AXI_WDATA,
    output     [(DW/8)-1:0]                 M_AXI_WSTRB,
    output                                  M_AXI_WVALID,
    output                                  M_AXI_WLAST,
    input                                                   M_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              M_AXI_BRESP,
    input                                                   M_AXI_BVALID,
    output                                  M_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output reg [63:0]                       M_AXI_ARADDR,
    output reg                              M_AXI_ARVALID,
    output     [2:0]                        M_AXI_ARPROT,
    output                                  M_AXI_ARLOCK,
    output     [3:0]                        M_AXI_ARID,
    output     [2:0]                        M_AXI_ARSIZE,
    output reg [7:0]                        M_AXI_ARLEN,
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

genvar i;

// When these are 1, the entire burst for the corresponding ABM has been fetched
reg[1:0] abm_fetched;

// When this is high, 'abm_fetched[1:0]' will be cleared
reg begin_new_burst;

// When we read from the PCIe bridge, this determines which FIFO the
// resulting data gets written to
reg fifo_select;

// This will be true on the last data-cycle of the incoming burst data
wire last_xfer = M_AXI_RREADY & M_AXI_RVALID & M_AXI_RLAST;

// The state of the state machine
reg[1:0] fsm_state;
localparam FSM_IDLE          = 0;
localparam FSM_WAIT_REQ0_ACK = 1;
localparam FSM_WAIT_REQ1_ACK = 2;
localparam FSM_WAIT_DATA     = 3;

// This is the offset we're reading from in the ABMs
reg[63:0] araddr;

// These are the tready signals from the input side of the two FIFOs
wire f0_in_tready, f1_in_tready;

// The tvalid signals for the input side of the two FIFOS
wire f0_in_tvalid = (fifo_select == 0) & M_AXI_RVALID;
wire f1_in_tvalid = (fifo_select == 1) & M_AXI_RVALID;

// These wires are the output side of the two FIFOS
wire[DW-1:0] f0_out_tdata,  f1_out_tdata;
wire         f0_out_tlast,  f1_out_tlast;
wire         f0_out_tvalid, f1_out_tvalid;

// The output of the FIFOs should advance only when S_AXI is ready to 
// receive and *both* FIFOs have valid data presented on the output
wire fifo_out_tready = S_AXI_RREADY & f0_out_tvalid & f1_out_tvalid;

//=============================================================================
// This sets one of the abm_fetched[] flags when it sees the last data-cycle
// of data arrive from the R-channel of M_AXI
//=============================================================================
for (i=0; i<2; i=i+1) begin
    always @(posedge clk) begin
        if (resetn == 0 || begin_new_burst)
            abm_fetched[i] <= 0;
        else if (last_xfer && fifo_select == i)
            abm_fetched[i] <= 1;
    end
end
//=============================================================================


//=============================================================================
// This manages the "fifo_select" register that determines which FIFO the 
// data arriving from the R-channel of M_AXI gets funneled into.
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0 || begin_new_burst) 
        fifo_select <= 0;
    else if (last_xfer)
        fifo_select <= 1;
end
//=============================================================================



//=============================================================================
// This state machine waits for a read-request to arrive on the AR-channel of
// S_AXI, then services it by issuing two corresponding read-requests on the AR
// channel of M_AXI.   The returned data from the R-channel of M_AXI will flow
// into a pair of FIFOs.  The outputs of the FIFOs are or'd together and 
// presented to the R-channel of S_AXI.
//=============================================================================
always @(posedge clk) begin
    
    // This will strobe high for a single cycle at a time
    begin_new_burst <= 0;

    // If we're in reset, initialize things
    if (resetn == 0) begin
        fsm_state     <= FSM_IDLE;
        M_AXI_ARVALID <= 0;
    end

    else case (fsm_state)

        // Here we wait for a read-request to arrive on S_AXI.  When 
        // it does, we issue the first of two read-requests on M_AXI.
        // The burst size of the read-request on M_AXI is the same
        // size of the burst-request that arrived on S_AXI.
        FSM_IDLE:   
            if (S_AXI_ARVALID & S_AXI_ARREADY) begin
                araddr          <= S_AXI_ARADDR;
                M_AXI_ARADDR    <= S_AXI_ARADDR + abm0_addr;
                M_AXI_ARLEN     <= S_AXI_ARLEN;
                M_AXI_ARVALID   <= 1;
                begin_new_burst <= 1;
                fsm_state       <= FSM_WAIT_REQ0_ACK;
            end

        // Wait for our 1st read-request to be acknowledged.  Once
        // that happens, issue our 2nd read request.        
        FSM_WAIT_REQ0_ACK:
            if (M_AXI_ARVALID & M_AXI_ARREADY) begin
                M_AXI_ARADDR  <= araddr + abm1_addr;
                fsm_state     <= FSM_WAIT_REQ1_ACK;
            end

        // Wait for the 2nd read-request to be acknowledged
        FSM_WAIT_REQ1_ACK:
            if (M_AXI_ARVALID & M_AXI_ARREADY) begin
                M_AXI_ARVALID <= 0;
                fsm_state     <= FSM_WAIT_DATA;
            end

        // Wait for all data to finish flowing into the FIFOs
        FSM_WAIT_DATA:
            if (abm_fetched == 2'b11) fsm_state <= FSM_IDLE;

    endcase
    
end
//=============================================================================

// We're ready to accept a new read request when we're idle
assign S_AXI_ARREADY = (fsm_state == FSM_IDLE) & (resetn);

// The data presented to the R-channel of S_AXI is the bitwise OR of the FIFO outputs
assign S_AXI_RDATA  = f0_out_tdata | f1_out_tdata;

// When both FIFOs are valid, TLAST for fifo_0 will always match TLAST for fifo_1
assign S_AXI_RLAST  = f0_out_tlast;

// Data on the R-channel of S_AXI is valid only when both FIFOs have valid outputs
assign S_AXI_RVALID = f0_out_tvalid & f1_out_tvalid;

// The response-type to the R-channel of S_AXI will always be "OKAY"
assign S_AXI_RRESP  = 0;

// The M_AXI_RREADY output comes from the input side of one of the FIFOs
assign M_AXI_RREADY = (fifo_select == 0) ? f0_in_tready : f1_in_tready;


//=============================================================================
// Constant port values for read-requests made on the AR-channel of M_AXI
//=============================================================================
assign M_AXI_ARPROT  = 0;
assign M_AXI_ARSIZE  = $clog2(DW/8);
assign M_AXI_ARLOCK  = 0;
assign M_AXI_ARID    = 0;
assign M_AXI_ARBURST = 1;
assign M_AXI_ARCACHE = 0;
assign M_AXI_ARQOS   = 0;
//=============================================================================


//=============================================================================
// We don't use the write-side of the S_AXI interface
//=============================================================================
assign S_AXI_AWREADY = 0;
assign S_AXI_WREADY  = 0;
assign S_AXI_BRESP   = 0;
assign S_AXI_BVALID  = 0;
//=============================================================================

//=============================================================================
// We don't use the write-side of the M_AXI interface
//=============================================================================
assign M_AXI_AWADDR  = 0;
assign M_AXI_AWVALID = 0;
assign M_AXI_AWLEN   = 0;
assign M_AXI_AWSIZE  = 0;
assign M_AXI_AWID    = 0;
assign M_AXI_AWBURST = 0;
assign M_AXI_AWLOCK  = 0;
assign M_AXI_AWCACHE = 0;
assign M_AXI_AWQOS   = 0;
assign M_AXI_AWPROT  = 0;
assign M_AXI_WDATA   = 0;
assign M_AXI_WSTRB   = 0;
assign M_AXI_WVALID  = 0;
assign M_AXI_WLAST   = 0;
assign M_AXI_BREADY  = 0;
//=============================================================================


//=============================================================================
// This FIFO holds data received from the R-channel of M_AXI
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (FIFO_DEPTH),
   .TDATA_WIDTH     (DW),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
fifo_0
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus of the FIFO
   .s_axis_tdata (M_AXI_RDATA ),
   .s_axis_tlast (M_AXI_RLAST ),   
   .s_axis_tvalid(f0_in_tvalid),
   .s_axis_tready(f0_in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (f0_out_tdata   ),
   .m_axis_tlast (f0_out_tlast   ),   
   .m_axis_tvalid(f0_out_tvalid  ),
   .m_axis_tready(fifo_out_tready),

    // Unused input stream signals
   .s_axis_tkeep(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tuser(),
   .m_axis_tkeep(),

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
// This FIFO holds data received from the R-channel of M_AXI
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH      (FIFO_DEPTH),
   .TDATA_WIDTH     (DW),
   .FIFO_MEMORY_TYPE("auto"),
   .PACKET_FIFO     ("false"),
   .USE_ADV_FEATURES("0000"),
   .CLOCKING_MODE   ("common_clock")
)
fifo_1
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input bus of the FIFO
   .s_axis_tdata (M_AXI_RDATA ),
   .s_axis_tlast (M_AXI_RLAST ),   
   .s_axis_tvalid(f1_in_tvalid),
   .s_axis_tready(f1_in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (f1_out_tdata   ),
   .m_axis_tlast (f1_out_tlast   ),   
   .m_axis_tvalid(f1_out_tvalid  ),
   .m_axis_tready(fifo_out_tready),

    // Unused input stream signals
   .s_axis_tkeep(),
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tuser(),
   .m_axis_tkeep(),

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

