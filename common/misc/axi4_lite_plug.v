//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 02-Mar-24  DWW     1  Initial creation
//
// 13-Apr-25  DWW     2  General cleanup
//====================================================================================

/*
    This is just a "plug" for an empty AXI4-Lite slave port, to keep Vivado
    happy.   This module does nothing at all, simply ensures that an otherwise
    unused AXI4-Lite slave port doesn't cause Vivado to whine.
*/


module axi4_lite_plug # (parameter DW=32, parameter AW=32)
(
    input clk,

    //====================  An AXI4-Lite Master Interface  =====================

    // "Specify write address"          -- Master --    -- Slave --
    output reg[AW-1:0]                  M_AXI_AWADDR,
    output reg                          M_AXI_AWVALID,
    input                                               M_AXI_AWREADY,

    // "Write Data"                     -- Master --    -- Slave --
    output reg[DW-1:0]                  M_AXI_WDATA,
    output reg[DW/8-1:0]                M_AXI_WSTRB,
    output reg                          M_AXI_WVALID,
    input                                               M_AXI_WREADY,

    // "Send Write Response"            -- Master --    -- Slave --
    input[1:0]                                          M_AXI_BRESP,
    input                                               M_AXI_BVALID,
    output reg                          M_AXI_BREADY,

    // "Specify read address"           -- Master --    -- Slave --
    output reg[AW-1:0]                  M_AXI_ARADDR,
    output reg                          M_AXI_ARVALID,
    input                                               M_AXI_ARREADY,

    // "Read data back to master"       -- Master --    -- Slave --
    input[DW-1:0]                                       M_AXI_RDATA,
    input                                               M_AXI_RVALID,
    input[1:0]                                          M_AXI_RRESP,
    output reg                          M_AXI_RREADY
    //==========================================================================
);

always @(posedge clk) begin
    M_AXI_AWADDR  <= 0;
    M_AXI_AWVALID <= 0;
    M_AXI_WDATA   <= 0;
    M_AXI_WSTRB   <= 0;
    M_AXI_WVALID  <= 0;
    M_AXI_BREADY  <= 0;
    M_AXI_ARADDR  <= 0;
    M_AXI_ARVALID <= 0;
    M_AXI_RREADY  <= 0;
end

endmodule