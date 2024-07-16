//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 19-Jun-24  DWW     1  Initial creation
//====================================================================================

/*
    This is a simple-dual-port RAM with two "write" interfaces
*/

module muxed_sdp_ram_if # (parameter DW=512, AW=64, DD=16384, RAM_TYPE="ultra")
(
    input   clk, resetn,

    // If asserted, input comes from S1_AXI, otherwise input comes from S0_AXI
    input   select_s1,

    // This will strobe high for a single cycle any time the last
    // word of the RAM is written to
    output last_word_written,

    // The "read only" RAM interface
    input  [$clog2(DD)-1:0] addrb,    
    output [DW-1:0]         dob,


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
    input                                   S1_AXI_RREADY
    //==========================================================================

);

//=============================================================================
// These wires connect the M_AXI interface of the i_abm_mux to the S_AXI 
// interface of i_sdp_ram_if
//=============================================================================
wire [AW-1:0]     m_axi_awaddr;
wire              m_axi_awvalid;
wire [7:0]        m_axi_awlen;
wire [2:0]        m_axi_awsize;
wire [3:0]        m_axi_awid;
wire [1:0]        m_axi_awburst;
wire              m_axi_awlock;
wire [3:0]        m_axi_awcache;
wire [3:0]        m_axi_awqos;
wire [2:0]        m_axi_awprot;
wire              m_axi_awready;
wire [DW-1:0]     m_axi_wdata;
wire [(DW/8)-1:0] m_axi_wstrb;
wire              m_axi_wvalid;
wire              m_axi_wlast;
wire              m_axi_wready;
wire [1:0]        m_axi_bresp;
wire              m_axi_bvalid;
wire              m_axi_bready;
wire [AW-1:0]     m_axi_araddr;
wire              m_axi_arvalid;
wire [2:0]        m_axi_arprot;
wire              m_axi_arlock;
wire [3:0]        m_axi_arid;
wire [2:0]        m_axi_arsize;
wire [7:0]        m_axi_arlen;
wire [1:0]        m_axi_arburst;
wire [3:0]        m_axi_arcache;
wire [3:0]        m_axi_arqos;
wire              m_axi_arready;
wire [DW-1:0]     m_axi_rdata;
wire              m_axi_rvalid;
wire [1:0]        m_axi_rresp;
wire              m_axi_rlast;
wire              m_axi_rready;
//=============================================================================



