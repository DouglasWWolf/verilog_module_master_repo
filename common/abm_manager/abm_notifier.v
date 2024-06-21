//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 20-Mar-24  DWW     1  Initial creation
//
// 21-Jun-24  DWW     2  Added output ports abm0_counter and abm1_counter 
//====================================================================================

/*
    This module strobes the "abm_ready" signal high for one cycle any time it
    detects that both ABM blocks have received an update.
*/

module abm_notifier
(
    input            clk, resetn,
    input            abm0_updated, abm1_updated,
    output reg[31:0] abm0_counter, abm1_counter,
    output           abm_ready
);

// This will increment when abm0_counter == abm1_counter
reg[31:0] abmx_counter;

// This strobes high for one cycle at a time any time both abm counters have
// been incremented to the same value
assign abm_ready = (resetn == 1)
                 & (abm0_counter == abm1_counter)
                 & (abm0_counter != abmx_counter);

//-----------------------------------------------------------------------------
// This block will strobe "abm_updated" high for one cycle every time it 
// senses an update on both ABM blocks.  The updates to the ABM blocks do
// not need to occur simultaneously.
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    
    if (resetn == 0) begin
        abmx_counter <= 0;
        abm0_counter <= 0;
        abm1_counter <= 0;
    end
    
    else begin

        // Keep track of how many times we see the signal that says a new ABM
        // has arrived
        if (abm0_updated) abm0_counter <= abm0_counter + 1;
        if (abm1_updated) abm1_counter <= abm1_counter + 1;
        

        // Any time the "ready" signal strobes high, keep track of 
        // the counter value that triggered it
        if (abm_ready) abmx_counter <= abm0_counter;

    end
end
//-----------------------------------------------------------------------------

endmodule