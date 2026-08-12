//------------------------------------------------------------------------
// axi_sim_mem -- simulation-only AXI4 slave backing v586's m00_AXI
// (code fetch + data) master port.
//
// Presents two byte-addressable regions in one flat AXI4 slave, modeled
// after soc_rtl/axi_rom.v's read-channel style (registered handshakes,
// burst-capable AR/R), extended with a write channel (AW/W/B) for RAM:
//
//   RAM: [0, RAM_BYTES)                  read/write
//   ROM: [ROM_BASE, ROM_BASE+ROM_BYTES)  read-only, loaded via $readmemh
//
// Anything outside both regions reads as 0 and silently discards writes,
// so a stray access can't hang the bus.
//
// Not synthesizable RTL -- simulation/testbench infrastructure only.
//------------------------------------------------------------------------

module axi_sim_mem #(
	parameter RAM_BYTES = 32'h0000_9000,
	parameter ROM_BASE  = 32'h000E_0000,
	parameter ROM_BYTES = 32'h0002_0000,
	parameter ROM_FILE  = "boot.hex"
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
	output reg         axi_RLAST
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
			if (axi_WLAST) begin
				aw_active <= 1'b0;
				b_pending <= 1'b1;
			end else begin
				cur_waddr <= cur_waddr + 32'h4;
			end
		end else begin
			axi_WREADY <= 1'b0;
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