//=============================================================================
// This allows two AXI master interfaces to connect to a single AXI slave
//=============================================================================
abm_mux # (.DW(DW), .AW(AW)) i_abm_mux
(
    .clk            (clk),
    .select_s1      (select_s1),

    .S0_AXI_ARADDR  (S0_AXI_ARADDR ),
    .S0_AXI_ARVALID (S0_AXI_ARVALID),
    .S0_AXI_ARPROT  (S0_AXI_ARPROT ),
    .S0_AXI_ARLOCK  (S0_AXI_ARLOCK ),
    .S0_AXI_ARID    (S0_AXI_ARID   ),
    .S0_AXI_ARSIZE  (S0_AXI_ARSIZE ),
    .S0_AXI_ARLEN   (S0_AXI_ARLEN  ),
    .S0_AXI_ARBURST (S0_AXI_ARBURST),
    .S0_AXI_ARCACHE (S0_AXI_ARCACHE),
    .S0_AXI_ARQOS   (S0_AXI_ARQOS  ),
    .S0_AXI_ARREADY (S0_AXI_ARREADY),
    .S0_AXI_RDATA   (S0_AXI_RDATA  ), 
    .S0_AXI_RVALID  (S0_AXI_RVALID ), 
    .S0_AXI_RRESP   (S0_AXI_RRESP  ), 
    .S0_AXI_RLAST   (S0_AXI_RLAST  ),  
    .S0_AXI_RREADY  (S0_AXI_RREADY ), 
    .S0_AXI_AWADDR  (S0_AXI_AWADDR ),     
    .S0_AXI_AWVALID (S0_AXI_AWVALID),     
    .S0_AXI_AWLEN   (S0_AXI_AWLEN  ),     
    .S0_AXI_AWSIZE  (S0_AXI_AWSIZE ),     
    .S0_AXI_AWID    (S0_AXI_AWID   ),     
    .S0_AXI_AWBURST (S0_AXI_AWBURST),     
    .S0_AXI_AWLOCK  (S0_AXI_AWLOCK ),     
    .S0_AXI_AWCACHE (S0_AXI_AWCACHE),      
    .S0_AXI_AWQOS   (S0_AXI_AWQOS  ),   
    .S0_AXI_AWPROT  (S0_AXI_AWPROT ),    
    .S0_AXI_AWREADY (S0_AXI_AWREADY),     
    .S0_AXI_WDATA   (S0_AXI_WDATA  ),     
    .S0_AXI_WSTRB   (S0_AXI_WSTRB  ),     
    .S0_AXI_WVALID  (S0_AXI_WVALID ),   
    .S0_AXI_WLAST   (S0_AXI_WLAST  ),     
    .S0_AXI_WREADY  (S0_AXI_WREADY ),      
    .S0_AXI_BRESP   (S0_AXI_BRESP  ),     
    .S0_AXI_BVALID  (S0_AXI_BVALID ),     
    .S0_AXI_BREADY  (S0_AXI_BREADY ),       

    .S1_AXI_ARADDR  (S1_AXI_ARADDR ),
    .S1_AXI_ARVALID (S1_AXI_ARVALID),
    .S1_AXI_ARPROT  (S1_AXI_ARPROT ),
    .S1_AXI_ARLOCK  (S1_AXI_ARLOCK ),
    .S1_AXI_ARID    (S1_AXI_ARID   ),
    .S1_AXI_ARSIZE  (S1_AXI_ARSIZE ),
    .S1_AXI_ARLEN   (S1_AXI_ARLEN  ),
    .S1_AXI_ARBURST (S1_AXI_ARBURST),
    .S1_AXI_ARCACHE (S1_AXI_ARCACHE),
    .S1_AXI_ARQOS   (S1_AXI_ARQOS  ),
    .S1_AXI_ARREADY (S1_AXI_ARREADY),
    .S1_AXI_RDATA   (S1_AXI_RDATA  ), 
    .S1_AXI_RVALID  (S1_AXI_RVALID ), 
    .S1_AXI_RRESP   (S1_AXI_RRESP  ), 
    .S1_AXI_RLAST   (S1_AXI_RLAST  ),  
    .S1_AXI_RREADY  (S1_AXI_RREADY ), 
    .S1_AXI_AWADDR  (S1_AXI_AWADDR ),     
    .S1_AXI_AWVALID (S1_AXI_AWVALID),     
    .S1_AXI_AWLEN   (S1_AXI_AWLEN  ),     
    .S1_AXI_AWSIZE  (S1_AXI_AWSIZE ),     
    .S1_AXI_AWID    (S1_AXI_AWID   ),     
    .S1_AXI_AWBURST (S1_AXI_AWBURST),     
    .S1_AXI_AWLOCK  (S1_AXI_AWLOCK ),     
    .S1_AXI_AWCACHE (S1_AXI_AWCACHE),      
    .S1_AXI_AWQOS   (S1_AXI_AWQOS  ),   
    .S1_AXI_AWPROT  (S1_AXI_AWPROT ),    
    .S1_AXI_AWREADY (S1_AXI_AWREADY),     
    .S1_AXI_WDATA   (S1_AXI_WDATA  ),     
    .S1_AXI_WSTRB   (S1_AXI_WSTRB  ),     
    .S1_AXI_WVALID  (S1_AXI_WVALID ),   
    .S1_AXI_WLAST   (S1_AXI_WLAST  ),     
    .S1_AXI_WREADY  (S1_AXI_WREADY ),      
    .S1_AXI_BRESP   (S1_AXI_BRESP  ),     
    .S1_AXI_BVALID  (S1_AXI_BVALID ),     
    .S1_AXI_BREADY  (S1_AXI_BREADY ),       


    .M_AXI_ARADDR   (m_axi_araddr  ),
    .M_AXI_ARVALID  (m_axi_arvalid ),
    .M_AXI_ARPROT   (m_axi_arprot  ),
    .M_AXI_ARLOCK   (m_axi_arlock  ),
    .M_AXI_ARID     (m_axi_arid    ),
    .M_AXI_ARSIZE   (m_axi_arsize  ),
    .M_AXI_ARLEN    (m_axi_arlen   ),
    .M_AXI_ARBURST  (m_axi_arburst ),
    .M_AXI_ARCACHE  (m_axi_arcache ),
    .M_AXI_ARQOS    (m_axi_arqos   ),
    .M_AXI_ARREADY  (m_axi_arready ),
    .M_AXI_RDATA    (m_axi_rdata   ), 
    .M_AXI_RVALID   (m_axi_rvalid  ), 
    .M_AXI_RRESP    (m_axi_rresp   ), 
    .M_AXI_RLAST    (m_axi_rlast   ),  
    .M_AXI_RREADY   (m_axi_rready  ), 
    .M_AXI_AWADDR   (m_axi_awaddr  ),     
    .M_AXI_AWVALID  (m_axi_awvalid ),     
    .M_AXI_AWLEN    (m_axi_awlen   ),     
    .M_AXI_AWSIZE   (m_axi_awsize  ),     
    .M_AXI_AWID     (m_axi_awid    ),     
    .M_AXI_AWBURST  (m_axi_awburst ),     
    .M_AXI_AWLOCK   (m_axi_awlock  ),     
    .M_AXI_AWCACHE  (m_axi_awcache ),      
    .M_AXI_AWQOS    (m_axi_awqos   ),   
    .M_AXI_AWPROT   (m_axi_awprot  ),    
    .M_AXI_AWREADY  (m_axi_awready ),     
    .M_AXI_WDATA    (m_axi_wdata   ),     
    .M_AXI_WSTRB    (m_axi_wstrb   ),     
    .M_AXI_WVALID   (m_axi_wvalid  ),   
    .M_AXI_WLAST    (m_axi_wlast   ),     
    .M_AXI_WREADY   (m_axi_wready  ),      
    .M_AXI_BRESP    (m_axi_bresp   ),     
    .M_AXI_BVALID   (m_axi_bvalid  ),     
    .M_AXI_BREADY   (m_axi_bready  )       
);
//=============================================================================


