//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//   This core doesn't do anything at all except for provide an AXI4 master interace
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 10-May-22  DWW  1000  Initial creation
//
// 06-Jun-25  DWW  1001  Rewrote to be a full AXI4-MM master instead of AXI4-Lite
//====================================================================================

module axi4_master_plug #
( 
    parameter integer DW=512, AW=64, IW=4
)
(
    input wire clk, 

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
    output     [(DW/8)-1:0]                 M_AXI_WSTRB,
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

    assign M_AXI_ARADDR  = 0;
    assign M_AXI_ARVALID = 0;
    assign M_AXI_ARPROT  = 0;
    assign M_AXI_ARLOCK  = 0;
    assign M_AXI_ARID    = 0;
    assign M_AXI_ARSIZE  = 0;
    assign M_AXI_ARLEN   = 0;
    assign M_AXI_ARBURST = 0;
    assign M_AXI_ARCACHE = 0;
    assign M_AXI_ARQOS   = 0;

    assign M_AXI_RREADY  = 0;

endmodule
