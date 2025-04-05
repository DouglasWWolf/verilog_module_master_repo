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
//====================================================================================


module axi4_master_plug #
( 
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)
(

    input wire clk, 

    //======================  An AXI Master Interface  =========================

    // "Specify write address"          -- Master --    -- Slave --
    output     [AXI_ADDR_WIDTH-1:0]     AXI_AWADDR,   
    output                              AXI_AWVALID,  
    input                                               AXI_AWREADY,


    // "Write Data"                     -- Master --    -- Slave --
    output     [AXI_DATA_WIDTH-1:0]     AXI_WDATA,      
    output                              AXI_WVALID,
    input                                               AXI_WREADY,


    // "Send Write Response"            -- Master --    -- Slave --
    input      [1:0]                                    AXI_BRESP,
    input                                               AXI_BVALID,
    output                              AXI_BREADY,

    // "Specify read address"           -- Master --    -- Slave --
    output     [AXI_ADDR_WIDTH-1:0]     AXI_ARADDR,     
    output                              AXI_ARVALID,
       input                                               AXI_ARREADY,

    // "Read data back to master"       -- Master --    -- Slave --
    input [AXI_DATA_WIDTH-1:0]                          AXI_RDATA,
    input                                               AXI_RVALID,
    input [1:0]                                         AXI_RRESP,
    output                              AXI_RREADY
    //==========================================================================
);


    assign AXI_WVALID  = 0;
    assign AXI_AWVALID = 0;
    assign AXI_ARVALID = 0;
    assign AXI_RREADY  = 0;
    assign AXI_BREADY  = 0;


endmodule
