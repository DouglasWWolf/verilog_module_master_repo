//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 22-Mar-24  DWW     1  Initial creation
// 18-Jun-24  DWW     2  Made much more generic
// 12-Jul-24  DWW     3  Now assigning unused signals to 0
// 15-Jul-24  DWW     4  Added ARSIZE to the AXI interface definitions
//                       Now assigning values to AxID, AxCACHE, AxPROT, and AxQOS
// 17-Jul-24  DWW     5  Now de-asserting DST_AXI_WVALID & SRC_AXI_WREADY in reset
//====================================================================================

/*
    This moves a block of data from a source AXI-MM interface to a destination
    AXI-MM interface.

    Data widths of the two interfaces must match.
*/


module data_mover # (parameter DW = 512, parameter AW = 64)
(
    input       clk, resetn,
    input[63:0] src_address, dst_address, byte_count,
    input[12:0] burst_size,
    input       start,
    output      idle,

    //=================  This is the source AXI4-master interface  ================

    // "Specify write address"              -- Master --    -- Slave --
    output     [AW-1:0]                     SRC_AXI_AWADDR,
    output                                  SRC_AXI_AWVALID,
    output     [7:0]                        SRC_AXI_AWLEN,
    output     [2:0]                        SRC_AXI_AWSIZE,
    output     [3:0]                        SRC_AXI_AWID,
    output     [1:0]                        SRC_AXI_AWBURST,
    output                                  SRC_AXI_AWLOCK,
    output     [3:0]                        SRC_AXI_AWCACHE,
    output     [3:0]                        SRC_AXI_AWQOS,
    output     [2:0]                        SRC_AXI_AWPROT,
    input                                                   SRC_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     SRC_AXI_WDATA,
    output     [(DW/8)-1:0]                 SRC_AXI_WSTRB,
    output                                  SRC_AXI_WVALID,
    output                                  SRC_AXI_WLAST,
    input                                                   SRC_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              SRC_AXI_BRESP,
    input                                                   SRC_AXI_BVALID,
    output                                  SRC_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output reg [AW-1:0]                     SRC_AXI_ARADDR,
    output                                  SRC_AXI_ARVALID,
    output     [2:0]                        SRC_AXI_ARPROT,
    output                                  SRC_AXI_ARLOCK,
    output     [3:0]                        SRC_AXI_ARID,
    output     [2:0]                        SRC_AXI_ARSIZE,
    output     [7:0]                        SRC_AXI_ARLEN,
    output     [1:0]                        SRC_AXI_ARBURST,
    output     [3:0]                        SRC_AXI_ARCACHE,
    output     [3:0]                        SRC_AXI_ARQOS,
    input                                                   SRC_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input[DW-1:0]                                           SRC_AXI_RDATA,
    input                                                   SRC_AXI_RVALID,
    input[1:0]                                              SRC_AXI_RRESP,
    input                                                   SRC_AXI_RLAST,
    output                                  SRC_AXI_RREADY,
    //==========================================================================


    //============= This is the destination AXI4-master interface  =============

    // "Specify write address"              -- Master --    -- Slave --
    output reg [AW-1:0]                     DST_AXI_AWADDR,
    output                                  DST_AXI_AWVALID,
    output     [7:0]                        DST_AXI_AWLEN,
    output     [2:0]                        DST_AXI_AWSIZE,
    output     [3:0]                        DST_AXI_AWID,
    output     [1:0]                        DST_AXI_AWBURST,
    output                                  DST_AXI_AWLOCK,
    output     [3:0]                        DST_AXI_AWCACHE,
    output     [3:0]                        DST_AXI_AWQOS,
    output     [2:0]                        DST_AXI_AWPROT,
    input                                                   DST_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     DST_AXI_WDATA,
    output     [(DW/8)-1:0]                 DST_AXI_WSTRB,
    output                                  DST_AXI_WVALID,
    output                                  DST_AXI_WLAST,
    input                                                   DST_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              DST_AXI_BRESP,
    input                                                   DST_AXI_BVALID,
    output                                  DST_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output[AW-1:0]                          DST_AXI_ARADDR,
    output                                  DST_AXI_ARVALID,
    output[2:0]                             DST_AXI_ARPROT,
    output                                  DST_AXI_ARLOCK,
    output[3:0]                             DST_AXI_ARID,
    output[2:0]                             DST_AXI_ARSIZE,
    output[7:0]                             DST_AXI_ARLEN,
    output[1:0]                             DST_AXI_ARBURST,
    output[3:0]                             DST_AXI_ARCACHE,
    output[3:0]                             DST_AXI_ARQOS,
    input                                                   DST_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input[DW-1:0]                                           DST_AXI_RDATA,
    input                                                   DST_AXI_RVALID,
    input[1:0]                                              DST_AXI_RRESP,
    input                                                   DST_AXI_RLAST,
    output                                  DST_AXI_RREADY
    //==========================================================================
);

