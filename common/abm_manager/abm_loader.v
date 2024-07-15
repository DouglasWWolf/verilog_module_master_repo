//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 18-Jun-24  DWW     1  Initial creation
//=============================================================================

/*
    This moves a block of data from a source AXI-MM interface to a destination
    AXI-MM interface.

    Data widths of the two interfaces must match.
*/ 
 

module abm_loader # (parameter DW = 512, parameter AW = 64)
(
    input       clk, resetn,
    input[63:0] pci_src_addr, 
    input       load,
    input       load_wstrobe,
    output      idle,
    output      slave_select,

    // ===========  AX4-Master that connnects to an ABM RAM buffer  ===========

    // "Specify write address"              -- Master --    -- Slave --
    output     [AW-1:0]                     ABM_AXI_AWADDR,
    output                                  ABM_AXI_AWVALID,
    output     [7:0]                        ABM_AXI_AWLEN,
    output     [2:0]                        ABM_AXI_AWSIZE,
    output     [3:0]                        ABM_AXI_AWID,
    output     [1:0]                        ABM_AXI_AWBURST,
    output                                  ABM_AXI_AWLOCK,
    output     [3:0]                        ABM_AXI_AWCACHE,
    output     [3:0]                        ABM_AXI_AWQOS,
    output     [2:0]                        ABM_AXI_AWPROT,
    input                                                   ABM_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     ABM_AXI_WDATA,
    output     [(DW/8)-1:0]                 ABM_AXI_WSTRB,
    output                                  ABM_AXI_WVALID,
    output                                  ABM_AXI_WLAST,
    input                                                   ABM_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input[1:0]                                              ABM_AXI_BRESP,
    input                                                   ABM_AXI_BVALID,
    output                                  ABM_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output     [AW-1:0]                     ABM_AXI_ARADDR,
    output                                  ABM_AXI_ARVALID,
    output     [2:0]                        ABM_AXI_ARPROT,
    output                                  ABM_AXI_ARLOCK,
    output     [3:0]                        ABM_AXI_ARID,
    output     [2:0]                        ABM_AXI_ARSIZE,
    output     [7:0]                        ABM_AXI_ARLEN,
    output     [1:0]                        ABM_AXI_ARBURST,
    output     [3:0]                        ABM_AXI_ARCACHE,
    output     [3:0]                        ABM_AXI_ARQOS,
    input                                                   ABM_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input      [DW-1:0]                                     ABM_AXI_RDATA,
    input                                                   ABM_AXI_RVALID,
    input      [1:0]                                        ABM_AXI_RRESP,
    input                                                   ABM_AXI_RLAST,
    output                                  ABM_AXI_RREADY,
    //==========================================================================


    
    // ===========  AX4-Master that connnects to a Host RAM buffer  ============

    // "Specify write address"              -- Master --    -- Slave --
    output     [AW-1:0]                     PCI_AXI_AWADDR,
    output                                  PCI_AXI_AWVALID,
    output     [7:0]                        PCI_AXI_AWLEN,
    output     [2:0]                        PCI_AXI_AWSIZE,
    output     [3:0]                        PCI_AXI_AWID,
    output     [1:0]                        PCI_AXI_AWBURST,
    output                                  PCI_AXI_AWLOCK,
    output     [3:0]                        PCI_AXI_AWCACHE,
    output     [3:0]                        PCI_AXI_AWQOS,
    output     [2:0]                        PCI_AXI_AWPROT,
    input                                                   PCI_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    output     [DW-1:0]                     PCI_AXI_WDATA,
    output     [(DW/8)-1:0]                 PCI_AXI_WSTRB,
    output                                  PCI_AXI_WVALID,
    output                                  PCI_AXI_WLAST,
    input                                                   PCI_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    input      [1:0]                                        PCI_AXI_BRESP,
    input                                                   PCI_AXI_BVALID,
    output                                  PCI_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    output      [AW-1:0]                    PCI_AXI_ARADDR,
    output                                  PCI_AXI_ARVALID,
    output      [2:0]                       PCI_AXI_ARPROT,
    output                                  PCI_AXI_ARLOCK,
    output      [3:0]                       PCI_AXI_ARID,
    output      [2:0]                       PCI_AXI_ARSIZE,
    output      [7:0]                       PCI_AXI_ARLEN,
    output      [1:0]                       PCI_AXI_ARBURST,
    output      [3:0]                       PCI_AXI_ARCACHE,
    output      [3:0]                       PCI_AXI_ARQOS,
    input                                                   PCI_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    input      [DW-1:0]                                     PCI_AXI_RDATA,
    input                                                   PCI_AXI_RVALID,
    input      [1:0]                                        PCI_AXI_RRESP,
    input                                                   PCI_AXI_RLAST,
    output                                  PCI_AXI_RREADY
    //==========================================================================
);

localparam ABM_ADDR = 0;

// This tells us when the data-transfer is complete
wire pci2abm_idle;

// Tell the outside world when our data-mover is idle
assign idle = pci2abm_idle;

// Assert the slave-select output when we're not idle
assign slave_select = !idle;

// We start the data-move when a '1' is written to 'load'. As a safety
// measure, we disallow a start when the source address is 0 
wire start_pci2abm = (resetn == 1)
                   & load_wstrobe
                   & load
                   & (pci_src_addr != 0);


