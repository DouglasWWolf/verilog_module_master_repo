//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 25-Oct-23  DWW     1  Initial creation
//
// 25-Feb-24  DWW     2  Made FIFO depth configurable, with a default of 16384
//====================================================================================

/*
    The purpose of this module is to stream out byte patterns that have been recorded  
    in a FIFO.   There are two input FIFOs, and only one at a time can be streaming out
    its contents.

    Whenever an entry is extracted from a FIFO it is written back into that FIFO so that
    the vector of values in the FIFO can be re-used in a continuous loop.
*/

module sensor_emu_ctl #
(
    // This must be 8, 16, 32, or 64
    parameter PATTERN_WIDTH = 32,

    // How many entries can our FIFO hold?    
    parameter FIFO_DEPTH = 16384    
)
(
    input clk, resetn,
 
    //==========================================================================
    //          These ports are probably mapped to AXI registers
    //==========================================================================

    // These reset the FIFOs
    input i_FIFO_CTL_f0_reset,
    input i_FIFO_CTL_f1_reset,
    input i_FIFO_CTL_wstrobe,

    // Upper 32 bits of data for a FIFO
    input [31:0] i_UPPER32,
    
    // Loads a word into FIFO 0
    input [31:0] i_LOAD_F0,
    input        i_LOAD_F0_wstrobe,
    
    // Loads a word into FIFO 1
    input [31:0] i_LOAD_F1,
    input        i_LOAD_F1_wstrobe,

    // Activates one of the FIFOs
    input [1:0]  i_START,
    input        i_START_wstrobe,

    // Forces a hard-stop
    input        i_HARD_STOP_wstrobe,

    // Module revision number
    output [31:0]  o_MODULE_REV,

    // The cell pattern width, in bytes
    output [3:0]   o_PATTERN_WIDTH,

    // FIFO status (indicates the FIFOs are ready to accept data)
    output         o_FIFO_STAT_f0_ready,
    output         o_FIFO_STAT_f1_ready,

    // The number of entries in each FIFO
    output [31:0]  o_F0_COUNT,
    output [31:0]  o_F1_COUNT,

    // Which FIFO is active (if any)
    output [1:0]   o_ACTIVE_FIFO,
    //==========================================================================


    //=========================   The output stream   ==========================
    output [PATTERN_WIDTH-1:0] AXIS_OUT_TDATA,
    output                     AXIS_OUT_TVALID,
    input                      AXIS_OUT_TREADY
    //==========================================================================
);  

    // Any time the register map of this module changes, this number should be bumped
    localparam MODULE_VERSION = 1;

    // When one of these counters is non-zero, the associated FIFO is held in reset
    reg[3:0] f0_reset_counter, f1_reset_counter;

    // These two wires control the reset input of the FIFOs
    wire f0_reset = (resetn == 0 || f0_reset_counter != 0);
    wire f1_reset = (resetn == 0 || f1_reset_counter != 0);

    // These signals are the input bus to fifo_0
    reg[PATTERN_WIDTH-1:0]  f0in_tdata;
    reg                     f0in_tvalid;
    wire                    f0in_tready;

    // These signals are the output bus of fifo_0
    wire[PATTERN_WIDTH-1:0] f0out_tdata;
    wire                    f0out_tvalid;
    wire                    f0out_tready;

    // These signals are the input bus to fifo_1
    reg[PATTERN_WIDTH-1:0]  f1in_tdata;
    reg                     f1in_tvalid;
    wire                    f1in_tready;

    // These signals are the output bus of fifo_1
    wire[PATTERN_WIDTH-1:0] f1out_tdata;
    wire                    f1out_tvalid;
    wire                    f1out_tready;

    // The number of data elements stored in each FIFO
    reg[14:0] f0_count, f1_count;

    // This is the value that will be loaded into a FIFO
    reg[63:0] input_value;

    // When one of these bits are strobed high, "input value" is loaded into that FIFO
    reg[1:0] fifo_load_strobe;

    // These bits indicate which FIFO will be output next
    reg[1:0] fifo_on_deck;

    // These bits indicate which FIFO is actively outputting data
    reg[1:0] active_fifo;

    // If this strobes high, the output-state-machine immediately goes idle
    reg hard_stop;

    // If we have an active FIFO, the frame generator can do its thing
    assign AXIS_OUT_TVALID = (active_fifo != 0);
    
    //==========================================================================
    // This state machine handles AXI4-Lite write requests
    //
    // Drives:
    //   f0_reset_counter (and therefore, f0_reset)
    //   f1_reset_counter (and therefore, f1_reset)
    //   f0_count and f1_count
    //   fifo_load_strobe
    //   input_value
    //   fifo_on_deck   
    //   hard_stop
    //==========================================================================
    always @(posedge clk) begin

        // The reset counters for the two FIFOs always count down to zero
        if (f0_reset_counter) f0_reset_counter <= f0_reset_counter - 1;
        if (f1_reset_counter) f1_reset_counter <= f1_reset_counter - 1;

        // When one of these bit strobes high, "input_value" is loaded into a FIFO
        fifo_load_strobe <= 0;

        // This only strobes high for a single cycle at a time
        hard_stop <= 0;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            f0_reset_counter <= 0;
            f1_reset_counter <= 0;
            f0_count         <= 0;
            f1_count         <= 0;
            fifo_on_deck     <= 0;

        // If we're not in reset, and a write-request has occured...        
        end else begin

            // Is the user requesting a reset of one or both of the FIFOs?
            if (i_FIFO_CTL_wstrobe) begin
                           
                // If the user wants to clear fifo_0...
                if (i_FIFO_CTL_f0_reset & ~active_fifo[0]) begin
                    f0_count         <= 0;
                    f0_reset_counter <= -1;
                end
                            
                // If the user wants to clear fifo_1...
                if (i_FIFO_CTL_f1_reset & ~active_fifo[1]) begin
                    f1_count         <= 0;
                    f1_reset_counter <= -1;
                end   
            end

        
            // Is the user loading an entry into fifo_0?
            if (i_LOAD_F0_wstrobe & ~active_fifo[0]) begin
                input_value      <= {i_UPPER32, i_LOAD_F0};
                fifo_load_strobe <= 1;
                f0_count         <= f0_count + 1;
            end

            // Is the user loading an entry into fifo_1?
            if (i_LOAD_F1_wstrobe & ~active_fifo[1]) begin
                input_value      <= {i_UPPER32, i_LOAD_F1};
                fifo_load_strobe <= 2;
                f1_count         <= f1_count + 1;
            end


            // Is the user requesting that we start or stop?    
            if (i_START_wstrobe) begin
                if (i_START == 0)
                    fifo_on_deck <= 0;

                else if (i_START == 1 && f0_count)
                    fifo_on_deck <= 1;
            
                else if (i_START == 2 && f1_count) 
                    fifo_on_deck <= 2;
            end

            // Is the user requesting a hard-stop?
            if (i_HARD_STOP_wstrobe) begin
                fifo_on_deck <= 0;
                hard_stop    <= 1;
            end
                    
        end
    end
    //==========================================================================



    //==========================================================================
    // This block updates the status ports
    //==========================================================================
    assign o_MODULE_REV         = MODULE_VERSION;
    assign o_PATTERN_WIDTH      = PATTERN_WIDTH / 8;
    assign o_FIFO_STAT_f0_ready = (f0_reset == 0) & (f0in_tready == 1);
    assign o_FIFO_STAT_f1_ready = (f1_reset == 0) & (f1in_tready == 1);
    assign o_F0_COUNT           = f0_count;
    assign o_F1_COUNT           = f1_count;
    assign o_ACTIVE_FIFO        = active_fifo;
    //==========================================================================
    

    //====================================================================================
    // This state machine controls the inputs to the FIFOs
    //
    // Drives:
    //    f0in_tvalid (TVALID line for input to fifo_0)
    //    f1in_tvalid (TVALID line for input to fifo_1)
    //    f0in_tdata  (TDATA lines for input to fifo_0)
    //    f1in_tdata  (TDATA lines for input to fifo_1)
    //====================================================================================
    always @(posedge clk) begin
        
        // By default, we're not writing to either FIFO
        f0in_tvalid <= 0;
        f1in_tvalid <= 0;

        // If F0 load_strobe is high, we write the input value to fif0_0
        if (fifo_load_strobe[0]) begin
            f0in_tdata  <= input_value;
            f0in_tvalid <= 1;
        end

        // If F1 load_strobe is high, we write the input value to fif0_1
        if (fifo_load_strobe[1]) begin
            f1in_tdata  <= input_value;
            f1in_tvalid <= 1;
        end

        // When an entry is output from fifo_0, feed it back to the input
        if (f0out_tvalid & f0out_tready) begin
            f0in_tdata  <= f0out_tdata;
            f0in_tvalid <= 1;
        end

        // When an entry is output from fifo_1, feed it back to the input
        if (f1out_tvalid & f1out_tready) begin
            f1in_tdata  <= f1out_tdata;
            f1in_tvalid <= 1;
        end
    end
    //====================================================================================



    //====================================================================================
    // This state machine moves data from a FIFO to the output stream
    //
    // Drives:
    //  AXIS_OUT_TDATA
    //  AXIS_OUT_TVALID
    //  active_fifo
    //  f0out_tready
    //  f1out_tready
    //
    // "osm" means "output state machine"
    //
    //====================================================================================
    reg       osm_state;
    reg[15:0] osm_counter;

    // The data being driven out on AXIS_OUT_TDATA is the output of one of the FIFOs
    assign AXIS_OUT_TDATA = (active_fifo == 1) ? f0out_tdata :
                            (active_fifo == 2) ? f1out_tdata : 8'h55;

    assign f0out_tready = (active_fifo == 1) ? AXIS_OUT_TREADY : 0;
    assign f1out_tready = (active_fifo == 2) ? AXIS_OUT_TREADY : 0;                                
    //====================================================================================
    always @(posedge clk) begin

        if (resetn == 0) begin
            osm_state   <= 0; 
            active_fifo <= 0;
        
        end else case(osm_state)

            
            0:  begin
                    active_fifo <= 0;
                    osm_state   <= 1;
                end
    
            1:  // If we've been told to return to idle...               
                if (hard_stop) begin
                    active_fifo <= 0;
                end 

                // If we're waiting for a start command or this data-cycle is a handshake on AXIS_OUT...
                else if (active_fifo == 0 || (AXIS_OUT_TVALID & AXIS_OUT_TREADY)) begin
                    
                    // Don't forget that this doesn't take effect until the end of the cycle!
                    osm_counter <= osm_counter - 1;

                    // If we're either waiting for a "start" or if we've output the entire FIFO already...
                    if (active_fifo == 0 || osm_counter == 1) begin

                        // If we've been told to start outputting from fifo_0...    
                        if (fifo_on_deck == 1) begin
                            active_fifo <= 1;
                            osm_counter <= f0_count;
                        end else

                        // If we've been told to start outputting from fifo_1....
                        if (fifo_on_deck == 2) begin
                            active_fifo <= 2;
                            osm_counter <= f1_count;
                        end else

                        begin
                            active_fifo <= 0;
                        end
                    end
                end
        endcase

    end
    //====================================================================================