// Compute the geometry of our data movement
wire[8:0] CYCLES_PER_BURST = burst_size / (DW/8);

//==========================================================================
// Compute BURSTS_PER_MOVE 
//==========================================================================
reg[31:0] BURSTS_PER_MOVE;
always @* case(burst_size)
          4: BURSTS_PER_MOVE = byte_count / 4;
          8: BURSTS_PER_MOVE = byte_count / 8;
         16: BURSTS_PER_MOVE = byte_count / 16; 
         32: BURSTS_PER_MOVE = byte_count / 32; 
         64: BURSTS_PER_MOVE = byte_count / 64; 
        128: BURSTS_PER_MOVE = byte_count / 128; 
        256: BURSTS_PER_MOVE = byte_count / 256; 
        512: BURSTS_PER_MOVE = byte_count / 512; 
       1024: BURSTS_PER_MOVE = byte_count / 1024; 
       2048: BURSTS_PER_MOVE = byte_count / 2048; 
    default: BURSTS_PER_MOVE = byte_count / 4096; 
endcase
//==========================================================================

// State machine states
reg      arsm_state;  // AR-channel of SRC_AXI
reg      awsm_state;  // AW-channel of DST_AXI
reg[1:0] wsm_state;   // W_channel  of DST_AXI

// These count bursts for each of the state machines
reg[31:0] ar_count, aw_count, w_count;

// We're always ready to receive write-acknowledgements
assign DST_AXI_BREADY = (resetn == 1);

// The number of writes requested, and the number of writes acknowledged
reg[31:0] writes_reqd, writes_ackd;

//=============================================================================
// This block sends read-requests to the SRC_AXI interace
//=============================================================================
assign SRC_AXI_ARID    = 0;
assign SRC_AXI_ARLOCK  = 0;
assign SRC_AXI_ARQOS   = 0;
assign SRC_AXI_ARSIZE  = $clog2(DW/8);
assign SRC_AXI_ARCACHE = 2; /* Modifiable */
assign SRC_AXI_ARPROT  = 2; /* Privileged */
assign SRC_AXI_ARBURST = 1; /* Incr Burst */
assign SRC_AXI_ARLEN   = CYCLES_PER_BURST - 1 ;
assign SRC_AXI_ARVALID = (resetn == 1 && arsm_state == 1);
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        arsm_state      <= 0;
    end else case (arsm_state)

        0:  if (start) begin
                ar_count        <= 1;
                SRC_AXI_ARADDR  <= src_address;
                arsm_state      <= 1;
            end

        1:  if (SRC_AXI_ARREADY & SRC_AXI_ARVALID) begin
                if (ar_count == BURSTS_PER_MOVE) begin
                    arsm_state      <= 0;
                end begin
                    SRC_AXI_ARADDR  <= SRC_AXI_ARADDR + burst_size;
                    ar_count        <= ar_count + 1; 
                end
            end

    endcase
end
//============================================================================



//=============================================================================
// This block sends write-requests to the DST_AXI interace
//=============================================================================
assign DST_AXI_AWID    = 0;
assign DST_AXI_AWLOCK  = 0;
assign DST_AXI_AWQOS   = 0;
assign DST_AXI_AWSIZE  = $clog2(DW/8);
assign DST_AXI_AWCACHE = 2; /* Modifiable */
assign DST_AXI_AWPROT  = 2; /* Privileged */
assign DST_AXI_AWBURST = 1; /* Incr Burst */
assign DST_AXI_AWLEN   = CYCLES_PER_BURST - 1 ;
assign DST_AXI_AWSIZE  = $clog2(DW/8);
assign DST_AXI_AWVALID = (resetn == 1 && awsm_state == 1);
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    
    if (resetn == 0) begin
        awsm_state <= 0;
    end
    
    else case (awsm_state)

        0:  if (start) begin
                aw_count        <= 1;
                DST_AXI_AWADDR  <= dst_address;
                awsm_state      <= 1;
            end

        1:  if (DST_AXI_AWREADY & DST_AXI_AWVALID) begin
                if (aw_count == BURSTS_PER_MOVE) begin
                    awsm_state      <= 0;
                end begin
                    DST_AXI_AWADDR  <= DST_AXI_AWADDR + burst_size;
                    aw_count        <= aw_count + 1; 
                end
            end

    endcase
