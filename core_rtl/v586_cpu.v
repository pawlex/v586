//------------------------------------------------------------------------
// cpu -- thin wrapper tying the decoder and execution datapath together
//
// Instantiates i_vliw (v586_vliw.v), i_deco (v586_decode.v), and i_acu
// (acu.v, address-calculation unit) which consumes deco's to_acu bus.
// Instantiated as `i_cpu` in core (see v586_core.v).
//
// NOTE: gate-level netlist below the port list (aside from i_acu) -- see
// the header of v586_biu32_axi.v for what that means.
//------------------------------------------------------------------------

module cpu(clk, rstn, iack, int_cpu, ivect, cr0, cr2, icr2, cr3, cs, pg_fault, ipg_fault
		, useq_ptr, valid_len, queue, pg_en, pc_out, pc_req, read_req, write_req
		, read_ack, write_ack, flush_Itlb, flush_Dtlb, readio_req, writeio_req
		, readio_ack, writeio_ack, write_data, writeio_data, read_data, readio_data
		, write_sz, read_sz, io_add, Daddr, pt_fault, wr_fault);

	input clk;
	input rstn;
	output iack;
	input int_cpu;
	input [7:0] ivect;
	output [31:0] cr0;
	input [31:0] cr2;
	input [31:0] icr2;
	output [31:0] cr3;
	output [31:0] cs;
	input pg_fault;
	input ipg_fault;
	output [3:0] useq_ptr;
	input [5:0] valid_len;
	input [127:0] queue;
	output pg_en;
	output [31:0] pc_out;
	output pc_req;
	output read_req;
	output write_req;
	input read_ack;
	input write_ack;
	output flush_Itlb;
	output flush_Dtlb;
	output readio_req;
	output writeio_req;
	input readio_ack;
	input writeio_ack;
	output [31:0] write_data;
	output [31:0] writeio_data;
	input [31:0] read_data;
	input [31:0] readio_data;
	output [1:0] write_sz;
	output [1:0] read_sz;
	output [31:0] io_add;
	output [31:0] Daddr;
	input pt_fault;
	input wr_fault;

	wire [2:0] reps;
	wire [2:0] opz;
	wire [127:0] dec2vliw;
	wire [31:0] lenpc;
	wire [31:0] add_src;
	wire [7:0] from_acu;
	wire [63:0] to_acu;
	wire [210:0] deco2acu;



	vliw i_vliw(.clk(clk), .rstn(rstn), .instrc(dec2vliw), .ie(ie), .readio_data
		(readio_data), .io_add({UNCONNECTED_000, UNCONNECTED_001, 
		UNCONNECTED_002, UNCONNECTED_003, UNCONNECTED_004, 
		UNCONNECTED_005, UNCONNECTED_006, UNCONNECTED_007, 
		UNCONNECTED_008, UNCONNECTED_009, UNCONNECTED_010, 
		UNCONNECTED_011, UNCONNECTED_012, UNCONNECTED_013, 
		UNCONNECTED_014, UNCONNECTED_015, io_add[15], io_add[14], io_add
		[13], io_add[12], io_add[11], io_add[10], io_add[9], io_add[8], io_add
		[7], io_add[6], io_add[5], io_add[4], io_add[3], io_add[2], io_add
		[1], io_add[0]}), .writeio_data(writeio_data), .writeio_req(writeio_req
		), .readio_req(readio_req), .writeio_ack(writeio_ack), .readio_ack
		(readio_ack), .read_reqs(read_req), .read_ack(read_ack), .read_data
		(read_data), .over_seg({\over_seg[5] , UNCONNECTED_016, 
		UNCONNECTED_017, UNCONNECTED_018, UNCONNECTED_019, 
		UNCONNECTED_020}), .cr3({cr3[31], cr3[30], cr3[29], cr3[28], cr3
		[27], cr3[26], cr3[25], cr3[24], cr3[23], cr3[22], cr3[21], cr3[
		20], cr3[19], cr3[18], cr3[17], cr3[16], cr3[15], cr3[14], cr3[
		13], cr3[12], UNCONNECTED_021, UNCONNECTED_022, UNCONNECTED_023,
		 UNCONNECTED_024, UNCONNECTED_025, UNCONNECTED_026, 
		UNCONNECTED_027, UNCONNECTED_028, UNCONNECTED_029, 
		UNCONNECTED_030, UNCONNECTED_031, UNCONNECTED_032}), .cr2(cr2), 
		.icr2(icr2), .cr0({UNCONNECTED_033, UNCONNECTED_034, 
		UNCONNECTED_035, UNCONNECTED_036, UNCONNECTED_037, 
		UNCONNECTED_038, UNCONNECTED_039, UNCONNECTED_040, 
		UNCONNECTED_041, UNCONNECTED_042, UNCONNECTED_043, 
		UNCONNECTED_044, UNCONNECTED_045, UNCONNECTED_046, 
		UNCONNECTED_047, cr0[16], UNCONNECTED_048, UNCONNECTED_049, 
		UNCONNECTED_050, UNCONNECTED_051, UNCONNECTED_052, 
		UNCONNECTED_053, UNCONNECTED_054, UNCONNECTED_055, 
		UNCONNECTED_056, UNCONNECTED_057, UNCONNECTED_058, 
		UNCONNECTED_059, UNCONNECTED_060, \cr0[2] , UNCONNECTED_061, \cr0[0] 
		}), .write_reqs(write_req), .write_ack(write_ack), .write_data(write_data
		), .Daddr(Daddr), .write_sz(write_sz), .cs({UNCONNECTED_062, 
		UNCONNECTED_063, UNCONNECTED_064, UNCONNECTED_065, 
		UNCONNECTED_066, UNCONNECTED_067, UNCONNECTED_068, 
		UNCONNECTED_069, UNCONNECTED_070, UNCONNECTED_071, 
		UNCONNECTED_072, UNCONNECTED_073, UNCONNECTED_074, 
		UNCONNECTED_075, UNCONNECTED_076, UNCONNECTED_077, 
		UNCONNECTED_078, UNCONNECTED_079, UNCONNECTED_080, 
		UNCONNECTED_081, UNCONNECTED_082, UNCONNECTED_083, 
		UNCONNECTED_084, UNCONNECTED_085, UNCONNECTED_086, 
		UNCONNECTED_087, UNCONNECTED_088, UNCONNECTED_089, 
		UNCONNECTED_090, UNCONNECTED_091, cs[1], cs[0]}), .add_src(add_src
		), .from_acu(from_acu), .to_acu(to_acu), .pg_en(pg_en), .imm({
		UNCONNECTED_092, UNCONNECTED_093, UNCONNECTED_094, 
		UNCONNECTED_095, UNCONNECTED_096, UNCONNECTED_097, 
		UNCONNECTED_098, UNCONNECTED_099, UNCONNECTED_100, 
		UNCONNECTED_101, UNCONNECTED_102, UNCONNECTED_103, 
		UNCONNECTED_104, UNCONNECTED_105, UNCONNECTED_106, 
		UNCONNECTED_107, \imm[47] , \imm[46] , \imm[45] , \imm[44] , \imm[43] 
		, \imm[42] , \imm[41] , \imm[40] , \imm[39] , \imm[38] , \imm[37] 
		, \imm[36] , \imm[35] , \imm[34] , \imm[33] , \imm[32] , \imm[31] 
		, \imm[30] , \imm[29] , \imm[28] , \imm[27] , \imm[26] , \imm[25] 
		, \imm[24] , \imm[23] , \imm[22] , \imm[21] , \imm[20] , \imm[19] 
		, \imm[18] , \imm[17] , \imm[16] , \imm[15] , \imm[14] , \imm[13] 
		, \imm[12] , \imm[11] , \imm[10] , \imm[9] , \imm[8] , \imm[7] ,
		 \imm[6] , \imm[5] , \imm[4] , \imm[3] , \imm[2] , \imm[1] , \imm[0] 
		}), .lenpc(lenpc), .pc_out(pc_out), .pc_req(pc_req), .opz(opz), 
		.reps(reps), .flush_tlb(flush_Itlb), .flush_Dtlb(flush_Dtlb), .terminate
		(term), .start_up(st), .pg_fault(pg_fault), .ipg_fault(ipg_fault
		), .wr_fault(wr_fault), .pt_fault(pt_fault));
	acu i_acu(.clk(clk), .rstn(rstn), .from_regf(to_acu), .add_src(add_src),
		 .to_regf(from_acu), .from_dec(deco2acu), .db67(\cr0[0] ));
	deco i_deco(.clk(clk), .rstn(rstn), .useq_ptr(useq_ptr), .in128(queue), 
		.adz(\cr0[0] ), .pc_req(pc_req), .ivect(ivect), .int_main(int_cpu
		), .iack(iack), .ie(ie), .pg_fault(pg_fault), .ipg_fault(ipg_fault
		), .cpl({cs[1], cs[0]}), .cr0({UNCONNECTED_108, UNCONNECTED_109,
		 UNCONNECTED_110, UNCONNECTED_111, UNCONNECTED_112, 
		UNCONNECTED_113, UNCONNECTED_114, UNCONNECTED_115, 
		UNCONNECTED_116, UNCONNECTED_117, UNCONNECTED_118, 
		UNCONNECTED_119, UNCONNECTED_120, UNCONNECTED_121, 
		UNCONNECTED_122, UNCONNECTED_123, UNCONNECTED_124, 
		UNCONNECTED_125, UNCONNECTED_126, UNCONNECTED_127, 
		UNCONNECTED_128, UNCONNECTED_129, UNCONNECTED_130, 
		UNCONNECTED_131, UNCONNECTED_132, UNCONNECTED_133, 
		UNCONNECTED_134, UNCONNECTED_135, UNCONNECTED_136, \cr0[2] , 
		UNCONNECTED_137, UNCONNECTED_138}), .valid_len(valid_len), .to_vliw
		(dec2vliw), .lenpc_out(lenpc), .immediate({UNCONNECTED_139, 
		UNCONNECTED_140, UNCONNECTED_141, UNCONNECTED_142, 
		UNCONNECTED_143, UNCONNECTED_144, UNCONNECTED_145, 
		UNCONNECTED_146, UNCONNECTED_147, UNCONNECTED_148, 
		UNCONNECTED_149, UNCONNECTED_150, UNCONNECTED_151, 
		UNCONNECTED_152, UNCONNECTED_153, UNCONNECTED_154, \imm[47] , \imm[46] 
		, \imm[45] , \imm[44] , \imm[43] , \imm[42] , \imm[41] , \imm[40] 
		, \imm[39] , \imm[38] , \imm[37] , \imm[36] , \imm[35] , \imm[34] 
		, \imm[33] , \imm[32] , \imm[31] , \imm[30] , \imm[29] , \imm[28] 
		, \imm[27] , \imm[26] , \imm[25] , \imm[24] , \imm[23] , \imm[22] 
		, \imm[21] , \imm[20] , \imm[19] , \imm[18] , \imm[17] , \imm[16] 
		, \imm[15] , \imm[14] , \imm[13] , \imm[12] , \imm[11] , \imm[10] 
		, \imm[9] , \imm[8] , \imm[7] , \imm[6] , \imm[5] , \imm[4] , \imm[3] 
		, \imm[2] , \imm[1] , \imm[0] }), .to_acu(deco2acu), .operand_size
		(opz), .reps(reps), .over_seg({\over_seg[5] , UNCONNECTED_155, 
		UNCONNECTED_156, UNCONNECTED_157, UNCONNECTED_158, 
		UNCONNECTED_159}), .term(term), .start(st));
endmodule
