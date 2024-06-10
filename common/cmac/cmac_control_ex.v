//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 29-Feb-23  DWW     1  Initial creation
//
// 16-Apr-24  DWW     2  sys_reset_out
//
// 25-Apr-24  DWW     3  Added "sys_reset_in" (synchronous to rx_clk)
//
// 06-May-24  DWW     4  Added "sys_resetn_out" (synchronous to rx_clk)
//
// 08-May-24  DWW     5  No longer managing the axis_rx bus
//
//                       sys_reset/resetn_out changed to rx_reset/resetn_out
//
//                       Added "rx_datapath_reset" signal
//
// 27-May-24  DWW     6  Now exporting the "sync_rx_aligned" signal
//                       Now driving the tx_precursor setting on the transceivers
//
// 08-Jun-24  DWW     7  Added "sys_reset_out", rsfec_enable, and tx_pre
//===================================================================================================

/*
    Notes:

    This module will handle synchronizing "sys_resetn_in" and "stat_rx_aligned"
    to "rx_clk".  No external synchronization is neccessary.

    This module serves several purposes:

    (1) Drives the RS-FEC ports of the CMAC
    
    (2) Manages PCS alignment of the CMAC
    
    (3) Performs a reset of the CMAC's rx-path when PCS alignment is lost.
        This behavior is recommended by "Clocking and Resets" section of
        Xilinx PG203

    (4) Provides a reset/resetn signal that is synchronous to rx_clk

    (5) Drives the tx_precursor setting for the transceivers
    

*/
  
module cmac_control_ex 
(
    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 rx_clk CLK"           *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rx_reset_out:rx_resetn_out:reset_rx_datapath, FREQ_HZ 322265625" *)
    input rx_clk,

    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 sys_resetn_in RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW "                         *)
    input sys_resetn_in,

    // Determines whether RS-FEC is enabled or disabled
    input  rsfec_enable, 

    // Pre-emphasis setting for GT signal shaping
    input[4:0] tx_pre,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable" *)
    output ctl_rx_rsfec_enable,
    
    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable_correction" *)
    output ctl_rx_rsfec_enable_correction,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable_indication" *)
    output ctl_rx_rsfec_enable_indication,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_tx_rsfec_enable" *)
    output ctl_tx_rsfec_enable,

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_tx ctl_enable" *)
    output ctl_tx_enable, 

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_tx ctl_tx_send_rfi" *)
    output ctl_tx_send_rfi,

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_rx ctl_enable" *)
    output ctl_rx_enable,

    (* X_INTERFACE_INFO = "xilinx.com:*:drp_ports:2.0 gt_trans_debug gt_txprecursor" *)
    output[19:0] gt_txprecursor,

    (* X_INTERFACE_INFO = "xilinx.com:*:statistics_ports:2.0 stat_rx stat_rx_aligned" *)
    input      stat_rx_aligned,

    // This is a resetn signal, synchronous to rx_clk
    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 rx_reset_out RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH"                         *)
    output     rx_reset_out,

    // This is a reset signal, synchronous to rx_clk
    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 rx_resetn_out RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW "                         *)
    output     rx_resetn_out,

    // Tie this to gtwiz_reset_rx_datapath on the CMAC
    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 reset_rx_datapath RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH "                        *)
    output     reset_rx_datapath,

    // stat_rx_aligned, synchronized to rx_clk
    output     sync_rx_aligned,

    // System reset, not synchronized to any clock
    output     sys_reset_out

);

//=============================================================================
// Drive the CMAC module's "sys_reset" pin.  We can't drive it from 
// "rx_reset_out" because that pin is synchronized with our clock, which may
// not be running yet.
//=============================================================================
assign sys_reset_out = ~sys_resetn_in;
//=============================================================================


//=============================================================================
// Select the desired amount of transceiver signal pre-emphasis
//=============================================================================
assign gt_txprecursor = {4{tx_pre}};
//=============================================================================

//=============================================================================
// The tx_enable and "send remote fault indicator" depend on whether or not
// PCS alignment has been acheived
//=============================================================================
assign ctl_rx_enable   = 1;
assign ctl_tx_enable   = stat_rx_aligned;
assign ctl_tx_send_rfi = ~stat_rx_aligned;
//=============================================================================



