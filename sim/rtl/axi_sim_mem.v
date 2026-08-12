//------------------------------------------------------------------------
// axi_sim_mem -- simulation-only AXI4 slave backing v586's m00_AXI
// (code fetch + data) master port.
//
// Presents three byte-addressable regions in one flat AXI4 slave, modeled
// after soc_rtl/axi_rom.v's read-channel style (registered handshakes,
// burst-capable AR/R), extended with a write channel (AW/W/B) for RAM:
//
//   RAM:    [0, RAM_BYTES)                          read/write
//   ROM:    [ROM_BASE, ROM_BASE+ROM_BYTES)           read-only, $readmemh
//   SHADOW: [SHADOW_BASE, SHADOW_BASE+ROM_BYTES)     read-only, mirrors ROM
//
// SHADOW mirrors the exact same rom[] array at a second base address
// (default 0xFFFE_0000, chosen so SHADOW_BASE+ROM_BYTES lands exactly on
// 32'hFFFF_FFFF+1 -- the full 128KiB ROM_BYTES fits with no truncation
// and no need to rely on the 32-bit address ceiling to cap it). Added to
// test a hypothesis from dbg_pc_out tracing: pc_out reports {CS,IP} as a
// raw 16+16 concatenation rather than a computed address (see
// core_rtl/README.md), so it's plausible the real fetch-address
// generation does something similarly non-standard (e.g. CS<<16 | IP
// instead of CS*16 + IP) -- for a large CS that would land fetches near
// the top of the address space, not the classic real-mode ~0xFFFF0.
// Mirroring the ROM there lets us observe what happens if a fetch
// actually lands there, instead of just reading unmapped zeros.
//
// Anything outside all three regions reads as 0 and silently discards
// writes, so a stray access can't hang the bus.
//
// Not synthesizable RTL -- simulation/testbench infrastructure only.
//------------------------------------------------------------------------

