//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 20-Feb-24  DWW    1   Inital creation
//====================================================================================

/*

    This module breaks out the fields of the Ethernet/IPv4/UDP/RDMX header 
    for easy debugging.

*/


module rdmx_monitor
(
    input            clk, resetn,
    output           capture,
    output [6*8-1:0] eth_dst_mac,
    output [6*8-1:0] eth_src_mac,
    output [2*8-1:0] eth_frame_type,
    output [2*8-1:0] ip4_ver_dsf,
    output [2*8-1:0] ip4_length,
    output [2*8-1:0] ip4_id,
    output [2*8-1:0] ip4_flags,
    output [2*8-1:0] ip4_ttl_prot,
    output [2*8-1:0] ip4_checksum,
    output [4*8-1:0] ip4_src_ip,
    output [4*8-1:0] ip4_dst_ip,
    output [2*8-1:0] udp_src_port,
    output [2*8-1:0] udp_dst_port,
    output [2*8-1:0] udp_length,
    output [2*8-1:0] udp_checksum,
    output [2*8-1:0] rdmx_magic,
    output [8*8-1:0] rdmx_address,

    
    (* X_INTERFACE_MODE = "monitor" *)
    input[511:0]    AXIS_RDMX_TDATA,
    input[ 63:0]    AXIS_RDMX_TKEEP,
    input           AXIS_RDMX_TLAST,
    input           AXIS_RDMX_TVALID,
    input           AXIS_RDMX_TREADY 
);




// Convert TDATA to big-endian
wire[511:0] be_tdata;
byte_swap#(.DW(512)) (.I(AXIS_RDMX_TDATA), .O(be_tdata));


wire[47:0]  w_eth_dst_mac    = be_tdata[511:464];
wire[47:0]  w_eth_src_mac    = be_tdata[463:416];
wire[15:0]  w_eth_frame_type = be_tdata[415:400];
wire[15:0]  w_ip4_ver_dsf    = be_tdata[399:384];
wire[15:0]  w_ip4_length     = be_tdata[383:368];
wire[15:0]  w_ip4_id         = be_tdata[367:352];
wire[15:0]  w_ip4_flags      = be_tdata[351:336];
wire[15:0]  w_ip4_ttl_prot   = be_tdata[335:320];
wire[15:0]  w_ip4_checksum   = be_tdata[319:304];
wire[31:0]  w_ip4_src_ip     = be_tdata[303:272];
wire[31:0]  w_ip4_dst_ip     = be_tdata[271:240];
wire[15:0]  w_udp_src_port   = be_tdata[239:224];
wire[15:0]  w_udp_dst_port   = be_tdata[223:208];
wire[15:0]  w_udp_length     = be_tdata[207:192];
wire[15:0]  w_udp_checksum   = be_tdata[191:176];
wire[15:0]  w_rdmx_magic     = be_tdata[175:160];
wire[63:0]  w_rdmx_address   = be_tdata[159:096];

reg[47:0]  r_eth_dst_mac    ;
reg[47:0]  r_eth_src_mac    ;
reg[15:0]  r_eth_frame_type ;
reg[15:0]  r_ip4_ver_dsf    ;
reg[15:0]  r_ip4_length     ;
reg[15:0]  r_ip4_id         ;
reg[15:0]  r_ip4_flags      ;
reg[15:0]  r_ip4_ttl_prot   ;
reg[15:0]  r_ip4_checksum   ;
reg[31:0]  r_ip4_src_ip     ;
reg[31:0]  r_ip4_dst_ip     ;
reg[15:0]  r_udp_src_port   ;
reg[15:0]  r_udp_dst_port   ;
reg[15:0]  r_udp_length     ;
reg[15:0]  r_udp_checksum   ;
reg[15:0]  r_rdmx_magic     ;
reg[63:0]  r_rdmx_address   ;


assign eth_dst_mac    = (capture ? w_eth_dst_mac    : r_eth_dst_mac   );
assign eth_src_mac    = (capture ? w_eth_src_mac    : r_eth_src_mac   );
assign eth_frame_type = (capture ? w_eth_frame_type : r_eth_frame_type);
assign ip4_ver_dsf    = (capture ? w_ip4_ver_dsf    : r_ip4_ver_dsf   );
assign ip4_length     = (capture ? w_ip4_length     : r_ip4_length    );
assign ip4_id         = (capture ? w_ip4_id         : r_ip4_id        );
assign ip4_flags      = (capture ? w_ip4_flags      : r_ip4_flags     );
assign ip4_ttl_prot   = (capture ? w_ip4_ttl_prot   : r_ip4_ttl_prot  );
assign ip4_checksum   = (capture ? w_ip4_checksum   : r_ip4_checksum  );
assign ip4_src_ip     = (capture ? w_ip4_src_ip     : r_ip4_src_ip    );
assign ip4_dst_ip     = (capture ? w_ip4_dst_ip     : r_ip4_dst_ip    );
assign udp_src_port   = (capture ? w_udp_src_port   : r_udp_src_port  );
assign udp_dst_port   = (capture ? w_udp_dst_port   : r_udp_dst_port  );
assign udp_length     = (capture ? w_udp_length     : r_udp_length    );
assign udp_checksum   = (capture ? w_udp_checksum   : r_udp_checksum  );
assign rdmx_magic     = (capture ? w_rdmx_magic     : r_rdmx_magic    );
assign rdmx_address   = (capture ? w_rdmx_address   : r_rdmx_address  );


// "Capture" is asserted during the AXI-stream handshake of any
// data-cycle that appears to be an RDMX packet
assign capture = AXIS_RDMX_TVALID 
               & AXIS_RDMX_TREADY
               & (w_rdmx_magic     == 16'h0122)
               & (w_eth_frame_type == 16'h0800);

always @(posedge clk) begin
    if (capture) begin
        r_eth_dst_mac    = w_eth_dst_mac;
        r_eth_src_mac    = w_eth_src_mac;
        r_eth_frame_type = w_eth_frame_type;
        r_ip4_ver_dsf    = w_ip4_ver_dsf;
        r_ip4_length     = w_ip4_length;
        r_ip4_id         = w_ip4_id;
        r_ip4_flags      = w_ip4_flags;
        r_ip4_ttl_prot   = w_ip4_ttl_prot;
        r_ip4_checksum   = w_ip4_checksum;
        r_ip4_src_ip     = w_ip4_src_ip;
        r_ip4_dst_ip     = w_ip4_dst_ip;
        r_udp_src_port   = w_udp_src_port;
        r_udp_dst_port   = w_udp_dst_port;
        r_udp_length     = w_udp_length;
        r_udp_checksum   = w_udp_checksum;
        r_rdmx_magic     = w_rdmx_magic;
        r_rdmx_address   = w_rdmx_address;
    end
end

endmodule