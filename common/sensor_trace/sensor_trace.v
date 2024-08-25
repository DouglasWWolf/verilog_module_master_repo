//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 23-Aug-24  DWW     1  Initial creation
//=============================================================================


/*

    This module looks for frames in the "lvds_in" data stream and stamps
    a user-defined "tracer" value into specified bytes within the stream.

*/

module sensor_trace # (parameter DW=512)
(
    input clk, resetn,

    // The number of data-cycles in a full data-frame
    input[31:0] cycles_per_frame,

    // The four bytes that define the 1st four cycles of the frame header
    input[31:0] frame_header,

    // The constant that will be stored in all "tracer cells"
    input[7:0]  tracer_value,

    // These bits enable or disable tracing for a given tracer
    input[7:0]  tracer_enable,

    // This is the index of the tracer being read or written
    input[2:0]  tracer_index,

    // This holds the cell index of tracer[tracer_index]
    output[31:0] rd_tracer_cell,

    // This is used to specify the cell index of a tracer
    input[31:0] wr_tracer_cell,
    input       wr_tracer_cell_wstrobe,

    // Input data-stream
    input      [DW-1:0] lvds_in,

    // Output data-stream
    output reg [DW-1:0] lvds_out,

    // Start of frame
    output sof
);


// We support up to 8 tracer cells
localparam TRACER_COUNT = 8;

// These are the cell indices of the cells that will act as "tracers"
reg[31:0] tracer_cell[0:TRACER_COUNT-1];

// Give the outside world read-access to our tracer cell indices
assign rd_tracer_cell = tracer_cell[tracer_index];

//=============================================================================
// Any time "wr_tracer_cell" is written to, store the value into the 
// appropriate tracer-cell
//=============================================================================
always @(posedge clk) begin
    if (wr_tracer_cell_wstrobe)
        tracer_cell[tracer_index] <= wr_tracer_cell;
end
//=============================================================================


//=============================================================================
// For each tracer, compute the frame-cycle it's in, and compute the bit-offset
// where the tracer value should be stored in the LVDS output
//=============================================================================
wire[31:0] tracer_cycle[0:TRACER_COUNT-1];
wire[10:0] tracer_offset[0:TRACER_COUNT-1];

genvar i;
for (i=0; i<TRACER_COUNT; i=i+1) begin
    assign tracer_cycle[i] = tracer_cell[i] / (DW/8);
    assign tracer_offset[i] = (tracer_cell[i] % (DW/8)) * 8;
end
//=============================================================================

// These match the full width of the LVDS bus during the first 4 cycles of a frame
wire[DW-1:0] fh0={(DW/8){frame_header[07:00]}};
wire[DW-1:0] fh1={(DW/8){frame_header[15:08]}};
wire[DW-1:0] fh2={(DW/8){frame_header[23:16]}};
wire[DW-1:0] fh3={(DW/8){frame_header[31:24]}};

// The data-cycle containing the 1st frame-header byte is frame_cycle 0
// The data-cycle containing the 2nd frame-header byte is frame_cycle 1
// (etc)
// 0 = "We haven't found the first data-cycle of the frame header yet"
reg [31:0] frame_cycle;


//=============================================================================
// This block counts frame-cycles.   It detects the start of a frame by looking
// for the four "frame-header" bytes on four consecutive clock-cycles
//=============================================================================
always @(posedge clk) begin
    
    if (resetn == 0) begin
        frame_cycle <= 0;
    end
    
    else case (frame_cycle)
    
        0:  frame_cycle <= (lvds_in == fh0) ? 1 : 0;
        1:  frame_cycle <= (lvds_in == fh1) ? 2 : 0;
        2:  frame_cycle <= (lvds_in == fh2) ? 3 : 0;
        3:  frame_cycle <= (lvds_in == fh3) ? 4 : 0;
        
        default:
            if (frame_cycle == cycles_per_frame - 1)
                frame_cycle <= 0;
            else
                frame_cycle <= frame_cycle + 1;
               

    endcase
end
//=============================================================================


//=============================================================================
// The LVDS output stream is the LVDS input stream, with any cells that are
// identified as "tracer cells" containing the tracer value
//=============================================================================
always @* begin

    lvds_out = lvds_in;

    if (tracer_enable[0] && frame_cycle == tracer_cycle[0])
        lvds_out[tracer_offset[0] +: 8] = tracer_value;

    if (tracer_enable[1] && frame_cycle == tracer_cycle[1])
        lvds_out[tracer_offset[1] +: 8] = tracer_value;

    if (tracer_enable[2] && frame_cycle == tracer_cycle[2])
        lvds_out[tracer_offset[2] +: 8] = tracer_value;

    if (tracer_enable[3] && frame_cycle == tracer_cycle[3])
        lvds_out[tracer_offset[3] +: 8] = tracer_value;

    if (tracer_enable[4] && frame_cycle == tracer_cycle[4])
        lvds_out[tracer_offset[4] +: 8] = tracer_value;

    if (tracer_enable[5] && frame_cycle == tracer_cycle[5])
        lvds_out[tracer_offset[5] +: 8] = tracer_value;

    if (tracer_enable[6] && frame_cycle == tracer_cycle[6])
        lvds_out[tracer_offset[6] +: 8] = tracer_value;

    if (tracer_enable[7] && frame_cycle == tracer_cycle[7])
        lvds_out[tracer_offset[7] +: 8] = tracer_value;

end
//=============================================================================


// Raise the "start of frame" output every time we encounter a new frame
assign sof = (frame_cycle == 4);

endmodule