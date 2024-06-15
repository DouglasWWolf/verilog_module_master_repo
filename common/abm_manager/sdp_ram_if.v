//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 20-Mar-24  DWW     1  Initial creation
//====================================================================================

/*
    This is an a block of simple-dual-port RAM, along with an AXI interface
    for writing to it.

    The AXI interface ignored M_AXI_WSTRB and expects every beat of ther write 
    to occupy the full width of the data bus.
*/

module sdp_ram_if #
(
    parameter DW       = 512,
    parameter DD       = 16384,
    parameter RAM_TYPE = "ultra"
)
( 
    input   clk, resetn,

    // This will strobe high for a single cycle any time the last
    // word of the RAM is written to
    output last_word_written,

    // The "read only" RAM interface
    input  [$clog2(DD)-1:0] addrb,    
    output [DW-1:0]         dob,

    //=================  This is the main AXI4-slave interface  ================

    // "Specify write address"              -- Master --    -- Slave --
    input[$clog2(DD * (DW/8))-1:0]          S_AXI_AWADDR,
    input                                   S_AXI_AWVALID,
    input[3:0]                              S_AXI_AWID,
    input[7:0]                              S_AXI_AWLEN,
    input[2:0]                              S_AXI_AWSIZE,
    input[1:0]                              S_AXI_AWBURST,
    input                                   S_AXI_AWLOCK,
    input[3:0]                              S_AXI_AWCACHE,
    input[3:0]                              S_AXI_AWQOS,
    input[2:0]                              S_AXI_AWPROT,
    output reg                                              S_AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input[DW-1:0]                           S_AXI_WDATA,
    input[DW/8-1:0]                         S_AXI_WSTRB,
    input                                   S_AXI_WVALID,
    input                                   S_AXI_WLAST,
    output reg                                              S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[$clog2(DD * (DW/8))-1:0]          S_AXI_ARADDR,
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
    output[DW-1:0]                                          S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY

    //==========================================================================
);

// This is the width of a RAM address
localparam AW = $clog2(DD);

//-----------------------------------------------------------------------------
// Data, address, and write-enable outputs for writing to RAM
//-----------------------------------------------------------------------------
reg[DW-1:0] ram_wdata;
reg[AW-1:0] ram_waddr;
reg         ram_we;
// -------------------------   A block of RAM   -------------------------------
sdp_ram # (.DW(DW), .DD(DD), .RAM_TYPE(RAM_TYPE)) u_sdp_ram
(
    .clk    (clk),
    .wea    (ram_we),
    .addra  (ram_waddr),
    .dia    (ram_wdata),
    .addrb  (addrb),
    .dob    (dob)    
);
//-----------------------------------------------------------------------------

// These are the handshakes for the AXI AW and W channels
wire aw_handshake = S_AXI_AWREADY & S_AXI_AWVALID;
wire  w_handshake = S_AXI_WREADY  & S_AXI_WVALID;

// This will be high any time the last word of RAM is written to
assign last_word_written = (ram_we & (ram_waddr == DD-1));

reg[   1:0] fsm_state;
reg[AW-1:0] next_waddr;

always @(posedge clk) begin

    // The "write-enable" for RAM defaults to 0
    ram_we <= 0;

    if (resetn == 0) begin
        fsm_state     <= 0;
        S_AXI_AWREADY <= 0;
        S_AXI_WREADY  <= 0;
    end else case(fsm_state)

        // As we come out of reset, tell the AXI master that we 
        // are ready to receive data on both the W and AW channel
        0:  begin
                S_AXI_AWREADY <= 1;
                S_AXI_WREADY  <= 1;
                fsm_state     <= 1;
            end

        1:  begin

                // If we get a transaction on the AW-channel, store the
                // destination address as an index into the RAM array, then
                // stop accepting transactions on the AW-channel
                if (aw_handshake) begin
                    ram_waddr     <= (S_AXI_AWADDR >> $clog2(DW/8));
                    next_waddr    <= (S_AXI_AWADDR >> $clog2(DW/8)) + 1;
                    S_AXI_AWREADY <= 0;
                end


                // If we get incoming data, write it to RAM, then examine WLAST
                // to determine whether or not this was the first beat of a
                // multi-beat burst
                if (w_handshake) begin
                    ram_wdata     <= S_AXI_WDATA;
                    ram_we        <= 1;
                    if (S_AXI_WLAST) 
                        S_AXI_AWREADY <= 1;
                    else    
                        fsm_state <= 2;
                end
            end

        // Here we handle the 2nd and subsequent beats of a burst
        2:  begin
                ram_waddr <= next_waddr;
                ram_wdata <= S_AXI_WDATA;

                if (w_handshake) begin
                    ram_we     <= 1;
                    next_waddr <= next_waddr + 1;
                    if (S_AXI_WLAST) begin
                        S_AXI_AWREADY <= 1;
                        fsm_state     <= 1;
                    end
                end
            end

    endcase

end

//-----------------------------------------------------------------------------
// The logic from here down ensures that an acknowledgement gets sent on the
// AXI B-channel every time we receive a complete burst of data on W-channel.
//-----------------------------------------------------------------------------

// Write acknowledgements on the B-channel will always be "OKAY"
assign S_AXI_BRESP = 0;

// The number of bursts of data received, and the number of them that we have acknowledged
reg[15:0] bursts_rcvd, bursts_ackd;

// BVALID is asserted while we have acknowledgemts we still need to send
assign S_AXI_BVALID = (bursts_ackd != bursts_rcvd);

// Count the number of bursts we receive.  That's how many acks we need to send
always @(posedge clk) begin
    if (resetn == 0)
        bursts_rcvd <= 0;
    else if (S_AXI_WVALID & S_AXI_WREADY & S_AXI_WLAST)
        bursts_rcvd <= bursts_rcvd + 1;
end

// Count the number of acknowledgements sent
always @(posedge clk) begin
    if (resetn == 0)
        bursts_ackd <= 0;
    else if (S_AXI_BREADY & S_AXI_BVALID)
        bursts_ackd <= bursts_ackd + 1;
end


endmodule

