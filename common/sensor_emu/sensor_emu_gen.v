//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 16-Dec-23  DWW     1  Initial creation
//====================================================================================

/*

    This generates frame data from N 8-bit wide input vectors.  (N is always 1, 2, 4
    or 8).  

    Frame data is output with cell interleaving.   The cell numbers for one row look 
    like this:   (Bit 511 is on the left, bit 0 is on the right)
    
         Clock cycle 0:    504, 496,   488, [...]   16,    8,    0
         Clock cycle 1:   1016, 1008, 1000, [...]  528,  520,  512
         Clock cycle 2:   1528, 1520, 1512, [...] 1040, 1032, 1024
         Clock cycle 3:   2040, 2032, 2024, [...] 1552, 1544, 1536

         Clock cycle 4 thru 7:
              Same as cycle 0 thru 3, but add 1 to every cell number
        
         Clock cycle 8 thru 11:
              Same as cycle 0 thru 3, but add 2 to every cell number

         Clock cycle 12 thru 15:
              Same as cycle 0 thru 3, but add 3 to every cell number
    
         (etc, through clock cycle 31)

*/

module sensor_emu_gen #
(
    PATTERN_WIDTH      = 32,
    LVDS_WIDTH         = 512,
    SYNC_PULSE_LENGTH  = 4
)
(
    input clk, resetn,

    // These both signal "start outputting a frame"
    input rs0, rs256,

    // The number of clock cycles per data-frame.  Must be even and at least 32
    input[31:0] cycles_per_frame,

    // The bytes that are output during the idle pattern
    input[7:0] idle_0, idle_1,

    // The first four bytes of a frame header
    input[31:0] frame_header,

    // A sync pulse with a period of 256 clock cycles
    output pa_sync,

    // The LVDS lines are the primary output of this module
    output reg[LVDS_WIDTH-1:0] lvds,

    // Denotes start-of-frame and end-of-frame
    output sof, eof,

    //==================  The stream of input bit-patterns  ====================
    input[PATTERN_WIDTH-1:0] PATTERN_TDATA,
    input                    PATTERN_TVALID,
    output                   PATTERN_TREADY
    //==========================================================================

);
genvar i;

// The width of the LVDS bus in bytes
localparam LVDS_BYTES = LVDS_WIDTH / 8;

// How many bytes are in the data pattern?
localparam PATTERN_BYTES = PATTERN_WIDTH / 8;

// This is the number of copies of the pattern in the 8-byte "extended pattern"
localparam EXTENDED_PATTERNS = 8 / PATTERN_BYTES;

// The number of data-cycles in the frame header
localparam HEADER_CYCLES = 16;

// The number of data-cycles in the frame footer
localparam FOOTER_CYCLES = 4;

// This is the cycle number of the last data-cycle before the frame-data
localparam LAST_HEADER_CYCLE = HEADER_CYCLES - 1;

// This is the cycle number of the last data-cycle before the footer
wire[31:0] last_frame_cycle = cycles_per_frame - 1 - FOOTER_CYCLES;

// This is the cycle number of the last data cycle of the footer
wire[31:0] last_footer_cycle = cycles_per_frame - 1;

// This is the data-pattern, replicated until we have an 8-byte pattern
reg[63:0] extended_pattern;

// This is an array of 8 bytes.  Each element is 1 byte of extended_pattern
wire[7:0] vector[0:7];

// Each element of "vector" is a byte from the extended_pattern
for (i=0; i<8; i=i+1) assign vector[i] = extended_pattern[8*(7-i) +: 8];

// This counts data-cycles in a data-frame.  First cycle of the frame is cycle 0
reg[31:0] cycle_number;

//-----------------------------------------------------------
// This will ensure that frame_cell is:
//
//    cycle_number 0 = vector[0]
//    cycle_number 1 = vector[0]
//    cycle_number 2 = vector[0]
//    cycle_number 3 = vector[0]
//
//    cycle_number 4 = vector[1]
//    cycle_number 5 = vector[1]
//    cycle_number 6 = vector[1]
//    cycle_number 7 = vector[1]
//
//                   ...
//   
//    cycle_number 28 = vector[7]
//    cycle_number 29 = vector[7]
//    cycle_number 30 = vector[7]
//    cycle_number 31 = vector[7]
//
//    cycle_number 33 = vector[0]
//    cycle_number 34 = vector[0]
//    cycle_number 35 = vector[0]
//    cycle_number 36 = vector[0]
//  
//               (etc)
//
//       
wire[7:0] frame_cell = vector[cycle_number[4:2]];
//-----------------------------------------------------------

