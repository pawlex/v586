//------------------------------------------------------------------------
// v586 -- top-level module: AXI4-wrapped 586-compatible soft core
//
// Instantiates ubiu (v586_biu32_axi.v, the AXI4 bus interface unit) and
// ucore (v586_core.v, the CPU core). This is the module the board-level
// wrappers (see board_specific_files/*/TOP_SYS.v) instantiate directly.
//
// NOTE: gate-level netlist below the port list -- see the header of
// v586_biu32_axi.v for what that means.
//------------------------------------------------------------------------

module v586(m00_AXI_RSTN, m00_AXI_CLK, m00_AXI_AWADDR, m00_AXI_AWVALID, m00_AXI_AWREADY
		, m00_AXI_AWBURST, m00_AXI_AWLEN, m00_AXI_AWSIZE, m00_AXI_ARADDR
		, m00_AXI_ARVALID, m00_AXI_ARREADY, m00_AXI_ARBURST, m00_AXI_ARLEN
		, m00_AXI_ARSIZE, m00_AXI_WDATA, m00_AXI_WVALID, m00_AXI_WREADY,
		 m00_AXI_WSTRB, m00_AXI_WLAST, m00_AXI_RDATA, m00_AXI_RVALID, m00_AXI_RREADY
		, m00_AXI_RLAST, m00_AXI_BVALID, m00_AXI_BREADY, m01_AXI_AWADDR,
		 m01_AXI_AWVALID, m01_AXI_AWREADY, m01_AXI_AWBURST, m01_AXI_AWLEN
		, m01_AXI_AWSIZE, m01_AXI_ARADDR, m01_AXI_ARVALID, m01_AXI_ARREADY
		, m01_AXI_ARBURST, m01_AXI_ARLEN, m01_AXI_ARSIZE, m01_AXI_WDATA,
		 m01_AXI_WVALID, m01_AXI_WREADY, m01_AXI_WSTRB, m01_AXI_WLAST, m01_AXI_RDATA
		, m01_AXI_RVALID, m01_AXI_RREADY, m01_AXI_RLAST, m01_AXI_BVALID,
		 m01_AXI_BREADY, int_pic, iack, ivect, debug
		, dbg_useq_ptr, dbg_pc_out);

	input m00_AXI_RSTN;
	input m00_AXI_CLK;
	output [31:0] m00_AXI_AWADDR;
	output m00_AXI_AWVALID;
	input m00_AXI_AWREADY;
	output [1:0] m00_AXI_AWBURST;
	output [7:0] m00_AXI_AWLEN;
	output [2:0] m00_AXI_AWSIZE;
	output [31:0] m00_AXI_ARADDR;
	output m00_AXI_ARVALID;
	input m00_AXI_ARREADY;
	output [1:0] m00_AXI_ARBURST;
	output [7:0] m00_AXI_ARLEN;
	output [2:0] m00_AXI_ARSIZE;
	output [31:0] m00_AXI_WDATA;
	output m00_AXI_WVALID;
	input m00_AXI_WREADY;
	output [3:0] m00_AXI_WSTRB;
	output m00_AXI_WLAST;
	input [31:0] m00_AXI_RDATA;
	input m00_AXI_RVALID;
	output m00_AXI_RREADY;
	input m00_AXI_RLAST;
	input m00_AXI_BVALID;
	output m00_AXI_BREADY;
	output [31:0] m01_AXI_AWADDR;
	output m01_AXI_AWVALID;
	input m01_AXI_AWREADY;
	output [1:0] m01_AXI_AWBURST;
	output [7:0] m01_AXI_AWLEN;
	output [2:0] m01_AXI_AWSIZE;
	output [31:0] m01_AXI_ARADDR;
	output m01_AXI_ARVALID;
	input m01_AXI_ARREADY;
	output [1:0] m01_AXI_ARBURST;
	output [7:0] m01_AXI_ARLEN;
	output [2:0] m01_AXI_ARSIZE;
	output [31:0] m01_AXI_WDATA;
	output m01_AXI_WVALID;
	input m01_AXI_WREADY;
	output [3:0] m01_AXI_WSTRB;
	output m01_AXI_WLAST;
	input [31:0] m01_AXI_RDATA;
	input m01_AXI_RVALID;
	output m01_AXI_RREADY;
	input m01_AXI_RLAST;
	input m01_AXI_BVALID;
	output m01_AXI_BREADY;
	input int_pic;
	output iack;
	input [7:0] ivect;
	output [4:0] debug;
	output [3:0] dbg_useq_ptr;
	output [31:0] dbg_pc_out;

	wire [3:0] write_msk;
	wire [31:0] writeio_data;
	wire [31:0] readio_data;
	wire [31:0] read_data;
	wire [31:0] write_data;
	wire [127:0] code_data;

	assign m00_AXI_BREADY = 1'b1;
	assign m01_AXI_AWBURST[1] = 1'b0;
	assign m01_AXI_AWBURST[0] = 1'b1;
	assign m01_AXI_AWLEN[7] = 1'b0;
	assign m01_AXI_AWLEN[6] = 1'b0;
	assign m01_AXI_AWLEN[5] = 1'b0;
	assign m01_AXI_AWLEN[4] = 1'b0;
	assign m01_AXI_AWLEN[3] = 1'b0;
	assign m01_AXI_AWLEN[2] = 1'b0;
	assign m01_AXI_AWLEN[1] = 1'b0;
	assign m01_AXI_AWLEN[0] = 1'b0;
	assign m01_AXI_AWSIZE[2] = 1'b0;
	assign m01_AXI_AWSIZE[1] = 1'b1;
	assign m01_AXI_AWSIZE[0] = 1'b0;
	assign m01_AXI_ARBURST[1] = 1'b0;
	assign m01_AXI_ARBURST[0] = 1'b1;
	assign m01_AXI_ARLEN[7] = 1'b0;
	assign m01_AXI_ARLEN[6] = 1'b0;
	assign m01_AXI_ARLEN[5] = 1'b0;
	assign m01_AXI_ARLEN[4] = 1'b0;
	assign m01_AXI_ARLEN[3] = 1'b0;
	assign m01_AXI_ARLEN[2] = 1'b0;
	assign m01_AXI_ARLEN[1] = 1'b0;
	assign m01_AXI_ARLEN[0] = 1'b0;
	assign m01_AXI_ARSIZE[2] = 1'b0;
	assign m01_AXI_ARSIZE[1] = 1'b1;
	assign m01_AXI_ARSIZE[0] = 1'b0;
	assign m01_AXI_WSTRB[3] = 1'b0;
	assign m01_AXI_WSTRB[2] = 1'b0;
	assign m01_AXI_WSTRB[1] = 1'b0;
	assign m01_AXI_WSTRB[0] = 1'b1;


	notech_inv i_15112(.A(n_63278), .Z(n_63280));
	notech_inv i_15111(.A(n_63278), .Z(n_63279));
	notech_inv i_15110(.A(m00_AXI_CLK), .Z(n_63278));
	biu32_axi ubiu(.rstn(m00_AXI_RSTN), .clk(n_63279), .write_req(write_req)
		, .write_ack(write_ack), .write_data(write_data), .write_msk(write_msk
		), .read_req(read_req), .read_ack(read_ack), .read_data(read_data
		), .Daddr({\Daddr[31] , \Daddr[30] , \Daddr[29] , \Daddr[28] , \Daddr[27] 
		, \Daddr[26] , \Daddr[25] , \Daddr[24] , \Daddr[23] , \Daddr[22] 
		, \Daddr[21] , \Daddr[20] , \Daddr[19] , \Daddr[18] , \Daddr[17] 
		, \Daddr[16] , \Daddr[15] , \Daddr[14] , \Daddr[13] , \Daddr[12] 
		, \Daddr[11] , \Daddr[10] , \Daddr[9] , \Daddr[8] , \Daddr[7] , \Daddr[6] 
		, \Daddr[5] , \Daddr[4] , \Daddr[3] , \Daddr[2] , 
		UNCONNECTED_000, UNCONNECTED_001}), .code_req(code_req), .code_ack
		(code_ack), .code_data(code_data), .code_addr({\code_addr[31] , \code_addr[30] 
		, \code_addr[29] , \code_addr[28] , \code_addr[27] , \code_addr[26] 
		, \code_addr[25] , \code_addr[24] , \code_addr[23] , \code_addr[22] 
		, \code_addr[21] , \code_addr[20] , \code_addr[19] , \code_addr[18] 
		, \code_addr[17] , \code_addr[16] , \code_addr[15] , \code_addr[14] 
		, \code_addr[13] , \code_addr[12] , \code_addr[11] , \code_addr[10] 
		, \code_addr[9] , \code_addr[8] , \code_addr[7] , \code_addr[6] 
		, \code_addr[5] , \code_addr[4] , \code_addr[3] , \code_addr[2] 
		, UNCONNECTED_002, UNCONNECTED_003}), .code_wreq(code_wreq), .code_wack
		(code_wack), .code_wdata({UNCONNECTED_004, UNCONNECTED_005, 
		UNCONNECTED_006, UNCONNECTED_007, UNCONNECTED_008, 
		UNCONNECTED_009, UNCONNECTED_010, UNCONNECTED_011, 
		UNCONNECTED_012, UNCONNECTED_013, UNCONNECTED_014, 
		UNCONNECTED_015, UNCONNECTED_016, UNCONNECTED_017, 
		UNCONNECTED_018, UNCONNECTED_019, UNCONNECTED_020, 
		UNCONNECTED_021, UNCONNECTED_022, UNCONNECTED_023, 
		UNCONNECTED_024, UNCONNECTED_025, UNCONNECTED_026, 
		UNCONNECTED_027, \code_wdata[7] , \code_wdata[6] , \code_wdata[5] 
		, \code_wdata[4] , \code_wdata[3] , \code_wdata[2] , \code_wdata[1] 
		, \code_wdata[0] }), .readio_req(readio_req), .writeio_req(writeio_req
		), .readio_ack(readio_ack), .writeio_ack(writeio_ack), .writeio_data
		(writeio_data), .readio_data(readio_data), .io_add({
		UNCONNECTED_028, UNCONNECTED_029, UNCONNECTED_030, 
		UNCONNECTED_031, UNCONNECTED_032, UNCONNECTED_033, 
		UNCONNECTED_034, UNCONNECTED_035, UNCONNECTED_036, 
		UNCONNECTED_037, UNCONNECTED_038, UNCONNECTED_039, 
		UNCONNECTED_040, UNCONNECTED_041, UNCONNECTED_042, 
		UNCONNECTED_043, \io_add[15] , \io_add[14] , \io_add[13] , \io_add[12] 
		, \io_add[11] , \io_add[10] , \io_add[9] , \io_add[8] , \io_add[7] 
		, \io_add[6] , \io_add[5] , \io_add[4] , \io_add[3] , \io_add[2] 
		, \io_add[1] , \io_add[0] }), .axi_AW(m00_AXI_AWADDR), .axi_AWVALID
		(m00_AXI_AWVALID), .axi_AWREADY(m00_AXI_AWREADY), .axi_AWBURST(m00_AXI_AWBURST
		), .axi_AWLEN(m00_AXI_AWLEN), .axi_AWSIZE(m00_AXI_AWSIZE), .axi_W
		(m00_AXI_WDATA), .axi_WVALID(m00_AXI_WVALID), .axi_WREADY(m00_AXI_WREADY
		), .axi_WSTRB(m00_AXI_WSTRB), .axi_WLAST(m00_AXI_WLAST), .axi_AR
		(m00_AXI_ARADDR), .axi_ARVALID(m00_AXI_ARVALID), .axi_ARREADY(m00_AXI_ARREADY
		), .axi_ARBURST(m00_AXI_ARBURST), .axi_ARLEN(m00_AXI_ARLEN), .axi_ARSIZE
		(m00_AXI_ARSIZE), .axi_R(m00_AXI_RDATA), .axi_RVALID(m00_AXI_RVALID
		), .axi_RREADY(m00_AXI_RREADY), .axi_RLAST(m00_AXI_RLAST), .axi_io_AW
		(m01_AXI_AWADDR), .axi_io_AWVALID(m01_AXI_AWVALID), .axi_io_AWREADY
		(m01_AXI_AWREADY), .axi_io_W(m01_AXI_WDATA), .axi_io_WVALID(m01_AXI_WVALID
		), .axi_io_WREADY(m01_AXI_WREADY), .axi_io_WLAST(m01_AXI_WLAST),
		 .axi_io_AR(m01_AXI_ARADDR), .axi_io_ARVALID(m01_AXI_ARVALID), .axi_io_ARREADY
		(m01_AXI_ARREADY), .axi_io_R(m01_AXI_RDATA), .axi_io_RVALID(m01_AXI_RVALID
		), .axi_io_RREADY(m01_AXI_RREADY), .busy(busy_ram));
	core ucore(.clk(n_63280), .rstn(m00_AXI_RSTN), .ivect(ivect), .int_main(int_pic
		), .iack(iack), .code_addr({\code_addr[31] , \code_addr[30] , \code_addr[29] 
		, \code_addr[28] , \code_addr[27] , \code_addr[26] , \code_addr[25] 
		, \code_addr[24] , \code_addr[23] , \code_addr[22] , \code_addr[21] 
		, \code_addr[20] , \code_addr[19] , \code_addr[18] , \code_addr[17] 
		, \code_addr[16] , \code_addr[15] , \code_addr[14] , \code_addr[13] 
		, \code_addr[12] , \code_addr[11] , \code_addr[10] , \code_addr[9] 
		, \code_addr[8] , \code_addr[7] , \code_addr[6] , \code_addr[5] 
		, \code_addr[4] , \code_addr[3] , \code_addr[2] , 
		UNCONNECTED_044, UNCONNECTED_045}), .code_data(code_data), .code_req
		(code_req), .code_ack(code_ack), .code_wreq(code_wreq), .code_wack
		(code_wack), .code_wdata({UNCONNECTED_046, UNCONNECTED_047, 
		UNCONNECTED_048, UNCONNECTED_049, UNCONNECTED_050, 
		UNCONNECTED_051, UNCONNECTED_052, UNCONNECTED_053, 
		UNCONNECTED_054, UNCONNECTED_055, UNCONNECTED_056, 
		UNCONNECTED_057, UNCONNECTED_058, UNCONNECTED_059, 
		UNCONNECTED_060, UNCONNECTED_061, UNCONNECTED_062, 
		UNCONNECTED_063, UNCONNECTED_064, UNCONNECTED_065, 
		UNCONNECTED_066, UNCONNECTED_067, UNCONNECTED_068, 
		UNCONNECTED_069, \code_wdata[7] , \code_wdata[6] , \code_wdata[5] 
		, \code_wdata[4] , \code_wdata[3] , \code_wdata[2] , \code_wdata[1] 
		, \code_wdata[0] }), .readio_data(readio_data), .io_add({
		UNCONNECTED_070, UNCONNECTED_071, UNCONNECTED_072, 
		UNCONNECTED_073, UNCONNECTED_074, UNCONNECTED_075, 
		UNCONNECTED_076, UNCONNECTED_077, UNCONNECTED_078, 
		UNCONNECTED_079, UNCONNECTED_080, UNCONNECTED_081, 
		UNCONNECTED_082, UNCONNECTED_083, UNCONNECTED_084, 
		UNCONNECTED_085, \io_add[15] , \io_add[14] , \io_add[13] , \io_add[12] 
		, \io_add[11] , \io_add[10] , \io_add[9] , \io_add[8] , \io_add[7] 
		, \io_add[6] , \io_add[5] , \io_add[4] , \io_add[3] , \io_add[2] 
		, \io_add[1] , \io_add[0] }), .writeio_data(writeio_data), .writeio_req
		(writeio_req), .readio_req(readio_req), .writeio_ack(writeio_ack
		), .readio_ack(readio_ack), .write_req(write_req), .write_ack(write_ack
		), .write_data(write_data), .write_msk(write_msk), .read_req(read_req
		), .read_ack(read_ack), .read_data(read_data), .Daddr({\Daddr[31] 
		, \Daddr[30] , \Daddr[29] , \Daddr[28] , \Daddr[27] , \Daddr[26] 
		, \Daddr[25] , \Daddr[24] , \Daddr[23] , \Daddr[22] , \Daddr[21] 
		, \Daddr[20] , \Daddr[19] , \Daddr[18] , \Daddr[17] , \Daddr[16] 
		, \Daddr[15] , \Daddr[14] , \Daddr[13] , \Daddr[12] , \Daddr[11] 
		, \Daddr[10] , \Daddr[9] , \Daddr[8] , \Daddr[7] , \Daddr[6] , \Daddr[5] 
		, \Daddr[4] , \Daddr[3] , \Daddr[2] , UNCONNECTED_086, 
		UNCONNECTED_087}), .busy_ram(busy_ram)
		, .dbg_useq_ptr(dbg_useq_ptr), .dbg_pc_out(dbg_pc_out));
endmodule