module axi_sim_mem #(
	parameter RAM_BYTES    = 32'h0000_9000,
	parameter ROM_BASE     = 32'h000E_0000,
	parameter ROM_BYTES    = 32'h0002_0000,
	parameter ROM_FILE     = "boot.hex",
	parameter SHADOW_BASE  = 32'hFFFE_0000
) (
	input  wire        clk,
	input  wire        rstn,

	// AW
	input  wire [31:0] axi_AWADDR,
	input  wire        axi_AWVALID,
	output reg         axi_AWREADY,
	// W
	input  wire [31:0] axi_WDATA,
	input  wire        axi_WVALID,
	output reg         axi_WREADY,
	input  wire [3:0]  axi_WSTRB,
	input  wire        axi_WLAST,
	// B
	output reg         axi_BVALID,
	input  wire        axi_BREADY,
	// AR
	input  wire [31:0] axi_ARADDR,
	input  wire        axi_ARVALID,
	output reg         axi_ARREADY,
	input  wire [7:0]  axi_ARLEN,
	input  wire [1:0]  axi_ARBURST,
	// R
	output reg  [31:0] axi_RDATA,
	output reg         axi_RVALID,
	input  wire        axi_RREADY,
	output reg         axi_RLAST,

	// Debug/trace-only outputs -- pulse dbg_ram_wr_valid for one cycle
	// per W beat that actually lands in the RAM region (addr <
	// RAM_BYTES), with the address/data written. Not part of the AXI
	// interface; for sim_main.cpp to log real memory stores, a stronger
	// "this executed" signal than pc_out position alone.
	output reg         dbg_ram_wr_valid,
	output reg  [31:0] dbg_ram_waddr,
	output reg  [31:0] dbg_ram_wdata
);

	reg [7:0] ram [0:RAM_BYTES-1];
	reg [7:0] rom [0:ROM_BYTES-1];

	integer init_i;
	initial begin
		for (init_i = 0; init_i < RAM_BYTES; init_i = init_i + 1) ram[init_i] = 8'h00;
		// Default-fill the ROM with NOP (0x90) rather than 0x00 -- a flat
		// NOP sled across the whole 128KiB window, so any entry point just
		// falls through harmlessly instead of executing 0x00 0x00
		// ("ADD [bx+si], al", a real memory-touching instruction).
		// boot.hex below overrides the specific bytes that matter.
		for (init_i = 0; init_i < ROM_BYTES; init_i = init_i + 1) rom[init_i] = 8'h90;
		$readmemh(ROM_FILE, rom);
	end

	// ---------------------------------------------------------------
	// Byte-level read/write helpers, address-decoded across both
	// regions.
	// ---------------------------------------------------------------
	function [7:0] rd_byte;
		input [31:0] addr;
		begin
			if (addr < RAM_BYTES)
				rd_byte = ram[addr[19:0]];
			else if ((addr >= ROM_BASE) && (addr < (ROM_BASE + ROM_BYTES)))
				rd_byte = rom[addr - ROM_BASE];
			// SHADOW_BASE + ROM_BYTES can overflow 32 bits (it does for the
			// default 0xFFFE_0000 base with a 128KiB ROM_BYTES -- the sum
			// is exactly 2^32), so don't compute that sum as an upper
			// bound -- addr can never exceed 32'hFFFF_FFFF anyway, which
			// naturally caps this region at (32'hFFFF_FFFF - SHADOW_BASE
			// + 1) bytes. For the default base that's exactly 128KiB, an
			// exact fit with no truncation, as long as SHADOW_BASE + a
			// ROM_BYTES-sized region continues to land exactly at the top
			// of the address space (2^32) if that ever changes.
			else if (addr >= SHADOW_BASE)
				rd_byte = rom[addr - SHADOW_BASE];
			else
				rd_byte = 8'h00;
		end
	endfunction

	task wr_byte;
		input [31:0] addr;
		input [7:0]  data;
		begin
			if (addr < RAM_BYTES)
				ram[addr[19:0]] <= data;
			// writes into the ROM region or unmapped space are no-ops
		end
	endtask

	// ---------------------------------------------------------------
	// Read channel (AR/R) -- single-beat or fixed/incrementing burst,
	// same handshake shape as soc_rtl/axi_rom.v.
	// ---------------------------------------------------------------
	wire [31:0] ar_word_addr = {axi_ARADDR[31:2], 2'b00};
	reg  [31:0] cur_raddr;
	reg         read_transaction;
	reg         burst_transaction;
	reg  [7:0]  burstn, rlen;

	always @(posedge clk) begin
		axi_RDATA[ 7: 0] <= rd_byte(cur_raddr + 0);
		axi_RDATA[15: 8] <= rd_byte(cur_raddr + 1);
		axi_RDATA[23:16] <= rd_byte(cur_raddr + 2);
		axi_RDATA[31:24] <= rd_byte(cur_raddr + 3);
	end

	always @(posedge clk or negedge rstn)
	if (~rstn) begin
		axi_ARREADY       <= 1'b0;
		axi_RVALID        <= 1'b0;
		axi_RLAST         <= 1'b0;
		read_transaction  <= 1'b0;
		burst_transaction <= 1'b0;
		burstn            <= 8'h0;
		rlen              <= 8'h0;
		cur_raddr         <= 32'h0;
	end else begin
		if (axi_ARVALID & ~read_transaction & ~burst_transaction) begin
			axi_ARREADY <= 1'b1;
			cur_raddr   <= ar_word_addr;
			if ((axi_ARLEN != 8'h0) && (axi_ARBURST == 2'b01)) begin
				rlen               <= axi_ARLEN;
				burst_transaction  <= 1'b1;
			end else begin
				read_transaction   <= 1'b1;
			end
		end else begin
			axi_ARREADY <= 1'b0;
		end

		if (axi_RREADY & read_transaction) begin
			axi_RVALID       <= 1'b1;
			axi_RLAST        <= 1'b1;
			read_transaction <= 1'b0;
		end else if (axi_RREADY & burst_transaction) begin
			axi_RVALID <= 1'b1;
			if (burstn == rlen) begin
				axi_RLAST         <= 1'b1;
				burst_transaction <= 1'b0;
			end
			burstn    <= burstn + 8'h1;
			cur_raddr <= cur_raddr + 32'h4;
		end else begin
			axi_RVALID <= 1'b0;
			axi_RLAST  <= 1'b0;
			burstn     <= 8'h0;
		end
	end

	// ---------------------------------------------------------------
	// Write channel (AW/W/B) -- single outstanding transaction,
	// incrementing address per W beat, RAM-only (see wr_byte above).
	// ---------------------------------------------------------------
	reg  [31:0] cur_waddr;
	reg         aw_active;
	reg         b_pending;

	always @(posedge clk or negedge rstn)
	if (~rstn) begin
		axi_AWREADY <= 1'b0;
		axi_WREADY  <= 1'b0;
		axi_BVALID  <= 1'b0;
		aw_active   <= 1'b0;
		b_pending   <= 1'b0;
		cur_waddr   <= 32'h0;
		dbg_ram_wr_valid <= 1'b0;
		dbg_ram_waddr    <= 32'h0;
		dbg_ram_wdata    <= 32'h0;
	end else begin
		// AW
		if (axi_AWVALID & ~aw_active & ~b_pending) begin
			axi_AWREADY <= 1'b1;
			cur_waddr   <= {axi_AWADDR[31:2], 2'b00};
			aw_active   <= 1'b1;
		end else begin
			axi_AWREADY <= 1'b0;
		end

		// W
		if (axi_WVALID & aw_active) begin
			axi_WREADY <= 1'b1;
			if (axi_WSTRB[0]) wr_byte(cur_waddr + 0, axi_WDATA[ 7: 0]);
			if (axi_WSTRB[1]) wr_byte(cur_waddr + 1, axi_WDATA[15: 8]);
			if (axi_WSTRB[2]) wr_byte(cur_waddr + 2, axi_WDATA[23:16]);
			if (axi_WSTRB[3]) wr_byte(cur_waddr + 3, axi_WDATA[31:24]);
			if (cur_waddr < RAM_BYTES) begin
				dbg_ram_wr_valid <= 1'b1;
				dbg_ram_waddr    <= cur_waddr;
				dbg_ram_wdata    <= axi_WDATA;
			end else begin
				dbg_ram_wr_valid <= 1'b0;
			end
			if (axi_WLAST) begin
				aw_active <= 1'b0;
				b_pending <= 1'b1;
			end else begin
				cur_waddr <= cur_waddr + 32'h4;
			end
		end else begin
			axi_WREADY <= 1'b0;
			dbg_ram_wr_valid <= 1'b0;
		end

		// B
		if (b_pending & ~axi_BVALID) begin
			axi_BVALID <= 1'b1;
		end else if (axi_BVALID & axi_BREADY) begin
			axi_BVALID <= 1'b0;
			b_pending  <= 1'b0;
		end
	end

endmodule
