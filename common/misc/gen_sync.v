//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 23-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    This is a simple signal synchronizer
*/


module gen_sync #
(
    parameter   W       = 1,
    parameter   STAGES  = 2
)
(
    input               clk,
    input   [W-1:0]     in,
    output  [W-1:0]     out
);


xpm_cdc_array_single #
(
    .DEST_SYNC_FF   (STAGES),
    .INIT_SYNC_FF   (0),   
    .SIM_ASSERT_CHK (0), 
    .SRC_INPUT_REG  (0),  
    .WIDTH          (W)           
)
i_cdc
(
  .src_clk  (1'b0),
  .src_in   (in), 
  .dest_clk (clk),
  .dest_out (out)
);


endmodule