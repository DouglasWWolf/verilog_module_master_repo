//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 18-Jun-24  DWW     1  Initial creation
//=============================================================================

/*
    This module has two AXI4-MM slave interfaces and a single AXI4-MM master
    interface.

    The "select_s1" input determines which slave interface is connected to
    the master interface

*/

module abm_mux # (parameter DW=512, AW=64)
(
    // This is just to keep the IP Integrator happy
    input   clk,

    // This selects which slave interface is connected to the master interface
    input   select_s1,

    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S0_AXI_AWADDR,
    input                                   S0_AXI_AWVALID,
    input     [7:0]                         S0_AXI_AWLEN,
    input     [2:0]                         S0_AXI_AWSIZE,
    input     [3:0]                         S0_AXI_AWID,
    input     [1:0]                         S0_AXI_AWBURST,
    input                                   S0_AXI_AWLOCK,
    input     [3:0]                         S0_AXI_AWCACHE,
    input     [3:0]                         S0_AXI_AWQOS,
    input     [2:0]                         S0_AXI_AWPROT,
    output                                                  S0_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S0_AXI_WDATA,
    input     [(DW/8)-1:0]                  S0_AXI_WSTRB,
    input                                   S0_AXI_WVALID,
    input                                   S0_AXI_WLAST,
    output                                                   S0_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output    [1:0]                                         S0_AXI_BRESP,
    output                                                  S0_AXI_BVALID,
    input                                   S0_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S0_AXI_ARADDR,
    input                                   S0_AXI_ARVALID,
    input     [2:0]                         S0_AXI_ARPROT,
    input                                   S0_AXI_ARLOCK,
    input     [3:0]                         S0_AXI_ARID,
    input     [2:0]                         S0_AXI_ARSIZE,
    input     [7:0]                         S0_AXI_ARLEN,
    input     [1:0]                         S0_AXI_ARBURST,
    input     [3:0]                         S0_AXI_ARCACHE,
    input     [3:0]                         S0_AXI_ARQOS,
    output                                                  S0_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output    [DW-1:0]                                      S0_AXI_RDATA,
    output                                                  S0_AXI_RVALID,
    output    [1:0]                                         S0_AXI_RRESP,
    output                                                  S0_AXI_RLAST,
    input                                   S0_AXI_RREADY,
    //==========================================================================



    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S1_AXI_AWADDR,
    input                                   S1_AXI_AWVALID,
    input     [7:0]                         S1_AXI_AWLEN,
    input     [2:0]                         S1_AXI_AWSIZE,
    input     [3:0]                         S1_AXI_AWID,
    input     [1:0]                         S1_AXI_AWBURST,
    input                                   S1_AXI_AWLOCK,
    input     [3:0]                         S1_AXI_AWCACHE,
    input     [3:0]                         S1_AXI_AWQOS,
    input     [2:0]                         S1_AXI_AWPROT,
    output                                                  S1_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S1_AXI_WDATA,
    input     [(DW/8)-1:0]                  S1_AXI_WSTRB,
    input                                   S1_AXI_WVALID,
    input                                   S1_AXI_WLAST,
    output                                                  S1_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output    [1:0]                                         S1_AXI_BRESP,
    output                                                  S1_AXI_BVALID,
    input                                   S1_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S1_AXI_ARADDR,
    input                                   S1_AXI_ARVALID,
    input     [2:0]                         S1_AXI_ARPROT,
    input                                   S1_AXI_ARLOCK,
    input     [3:0]                         S1_AXI_ARID,
    input     [2:0]                         S1_AXI_ARSIZE,
    input     [7:0]                         S1_AXI_ARLEN,
    input     [1:0]                         S1_AXI_ARBURST,
    input     [3:0]                         S1_AXI_ARCACHE,
    input     [3:0]                         S1_AXI_ARQOS,
    output                                                  S1_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output    [DW-1:0]                                      S1_AXI_RDATA,
    output                                                  S1_AXI_RVALID,
    output    [1:0]                                         S1_AXI_RRESP,
    output                                                  S1_AXI_RLAST,
    input                                   S1_AXI_RREADY,
    //==========================================================================



    //==================  This is an AXI4-master interface  ===================

    // "Specify write address"              -- Master --    -- Slave --
    output reg [AW-1:0]                     M_AXI_AWADDR,
    output reg                              M_AXI_AWVALID,
    output reg [7:0]                        M_AXI_AWLEN,
    output reg [2:0]                        M_AXI_AWSIZE,
    output reg [3:0]                        M_AXI_AWID,
    output reg [1:0]                        M_AXI_AWBURST,
    output reg                              M_AXI_AWLOCK,
    output reg [3:0]                        M_AXI_AWCACHE,
    output reg [3:0]                        M_AXI_AWQOS,
    output reg [2:0]                        M_AXI_AWPROT,
    input                                                   M_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output reg [DW-1:0]                     M_AXI_WDATA,
    output reg [(DW/8)-1:0]                 M_AXI_WSTRB,
    output reg                              M_AXI_WVALID,
    output reg                              M_AXI_WLAST,
    input                                                   M_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              M_AXI_BRESP,
    input                                                   M_AXI_BVALID,
    output reg                              M_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output reg [AW-1:0]                     M_AXI_ARADDR,
    output reg                              M_AXI_ARVALID,
    output reg [2:0]                        M_AXI_ARPROT,
    output reg                              M_AXI_ARLOCK,
    output reg [3:0]                        M_AXI_ARID,
    output reg [2:0]                        M_AXI_ARSIZE,
    output reg [7:0]                        M_AXI_ARLEN,
    output reg [1:0]                        M_AXI_ARBURST,
    output reg [3:0]                        M_AXI_ARCACHE,
    output reg [3:0]                        M_AXI_ARQOS,
    input                                                   M_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input[DW-1:0]                                           M_AXI_RDATA,
    input                                                   M_AXI_RVALID,
    input[1:0]                                              M_AXI_RRESP,
    input                                                   M_AXI_RLAST,
    output reg                              M_AXI_RREADY
    //==========================================================================

);

