//=============================================================================
//                ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 24-Oct-24  DWW     1  Initial creation
//=============================================================================


/*
    This injects data into specified cells of the data-stream
*/

module sensor_inject # (parameter DW=512)
(
    input clk, resetn,

    // The input stream
    input [DW-1:0] axis_in_tdata,
    input          axis_in_tvalid,
    output         axis_in_tready,

    // The output stream
    output reg[DW-1:0] axis_out_tdata,
    output             axis_out_tvalid,
    input              axis_out_tready, 

    // The cell-data vector
    input [7:0] axis_vector_tdata,
    input       axis_vector_tvalid,
    output reg  axis_vector_tready,

    // The size of a sensor-frame, in bytes
    input[31:0] frame_size,
    
    // These bits enable or disable tracing for a given tracer
    input[7:0]  tracer_enable,

    // This is the index of the tracer being read or written
    input[2:0]  tracer_index,

    // This holds the cell index of tracer[tracer_index]
    output[31:0] rd_tracer_cell,

    // This is used to specify the cell index of a tracer
    input[31:0] wr_tracer_cell,
    input       wr_tracer_cell_wstrobe,

    // Start of frame
    output sof
);

// Compute the number of data-cycles in a frame
wire[31:0] cycles_per_frame = frame_size / (DW/8);

// "TVALID" on the output stream is driven directly from the input
assign axis_out_tvalid = axis_in_tvalid;

// "TREADY" on the input stream is driven directly from the output
assign axis_in_tready  = axis_out_tready;

// We support up to 8 tracer cells
localparam TRACER_COUNT = 8;

// These are the cell indices of the cells that will act as "tracers"
reg[31:0] tracer_cell[0:TRACER_COUNT-1];

// Give the outside world read-access to our tracer cell indices
assign rd_tracer_cell = tracer_cell[tracer_index];

// Which data-cycle of the frame are we in.  0 based
reg [31:0] frame_cycle;

// This will be while waiting for the last data-cycle of a frame
wire last_cycle_in_frame = (frame_cycle == (cycles_per_frame - 1));


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



//=============================================================================
// This block keeps "tracer_value" populated
//
// This block assumes that once axis_vector_tvalid goes high, it will always
// be high, and that if it goes low then we should reset the state machine
//=============================================================================
// Vector-state machine, reads tracer values from a fifo
reg vsm_state;

// The value to be stamped into the data frames
reg[7:0] tracer_value;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    
    // This will strobe high for 1 cycle at a time
    axis_vector_tready <= 0;

    // Are we in reset?  "TVALID low" indicates the ctl module halted FIFO output
    if (resetn == 0 || axis_vector_tvalid == 0) begin
        vsm_state <= 0;
    end

    else case (vsm_state)

        // Fetch the tracer-value we're going to stamp into the first frame 
        0:  begin
                tracer_value       <= axis_vector_tdata;
                axis_vector_tready <= 1;
                vsm_state          <= 1;
            end
        
        // When we see the last cycle of the frame, fetch the next tracer value
        1:  if (axis_in_tready & axis_in_tvalid & last_cycle_in_frame) begin
                tracer_value       <= axis_vector_tdata;
                axis_vector_tready <= 1;
            end

    endcase

end
//=============================================================================


//=============================================================================
// This block counts data-cycles within the frame that is streaming by. 
//=============================================================================
always @(posedge clk) begin
    
    if (resetn == 0) begin
        frame_cycle <= 0;
    end
    
    else if (axis_in_tvalid & axis_in_tready) begin
   
         if (last_cycle_in_frame)
             frame_cycle <= 0;
         else
             frame_cycle <= frame_cycle + 1;
    end

end
//=============================================================================


//=============================================================================
// The LVDS output stream is the LVDS input stream, with any cells that are
// identified as "tracer cells" containing the tracer value
//=============================================================================
always @* begin

    axis_out_tdata = axis_in_tdata;

    if (tracer_enable[0] && frame_cycle == tracer_cycle[0])
        axis_out_tdata[tracer_offset[0] +: 8] = tracer_value;

    if (tracer_enable[1] && frame_cycle == tracer_cycle[1])
        axis_out_tdata[tracer_offset[1] +: 8] = tracer_value;

    if (tracer_enable[2] && frame_cycle == tracer_cycle[2])
        axis_out_tdata[tracer_offset[2] +: 8] = tracer_value;

    if (tracer_enable[3] && frame_cycle == tracer_cycle[3])
        axis_out_tdata[tracer_offset[3] +: 8] = tracer_value;

    if (tracer_enable[4] && frame_cycle == tracer_cycle[4])
        axis_out_tdata[tracer_offset[4] +: 8] = tracer_value;

    if (tracer_enable[5] && frame_cycle == tracer_cycle[5])
        axis_out_tdata[tracer_offset[5] +: 8] = tracer_value;

    if (tracer_enable[6] && frame_cycle == tracer_cycle[6])
        axis_out_tdata[tracer_offset[6] +: 8] = tracer_value;

    if (tracer_enable[7] && frame_cycle == tracer_cycle[7])
        axis_out_tdata[tracer_offset[7] +: 8] = tracer_value;

end
//=============================================================================


// Raise the "start of frame" output every time we encounter a new frame
assign sof = (frame_cycle == 0) & axis_in_tvalid & axis_in_tready;

endmodule