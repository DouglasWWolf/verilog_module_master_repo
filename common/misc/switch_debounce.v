//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 23-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    This is a simple debouncer for a switch.

    When GSR releases at startup, register "startup_sr" is all zeros.   We use
    this shift register to wait a few clock-cycles before sampling the sync'd
    version of "async_in" so we can set our initial "sw_out" value.   This delay
    is to give "async_in" time to propagate through the synchronizer.
*/

module switch_debounce #
(
    parameter FREQ_HZ    = 100000000,
    parameter PERIOD_MS  = 5,
    parameter INIT_STATE = 1
)
(
    input   clk,

    // Raw switch input
    input      async_in,

    // Debounced switch output
    output reg sw_out = INIT_STATE
);

// The number of synchronizer stages
localparam SYNC_STAGES = 2;

// The number of clock cycles we'll debounce for
localparam DEBOUNCE_TIME = (FREQ_HZ / 1000) * PERIOD_MS;

// This is "async_in", synchronized to "clk"
wire sw_in;

// This is the new state we will potentially change "sw_out" to
reg new_state;

// We don't have a reset port, so keep track of clock-cycles at startup
reg [SYNC_STAGES+1:0] startup_sr = 0;

// This is a count-down timer for our debounce period
reg[$clog2(DEBOUNCE_TIME):0] debounce_timer = 0;

// The state of our state machine
reg fsm_state = 0;


//=============================================================================
// We are in state 0 immediately after power on, and are waiting for "async_in"
// to percolate through its synchronizer.
//
// In state 1, 
//=============================================================================
always @(posedge clk) begin

    case (fsm_state)

        // When the startup time expires, our debounced output
        // will be whatever the current switch input value is
        0:  if (!startup_sr[SYNC_STAGES+1])
                startup_sr <= {startup_sr[SYNC_STAGES:0], 1'b1};
            else begin
                sw_out    <= sw_in;
                new_state <= sw_in;
                fsm_state <= 1;
            end

        // If there is a change on the switch input, restart
        // the debounce timer.   When the debounce timer expires,
        // set sw_out to its new state
        1:  if (sw_in != new_state) begin
                new_state      <= sw_in;
                debounce_timer <= DEBOUNCE_TIME;
            end else if (debounce_timer)
                debounce_timer <= debounce_timer - 1;
            else begin
                sw_out <= new_state;
            end


    endcase
end
//=============================================================================


//=============================================================================
// Synchronize "async_in" into "sw_in"
//=============================================================================
xpm_cdc_single #
(
    .DEST_SYNC_FF  (SYNC_STAGES),
    .INIT_SYNC_FF  (0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG (0)
)
i_cdc
(
    .src_clk (1'b0    ),
    .src_in  (async_in),
    .dest_clk(clk     ),
    .dest_out(sw_in   )
);
//=============================================================================



endmodule