//=============================================================================
// Route all the M_AXI input signals to the correct slave interface
//=============================================================================
assign S0_AXI_AWREADY = (select_s1) ? 0             : M_AXI_AWREADY;
assign S1_AXI_AWREADY = (select_s1) ? M_AXI_AWREADY : 0;

assign S0_AXI_WREADY  = (select_s1) ? 0             : M_AXI_WREADY;
assign S1_AXI_WREADY  = (select_s1) ? M_AXI_WREADY  : 0;

assign S0_AXI_BVALID  = (select_s1) ? 0             : M_AXI_BVALID;
assign S1_AXI_BVALID  = (select_s1) ? M_AXI_BVALID  : 0;

assign S0_AXI_BRESP   = (select_s1) ? 0             : M_AXI_BRESP;
assign S1_AXI_BRESP   = (select_s1) ? M_AXI_BRESP   : 0;

assign S0_AXI_ARREADY = (select_s1) ? 0             : M_AXI_ARREADY;
assign S1_AXI_ARREADY = (select_s1) ? M_AXI_ARREADY : 0;

assign S0_AXI_RDATA   = (select_s1) ? 0             : M_AXI_RDATA;
assign S1_AXI_RDATA   = (select_s1) ? M_AXI_RDATA   : 0;

assign S0_AXI_RVALID  = (select_s1) ? 0             : M_AXI_RVALID;
assign S1_AXI_RVALID  = (select_s1) ? M_AXI_RVALID  : 0;

assign S0_AXI_RRESP   = (select_s1) ? 0             : M_AXI_RRESP;
assign S1_AXI_RRESP   = (select_s1) ? M_AXI_RRESP   : 0;

assign S0_AXI_RLAST   = (select_s1) ? 0             : M_AXI_RLAST;
assign S1_AXI_RLAST   = (select_s1) ? M_AXI_RLAST   : 0;
//=============================================================================