//====================================================================================
// This FIFO holds a vector of cell patterns
//====================================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH(FIFO_DEPTH),        // DECIMAL
   .TDATA_WIDTH(PATTERN_WIDTH),    // DECIMAL
   .FIFO_MEMORY_TYPE("auto"),      // String
   .PACKET_FIFO("false"),          // String
   .USE_ADV_FEATURES("0000")       // String
)
fifo_0
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(~f0_reset),

    // The input bus to the FIFO
   .s_axis_tdata (f0in_tdata ),
   .s_axis_tvalid(f0in_tvalid),
   .s_axis_tready(f0in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (f0out_tdata ),
   .m_axis_tvalid(f0out_tvalid),
   .m_axis_tready(f0out_tready),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),
   .s_axis_tkeep(),
   .s_axis_tlast(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tuser(),
   .m_axis_tkeep(),
   .m_axis_tlast(),

    // Other unused signals
   .almost_empty_axis(),
   .almost_full_axis(),
   .dbiterr_axis(),
   .prog_empty_axis(),
   .prog_full_axis(),
   .rd_data_count_axis(),
   .sbiterr_axis(),
   .wr_data_count_axis(),
   .injectdbiterr_axis(),
   .injectsbiterr_axis()
);
//====================================================================================


//====================================================================================
// This FIFO holds a vector of 8-bit cell-values
//====================================================================================
xpm_fifo_axis # 
(
   .FIFO_DEPTH(FIFO_DEPTH),        // DECIMAL
   .TDATA_WIDTH(PATTERN_WIDTH),    // DECIMAL
   .FIFO_MEMORY_TYPE("auto"),      // String
   .PACKET_FIFO("false"),          // String
   .USE_ADV_FEATURES("0000")       // String
)
fifo_1
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(~f1_reset),

    // The input bus to the FIFO
   .s_axis_tdata (f1in_tdata),
   .s_axis_tvalid(f1in_tvalid),
   .s_axis_tready(f1in_tready),

    // The output bus of the FIFO
   .m_axis_tdata (f1out_tdata),
   .m_axis_tvalid(f1out_tvalid),
   .m_axis_tready(f1out_tready),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),
   .s_axis_tkeep(),
   .s_axis_tlast(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tuser(),
   .m_axis_tkeep(),
   .m_axis_tlast(),

    // Other unused signals
   .almost_empty_axis(),
   .almost_full_axis(),
   .dbiterr_axis(),
   .prog_empty_axis(),
   .prog_full_axis(),
   .rd_data_count_axis(),
   .sbiterr_axis(),
   .wr_data_count_axis(),
   .injectdbiterr_axis(),
   .injectsbiterr_axis()
);
//====================================================================================

endmodule