// "sys_resetn_in" is active-low
localparam RESET_ACTIVE = 0;

// The frequency of rx_clk
localparam FREQ_HZ = 322265625;

// Various timeouts, measured in clock cycles
localparam ALIGNMENT_TIMEOUT = 2 * FREQ_HZ;
localparam RESET_TIMEOUT     = 50;

// Countdown timers
reg[31:0] alignment_timer, reset_timer = 0;

// The CMAC's "gtwiz_reset_rx_datapath" is asserted until the timer expires
assign reset_rx_datapath = (reset_timer != 0);

// "rx_reset_out" is always the inverse of "rx_resetn_out"
assign rx_reset_out = ~rx_resetn_out;

//=============================================================================
// Synchronize "stat_rx_aligned" into "sync_rx_aligned"
//=============================================================================
xpm_cdc_single #
(
    .DEST_SYNC_FF  (4),   
    .INIT_SYNC_FF  (0),   
    .SIM_ASSERT_CHK(0), 
    .SRC_INPUT_REG (0)   
)
cdc0
(
    .src_clk (               ),  
    .src_in  (stat_rx_aligned),
    .dest_clk(rx_clk         ), 
    .dest_out(sync_rx_aligned) 
);
//=============================================================================


//=============================================================================
// Synchronize "rsfec_enable" into "rsfec_enable_sync"
//=============================================================================
wire rsfec_enable_sync;
xpm_cdc_single #
(
    .DEST_SYNC_FF  (4),   
    .INIT_SYNC_FF  (0),   
    .SIM_ASSERT_CHK(0), 
    .SRC_INPUT_REG (0)   
)
i_sync_rsfec_enable
(
    .src_clk (                 ),  
    .src_in  (rsfec_enable     ),
    .dest_clk(rx_clk           ), 
    .dest_out(rsfec_enable_sync) 
);
//=============================================================================




//=============================================================================
// Synchronize "sys_resetn_in" into "rx_resetn_out"
//=============================================================================
xpm_cdc_async_rst #
(
    .DEST_SYNC_FF(4),
    .INIT_SYNC_FF(0),
    .RST_ACTIVE_HIGH(RESET_ACTIVE)
)
i_sync_sys_resetn_in
(
    .src_arst (sys_resetn_in),
    .dest_clk (rx_clk),
    .dest_arst(rx_resetn_out)
);
//=============================================================================


//=============================================================================
// Enable or disable forward error correction
//=============================================================================
assign ctl_rx_rsfec_enable            = rsfec_enable_sync;
assign ctl_rx_rsfec_enable_correction = rsfec_enable_sync;
assign ctl_rx_rsfec_enable_indication = rsfec_enable_sync;
assign ctl_tx_rsfec_enable            = rsfec_enable_sync;
//=============================================================================


//=============================================================================
// This state machine waits for alignment to be acheived.  If a timeout
// occurs before that happens, the CMAC gets reset, then we go back to waiting
// for alignment.
//
// Once we have alignment, if it is subsequently lost (i.e., if someone unplugs
// the QSFP cable), we reset the CMAC's RX path and start the process over.
//=============================================================================
reg[1:0] fsm_state = 0;
always @(posedge rx_clk) begin

    // Count down while waiting for PCS alignment
    if (alignment_timer)
        alignment_timer <= alignment_timer - 1;

    // Count down while waiting for reset_out to complete
    if (reset_timer)
        reset_timer <= reset_timer - 1;

    else case (fsm_state)

        // If we're done resetting the CMAC, go wait for PCS alignment
        0:  if (reset_timer == 0) begin
                alignment_timer <= ALIGNMENT_TIMEOUT;
                fsm_state       <= 1;
            end

        // Wait for alignment to occur.  If we don't get PCS alignment
        // before the timeout, reset the CMAC and try again
        1:  if (sync_rx_aligned) begin
                fsm_state     <= 2;
            end else if (alignment_timer == 0) begin
                reset_timer   <= RESET_TIMEOUT;
                fsm_state     <= 0;
            end

        // If we lose alignment, reset the CMAC
        2:  if (~sync_rx_aligned) begin
                reset_timer   <= RESET_TIMEOUT;
                fsm_state     <= 0;
            end
    endcase
end
//=============================================================================


endmodule