// This is a free-running timer
reg[7:0] free_timer;

// Our sync pulse goes out periodically, but only when sensor_emu_ctl is
// ready to supply cell data
assign pa_sync = (PATTERN_TVALID & free_timer < SYNC_PULSE_LENGTH);

// We only look for "begin outputting a frame" when the free-timer is 0
wire frame_trigger = (rs0 | rs256) & (free_timer == 0);

// The state of our main state machine
reg[5:0] fsm_state;
localparam FSM_RESET       =  1;
localparam FSM_IDLE0       =  2;
localparam FSM_IDLE1       =  4;
localparam FSM_FRAME_HDR   =  8;
localparam FSM_FRAME_DATA  = 16;
localparam FSM_FRAME_FTR   = 32;

// Provide "start of frame" and "end of frame" markers to ease debugging
assign sof = (fsm_state == FSM_FRAME_HDR);
assign eof = (fsm_state == FSM_FRAME_FTR);

// This is going to be 0x3f3e3d3c...03020100
wire[LVDS_WIDTH-1:0] byte_numbers;
for (i=0; i<LVDS_BYTES; i=i+1) assign byte_numbers[i*8 +: 8] = i;

// This wire contains the lvds bus values during the frame-header
wire[LVDS_WIDTH-1:0] header_output = 
    (cycle_number ==  0) ? {LVDS_BYTES{frame_header[0*8 +: 8]}} :
    (cycle_number ==  1) ? {LVDS_BYTES{frame_header[1*8 +: 8]}} :
    (cycle_number ==  2) ? {LVDS_BYTES{frame_header[2*8 +: 8]}} :
    (cycle_number ==  3) ? {LVDS_BYTES{frame_header[3*8 +: 8]}} :
    (cycle_number == 11) ? byte_numbers                         : 0;


//=============================================================================
// The data on the lvds bus depends on what state we're in
//=============================================================================
always @* begin
    case (fsm_state)
        FSM_IDLE0:
            lvds = {LVDS_BYTES{idle_0}};  

        FSM_IDLE1:
            lvds = {LVDS_BYTES{idle_1}};  

        FSM_FRAME_HDR:
            lvds = header_output;

        FSM_FRAME_DATA:
            lvds = {LVDS_BYTES{frame_cell}};

        default:
            lvds = 0;
    endcase
end
//=============================================================================


// We ask for another incoming data pattern on the first cycle of a frame header
assign PATTERN_TREADY = (fsm_state == FSM_FRAME_HDR) & (cycle_number == 0);

//==========================================================================
// This is a free-running timer
//==========================================================================
always @(posedge clk) begin
    if (resetn == 0)
        free_timer <= 0;
    else
        free_timer <= free_timer + 1;
end
//==========================================================================


//==========================================================================
// Our main state machine - generates idle cycles and data frames
//==========================================================================
always @(posedge clk) begin

    // This is the clock-cycle number of the current frame
    cycle_number <= cycle_number + 1;

    if (resetn == 0)
        fsm_state <= FSM_RESET;

    else case (fsm_state)

        // Are we just coming out of reset?    
        FSM_RESET:
            fsm_state <= FSM_IDLE0;

        // Are we outputting the first idle byte?
        FSM_IDLE0:
            fsm_state <= FSM_IDLE1;

        // Are we outputting the second idle byte?
        FSM_IDLE1:
            if (frame_trigger) begin
                extended_pattern <= {EXTENDED_PATTERNS{PATTERN_TDATA}};                     
                cycle_number     <= 0;
                fsm_state        <= FSM_FRAME_HDR;
            end else
                fsm_state        <= FSM_IDLE0;

        // Are we outputting the frame header?
        FSM_FRAME_HDR:
            if (cycle_number == LAST_HEADER_CYCLE) begin
                fsm_state <= FSM_FRAME_DATA;
            end
        
        // Are we outputting a frame's ordinary data?
        FSM_FRAME_DATA:
            if (cycle_number == last_frame_cycle) begin
                fsm_state  <= FSM_FRAME_FTR;
            end

        // Are we outputting the frame footer?
        FSM_FRAME_FTR:
            if (cycle_number == last_footer_cycle) begin
                if (frame_trigger) begin
                    extended_pattern <= {EXTENDED_PATTERNS{PATTERN_TDATA}};                     
                    cycle_number     <= 0;
                    fsm_state        <= FSM_FRAME_HDR;                    
                end else
                    fsm_state        <= FSM_IDLE0;
            end

    endcase
end
//==========================================================================


endmodule