end
//============================================================================


//============================================================================
// The W-channel of DST_AXI is fed directly from the R-channel of SRC_AXI
//============================================================================
assign DST_AXI_WDATA  = SRC_AXI_RDATA;
assign DST_AXI_WSTRB  = -1;
assign DST_AXI_WLAST  = SRC_AXI_RLAST;
assign DST_AXI_WVALID = SRC_AXI_RVALID & (wsm_state == 1) & (resetn == 1);
assign SRC_AXI_RREADY = DST_AXI_WREADY & (wsm_state == 1) & (resetn == 1);
//============================================================================


//============================================================================
// This keeps track of the data-bursts as they are emitted on the W-channel
// of interface DST_AXI
//============================================================================
always @(posedge clk) begin

    if (resetn == 0) begin
        wsm_state <= 0;
    end else case(wsm_state)

        // Wait for someone to tell us to start
        0:  if (start) begin
                w_count   <= 1;
                wsm_state <= 1;
            end

        // Every time a burst completes, count it44A0
        1:  if (DST_AXI_WREADY & DST_AXI_WVALID & DST_AXI_WLAST) begin
                if (w_count == BURSTS_PER_MOVE)
                    wsm_state <= 2;
                else
                    w_count   <= w_count + 1;
            end

        // Wait for all write-bursts to be acknowledged
        2:  if (writes_ackd == writes_reqd)
                wsm_state <= 0;
    endcase

end

// We're idle whenever we're not busy writing data
assign idle = (start == 0) & (wsm_state == 0);
//============================================================================


//============================================================================
// This block counts the number of write transactions requested
//============================================================================
always @(posedge clk) begin
    if (resetn == 0)
        writes_reqd <= 0;
    else if (DST_AXI_AWVALID & DST_AXI_AWREADY)
        writes_reqd <= writes_reqd + 1;
end
//============================================================================


//============================================================================
// This block counts the number of write transactions acknowledged
//============================================================================
always @(posedge clk) begin
    if (resetn == 0)
        writes_ackd <= 0;
    else if (DST_AXI_BVALID & DST_AXI_BREADY)
        writes_ackd <= writes_ackd + 1;
end
//============================================================================


//============================================================================
// unused signals
//============================================================================

// AW-chanel of SRC_AXI
assign SRC_AXI_AWADDR  = 0;
assign SRC_AXI_AWVALID = 0;
assign SRC_AXI_AWLEN   = 0;
assign SRC_AXI_AWSIZE  = 0;
assign SRC_AXI_AWID    = 0;
assign SRC_AXI_AWBURST = 0;
assign SRC_AXI_AWLOCK  = 0;
assign SRC_AXI_AWCACHE = 0;
assign SRC_AXI_AWQOS   = 0;
assign SRC_AXI_AWPROT  = 0;

// W-channel of SRC_AXI
assign SRC_AXI_WDATA   = 0; 
assign SRC_AXI_WSTRB   = 0;
assign SRC_AXI_WVALID  = 0;
assign SRC_AXI_WLAST   = 0;

// B-channel of SRC_AXI
assign SRC_AXI_BREADY  = 0;

// AR-channel of DST_AXI
assign DST_AXI_ARADDR  = 0;
assign DST_AXI_ARVALID = 0;
assign DST_AXI_ARPROT  = 0;
assign DST_AXI_ARLOCK  = 0;
assign DST_AXI_ARID    = 0;
assign DST_AXI_ARSIZE  = 0;
assign DST_AXI_ARLEN   = 0;
assign DST_AXI_ARBURST = 0;
assign DST_AXI_ARCACHE = 0;
assign DST_AXI_ARQOS   = 0;

// R-channel of DST_AXI
assign DST_AXI_RREADY  = 0;
//============================================================================

endmodule