//=============================================================================
// Mux for the AW-channel
//=============================================================================
always @* begin
    if (select_s1) begin
        M_AXI_AWADDR  = S1_AXI_AWADDR;
        M_AXI_AWVALID = S1_AXI_AWVALID;
        M_AXI_AWLEN   = S1_AXI_AWLEN;
        M_AXI_AWSIZE  = S1_AXI_AWSIZE;
        M_AXI_AWID    = S1_AXI_AWID;
        M_AXI_AWBURST = S1_AXI_AWBURST;
        M_AXI_AWLOCK  = S1_AXI_AWLOCK;
        M_AXI_AWCACHE = S1_AXI_AWCACHE;
        M_AXI_AWQOS   = S1_AXI_AWQOS;
        M_AXI_AWPROT  = S1_AXI_AWPROT;
    end else begin
        M_AXI_AWADDR  = S0_AXI_AWADDR;
        M_AXI_AWVALID = S0_AXI_AWVALID;
        M_AXI_AWLEN   = S0_AXI_AWLEN;
        M_AXI_AWSIZE  = S0_AXI_AWSIZE;
        M_AXI_AWID    = S0_AXI_AWID;
        M_AXI_AWBURST = S0_AXI_AWBURST;
        M_AXI_AWLOCK  = S0_AXI_AWLOCK;
        M_AXI_AWCACHE = S0_AXI_AWCACHE;
        M_AXI_AWQOS   = S0_AXI_AWQOS;
        M_AXI_AWPROT  = S0_AXI_AWPROT;
    end
end
//=============================================================================


//=============================================================================
// Mux for the W-channel
//=============================================================================
always @* begin
    if (select_s1) begin
        M_AXI_WDATA  = S1_AXI_WDATA;
        M_AXI_WSTRB  = S1_AXI_WSTRB;
        M_AXI_WVALID = S1_AXI_WVALID;
        M_AXI_WLAST  = S1_AXI_WLAST;
    end else begin
        M_AXI_WDATA  = S0_AXI_WDATA;
        M_AXI_WSTRB  = S0_AXI_WSTRB;
        M_AXI_WVALID = S0_AXI_WVALID;
        M_AXI_WLAST  = S0_AXI_WLAST;
    end
end
//=============================================================================


//=============================================================================
// Mux for B-Channel
//=============================================================================
always @* begin
    if (select_s1) begin
        M_AXI_BREADY = S1_AXI_BREADY;
    end else begin
        M_AXI_BREADY = S0_AXI_BREADY;
    end
end
//=============================================================================


//=============================================================================
// Mux for the AR-channel
//=============================================================================
always @* begin
    if (select_s1) begin
        M_AXI_ARADDR  = S1_AXI_ARADDR;
        M_AXI_ARVALID = S1_AXI_ARVALID;
        M_AXI_ARPROT  = S1_AXI_ARPROT;
        M_AXI_ARLOCK  = S1_AXI_ARLOCK;
        M_AXI_ARID    = S1_AXI_ARID;
        M_AXI_ARSIZE  = S1_AXI_ARSIZE;
        M_AXI_ARLEN   = S1_AXI_ARLEN;
        M_AXI_ARBURST = S1_AXI_ARBURST;
        M_AXI_ARCACHE = S1_AXI_ARCACHE;
        M_AXI_ARQOS   = S1_AXI_ARQOS;
    end else begin
        M_AXI_ARADDR  = S0_AXI_ARADDR;
        M_AXI_ARVALID = S0_AXI_ARVALID;
        M_AXI_ARPROT  = S0_AXI_ARPROT;
        M_AXI_ARLOCK  = S0_AXI_ARLOCK;
        M_AXI_ARID    = S0_AXI_ARID;
        M_AXI_ARSIZE  = S0_AXI_ARSIZE;
        M_AXI_ARLEN   = S0_AXI_ARLEN;
        M_AXI_ARBURST = S0_AXI_ARBURST;
        M_AXI_ARCACHE = S0_AXI_ARCACHE;
        M_AXI_ARQOS   = S0_AXI_ARQOS;
    end
end
//=============================================================================


//=============================================================================
// Mux for R-Channel
//=============================================================================
always @* begin
    if (select_s1) begin
        M_AXI_RREADY = S1_AXI_RREADY;
    end else begin
        M_AXI_RREADY = S0_AXI_RREADY;
    end
end
//=============================================================================


endmodule