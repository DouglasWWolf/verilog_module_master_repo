//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 20-Mar-24  DWW     1  Initial creation
//====================================================================================

/*
    This module strobes the "abm_ready" signal high for one cycle any time it
    detects that both ABM blocks have received an update.
*/

module abm_notifier
(
    input      clk, resetn,
    input      abm0_updated, abm1_updated,
    output reg abm_ready
);

// These bits latch the state of input ports abm0_updated and abm1_updated
reg[1:0] abm_updated;

//-----------------------------------------------------------------------------
// This block will strobe "abm_updated" high for one cycle every time it 
// senses an update on both ABM blocks.  The updates to the ABM blocks do
// not need to occur simultaneously.
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    
    // This will strobe high for a single cycle at a time
    abm_ready <= 0;

    if (resetn == 0)
        abm_updated <= 0;
    else begin

        // Keep track of whether we have seen an update for ABM block 0
        if (abm0_updated)
            abm_updated[0] <= 1;
        
        // Keep track of whether we have seen an update for ABM block 1        
        if (abm1_updated)
            abm_updated[1] <= 1;

        // Once both blocks have been updated, strobe "abm_ready" high
        // to tell the outside world that a new ABM is available.
        if (abm_updated == 2'b11) begin
            abm_updated <= 0;
            abm_ready   <= 1;
        end

    end
end
//-----------------------------------------------------------------------------

endmodule