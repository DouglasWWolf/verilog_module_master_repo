//=============================================================================
//                    ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 30-Jun-26  DWW     1  Initial creation
//=============================================================================

/*
    This is a chain of FIFOs, linked together with "slice" registers between
    them to ease timing.  It looks like this:

    Input Stream --> FIFO --> Slice --> FIFO --> Slice (etc) --> Output stream

    Parameter FIFO_DEPTH is the overall depth of the entire chain of FIFOs
    
    Parameter SECTIONS determines how many FIFOs are chained together in
    order to acheive FIFO_DEPTH

    There are a total of 4 cycles of latency for each section.

    Both FIFO_DEPTH and SECTIONS must be powers of 2.    

    The value of FIFO_DEPTH / SECTIONS must be at least 16

    The value of FIFO_MEMORY_TYPE can be "auto", "block" or "ultra"
*/


module ldp_fifo #
(
    parameter TDATA_WIDTH      = 512,
    parameter TUSER_WIDTH      = 8,
    parameter FIFO_DEPTH       = 32768,
    parameter FIFO_MEMORY_TYPE = "auto",
    parameter SECTIONS         = 2

)
(
    input   clk,
    input   resetn,

    // Input stream
    input [TDATA_WIDTH-1:0] axis_in_tdata,
    input [TUSER_WIDTH-1:0] axis_in_tuser,
    input                   axis_in_tvalid,
    output                  axis_in_tready,

    // Output stream
    output[TDATA_WIDTH-1:0] axis_out_tdata,
    output[TUSER_WIDTH-1:0] axis_out_tuser,
    output                  axis_out_tvalid,
    input                   axis_out_tready
);
genvar i;

// How deep is each individual FIFO section in the chain?
localparam SECTION_DEPTH = FIFO_DEPTH / SECTIONS;

// One per section, plus an extra one to come out of the last slice
wire[TDATA_WIDTH-1:0] fifo_in_tdata [0:SECTIONS];
wire[TUSER_WIDTH-1:0] fifo_in_tuser [0:SECTIONS];
wire                  fifo_in_tvalid[0:SECTIONS];
wire                  fifo_in_tready[0:SECTIONS];

wire[TDATA_WIDTH-1:0] fifo_out_tdata [0:SECTIONS-1];
wire[TUSER_WIDTH-1:0] fifo_out_tuser [0:SECTIONS-1];
wire                  fifo_out_tvalid[0:SECTIONS-1];
wire                  fifo_out_tready[0:SECTIONS-1];

// The the input stream to the wires going into the first section
assign fifo_in_tdata[0]  = axis_in_tdata;
assign fifo_in_tuser[0]  = axis_in_tuser;
assign fifo_in_tvalid[0] = axis_in_tvalid;
assign axis_in_tready    = fifo_in_tready[0];

// The output stream takes the place of the next FIFO in line
assign axis_out_tdata  = fifo_in_tdata [SECTIONS];
assign axis_out_tuser  = fifo_in_tuser [SECTIONS];
assign axis_out_tvalid = fifo_in_tvalid[SECTIONS];
assign fifo_in_tready[SECTIONS] = axis_out_tready;


// Here we generate one FIFO and one register slice per section
for (i=0; i<SECTIONS; i=i+1) begin

    //=============================================================================
    // This is a single section of our larger FIFO
    //=============================================================================
    xpm_fifo_axis #
    (
       .TDATA_WIDTH     (TDATA_WIDTH),
       .TUSER_WIDTH     (TUSER_WIDTH),
       .FIFO_DEPTH      (SECTION_DEPTH),
       .FIFO_MEMORY_TYPE(FIFO_MEMORY_TYPE),
       .PACKET_FIFO     ("false"),
       .USE_ADV_FEATURES("0000"),
       .CLOCKING_MODE   ("common_clock")
    )
    i_fifo
    (
        // Clock and reset
        .s_aclk   (clk   ),
        .m_aclk   (clk   ),
        .s_aresetn(resetn),

        // The input bus of the FIFO
        .s_axis_tdata (fifo_in_tdata [i]),
        .s_axis_tuser (fifo_in_tuser [i]),
        .s_axis_tvalid(fifo_in_tvalid[i]),
        .s_axis_tready(fifo_in_tready[i]),

        // The output bus of the FIFO
        .m_axis_tdata (fifo_out_tdata [i]),
        .m_axis_tuser (fifo_out_tuser [i]),
        .m_axis_tvalid(fifo_out_tvalid[i]),
        .m_axis_tready(fifo_out_tready[i]),

        // Unused input stream signals
        .s_axis_tkeep(),
        .s_axis_tlast(),
        .s_axis_tdest(),
        .s_axis_tid  (),
        .s_axis_tstrb(),

        // Unused output stream signals
        .m_axis_tdest(),
        .m_axis_tid  (),
        .m_axis_tstrb(),
        .m_axis_tkeep(),
        .m_axis_tlast(),

        // Other unused signals
        .almost_empty_axis (),
        .almost_full_axis  (),
        .dbiterr_axis      (),
        .prog_empty_axis   (),
        .prog_full_axis    (),
        .rd_data_count_axis(),
        .sbiterr_axis      (),
        .wr_data_count_axis(),
        .injectdbiterr_axis(),
        .injectsbiterr_axis()
    );
    //=============================================================================


    //=============================================================================
    // The output side of each individual FIFO section connects to an register 
    // slice.  The output of each slice connects to the next FIFO in the chain
    //=============================================================================
    ldp_slice #
    (
        .DATA_WIDTH     (TDATA_WIDTH),
        .LAST_ENABLE    (0),
        .USER_WIDTH     (TUSER_WIDTH),
        .USER_ENABLE    (1),
        .ID_ENABLE      (0),
        .DEST_ENABLE    (0)
    )
    i_slice
    (
        .clk            (clk),
        .rst            (~resetn),
    
        .s_axis_tdata   (fifo_out_tdata [i]),
        .s_axis_tuser   (fifo_out_tuser [i]),
        .s_axis_tvalid  (fifo_out_tvalid[i]),
        .s_axis_tready  (fifo_out_tready[i]),
        .s_axis_tkeep   (                  ),
        .s_axis_tlast   (                  ),    
        .s_axis_tid     (                  ),    
        .s_axis_tdest   (                  ),    

        .m_axis_tdata   (fifo_in_tdata  [i+1]),
        .m_axis_tuser   (fifo_in_tuser  [i+1]),
        .m_axis_tvalid  (fifo_in_tvalid [i+1]),
        .m_axis_tready  (fifo_in_tready [i+1]),
        .m_axis_tkeep   (                    ),
        .m_axis_tlast   (                    ),    
        .m_axis_tid     (                    ),    
        .m_axis_tdest   (                    )    
    );
end
//=============================================================================


endmodule
