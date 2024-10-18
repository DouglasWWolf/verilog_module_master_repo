//=============================================================================
//                        ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 17-Oct-24  DWW     1  Initial creation
// 18-Oct-24  DWW     2  Now initializing fsm_state when resetn is asserted
//=============================================================================
 
/*

   This modules measures and monitors backpressure

   The acronym "bp" means "backpressure"

   The acronym "rxad" means "rx alignment dropped"

*/

module cmac_bp_monitor# (parameter DW=512, FIFO_DEPTH = 128, BP_LIMIT = 322000000)
(
    input clk, resetn,
   

    // The AXI stream that we're monitoring
    (* X_INTERFACE_MODE = "monitor" *)
    input           monitor_tready,  

    // This is here to keep the IPI happy and doesn't have to be connected
    input[DW-1:0]   monitor_tdata, 

    // This tells us if the CMAC has acheived RX alignment
    input           rx_aligned,

    // Status and control for the FIFO that holds back-pressure event entries
    output [31:0] fifo_bp_length,
    output        fifo_bp_rxad,
    output [63:0] fifo_bp_ts,
    output        fifo_valid,
    input         fifo_next
);

// Strobing this register high will write an entry to our FIFO
reg fifo_write;

// The state of the state machine
reg[1:0] fsm_state;

//=============================================================================
// This block manages the timestamp counter
//=============================================================================
reg[63:0] timestamp;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0)
        timestamp <= 0;
    else if (fsm_state > 0)
        timestamp <= timestamp + 1;
end
//=============================================================================

//=============================================================================
// We always keep track of the state of "fifo_next" in order to perform
// edge detection
//=============================================================================
reg prior_fifo_next;
always @(posedge clk) begin
    if (resetn == 0)
        prior_fifo_next <= 0;
    else
        prior_fifo_next <= fifo_next;
end
//=============================================================================

// This is asserted for one clock-cycle on a high-going edge of "fifo_next"
wire read_fifo = (fifo_next == 1 && prior_fifo_next == 0);

//=============================================================================
// This state machine counts the number of clock-cycles where backpressure
// was sensed, and keeps track of the maximum 
//=============================================================================
reg[31:0] current_bp, max_bp;
reg       current_bp_rxad;

always @(posedge clk) begin

    // This will strobe high for only 1 cycle at a time
    fifo_write <= 0;

    if (resetn == 0) begin 
        fsm_state       <= 0;
        max_bp          <= 0;
        current_bp      <= 0;
        current_bp_rxad <= 0;
    end

    else case(fsm_state)

        // Wait for RX alignment to be acheived
        0:  if (rx_aligned & monitor_tready)
                fsm_state <= 1;

        // If we see backpressure, start counting clock-cycles
        1:  if (monitor_tready == 0) begin
                current_bp      <= 1;
                current_bp_rxad <= !rx_aligned;
                fsm_state       <= 2;
            end

        // Here we're waiting the back-pressure to stop or for the BP_LIMIT to
        // be hit, causing us to artifically stop counting back-pressure cycles
        2:  if (monitor_tready == 0 && current_bp < BP_LIMIT) begin
    
                // Keep track of the number of backpressure cycles
                current_bp <= current_bp + 1;
    
                // Keep track of whether rx-alignment dropped
                if (rx_aligned == 0) current_bp_rxad <= 1;
                         
            end else begin

                if (current_bp > max_bp) begin
                    max_bp      <= current_bp;
                    fifo_write  <= 1;
                end

                fsm_state  <= 1;                
            end
    endcase

end
//=============================================================================


//=============================================================================
// This FIFO holds descriptons of backpressure events
//=============================================================================
xpm_fifo_axis #
(
   .FIFO_DEPTH(FIFO_DEPTH),        // DECIMAL
   .TDATA_WIDTH(13 * 8),           // DECIMAL
   .FIFO_MEMORY_TYPE("auto"),      // String
   .PACKET_FIFO("false"),          // String
   .USE_ADV_FEATURES("0000")       // String
)
packet_data_fifo
(
    // Clock and reset
   .s_aclk   (clk   ),
   .m_aclk   (clk   ),
   .s_aresetn(resetn),

    // The input of this FIFO is the current backpressure entry
   .s_axis_tdata ({current_bp_rxad, current_bp, timestamp}),
   .s_axis_tkeep (          ),
   .s_axis_tlast (          ),
   .s_axis_tvalid(fifo_write),
   .s_axis_tready(          ),

    // The output of this FIFO drives the output ports
   .m_axis_tdata ({fifo_bp_rxad, fifo_bp_length, fifo_bp_ts}),
   .m_axis_tkeep (          ),
   .m_axis_tvalid(fifo_valid),
   .m_axis_tlast (          ),
   .m_axis_tready(read_fifo ),

    // Unused input stream signals
   .s_axis_tdest(),
   .s_axis_tid  (),
   .s_axis_tstrb(),
   .s_axis_tuser(),

    // Unused output stream signals
   .m_axis_tdest(),
   .m_axis_tid  (),
   .m_axis_tstrb(),
   .m_axis_tuser(),

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
//=============================================================================




endmodule