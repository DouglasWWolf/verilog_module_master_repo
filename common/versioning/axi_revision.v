//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 26-Jul-22  DWW     1  Initial creation
//  
// 29-Apr-24  DWW     2  Added support for RTL_TYPE and RTL_SUBTYPE
//
// 04-Jun-25  DWW     3  Added support for reporting git-hash
//
// 05-Jun-25  DWW     4  Added support for reporting build-time
//====================================================================================

/*

    This module serves as a simple AXI4-Lite slave for reporting build version:

    On the AXI4-lite slave interface, there are twelve 32-bit registers:
       Offset 0x00 : Read-only = Major Revision
       Offset 0x04 : Read-only = Minor Revision
       Offset 0x08 : Read-only = Build Number
       Offset 0x0C : Read-only = Release candidate
       Offset 0x10 : Read-only = Build Date
       Offset 0x14 : Read-only = RTL type
       Offset 0x18 : Read-only = RTL subtype
       Offset 0x1C : Read-only = Build Time
       Offset 0x40 : Read-only = Git-Hash word #0
       Offset 0x44 : Read-only = Git-Hash word #1
       Offset 0x48 : Read-only = Git-Hash word #2
       Offset 0x4C : Read-only = Git-Hash word #3
       Offset 0x50 : Read-only = Git-Hash word #4
*/


//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//            Application-specific logic goes at the bottom of the file
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

