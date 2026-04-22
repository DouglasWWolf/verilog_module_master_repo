`timescale 1ns / 1ps
//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 10-May-22  DWW  1000  Initial creation
//
// 22-Jul-25  DWW  1001  Added the missing AxPROT signals and some comments
//                       Module parameter is now AW instead of ADDR_MASK !!
//
// 21-Apr-26  DWW  1002  Fixed bug in the write-logic that could cause an 
//                       incorrect write-address to be used
//====================================================================================


/*
        >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        >>>> This is the AXI4 interface you should place in your module <<<<
        <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    input[   2:0]                           S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,


    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[ 3:0]                             S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_ARADDR,     
    input[   2:0]                           S_AXI_ARPROT,     
    input                                   S_AXI_ARVALID,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[ 1:0]                                            S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================



        >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        >>>>             Declare these signals in your module           <<<<
        <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


    //==========================================================================
    // We'll communicate with the AXI4-Lite Slave core with these signals.
    //==========================================================================
    // AXI Slave Handler Interface for write requests
    wire[  31:0]  ashi_windx;     // Input   Write register-index
    wire[AW-1:0]  ashi_waddr;     // Input:  Write-address
    wire[  31:0]  ashi_wdata;     // Input:  Write-data
    wire          ashi_write;     // Input:  1 = Handle a write request
    reg [   1:0]  ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
    wire          ashi_widle;     // Output: 1 = Write state machine is idle

    // AXI Slave Handler Interface for read requests
    wire[  31:0]  ashi_rindx;     // Input   Read register-index
    wire[AW-1:0]  ashi_raddr;     // Input:  Read-address
    wire          ashi_read;      // Input:  1 = Handle a read request
    reg [  31:0]  ashi_rdata;     // Output: Read data
    reg [   1:0]  ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
    wire          ashi_ridle;     // Output: 1 = Read state machine is idle
    //==========================================================================



        >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        >>>>    This is how you instantiate the module in your code     <<<<
        <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



    //==========================================================================
    // This connects us to an AXI4-Lite slave core
    //==========================================================================
    axi4_lite_slave#(.AW(AW)) i_axi4lite_slave
    (
        .clk            (clk),
        .resetn         (resetn),

        // AXI AW channel
        .AXI_AWADDR     (S_AXI_AWADDR),
        .AXI_AWPROT     (S_AXI_AWPROT),
        .AXI_AWVALID    (S_AXI_AWVALID),   
        .AXI_AWREADY    (S_AXI_AWREADY),

        // AXI W channel
        .AXI_WDATA      (S_AXI_WDATA),
        .AXI_WVALID     (S_AXI_WVALID),
        .AXI_WSTRB      (S_AXI_WSTRB),
        .AXI_WREADY     (S_AXI_WREADY),

        // AXI B channel
        .AXI_BRESP      (S_AXI_BRESP),
        .AXI_BVALID     (S_AXI_BVALID),
        .AXI_BREADY     (S_AXI_BREADY),

        // AXI AR channel
        .AXI_ARADDR     (S_AXI_ARADDR), 
        .AXI_ARPROT     (S_AXI_ARPROT),
        .AXI_ARVALID    (S_AXI_ARVALID),
        .AXI_ARREADY    (S_AXI_ARREADY),

        // AXI R channel
        .AXI_RDATA      (S_AXI_RDATA),
        .AXI_RVALID     (S_AXI_RVALID),
        .AXI_RRESP      (S_AXI_RRESP),
        .AXI_RREADY     (S_AXI_RREADY),

        // ASHI write-request registers
        .ASHI_WADDR     (ashi_waddr),
        .ASHI_WINDX     (ashi_windx),
        .ASHI_WDATA     (ashi_wdata),
        .ASHI_WRITE     (ashi_write),
        .ASHI_WRESP     (ashi_wresp),
        .ASHI_WIDLE     (ashi_widle),

        // ASHI read registers
        .ASHI_RADDR     (ashi_raddr),
        .ASHI_RINDX     (ashi_rindx),
        .ASHI_RDATA     (ashi_rdata),
        .ASHI_READ      (ashi_read ),
        .ASHI_RRESP     (ashi_rresp),
        .ASHI_RIDLE     (ashi_ridle)
    );
    //==========================================================================


*/

module axi4_lite_slave # (parameter AW = 8)
(
    input clk, resetn,

    //======================  AXI Slave Handler Interface  =====================

    // ASHI signals for handling AXI write requests
    output[AW-1:0]  ASHI_WADDR,
    output[  31:0]  ASHI_WINDX,
    output[  31:0]  ASHI_WDATA,
    output          ASHI_WRITE,
    input           ASHI_WIDLE,
    input [   1:0]  ASHI_WRESP,

    // ASHI signals for handling AXI read requests
    output[AW-1:0]  ASHI_RADDR,
    output[  31:0]  ASHI_RINDX,
    output          ASHI_READ,
    input           ASHI_RIDLE,
    input [  31:0]  ASHI_RDATA,
    input [   1:0]  ASHI_RRESP,

    //================ From here down is the AXI4-Lite interface ===============
        
    // "Specify write address"              -- Master --    -- Slave --
    input[AW-1:0]                           AXI_AWADDR,   
    input[   2:0]                           AXI_AWPROT,
    input                                   AXI_AWVALID,  
    output reg                                              AXI_AWREADY,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             AXI_WDATA,      
    input                                   AXI_WVALID,
    input[3:0]                              AXI_WSTRB,
    output reg                                              AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             AXI_BRESP,
    output                                                  AXI_BVALID,
    input                                   AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[AW-1:0]                           AXI_ARADDR,     
    input[   2:0]                           AXI_ARPROT,
    input                                   AXI_ARVALID,
    output                                                  AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            AXI_RDATA,
    output[ 1:0]                                            AXI_RRESP,
    output                                                  AXI_RVALID,
    input                                   AXI_RREADY
    //==========================================================================
 );

    
// The main fields that we pass to the handler when a read or write request comes in
reg[31:0] ashi_waddr, ashi_wdata, ashi_raddr;

// Exchange address and data with the ASHI handler
assign ASHI_WADDR = ashi_waddr;
assign ASHI_WDATA = ashi_wdata;
assign ASHI_RADDR = ashi_raddr;

// These are signals to the handler that they should handle a read or a write
reg    start_wr_stb;
reg    start_rd_stb;
assign ASHI_READ  = start_rd_stb;
assign ASHI_WRITE = start_wr_stb;

// The two response signals are always whatever the handler says they are
assign AXI_BRESP = ASHI_WRESP;
assign AXI_RRESP = ASHI_RRESP;

// Read-data is always whatever the handler says it is
assign AXI_RDATA = (resetn == 0) ? 32'hDEAD_BEEF : ASHI_RDATA;

// The register index for writes is determined by the register address
assign ASHI_WINDX = ASHI_WADDR >> 2;

// The register index for reads is determined by the register address
assign ASHI_RINDX = ASHI_RADDR >> 2;

//=========================================================================================================
// FSM logic for handling AXI read transactions
//=========================================================================================================
reg read_state;
always @(posedge clk) begin

    start_rd_stb <= 0;

    if (resetn == 0) begin
        read_state <= 0;
    end
    
    else case(read_state)

        0:  if (AXI_ARVALID & AXI_ARREADY) begin // If the AXI master has given us an address to read...
                ashi_raddr   <= AXI_ARADDR;      //   Register the address that is being read from
                start_rd_stb <= 1;               //   Tell the ASHI handler to perform the read
                read_state   <= 1;               //   And go wait for that read-logic to finish
            end


        1:  if (AXI_RVALID & AXI_RREADY) begin   // Wait for the AXI master to say "OK, I saw your response"
                read_state  <= 0;                //   And go wait for a new transaction to arrive
            end

    endcase
end
assign AXI_ARREADY = (read_state == 0) & (resetn == 1); 
assign AXI_RVALID  = (read_state == 1) & ASHI_RIDLE;
//=========================================================================================================


//=========================================================================================================
// FSM logic for handling AXI write transactions
//=========================================================================================================
reg[1:0] write_state;
always @(posedge clk) begin

    // This strobes high for a single-cycle at a time
    start_wr_stb <= 0;

    if (resetn == 0) begin
        write_state   <= 0;
        AXI_AWREADY   <= 0;
        AXI_WREADY    <= 0;
    end
    
    else case(write_state)

        0:  begin
                AXI_AWREADY <= 1;
                AXI_WREADY  <= 1;
                write_state <= 1;
            end

        1:  begin
                if (AXI_AWVALID & AXI_WREADY) begin // If this is the write-address handshake...
                    ashi_waddr  <= AXI_AWADDR;      //   Latch the address we're writing to
                    AXI_AWREADY <= 0;               //   We are no longer ready to accept a new address
                end

                if (AXI_WVALID & AXI_WREADY) begin  // If this is the write-data handshake...
                    ashi_wdata  <= AXI_WDATA;       //   Latch the data we're going to write
                    AXI_WREADY  <= 0;               //   We are no longer ready to accept new data
                end

                // If we've seen both handshakes, go wait for the ASHI handler
                if ((AXI_AWVALID | !AXI_AWREADY) & (AXI_WVALID | !AXI_WREADY)) begin
                    start_wr_stb <= 1;
                    write_state  <= 2;
                end
            end

        // Wait for the AXI master to receive our acknowledgement
        2:  if (AXI_BVALID & AXI_BREADY) begin
                AXI_AWREADY <= 1;
                AXI_WREADY  <= 1;
                write_state <= 1;
            end

    endcase
end

// AXI_BVALID is asserted only when the ASHI handler is idle
assign AXI_BVALID = (write_state == 2 && ASHI_WIDLE);
//=========================================================================================================


endmodule
