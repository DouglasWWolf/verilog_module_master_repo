//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 02-Apr-25  DWW     1  Initial creation
//====================================================================================

/*
    This splits an AXI4MM "slave" interface into separate read/write interfaces
*/


module axi4_breakout # (parameter DW=512, AW=64, IW=5)
(

    // This isn't used and is just here to keep Vivado IPI happy
    input clk,


    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S_RD_AWADDR,
    input                                   S_RD_AWVALID,
    input     [7:0]                         S_RD_AWLEN,
    input     [2:0]                         S_RD_AWSIZE,
    input     [IW-1:0]                      S_RD_AWID,
    input     [1:0]                         S_RD_AWBURST,
    input                                   S_RD_AWLOCK,
    input     [3:0]                         S_RD_AWCACHE,
    input     [3:0]                         S_RD_AWQOS,
    input     [2:0]                         S_RD_AWPROT,
    output                                                  S_RD_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S_RD_WDATA,
    input     [DW/8-1:0]                    S_RD_WSTRB,
    input                                   S_RD_WVALID,
    input                                   S_RD_WLAST,
    output                                                  S_RD_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_RD_BRESP,
    output                                                  S_RD_BVALID,
    input                                   S_RD_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S_RD_ARADDR,
    input                                   S_RD_ARVALID,
    input     [2:0]                         S_RD_ARPROT,
    input                                   S_RD_ARLOCK,
    input     [IW-1:0]                      S_RD_ARID,
    input     [2:0]                         S_RD_ARSIZE,
    input     [7:0]                         S_RD_ARLEN,
    input     [1:0]                         S_RD_ARBURST,
    input     [3:0]                         S_RD_ARCACHE,
    input     [3:0]                         S_RD_ARQOS,
    output                                                  S_RD_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_RD_RDATA,
    output                                                  S_RD_RVALID,
    output[1:0]                                             S_RD_RRESP,
    output                                                  S_RD_RLAST,
    input                                   S_RD_RREADY,
    //==========================================================================




    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S_WR_AWADDR,
    input                                   S_WR_AWVALID,
    input     [7:0]                         S_WR_AWLEN,
    input     [2:0]                         S_WR_AWSIZE,
    input     [IW-1:0]                      S_WR_AWID,
    input     [1:0]                         S_WR_AWBURST,
    input                                   S_WR_AWLOCK,
    input     [3:0]                         S_WR_AWCACHE,
    input     [3:0]                         S_WR_AWQOS,
    input     [2:0]                         S_WR_AWPROT,
    output                                                  S_WR_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S_WR_WDATA,
    input     [DW/8-1:0]                    S_WR_WSTRB,
    input                                   S_WR_WVALID,
    input                                   S_WR_WLAST,
    output                                                  S_WR_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_WR_BRESP,
    output                                                  S_WR_BVALID,
    input                                   S_WR_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S_WR_ARADDR,
    input                                   S_WR_ARVALID,
    input     [2:0]                         S_WR_ARPROT,
    input                                   S_WR_ARLOCK,
    input     [IW-1:0]                      S_WR_ARID,
    input     [2:0]                         S_WR_ARSIZE,
    input     [7:0]                         S_WR_ARLEN,
    input     [1:0]                         S_WR_ARBURST,
    input     [3:0]                         S_WR_ARCACHE,
    input     [3:0]                         S_WR_ARQOS,
    output                                                  S_WR_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_WR_RDATA,
    output                                                  S_WR_RVALID,
    output[1:0]                                             S_WR_RRESP,
    output                                                  S_WR_RLAST,
    input                                   S_WR_RREADY,
    //==========================================================================


    //==================  This is an AXI4-master interface  ===================

    // "Specify write address"              -- Master --    -- Slave --
    output     [AW-1:0]                     M_AXI_AWADDR,
    output                                  M_AXI_AWVALID,
    output     [7:0]                        M_AXI_AWLEN,
    output     [2:0]                        M_AXI_AWSIZE,
    output     [IW-1:0]                     M_AXI_AWID,
    output     [1:0]                        M_AXI_AWBURST,
    output                                  M_AXI_AWLOCK,
    output     [3:0]                        M_AXI_AWCACHE,
    output     [3:0]                        M_AXI_AWQOS,
    output     [2:0]                        M_AXI_AWPROT,
    input                                                   M_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     M_AXI_WDATA,
    output     [DW/8-1:0]                   M_AXI_WSTRB,
    output                                  M_AXI_WVALID,
    output                                  M_AXI_WLAST,
    input                                                   M_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              M_AXI_BRESP,
    input                                                   M_AXI_BVALID,
    output                                  M_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output     [AW-1:0]                     M_AXI_ARADDR,
    output                                  M_AXI_ARVALID,
    output     [2:0]                        M_AXI_ARPROT,
    output                                  M_AXI_ARLOCK,
    output     [IW-1:0]                     M_AXI_ARID,
    output     [2:0]                        M_AXI_ARSIZE,
    output     [7:0]                        M_AXI_ARLEN,
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


//=============================================================================
// The "read only" slave interface doesn't use "write" signals
//=============================================================================
assign S_RD_AWREADY = 0;
assign S_RD_WREADY  = 0;
assign S_RD_BVALID  = 0;
assign S_RD_BRESP   = 0;
//=============================================================================


//=============================================================================
// The "write only" slave interface doesn't use "read" signals
//=============================================================================
assign S_WR_ARREADY = 0;
assign S_WR_RDATA   = 0;
assign S_WR_RLAST   = 0;
assign S_WR_RRESP   = 0;
assign S_WR_RVALID  = 0;
//=============================================================================


// Wire the AW-channel of the output
assign M_AXI_AWADDR  = S_WR_AWADDR;
assign M_AXI_AWVALID = S_WR_AWVALID;
assign M_AXI_AWLEN   = S_WR_AWLEN;
assign M_AXI_AWSIZE  = S_WR_AWSIZE;
assign M_AXI_AWID    = S_WR_AWID;
assign M_AXI_AWBURST = S_WR_AWBURST;
assign M_AXI_AWLOCK  = S_WR_AWLOCK;
assign M_AXI_AWCACHE = S_WR_AWCACHE;
assign M_AXI_AWQOS   = S_WR_AWQOS;
assign M_AXI_AWPROT  = S_WR_AWPROT;
assign S_WR_AWREADY  = M_AXI_AWREADY;

// Wire the W-channel of the output
assign M_AXI_WDATA   = S_WR_WDATA;
assign M_AXI_WSTRB   = S_WR_WSTRB;
assign M_AXI_WLAST   = S_WR_WLAST;
assign M_AXI_WVALID  = S_WR_WVALID;
assign S_WR_WREADY   = M_AXI_WREADY;

// Wire the B-channel of the output
assign S_WR_BRESP    = M_AXI_BRESP;
assign S_WR_BVALID   = M_AXI_BVALID;
assign M_AXI_BREADY  = S_WR_BREADY;

// Wire the AR-channel of the output
assign M_AXI_ARADDR  = S_RD_ARADDR;
assign M_AXI_ARVALID = S_RD_ARVALID;
assign M_AXI_ARLEN   = S_RD_ARLEN;
assign M_AXI_ARSIZE  = S_RD_ARSIZE;
assign M_AXI_ARID    = S_RD_ARID;
assign M_AXI_ARBURST = S_RD_ARBURST;
assign M_AXI_ARLOCK  = S_RD_ARLOCK;
assign M_AXI_ARCACHE = S_RD_ARCACHE;
assign M_AXI_ARQOS   = S_RD_ARQOS;
assign M_AXI_ARPROT  = S_RD_ARPROT;
assign S_RD_ARREADY  = M_AXI_ARREADY;

// Wire the R-channel of the output
assign S_RD_RDATA    = M_AXI_RDATA;
assign S_RD_RLAST    = M_AXI_RLAST;
assign S_RD_RRESP    = M_AXI_RRESP;
assign S_RD_RVALID   = M_AXI_RVALID;
assign M_AXI_RREADY  = S_RD_RREADY;

endmodule