module rdmx_xmit_fe # 
(
    // This width of the incoming and outgoing data bus in bits
    parameter DATA_WBITS = 512,

    // Width of an AXI address in bits
    parameter ADDR_WBITS = 64

) 
(
    input clk, resetn,
    
    //=================  This is the main AXI4-slave interface  ================
    
    // "Specify write address"              -- Master --    -- Slave --
    input[ADDR_WBITS-1:0]                   S_AXI_AWADDR,
    input                                   S_AXI_AWVALID,
    input[3:0]                              S_AXI_AWID,
    input[7:0]                              S_AXI_AWLEN,
    input[2:0]                              S_AXI_AWSIZE,
    input[1:0]                              S_AXI_AWBURST,
    input                                   S_AXI_AWLOCK,
    input[3:0]                              S_AXI_AWCACHE,
    input[3:0]                              S_AXI_AWQOS,
    input[2:0]                              S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input[DATA_WBITS-1:0]                   S_AXI_WDATA,
    input[DATA_WBITS/8-1:0]                 S_AXI_WSTRB,
    input                                   S_AXI_WVALID,
    input                                   S_AXI_WLAST,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[ADDR_WBITS-1:0]                   S_AXI_ARADDR,
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,
    input                                   S_AXI_ARLOCK,
    input[3:0]                              S_AXI_ARID,
    input[7:0]                              S_AXI_ARLEN,
    input[1:0]                              S_AXI_ARBURST,
    input[3:0]                              S_AXI_ARCACHE,
    input[3:0]                              S_AXI_ARQOS,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DATA_WBITS-1:0]                                  S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY,
    //==========================================================================


    //==========================================================================
    //                  Packet-length output stream
    //==========================================================================
    output [15:0]           AXIS_PLEN_TDATA,
    output                  AXIS_PLEN_TVALID,
    input                   AXIS_PLEN_TREADY,
    //==========================================================================

    //==========================================================================
    //                  Target address output stream
    //==========================================================================
    output [ADDR_WBITS-1:0] AXIS_ADDR_TDATA,
    output                  AXIS_ADDR_TVALID,
    input                   AXIS_ADDR_TREADY,
    //==========================================================================


    //==========================================================================
    //                    Packet-data output stream
    //==========================================================================
    output [DATA_WBITS-1:0] AXIS_DATA_TDATA,
    output                  AXIS_DATA_TLAST,
    output                  AXIS_DATA_TVALID,
    input                   AXIS_DATA_TREADY
    //==========================================================================
);


//=============================================================================
// This block counts the number of one bits in S_AXI_WSTRB, thereby determining
// the number of data-bytes in the S_AXI_WDATA field. 
//=============================================================================
reg[7:0] data_byte_count;
//-----------------------------------------------------------------------------
integer n;
always @*
begin
    data_byte_count = 0;  
    for (n=0;n<(DATA_WBITS/8);n=n+1) begin   
        data_byte_count = data_byte_count + S_AXI_WSTRB[n];
    end
end
//=============================================================================


//=============================================================================
// This block counts the number of bytes in the packet and stores them in 
// packet_size;
//=============================================================================
reg[15:0] packet_size;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        packet_size <= 0;
    end else if (S_AXI_WVALID & S_AXI_WREADY) begin
        if (S_AXI_WLAST == 0)
            packet_size <= packet_size + data_byte_count;
        else 
            packet_size <= 0;
    end
end
//=============================================================================


// Output stream "target address" is driven directly from the AW-channel
assign AXIS_ADDR_TDATA  = S_AXI_AWADDR;
assign AXIS_ADDR_TVALID = S_AXI_AWVALID;
assign S_AXI_AWREADY    = AXIS_ADDR_TREADY;

// Output stream "packet data" is driven directly from the W-channel
assign AXIS_DATA_TDATA  = S_AXI_WDATA;
assign AXIS_DATA_TLAST  = S_AXI_WLAST;
assign AXIS_DATA_TVALID = S_AXI_WVALID;
assign S_AXI_WREADY     = AXIS_DATA_TREADY;

// Output stream "packet length" gets written to on the last data-cycle
// of the incoming packet
assign AXIS_PLEN_TDATA  = packet_size + data_byte_count;
assign AXIS_PLEN_TVALID = AXIS_DATA_TVALID & AXIS_DATA_TREADY & AXIS_DATA_TLAST;

// The number of AXI write transactions received, and the number of transactions responded to
reg[63:0] transactions_rcvd, transactions_resp;

//=============================================================================
// This state machine counts the number of AXI write transactions received.
//
// Drives:
//    transactions_rcvd
//=============================================================================
always @(posedge clk) begin
    
    // If we're in reset...
    if (resetn == 0)
        transactions_rcvd <= 0;
    
    // Otherwise, if this is the last beat of a burst...
    else if (S_AXI_WVALID & S_AXI_WREADY & S_AXI_WLAST)
        transactions_rcvd <= transactions_rcvd + 1;
end
//=============================================================================



//=============================================================================
// This state machine ensures that we issue an AXI response for each AXI
// transaction that we receive.
//
// Drives:
//    S_AXI_BVALID
//    transactions_resp
//=============================================================================

// Our BRESP response is always "OKAY"
assign S_AXI_BRESP = 0;

// BVALID is asserted while there are transactions we haven't responded to
assign S_AXI_BVALID = (resetn == 1 && transactions_resp < transactions_rcvd);

// Every time we see a valid handshake on the B-channel, it means that
// we have successfully responded to an AXI write transaction
always @(posedge clk) begin
    if (resetn == 0) 
        transactions_resp <= 0;
    else if (S_AXI_BVALID & S_AXI_BREADY)
        transactions_resp <= transactions_resp + 1;
end
//=============================================================================



endmodule