module axi_revision
(
    input wire  AXI_ACLK,
    input wire  AXI_ARESETN,

    //==========================================================================
    //               This defines the AXI4-Lite slave interface
    //==========================================================================
    // "Specify write address"              -- Master --    -- Slave --
    input  wire [6:0]                       S_AXI_AWADDR,   
    input  wire                             S_AXI_AWVALID,  
    output wire                                             S_AXI_AWREADY,
    input  wire [2:0]                       S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input  wire [31:0]                      S_AXI_WDATA,      
    input  wire                             S_AXI_WVALID,
    input  wire [3:0]                       S_AXI_WSTRB,
    output wire                                             S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output  wire [1:0]                                      S_AXI_BRESP,
    output  wire                                            S_AXI_BVALID,
    input   wire                            S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input  wire [6:0]                       S_AXI_ARADDR,     
    input  wire                             S_AXI_ARVALID,
    input  wire [2:0]                       S_AXI_ARPROT,     
    output wire                                             S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output  wire [31:0]                     S_AXI_RDATA,
    output  wire                                            S_AXI_RVALID,
    output  wire [1:0]                                      S_AXI_RRESP,
    input   wire                            S_AXI_RREADY
    //==========================================================================
 );

    /*
        @register "major" portion of RTL revision "major.minor.build"
    */
    localparam REG_MAJOR       = 0;

    /*
        @register "minor" portion of RTL revision "major.minor.build"
    */
    localparam REG_MINOR       = 1;
    
    /*
        @register "build" portion of RTL revision "major.minor.build"
    */
    localparam REG_BUILD       = 2;

    localparam REG_RCAND       = 3;

    /*
        @register Build date
        @field month  8 24 RO N/A Build month (1 thru 12)
        @field day    8 16 RO N/A Build date  (1 thru 31)
        @field year  16  0 RO N/A Build year  (4 digit year)
    */
    localparam REG_DATE        = 4;

    /*
        @register Uniquely identifies this RTL design
        @rname    REG_TYPE
    */
    localparam REG_RTL_TYPE    = 5;
    localparam REG_RTL_SUBTYPE = 6;

    /*
        @register Build date
        @field hour  8 16 RO N/A Build month (0 thru 23)
        @field min   8  8 RO N/A Build date  (0 thru 59)
        @field sec   8  0 RO N/A Build year  (0 thru 59)
    */
    localparam REG_TIME        = 7;


    /*
        @register Git commit hash
        @rsize    This is an array of five consecutive 32-bit registers
        @rname    REG_GIT_HASH
    */
    localparam REG_GIT_HASH_0  = 16;
    localparam REG_GIT_HASH_1  = 17;
    localparam REG_GIT_HASH_2  = 18;
    localparam REG_GIT_HASH_3  = 19;
    localparam REG_GIT_HASH_4  = 20;

   
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //                           This section is standard AXI4-Lite Slave logic
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><

    // These are valid values for BRESP and RRESP
    localparam OKAY   = 0;
    localparam DECERR = 1;
    localparam SLVERR = 2;

    // These are for communicating with application-specific read and write logic
    reg  user_read_start,  user_read_idle;
    reg  user_write_start, user_write_idle;
    wire user_write_complete = (user_write_start == 0) & user_write_idle;
    wire user_read_complete  = (user_read_start  == 0) & user_read_idle;


    // Define the handshakes for all 5 slave AXI channels
    wire S_B_HANDSHAKE  = S_AXI_BVALID  & S_AXI_BREADY;
    wire S_R_HANDSHAKE  = S_AXI_RVALID  & S_AXI_RREADY;
    wire S_W_HANDSHAKE  = S_AXI_WVALID  & S_AXI_WREADY;
    wire S_AR_HANDSHAKE = S_AXI_ARVALID & S_AXI_ARREADY;
    wire S_AW_HANDSHAKE = S_AXI_AWVALID & S_AXI_AWREADY;

        
    //=========================================================================================================
    // FSM logic for handling AXI4-Lite read-from-slave transactions
    //=========================================================================================================
    // When a valid address is presented on the bus, this register holds it
    reg[7-1:0] s_axi_araddr;

    // Wire up the AXI interface outputs
    reg                       s_axi_arready; assign S_AXI_ARREADY = s_axi_arready;
    reg                       s_axi_rvalid;  assign S_AXI_RVALID  = s_axi_rvalid;
    reg[1:0]                  s_axi_rresp;   assign S_AXI_RRESP   = s_axi_rresp;
    reg[32-1:0] s_axi_rdata;   assign S_AXI_RDATA   = s_axi_rdata;
     //=========================================================================================================
    reg s_read_state;
    always @(posedge AXI_ACLK) begin
        user_read_start <= 0;
        
        if (AXI_ARESETN == 0) begin
            s_read_state  <= 0;
            s_axi_arready <= 1;
            s_axi_rvalid  <= 0;
        end else case(s_read_state)

        0:  begin
                s_axi_rvalid <= 0;                      // RVALID will go high only when we have filled in RDATA
                if (S_AXI_ARVALID) begin                // If the AXI master has given us an address to read...
                    s_axi_arready   <= 0;               //   We are no longer ready to accept an address
                    s_axi_araddr    <= S_AXI_ARADDR;    //   Register the address that is being read from
                    user_read_start <= 1;               //   Start the application-specific read-logic
                    s_read_state    <= 1;               //   And go wait for that read-logic to finish
                end
            end

        1:  if (user_read_complete) begin               // If the application-specific read-logic is done...
                s_axi_rvalid <= 1;                      //   Tell the AXI master that RDATA and RRESP are valid
                if (S_R_HANDSHAKE) begin                //   Wait for the AXI master to say "OK, I saw your response"
                    s_axi_rvalid  <= 0;                 //     The AXI master has registered our data
                    s_axi_arready <= 1;                 //     Once that happens, we're ready to start a new transaction
                    s_read_state  <= 0;                 //     And go wait for a new transaction to arrive
                end
            end

        endcase
    end
    //=========================================================================================================


    //=========================================================================================================
    // FSM logic for handling AXI4-Lite write-to-slave transactions
    //=========================================================================================================
    // When a valid address is presented on the bus, this register holds it
    reg[7-1:0] s_axi_awaddr;

    // When valid write-data is presented on the bus, this register holds it
    reg[32-1:0] s_axi_wdata;
    
    // Wire up the AXI interface outputs
    reg      s_axi_awready; assign S_AXI_AWREADY = s_axi_arready;
    reg      s_axi_wready;  assign S_AXI_WREADY  = s_axi_wready;
    reg      s_axi_bvalid;  assign S_AXI_BVALID  = s_axi_bvalid;
    reg[1:0] s_axi_bresp;   assign S_AXI_BRESP   = s_axi_bresp;
    //=========================================================================================================
    reg s_write_state;
    always @(posedge AXI_ACLK) begin
        user_write_start <= 0;
        if (AXI_ARESETN == 0) begin
            s_write_state <= 0;
            s_axi_awready <= 1;
            s_axi_wready  <= 1;
            s_axi_bvalid  <= 0;
        end else case(s_write_state)

        0:  begin
                s_axi_bvalid <= 0;                    // BVALID will go high only when we have filled in BRESP

                if (S_AW_HANDSHAKE) begin             // If this is the write-address handshake...
                    s_axi_awready <= 0;               //     We are no longer ready to accept a new address
                    s_axi_awaddr  <= S_AXI_AWADDR;    //     Keep track of the address we should write to
                end

                if (S_W_HANDSHAKE) begin              // If this is the write-data handshake...
                    s_axi_wready     <= 0;            //     We are no longer ready to accept new data
                    s_axi_wdata      <= S_AXI_WDATA;  //     Keep track of the data we're supposed to write
                    user_write_start <= 1;            //     Start the application-specific write logic
                    s_write_state    <= 1;            //     And go wait for that write-logic to complete
                end
            end

        1:  if (user_write_complete) begin            // If the application-specific write-logic is done...
                s_axi_bvalid <= 1;                    //   Tell the AXI master that BRESP is valid
                if (S_B_HANDSHAKE) begin              //   Wait for the AXI master to say "OK, I saw your response"
                    s_axi_awready <= 1;               //     Once that happens, we're ready for a new address
                    s_axi_wready  <= 1;               //     And we're ready for new data
                    s_write_state <= 0;               //     Go wait for a new transaction to arrive
                end
            end

        endcase
    end
    //=========================================================================================================
  
 
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //                  Application-specific read/write logic goes below this point
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    //<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
    `include "revision_history.vh"
    `include "git_hash.vh"
    `include "timestamp.vh"
    

    //=========================================================================================================
    // State machine that handles AXI master reads of our AXI4-Lite slave registers
    //
    // When user_read_start goes high, this state machine should handle the read-request.
    //    s_axi_araddr = The byte address of the register to read
    //
    // When read operation is complete:
    //    user_read_idle = 1
    //    s_axi_rresp     = OKAY/SLVERR response to send to the requesting master
    //    s_axi_rdata     = The read-data to send back to the requesting master
    //=========================================================================================================
    always @(posedge AXI_ACLK) begin
        if (AXI_ARESETN == 0) begin
            user_read_idle <= 1;
        end else if (user_read_start) begin
            s_axi_rresp <= OKAY;
            case(s_axi_araddr >> 2)
                REG_MAJOR:       s_axi_rdata <= VERSION_MAJOR;
                REG_MINOR:       s_axi_rdata <= VERSION_MINOR;
                REG_BUILD:       s_axi_rdata <= VERSION_BUILD;
                REG_RCAND:       s_axi_rdata <= VERSION_RCAND;
                REG_DATE:        s_axi_rdata <= BUILD_DATE;
                REG_TIME:        s_axi_rdata <= BUILD_TIME;
                REG_RTL_TYPE:    s_axi_rdata <= RTL_TYPE;
                REG_RTL_SUBTYPE: s_axi_rdata <= RTL_SUBTYPE;
                REG_GIT_HASH_0:  s_axi_rdata <= GIT_HASH[4 * 32 +: 32];
                REG_GIT_HASH_1:  s_axi_rdata <= GIT_HASH[3 * 32 +: 32];
                REG_GIT_HASH_2:  s_axi_rdata <= GIT_HASH[2 * 32 +: 32];
                REG_GIT_HASH_3:  s_axi_rdata <= GIT_HASH[1 * 32 +: 32];
                REG_GIT_HASH_4:  s_axi_rdata <= GIT_HASH[0 * 32 +: 32];
                default: 
                    begin
                        s_axi_rdata <= 0;
                        s_axi_rresp <= DECERR;
                    end
            endcase
        end
    end
    //=========================================================================================================
    


    //=========================================================================================================
    // State machine that handles AXI master writes to our AXI4-Lite slave registers
    //
    // When user_write_start goes high, this state machine should handle the write-request.
    //    s_axi_awaddr = The byte address of the register to write to
    //    s_axi_wdata  = The 32-bit word to write into that register
    //
    // When write operation is complete:
    //    user_write_idle = 1
    //    s_axi_bresp     = OKAY/SLVERR response to send to the requesting master
    //=========================================================================================================
    always @(posedge AXI_ACLK) begin
        user_write_idle <= 1;
        s_axi_bresp     <= OKAY;
    end
    //=========================================================================================================


endmodule
