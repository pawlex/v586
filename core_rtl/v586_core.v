//------------------------------------------------------------------------
// core -- integrates the TLBs, microsequencer and cpu into one core
//
// Instantiates i_Dtlb (v586_dtlb.v), i_Itlb (v586_itlb.v), i_useq
// (v586_useq.v), i_cpu (v586_cpu.v), plus the readable behavioral
// sub-blocks c1 (datacache.v) and i_realign (realign.v, unaligned-access
// data realignment). Instantiated as `ucore` in v586 (see v586_top.v).
//
// NOTE: gate-level netlist below the port list (aside from c1/i_realign)
// -- see the header of v586_biu32_axi.v for what that means.
//------------------------------------------------------------------------

module core(clk, rstn, ivect, int_main, iack, code_addr, code_data, code_req, code_ack
		, code_wreq, code_wack, code_wdata, readio_data, io_add, writeio_data
		, writeio_req, readio_req, writeio_ack, readio_ack, write_req, write_ack
		, write_data, write_sz, read_sz, write_msk, read_req, read_ack, read_data
		, Daddr, busy_ram, ipg_fault, outstanding);

	input clk;
	input rstn;
	input [7:0] ivect;
	input int_main;
	output iack;
	output [31:0] code_addr;
	input [127:0] code_data;
	output code_req;
	input code_ack;
	output code_wreq;
	input code_wack;
	output [31:0] code_wdata;
	input [31:0] readio_data;
	output [31:0] io_add;
	output [31:0] writeio_data;
	output writeio_req;
	output readio_req;
	input writeio_ack;
	input readio_ack;
	output write_req;
	input write_ack;
	output [31:0] write_data;
	output [1:0] write_sz;
	output [1:0] read_sz;
	output [3:0] write_msk;
	output read_req;
	input read_ack;
	input [31:0] read_data;
	output [31:0] Daddr;
	input busy_ram;
	output ipg_fault;
	output outstanding;

	wire [31:0] pc_out;
	wire [3:0] useq_ptr;
	wire [5:0] valid_len;
	wire [31:0] icr2;
	wire [31:0] cr2;
	wire [127:0] queue;
	wire [1:0] int_write_sz;
	wire [31:0] int_Daddr;
	wire [31:0] iwrite_data;
	wire [31:0] int_code_addr;
	wire [31:0] write_data_realign;
	wire [1:0] nbus_14544;
	wire [31:0] Daddr_realign;
	wire [31:0] read_data_realign;



	Dtlb i_Dtlb(.clk(clk), .rstn(rstn), .addr_phys(Daddr_realign), .cr3({\cr3[31] 
		, \cr3[30] , \cr3[29] , \cr3[28] , \cr3[27] , \cr3[26] , \cr3[25] 
		, \cr3[24] , \cr3[23] , \cr3[22] , \cr3[21] , \cr3[20] , \cr3[19] 
		, \cr3[18] , \cr3[17] , \cr3[16] , \cr3[15] , \cr3[14] , \cr3[13] 
		, \cr3[12] , UNCONNECTED_000, UNCONNECTED_001, UNCONNECTED_002, 
		UNCONNECTED_003, UNCONNECTED_004, UNCONNECTED_005, 
		UNCONNECTED_006, UNCONNECTED_007, UNCONNECTED_008, 
		UNCONNECTED_009, UNCONNECTED_010, UNCONNECTED_011}), .cr0({
		UNCONNECTED_012, UNCONNECTED_013, UNCONNECTED_014, 
		UNCONNECTED_015, UNCONNECTED_016, UNCONNECTED_017, 
		UNCONNECTED_018, UNCONNECTED_019, UNCONNECTED_020, 
		UNCONNECTED_021, UNCONNECTED_022, UNCONNECTED_023, 
		UNCONNECTED_024, UNCONNECTED_025, UNCONNECTED_026, \cr0[16] , 
		UNCONNECTED_027, UNCONNECTED_028, UNCONNECTED_029, 
		UNCONNECTED_030, UNCONNECTED_031, UNCONNECTED_032, 
		UNCONNECTED_033, UNCONNECTED_034, UNCONNECTED_035, 
		UNCONNECTED_036, UNCONNECTED_037, UNCONNECTED_038, 
		UNCONNECTED_039, UNCONNECTED_040, UNCONNECTED_041, 
		UNCONNECTED_042}), .data_miss(read_data_realign), .iDaddr(int_Daddr
		), .pg_en(pg_en), .iwrite_data(iwrite_data), .owrite_data(write_data_realign
		), .iread_req(int_read_req), .iread_ack(read_ack_realign), .iwrite_req
		(int_write_req), .iwrite_ack(write_ack_realign), .iwrite_sz(int_write_sz
		), .owrite_sz(nbus_14544), .oread_req(read_req_realign), .oread_ack
		(int_read_ack), .owrite_req(write_req_realign), .owrite_ack(int_write_ack
		), .pg_fault(pg_fault), .wr_fault(wr_fault), .cr2(cr2), .flush_tlb
		(flush_Dtlb), .cs({UNCONNECTED_043, UNCONNECTED_044, 
		UNCONNECTED_045, UNCONNECTED_046, UNCONNECTED_047, 
		UNCONNECTED_048, UNCONNECTED_049, UNCONNECTED_050, 
		UNCONNECTED_051, UNCONNECTED_052, UNCONNECTED_053, 
		UNCONNECTED_054, UNCONNECTED_055, UNCONNECTED_056, 
		UNCONNECTED_057, UNCONNECTED_058, UNCONNECTED_059, 
		UNCONNECTED_060, UNCONNECTED_061, UNCONNECTED_062, 
		UNCONNECTED_063, UNCONNECTED_064, UNCONNECTED_065, 
		UNCONNECTED_066, UNCONNECTED_067, UNCONNECTED_068, 
		UNCONNECTED_069, UNCONNECTED_070, UNCONNECTED_071, 
		UNCONNECTED_072, \cs[1] , \cs[0] }), .pt_fault(pt_fault), .busy_ram
		(busy_ram));
	realign i_realign(.clk(clk), .rstn(rstn), .write_msk_out(write_msk), .addr_in
		(Daddr_realign), .addr_out({Daddr[31], Daddr[30], Daddr[29], Daddr
		[28], Daddr[27], Daddr[26], Daddr[25], Daddr[24], Daddr[23], Daddr
		[22], Daddr[21], Daddr[20], Daddr[19], Daddr[18], Daddr[17], Daddr
		[16], Daddr[15], Daddr[14], Daddr[13], Daddr[12], Daddr[11], Daddr
		[10], Daddr[9], Daddr[8], Daddr[7], Daddr[6], Daddr[5], Daddr[4]
		, Daddr[3], Daddr[2], UNCONNECTED_073, UNCONNECTED_074}), .write_sz_in
		(nbus_14544), .write_req_in(write_req_realign), .write_req_out(write_req
		), .write_ack_in(write_ack), .write_ack_out(write_ack_realign), 
		.read_req_in(read_req_realign), .read_req_out(read_req), .read_ack_in
		(read_ack), .read_ack_out(read_ack_realign), .read_data_in(read_data
		), .read_data_out(read_data_realign), .write_data_in(write_data_realign
		), .write_data_out(write_data));
	Itlb i_Itlb(.clk(clk), .rstn(rstn), .addr_phys({code_addr[31], code_addr
		[30], code_addr[29], code_addr[28], code_addr[27], code_addr[26]
		, code_addr[25], code_addr[24], code_addr[23], code_addr[22], code_addr
		[21], code_addr[20], code_addr[19], code_addr[18], code_addr[17]
		, code_addr[16], code_addr[15], code_addr[14], code_addr[13], code_addr
		[12], code_addr[11], code_addr[10], code_addr[9], code_addr[8], code_addr
		[7], code_addr[6], code_addr[5], code_addr[4], code_addr[3], code_addr
		[2], UNCONNECTED_075, UNCONNECTED_076}), .cr3({\cr3[31] , \cr3[30] 
		, \cr3[29] , \cr3[28] , \cr3[27] , \cr3[26] , \cr3[25] , \cr3[24] 
		, \cr3[23] , \cr3[22] , \cr3[21] , \cr3[20] , \cr3[19] , \cr3[18] 
		, \cr3[17] , \cr3[16] , \cr3[15] , \cr3[14] , \cr3[13] , \cr3[12] 
		, UNCONNECTED_077, UNCONNECTED_078, UNCONNECTED_079, 
		UNCONNECTED_080, UNCONNECTED_081, UNCONNECTED_082, 
		UNCONNECTED_083, UNCONNECTED_084, UNCONNECTED_085, 
		UNCONNECTED_086, UNCONNECTED_087, UNCONNECTED_088}), .data_miss(
		{code_data[31], code_data[30], code_data[29], code_data[28], code_data
		[27], code_data[26], code_data[25], code_data[24], code_data[23]
		, code_data[22], code_data[21], code_data[20], code_data[19], code_data
		[18], code_data[17], code_data[16], code_data[15], code_data[14]
		, code_data[13], code_data[12], UNCONNECTED_089, UNCONNECTED_090
		, UNCONNECTED_091, UNCONNECTED_092, code_data[7], code_data[6], code_data
		[5], code_data[4], code_data[3], code_data[2], code_data[1], code_data
		[0]}), .iDaddr(int_code_addr), .pg_en(pg_en), .owrite_data({
		UNCONNECTED_093, UNCONNECTED_094, UNCONNECTED_095, 
		UNCONNECTED_096, UNCONNECTED_097, UNCONNECTED_098, 
		UNCONNECTED_099, UNCONNECTED_100, UNCONNECTED_101, 
		UNCONNECTED_102, UNCONNECTED_103, UNCONNECTED_104, 
		UNCONNECTED_105, UNCONNECTED_106, UNCONNECTED_107, 
		UNCONNECTED_108, UNCONNECTED_109, UNCONNECTED_110, 
		UNCONNECTED_111, UNCONNECTED_112, UNCONNECTED_113, 
		UNCONNECTED_114, UNCONNECTED_115, UNCONNECTED_116, code_wdata[7]
		, code_wdata[6], code_wdata[5], code_wdata[4], code_wdata[3], code_wdata
		[2], code_wdata[1], code_wdata[0]}), .iread_req(int_code_req), .iread_ack
		(code_ack), .iwrite_ack(code_wack), .oread_req(code_req), .oread_ack
		(int_code_ack), .owrite_req(code_wreq), .pg_fault(n_4695), .cr2(icr2
		), .flush_tlb(flush_Itlb), .busy_ram(busy_ram));
	useq i_useq(.iaddr(int_code_addr), .idata(code_data), .code_req(int_code_req
		), .code_ack(int_code_ack), .clk(clk), .rstn(rstn), .useq_ptr(useq_ptr
		), .squeue(queue), .pc_in(pc_out), .pc_req(pc_req), .pg_fault(n_4695
		), .pc_pg_fault(pc_pg_fault), .valid_len(valid_len), .busy_ram(busy_ram
		));
	cpu i_cpu(.clk(clk), .rstn(rstn), .iack(iack), .int_cpu(int_main), .ivect
		(ivect), .cr0({UNCONNECTED_117, UNCONNECTED_118, UNCONNECTED_119
		, UNCONNECTED_120, UNCONNECTED_121, UNCONNECTED_122, 
		UNCONNECTED_123, UNCONNECTED_124, UNCONNECTED_125, 
		UNCONNECTED_126, UNCONNECTED_127, UNCONNECTED_128, 
		UNCONNECTED_129, UNCONNECTED_130, UNCONNECTED_131, \cr0[16] , 
		UNCONNECTED_132, UNCONNECTED_133, UNCONNECTED_134, 
		UNCONNECTED_135, UNCONNECTED_136, UNCONNECTED_137, 
		UNCONNECTED_138, UNCONNECTED_139, UNCONNECTED_140, 
		UNCONNECTED_141, UNCONNECTED_142, UNCONNECTED_143, 
		UNCONNECTED_144, UNCONNECTED_145, UNCONNECTED_146, 
		UNCONNECTED_147}), .cr2(cr2), .icr2(icr2), .cr3({\cr3[31] , \cr3[30] 
		, \cr3[29] , \cr3[28] , \cr3[27] , \cr3[26] , \cr3[25] , \cr3[24] 
		, \cr3[23] , \cr3[22] , \cr3[21] , \cr3[20] , \cr3[19] , \cr3[18] 
		, \cr3[17] , \cr3[16] , \cr3[15] , \cr3[14] , \cr3[13] , \cr3[12] 
		, UNCONNECTED_148, UNCONNECTED_149, UNCONNECTED_150, 
		UNCONNECTED_151, UNCONNECTED_152, UNCONNECTED_153, 
		UNCONNECTED_154, UNCONNECTED_155, UNCONNECTED_156, 
		UNCONNECTED_157, UNCONNECTED_158, UNCONNECTED_159}), .cs({
		UNCONNECTED_160, UNCONNECTED_161, UNCONNECTED_162, 
		UNCONNECTED_163, UNCONNECTED_164, UNCONNECTED_165, 
		UNCONNECTED_166, UNCONNECTED_167, UNCONNECTED_168, 
		UNCONNECTED_169, UNCONNECTED_170, UNCONNECTED_171, 
		UNCONNECTED_172, UNCONNECTED_173, UNCONNECTED_174, 
		UNCONNECTED_175, UNCONNECTED_176, UNCONNECTED_177, 
		UNCONNECTED_178, UNCONNECTED_179, UNCONNECTED_180, 
		UNCONNECTED_181, UNCONNECTED_182, UNCONNECTED_183, 
		UNCONNECTED_184, UNCONNECTED_185, UNCONNECTED_186, 
		UNCONNECTED_187, UNCONNECTED_188, UNCONNECTED_189, \cs[1] , \cs[0] 
		}), .pg_fault(pg_fault), .ipg_fault(pc_pg_fault), .useq_ptr(useq_ptr
		), .valid_len(valid_len), .queue(queue), .pg_en(pg_en), .pc_out(pc_out
		), .pc_req(pc_req), .read_req(int_read_req), .write_req(int_write_req
		), .read_ack(int_read_ack), .write_ack(int_write_ack), .flush_Itlb
		(flush_Itlb), .flush_Dtlb(flush_Dtlb), .readio_req(readio_req), 
		.writeio_req(writeio_req), .readio_ack(readio_ack), .writeio_ack
		(writeio_ack), .write_data(iwrite_data), .writeio_data(writeio_data
		), .read_data(read_data_realign), .readio_data(readio_data), .write_sz
		(int_write_sz), .io_add({UNCONNECTED_190, UNCONNECTED_191, 
		UNCONNECTED_192, UNCONNECTED_193, UNCONNECTED_194, 
		UNCONNECTED_195, UNCONNECTED_196, UNCONNECTED_197, 
		UNCONNECTED_198, UNCONNECTED_199, UNCONNECTED_200, 
		UNCONNECTED_201, UNCONNECTED_202, UNCONNECTED_203, 
		UNCONNECTED_204, UNCONNECTED_205, io_add[15], io_add[14], io_add
		[13], io_add[12], io_add[11], io_add[10], io_add[9], io_add[8], io_add
		[7], io_add[6], io_add[5], io_add[4], io_add[3], io_add[2], io_add
		[1], io_add[0]}), .Daddr(int_Daddr), .pt_fault(pt_fault), .wr_fault
		(wr_fault));
endmodule
