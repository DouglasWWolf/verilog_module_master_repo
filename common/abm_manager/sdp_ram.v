//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changess
//====================================================================================
// 20-Mar-24  DWW     1  Initial creation
// 17-Jul-24  DWW     2  Re-arranged code to avoid reuse of a single scope name
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

if (RAM_TYPE == "distributed") begin : distributed 
    (* ram_style = "distributed" *) reg [DW-1:0] RAM [DD-1:0];
end : distributed

if (RAM_TYPE == "block") begin : block
    (* ram_style = "block" *) reg [DW-1:0] RAM [DD-1:0];
end : block

if (RAM_TYPE == "ultra") begin : ultra
    (* ram_style = "ultra" *) reg [DW-1:0] RAM [DD-1:0];
end : ultra


if (RAM_TYPE == "distributed") begin
    always @(posedge clk) begin
        if (wea) distributed.RAM[addra] <= dia;
    end

    always @(posedge clk) begin
        dob <= distributed.RAM[addrb];
    end
end


if (RAM_TYPE == "block") begin
    always @(posedge clk) begin
        if (wea) block.RAM[addra] <= dia;
    end

    always @(posedge clk) begin
        dob <= block.RAM[addrb];
    end
end


if (RAM_TYPE == "ultra") begin
    always @(posedge clk) begin
        if (wea) ultra.RAM[addra] <= dia;
    end

    always @(posedge clk) begin
        dob <= ultra.RAM[addrb];
    end
end




endmodule


