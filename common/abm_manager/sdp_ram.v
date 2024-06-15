//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 20-Mar-24  DWW     1  Initial creation
//====================================================================================

/*

    This is a simple dual-port RAM of configurable width, configurable depth,
    and configurable RAM type.

    RAM_TYPE can be "distributed", "block", or "ultra"

*/

module sdp_ram #
(
    parameter DW=512,
    parameter DD=16384,
    parameter RAM_TYPE = "ultra"
)    
(
    // Clock
    input clk,

    // Write-enable, port A
    input wea,
    
    // Address register, port A and port B
    input [$clog2(DD)-1:0] addra, addrb,    

    // Data-input, port A
    input [DW-1:0] dia,
    
    // Data-output, port B
    output reg [DW-1:0] dob
);


if (RAM_TYPE == "distributed") begin : ram_scope
    (* ram_style = "distributed" *) reg [DW-1:0] RAM [DD-1:0];
end : ram_scope

if (RAM_TYPE == "block") begin : ram_scope
    (* ram_style = "block" *) reg [DW-1:0] RAM [DD-1:0];
end : ram_scope

if (RAM_TYPE == "ultra") begin : ram_scope
    (* ram_style = "ultra" *) reg [DW-1:0] RAM [DD-1:0];
end : ram_scope

always @(posedge clk) begin
    if (wea) ram_scope.RAM[addra] <= dia;
end

always @(posedge clk) begin
    dob <= ram_scope.RAM[addrb];
end


endmodule


