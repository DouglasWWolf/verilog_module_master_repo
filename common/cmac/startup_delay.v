//=============================================================================
//                  ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 11-May-24  DWW     1  Initial creation
//=============================================================================

/*

    This module asserts "reset_out" for 1 second, the de-asserts it permanently.

    This is useful (for example) for holding a CMAC in reset immediately after
    power-up in order to give the clocks a chance to stableize

*/

module startup_delay # (parameter FREQ_HZ = 100000000)
(
    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET reset_out"          *)
    input   clk,
  
    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 reset_out RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH"                      *)
    output  reset_out
);


reg[31:0] timer = FREQ_HZ;
always @(posedge clk)
    if (timer) timer <= timer - 1;

// Reset is asserted until the countdown timer hits zero
assign reset_out = (timer != 0);

endmodule
