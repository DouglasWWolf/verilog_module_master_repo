//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 17-Jun-25  DWW     1  Initial creation
//====================================================================================

/*

    Provides a memory fencing mechanism for an AXI4-MM interface

*/

module axi4_memfence # (parameter DW=512, AW=64, IW=4)
(
    input       clk, resetn,

    //============= This is the input AXI4-master interface  =============

    // "Specify write address"              -- Master --    -- Slave --
    input      [AW-1:0]                     SRC_AXI_AWADDR,
    input                                   SRC_AXI_AWUSER,
    input                                   SRC_AXI_AWVALID,
    input      [7:0]                        SRC_AXI_AWLEN,
    input      [2:0]                        SRC_AXI_AWSIZE,
    input      [IW-1:0]                     SRC_AXI_AWID,
    input      [1:0]                        SRC_AXI_AWBURST,
    input                                   SRC_AXI_AWLOCK,
    input      [3:0]                        SRC_AXI_AWCACHE,
    input      [3:0]                        SRC_AXI_AWQOS,
    input      [2:0]                        SRC_AXI_AWPROT,
    output                                                  SRC_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input      [DW-1:0]                     SRC_AXI_WDATA,
    input      [(DW/8)-1:0]                 SRC_AXI_WSTRB,
    input                                   SRC_AXI_WVALID,
    input                                   SRC_AXI_WLAST,
    output                                                  SRC_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output    [1:0]                                         SRC_AXI_BRESP,
    output    [IW-1:0]                                      SRC_AXI_BID,
    output                                                  SRC_AXI_BVALID,
    input                                   SRC_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input [AW-1:0]                          SRC_AXI_ARADDR,
    input                                   SRC_AXI_ARVALID,
    input [2:0]                             SRC_AXI_ARPROT,
    input                                   SRC_AXI_ARLOCK,
    input [IW-1:0]                          SRC_AXI_ARID,
    input [2:0]                             SRC_AXI_ARSIZE,
    input [7:0]                             SRC_AXI_ARLEN,
    input [1:0]                             SRC_AXI_ARBURST,
    input [3:0]                             SRC_AXI_ARCACHE,
    input [3:0]                             SRC_AXI_ARQOS,
    output                                                  SRC_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          SRC_AXI_RDATA,
    output[IW-1:0]                                          SRC_AXI_RID,
    output                                                  SRC_AXI_RVALID,
    output[1:0]                                             SRC_AXI_RRESP,
    output                                                  SRC_AXI_RLAST,
    input                                   SRC_AXI_RREADY,
    //==========================================================================


    //=================  This output AXI4-master interface  ================

    // "Specify write address"              -- Master --    -- Slave --
    output     [AW-1:0]                     DST_AXI_AWADDR,
    output                                  DST_AXI_AWVALID,
    output     [7:0]                        DST_AXI_AWLEN,
    output     [2:0]                        DST_AXI_AWSIZE,
    output     [IW-1:0]                     DST_AXI_AWID,
    output     [1:0]                        DST_AXI_AWBURST,
    output                                  DST_AXI_AWLOCK,
    output     [3:0]                        DST_AXI_AWCACHE,
    output     [3:0]                        DST_AXI_AWQOS,
    output     [2:0]                        DST_AXI_AWPROT,
    input                                                   DST_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     DST_AXI_WDATA,
    output     [DW/8-1:0]                   DST_AXI_WSTRB,
    output                                  DST_AXI_WVALID,
    output                                  DST_AXI_WLAST,
    input                                                   DST_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input      [1:0]                                        DST_AXI_BRESP,
    input      [IW-1:0]                                     DST_AXI_BID,
    input                                                   DST_AXI_BVALID,
    output                                  DST_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output     [AW-1:0]                     DST_AXI_ARADDR,
    output                                  DST_AXI_ARVALID,
    output     [2:0]                        DST_AXI_ARPROT,
    output                                  DST_AXI_ARLOCK,
    output     [IW-1:0]                     DST_AXI_ARID,
    output     [2:0]                        DST_AXI_ARSIZE,
    output     [7:0]                        DST_AXI_ARLEN,
    output     [1:0]                        DST_AXI_ARBURST,
    output     [3:0]                        DST_AXI_ARCACHE,
    output     [3:0]                        DST_AXI_ARQOS,
    input                                                   DST_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input      [DW-1:0]                                     DST_AXI_RDATA,
    input      [IW-1:0]                                     DST_AXI_RID,
    input                                                   DST_AXI_RVALID,
    input      [1:0]                                        DST_AXI_RRESP,
    input                                                   DST_AXI_RLAST,
    output                                  DST_AXI_RREADY
    //==========================================================================
);

// Output on the AW channel is suspended when this is 0
reg aw_enable;

// A write-request while AWUSER is asserted will cause a memory fence transaction
wire memfence_flag = SRC_AXI_AWVALID & SRC_AXI_AWUSER;

// Define handshakes for the outgoing AW and B channels
wire  b_handshake = DST_AXI_BVALID  & DST_AXI_BREADY;
wire aw_handshake = DST_AXI_AWVALID & DST_AXI_AWREADY;

//=============================================================================
// The possible states of our finite state machine
//=============================================================================
reg[2:0]   fsm_state;
localparam FSM_NORMAL_FLOW       = 0;
localparam FSM_WAIT_FOR_ACKS     = 1;
localparam FSM_WAIT_AR_HSK       = 2;
localparam FSM_WAIT_READ_DATA    = 3;
localparam FSM_WAIT_FENCED_WRITE = 4;
//=============================================================================