//=============================================================================
// This connects us to our data-mover core
//=============================================================================
data_mover # (.DW(DW), .AW(AW)) i_data_mover
(
    .clk             (clk),
    .resetn          (resetn),
    .src_address     (pci_src_addr),
    .dst_address     (ABM_ADDR),
    .byte_count      (64'h10_0000),
    .burst_size      (4096),
    .start           (start_pci2abm),
    .idle            (pci2abm_idle),

    .SRC_AXI_AWADDR  (PCI_AXI_AWADDR ),     
    .SRC_AXI_AWVALID (PCI_AXI_AWVALID),     
    .SRC_AXI_AWLEN   (PCI_AXI_AWLEN  ),     
    .SRC_AXI_AWSIZE  (PCI_AXI_AWSIZE ),     
    .SRC_AXI_AWID    (PCI_AXI_AWID   ),     
    .SRC_AXI_AWBURST (PCI_AXI_AWBURST),     
    .SRC_AXI_AWLOCK  (PCI_AXI_AWLOCK ),     
    .SRC_AXI_AWCACHE (PCI_AXI_AWCACHE),      
    .SRC_AXI_AWQOS   (PCI_AXI_AWQOS  ),   
    .SRC_AXI_AWPROT  (PCI_AXI_AWPROT ),    
    .SRC_AXI_AWREADY (PCI_AXI_AWREADY),     
    
    .SRC_AXI_WDATA   (PCI_AXI_WDATA  ),     
    .SRC_AXI_WSTRB   (PCI_AXI_WSTRB  ),     
    .SRC_AXI_WVALID  (PCI_AXI_WVALID ),   
    .SRC_AXI_WLAST   (PCI_AXI_WLAST  ),     
    .SRC_AXI_WREADY  (PCI_AXI_WREADY ),      
    
    .SRC_AXI_BRESP   (PCI_AXI_BRESP  ),     
    .SRC_AXI_BVALID  (PCI_AXI_BVALID ),     
    .SRC_AXI_BREADY  (PCI_AXI_BREADY ),       

    .SRC_AXI_ARADDR  (PCI_AXI_ARADDR ),
    .SRC_AXI_ARVALID (PCI_AXI_ARVALID),
    .SRC_AXI_ARPROT  (PCI_AXI_ARPROT ),
    .SRC_AXI_ARLOCK  (PCI_AXI_ARLOCK ),
    .SRC_AXI_ARID    (PCI_AXI_ARID   ),
    .SRC_AXI_ARSIZE  (PCI_AXI_ARSIZE ),
    .SRC_AXI_ARLEN   (PCI_AXI_ARLEN  ),
    .SRC_AXI_ARBURST (PCI_AXI_ARBURST),
    .SRC_AXI_ARCACHE (PCI_AXI_ARCACHE),
    .SRC_AXI_ARQOS   (PCI_AXI_ARQOS  ),
    .SRC_AXI_ARREADY (PCI_AXI_ARREADY),

    .SRC_AXI_RDATA   (PCI_AXI_RDATA  ), 
    .SRC_AXI_RVALID  (PCI_AXI_RVALID ), 
    .SRC_AXI_RRESP   (PCI_AXI_RRESP  ), 
    .SRC_AXI_RLAST   (PCI_AXI_RLAST  ),  
    .SRC_AXI_RREADY  (PCI_AXI_RREADY ), 

    .DST_AXI_AWADDR  (ABM_AXI_AWADDR ),     
    .DST_AXI_AWVALID (ABM_AXI_AWVALID),     
    .DST_AXI_AWLEN   (ABM_AXI_AWLEN  ),     
    .DST_AXI_AWSIZE  (ABM_AXI_AWSIZE ),     
    .DST_AXI_AWID    (ABM_AXI_AWID   ),     
    .DST_AXI_AWBURST (ABM_AXI_AWBURST),     
    .DST_AXI_AWLOCK  (ABM_AXI_AWLOCK ),     
    .DST_AXI_AWCACHE (ABM_AXI_AWCACHE),      
    .DST_AXI_AWQOS   (ABM_AXI_AWQOS  ),   
    .DST_AXI_AWPROT  (ABM_AXI_AWPROT ),    
    .DST_AXI_AWREADY (ABM_AXI_AWREADY),     

    .DST_AXI_WDATA   (ABM_AXI_WDATA  ),     
    .DST_AXI_WSTRB   (ABM_AXI_WSTRB  ),     
    .DST_AXI_WVALID  (ABM_AXI_WVALID ),   
    .DST_AXI_WLAST   (ABM_AXI_WLAST  ),     
    .DST_AXI_WREADY  (ABM_AXI_WREADY ),      

    .DST_AXI_BRESP   (ABM_AXI_BRESP  ),     
    .DST_AXI_BVALID  (ABM_AXI_BVALID ),     
    .DST_AXI_BREADY  (ABM_AXI_BREADY ),       

    .DST_AXI_ARADDR  (ABM_AXI_ARADDR ),
    .DST_AXI_ARVALID (ABM_AXI_ARVALID),
    .DST_AXI_ARPROT  (ABM_AXI_ARPROT ),
    .DST_AXI_ARLOCK  (ABM_AXI_ARLOCK ),
    .DST_AXI_ARID    (ABM_AXI_ARID   ),
    .DST_AXI_ARSIZE  (ABM_AXI_ARSIZE ),
    .DST_AXI_ARLEN   (ABM_AXI_ARLEN  ),
    .DST_AXI_ARBURST (ABM_AXI_ARBURST),
    .DST_AXI_ARCACHE (ABM_AXI_ARCACHE),
    .DST_AXI_ARQOS   (ABM_AXI_ARQOS  ),
    .DST_AXI_ARREADY (ABM_AXI_ARREADY),
    
    .DST_AXI_RDATA   (ABM_AXI_RDATA  ), 
    .DST_AXI_RVALID  (ABM_AXI_RVALID ), 
    .DST_AXI_RRESP   (ABM_AXI_RRESP  ), 
    .DST_AXI_RLAST   (ABM_AXI_RLAST  ),  
    .DST_AXI_RREADY  (ABM_AXI_RREADY ) 

);
//=============================================================================


endmodule