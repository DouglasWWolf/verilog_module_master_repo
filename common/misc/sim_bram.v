module sim_bram #
(
    parameter DW=512,
    parameter AW=64,
    parameter IW=4
)
(
    input clk, resetn,

    //==================  This is an AXI4-slave interface  =====================

    // "Specify write address"              -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_AWADDR,
    input                                   S_AXI_AWVALID,
    input     [7:0]                         S_AXI_AWLEN,
    input     [2:0]                         S_AXI_AWSIZE,
    input     [IW-1:0]                      S_AXI_AWID,
    input     [1:0]                         S_AXI_AWBURST,
    input                                   S_AXI_AWLOCK,
    input     [3:0]                         S_AXI_AWCACHE,
    input     [3:0]                         S_AXI_AWQOS,
    input     [2:0]                         S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input     [DW-1:0]                      S_AXI_WDATA,
    input     [(DW/8)-1:0]                  S_AXI_WSTRB,
    input                                   S_AXI_WVALID,
    input                                   S_AXI_WLAST,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input     [AW-1:0]                      S_AXI_ARADDR,
    input                                   S_AXI_ARVALID,
    input     [2:0]                         S_AXI_ARPROT,
    input                                   S_AXI_ARLOCK,
    input     [IW-1:0]                      S_AXI_ARID,
    input     [2:0]                         S_AXI_ARSIZE,
    input     [7:0]                         S_AXI_ARLEN,
    input     [1:0]                         S_AXI_ARBURST,
    input     [3:0]                         S_AXI_ARCACHE,
    input     [3:0]                         S_AXI_ARQOS,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[DW-1:0]                                          S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY
    //==========================================================================

);

reg[63:0] aw_blocks, w_blocks, b_blocks;

// The number of write requests currently queued up
wire[63:0] aw_queued = (aw_blocks - w_blocks);

//=============================================================================
// This blocks queues up write-requests received on the AW-channel
//=============================================================================
reg awsm_state;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    if (resetn == 0) begin
        aw_blocks  <= 0;
        awsm_state <= 0;
    end

    else case(awsm_state)

        0:  if (S_AXI_AWREADY & S_AXI_AWVALID) begin
                aw_blocks <= aw_blocks + 1;
                awsm_state <= 1;
            end

        1:  awsm_state <= 0;

    endcase

end

assign S_AXI_AWREADY = (resetn == 1 && awsm_state == 0 && aw_queued < 4);
//=============================================================================


//=============================================================================
// This block reads bursts from the W-channel
//=============================================================================
reg      wsm_state;
reg[7:0] w_counter;
reg[2:0] w_cycles;
//-----------------------------------------------------------------------------

always @(posedge clk) begin

    if (resetn == 0) begin
        wsm_state <= 0;
        w_blocks  <= 0;
        w_cycles  <= 0;
    end

    else case(wsm_state)

        0:  if (S_AXI_WREADY & S_AXI_WVALID) begin
                w_cycles <= w_cycles + 1;

                if (S_AXI_WLAST) begin
                    w_cycles  <= 0;
                    w_blocks  <= w_blocks + 1;
                    w_counter <= 3;
                    wsm_state <= 1;
                end

                else if (w_cycles == 7) begin
                    w_counter <= 0;
                    wsm_state <= 1;
                end
            end

        1:  if (w_counter)
                w_counter <= w_counter - 1;
            else
                wsm_state <= 0;

    endcase

end

assign S_AXI_WREADY = (resetn == 1)
                    & (wsm_state == 0)
                    & (aw_queued || S_AXI_AWREADY);
//=============================================================================


//=============================================================================
// Use a B-channel acknowledge for every block we receive on the W-channel
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0)
        b_blocks  <= 0;

    else if (S_AXI_BREADY & S_AXI_BVALID)
        b_blocks <= b_blocks + 1;
end

assign S_AXI_BRESP  = 0;
assign S_AXI_BVALID = (resetn == 1) & (w_blocks > b_blocks);
//=============================================================================


//=============================================================================
// State machine that handles the AR and R channels
//=============================================================================
reg        rsm_state;
reg [63:0] araddr;
reg [ 7:0] arlen, r_cycles;
wire[31:0] rdata = araddr[31:0] + (r_cycles * (DW/8));
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        rsm_state <= 0;
    end

    else case(rsm_state)

        0:  if (S_AXI_ARVALID & S_AXI_ARREADY) begin
                araddr    <= S_AXI_ARADDR;
                arlen     <= S_AXI_ARLEN;
                r_cycles  <= 0;
                rsm_state <= 1;
            end

        1:  if (S_AXI_RVALID & S_AXI_RREADY) begin
                if (r_cycles == arlen)
                    rsm_state <= 0;
                else
                    r_cycles <= r_cycles + 1;
            end

    endcase

end

assign S_AXI_ARREADY = (resetn == 1) & (rsm_state == 0);
assign S_AXI_RVALID  = (resetn == 1) & (rsm_state == 1);
assign S_AXI_RRESP   = 0;
assign S_AXI_RDATA   = (rsm_state == 1) ? {(DW/32){rdata}}    : 0;
assign S_AXI_RLAST   = (rsm_state == 1) ? (r_cycles == arlen) : 0;
//=============================================================================


endmodule
 