//=============================================================================
// This block keeps track of the number of write-requests that have not yet
// been acknowledged on the B-channel
//=============================================================================
reg[15:0] pending_writes;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0)
        pending_writes <= 0;
    else if (aw_handshake & !b_handshake)
        pending_writes <= pending_writes + 1;
    else if (b_handshake & !aw_handshake)
        pending_writes <= pending_writes - 1;
end
//=============================================================================

// This will assert on the same clock cycle where we receive the ackowledgement
// from the final pending write
wire no_pending_writes = (pending_writes == 0) 
                       | (pending_writes == 1 && b_handshake && !aw_handshake);


//=============================================================================
// Here we control exactly when write-requests are allowed to flow across
// the AW channel.
//
// During normal flow, we allow write-requests to be emitted unless the AWUSER 
// flag is asserted.    We also allow a write-request to be emitted when we
// are in the state where we emit the "fenced" write-request
//=============================================================================
always @* begin
    
    case (fsm_state)
        
        FSM_NORMAL_FLOW:
            aw_enable = (memfence_flag == 0);

        FSM_WAIT_FENCED_WRITE:
            aw_enable = 1;

        default:
            aw_enable = 0;

    endcase
end
//=============================================================================



//=============================================================================
// This block manages transitions of our state machine
//=============================================================================
always @(posedge clk) begin

    if (resetn == 0) begin
        fsm_state <= FSM_NORMAL_FLOW;
    end

    else case (fsm_state)

        // Data flows normally from the input to the output until we
        // discover the memfence flag (i.e., AWVALID & AWUSER) is asserted
        FSM_NORMAL_FLOW:
            if (memfence_flag) begin
                fsm_state <= FSM_WAIT_FOR_ACKS;
            end

        // Here we wait for all of our pending write-requests to be acknowledged
        FSM_WAIT_FOR_ACKS:
            if (no_pending_writes) begin
                fsm_state <= FSM_WAIT_AR_HSK;
            end

        // Here we wait for the read-request to be accepted
        FSM_WAIT_AR_HSK:
            if (DST_AXI_ARVALID & DST_AXI_ARREADY) begin
                fsm_state <= FSM_WAIT_READ_DATA;
            end

        // Here we wait to receive the read response.
        FSM_WAIT_READ_DATA:
            if (DST_AXI_RREADY & DST_AXI_RVALID) begin
                fsm_state <= FSM_WAIT_FENCED_WRITE;
            end

        // After all pending write-requests have been acknowledged and
        // after a read-request has been satisfied, we can be gauranteed
        // that all prior write-requests have been completed and it is
        // now safe to issue the "fenced" write-request
        FSM_WAIT_FENCED_WRITE:
            if (DST_AXI_AWREADY & DST_AXI_AWVALID) begin
                fsm_state <= FSM_NORMAL_FLOW;
            end

    endcase
end
//=============================================================================


// The AW handshake only occurs when aw_enable is asserted
assign DST_AXI_AWVALID = SRC_AXI_AWVALID & aw_enable; 
assign SRC_AXI_AWREADY = DST_AXI_AWREADY & aw_enable;

// The output AW channel is driven directly from the input
assign DST_AXI_AWADDR  = SRC_AXI_AWADDR ; 
assign DST_AXI_AWLEN   = SRC_AXI_AWLEN  ; 
assign DST_AXI_AWSIZE  = SRC_AXI_AWSIZE ; 
assign DST_AXI_AWID    = SRC_AXI_AWID   ; 
assign DST_AXI_AWBURST = SRC_AXI_AWBURST; 
assign DST_AXI_AWLOCK  = SRC_AXI_AWLOCK ; 
assign DST_AXI_AWCACHE = SRC_AXI_AWCACHE; 
assign DST_AXI_AWQOS   = SRC_AXI_AWQOS  ; 
assign DST_AXI_AWPROT  = SRC_AXI_AWPROT ; 


// The output W channel is driven directly from the input
assign DST_AXI_WDATA   = SRC_AXI_WDATA  ; 
assign DST_AXI_WSTRB   = SRC_AXI_WSTRB  ; 
assign DST_AXI_WVALID  = SRC_AXI_WVALID ; 
assign DST_AXI_WLAST   = SRC_AXI_WLAST  ; 
assign SRC_AXI_WREADY  = DST_AXI_WREADY ;


// The output R-channel mostly copies the input AW channel
assign DST_AXI_ARADDR  = SRC_AXI_AWADDR;
assign DST_AXI_ARVALID = (fsm_state == FSM_WAIT_AR_HSK);
assign DST_AXI_ARPROT  = SRC_AXI_AWPROT;
assign DST_AXI_ARLOCK  = SRC_AXI_ARLOCK;
assign DST_AXI_ARID    = SRC_AXI_AWID;
assign DST_AXI_ARSIZE  = $clog2(DW/8);
assign DST_AXI_ARLEN   = 0;
assign DST_AXI_ARBURST = 1;
assign DST_AXI_ARCACHE = SRC_AXI_AWCACHE;
assign DST_AXI_ARQOS   = SRC_AXI_AWQOS;

// The output B-channel feeds the input B-channel
assign SRC_AXI_BRESP  = DST_AXI_BRESP;
assign SRC_AXI_BID    = DST_AXI_BID;
assign SRC_AXI_BVALID = DST_AXI_BVALID;
assign DST_AXI_BREADY = SRC_AXI_BREADY;

// The read-related channels of the input interface go unused
assign SRC_AXI_ARREADY = 0;
assign SRC_AXI_RDATA   = 0;
assign SRC_AXI_RID     = 0;
assign SRC_AXI_RVALID  = 0;
assign SRC_AXI_RRESP   = 0;
assign SRC_AXI_RLAST   = 0;

// And we're always read to receive data on the output side's R-channel
assign DST_AXI_RREADY = (resetn == 1);

endmodule