//=============================================================================
// This is a simple dual-port RAM
//=============================================================================
sdp_ram_if # (.DW(DW), .DD(DD), .RAM_TYPE(RAM_TYPE)) i_sdp_ram_if
(
    .clk               (clk),
    .resetn            (resetn),
    .last_word_written (last_word_written),
    .addrb             (addrb),
    .dob               (dob),

    .S_AXI_ARADDR  (m_axi_araddr ),
    .S_AXI_ARVALID (m_axi_arvalid),
    .S_AXI_ARPROT  (m_axi_arprot ),
    .S_AXI_ARLOCK  (m_axi_arlock ),
    .S_AXI_ARID    (m_axi_arid   ),
    .S_AXI_ARSIZE  (m_axi_arsize ),
    .S_AXI_ARLEN   (m_axi_arlen  ),
    .S_AXI_ARBURST (m_axi_arburst),
    .S_AXI_ARCACHE (m_axi_arcache),
    .S_AXI_ARQOS   (m_axi_arqos  ),
    .S_AXI_ARREADY (m_axi_arready),
    .S_AXI_RDATA   (m_axi_rdata  ), 
    .S_AXI_RVALID  (m_axi_rvalid ), 
    .S_AXI_RRESP   (m_axi_rresp  ), 
    .S_AXI_RLAST   (m_axi_rlast  ),  
    .S_AXI_RREADY  (m_axi_rready ), 
    .S_AXI_AWADDR  (m_axi_awaddr ),     
    .S_AXI_AWVALID (m_axi_awvalid),     
    .S_AXI_AWLEN   (m_axi_awlen  ),     
    .S_AXI_AWSIZE  (m_axi_awsize ),     
    .S_AXI_AWID    (m_axi_awid   ),     
    .S_AXI_AWBURST (m_axi_awburst),     
    .S_AXI_AWLOCK  (m_axi_awlock ),     
    .S_AXI_AWCACHE (m_axi_awcache),      
    .S_AXI_AWQOS   (m_axi_awqos  ),   
    .S_AXI_AWPROT  (m_axi_awprot ),    
    .S_AXI_AWREADY (m_axi_awready),     
    .S_AXI_WDATA   (m_axi_wdata  ),     
    .S_AXI_WSTRB   (m_axi_wstrb  ),     
    .S_AXI_WVALID  (m_axi_wvalid ),   
    .S_AXI_WLAST   (m_axi_wlast  ),     
    .S_AXI_WREADY  (m_axi_wready ),      
    .S_AXI_BRESP   (m_axi_bresp  ),     
    .S_AXI_BVALID  (m_axi_bvalid ),     
    .S_AXI_BREADY  (m_axi_bready )       

);
//=============================================================================


endmodule
