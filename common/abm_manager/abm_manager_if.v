//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 21-Mar-24  DWW     1  Initial creation
//====================================================================================


/*
    This is an AXI slave-interface to a pair of SDP (Simple Dual Port) RAM
    blocks.

    Reading from the S_AXI interface will return data that is the arithmetic-or 
    of the two blocks of RAM

    The S_AXI interface is read-only and does not support narrow reads or burst 
    modes other than "increment"
*/

module abm_manager_if # (parameter DW = 512, DD = 16384)
(
    input clk, resetn,

    output reg [$clog2(DD)-1:0] ram_addr,
    input      [DW-1:0]         ram0_data, ram1_data,

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
    output reg                                              S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output reg [DW-1:0]                                     S_AXI_RDATA,
    output reg                                              S_AXI_RVALID,
    output     [1:0]                                        S_AXI_RRESP,
    output                                                  S_AXI_RLAST,
    input                                   S_AXI_RREADY

    //==========================================================================
);

reg [2:0] fsm_state;
reg [7:0] burst_length, beat;

// Assert RLAST on the last beat of every burst
assign S_AXI_RLAST = (beat == burst_length);

// The read-response is always "OKAY"
assign S_AXI_RRESP = 0;


always @(posedge clk) begin
    
    if (resetn == 0) begin
        fsm_state     <= 0;
        S_AXI_ARREADY <= 0;
    end else case (fsm_state)

        // As we come out of reset, begin accepting read-requests
        0:  begin
                S_AXI_ARREADY <= 1;
                fsm_state     <= fsm_state + 1;
            end

        // If we receive a read-request, prepare to transmit a 
        // burst of data and stop accepting read requests
        1:  if (S_AXI_ARVALID & S_AXI_ARREADY) begin
                burst_length   <= S_AXI_ARLEN;
                beat           <= 0;
                ram_addr       <= S_AXI_ARADDR >> $clog2(DW/8);
                S_AXI_ARREADY  <= 0;
                fsm_state      <= fsm_state + 1;
            end

        // Waste 1 cycle of latency while we wait for ram0_data and ram1_data
        // to contain valid data
        2: fsm_state <= fsm_state + 1;

        // Send the "ram0_data | ram_1_data" to the AXI master
        // and start the next read from RAM
        3:  begin
                S_AXI_RDATA    <= ram0_data | ram1_data;
                S_AXI_RVALID   <= 1;
                ram_addr       <= ram_addr + 1;
                fsm_state      <= fsm_state + 1;
            end

        // Once the master accepts the data we just sent, either
        // complete the burst, or (if this was the last beat of
        // the burst), go back to waiting for a new read-request
        4:  if (S_AXI_RREADY & S_AXI_RVALID) begin
                S_AXI_RVALID <= 0;
                if (S_AXI_RLAST) begin
                    S_AXI_ARREADY <= 1;
                    fsm_state     <= 1;
                end else begin
                    beat          <= beat + 1;
                    fsm_state     <= fsm_state - 1;
                end
            end

    endcase
end


endmodule
