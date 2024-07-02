//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 01-Jul-24  DWW  1000  Initial creation
//====================================================================================

/*

           This module serves as a dummy "AXI Stream data consumer"

*/

module data_consumer # (parameter DW=512, parameter READY_CYCLES = 0, NREADY_CYCLES = 0)
(
    input           clk, resetn,

    input[DW-1:0]   AXIS_RX_TDATA,
    input[DW/8-1:0] AXIS_RX_TKEEP,
    input           AXIS_RX_TLAST,
    input           AXIS_RX_TVALID,
    output          AXIS_RX_TREADY 
);

// Counts either data-cycles or clock-cycles
reg[15:0] counter;

// The state of our simple state machine
reg       fsm_state;

// We're ready to receive data whenever we're in state 0
assign AXIS_RX_TREADY = (resetn == 1) & (fsm_state == 0);

always @(posedge clk) begin
    
    if (resetn == 0) begin
        counter   <= 1;
        fsm_state <= 0;
    end

    else case(fsm_state)

        // In this state, we're accepting data
        0:  if (AXIS_RX_TREADY & AXIS_RX_TVALID) begin
                if (NREADY_CYCLES && counter == READY_CYCLES) begin
                    counter   <= 1;
                    fsm_state <= 1;
                end else
                    counter   <= counter + 1;
            end

        // In this state, we're burning clock cycles with
        // AXIS_RX_TREADY de-asserted
        1:  if (counter == NREADY_CYCLES) begin
                counter   <= 1;
                fsm_state <= 0;
            end else 
                counter   <= counter + 1;

    endcase
end

endmodule
