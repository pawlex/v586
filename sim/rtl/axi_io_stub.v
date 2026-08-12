//------------------------------------------------------------------------
// axi_io_stub -- simulation-only AXI4 slave for v586's m01_AXI (I/O
// space) master port.
//
// v586's top-level ties m01_AXI to always be single-beat (see
// core_rtl/v586_top.v's fixed AWBURST/AWLEN/ARLEN/WSTRB assigns), so this
// stub only needs to handle one beat at a time. It accepts every write
// immediately (data discarded -- there's no peripheral behind it) and
// returns 0 for every read, so IN/OUT instructions complete instead of
// hanging the bus.
//
// Not synthesizable RTL -- simulation/testbench infrastructure only.
//------------------------------------------------------------------------

module axi_io_stub (
	input  wire        clk,
	input  wire        rstn,

	// AW
	input  wire [31:0] axi_AWADDR,
	input  wire        axi_AWVALID,
	output reg          axi_AWREADY,
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
	// R
	output reg  [31:0] axi_RDATA,
	output reg         axi_RVALID,
	input  wire        axi_RREADY,
	output reg         axi_RLAST
);

	reg aw_seen, w_seen;

	always @(posedge clk or negedge rstn)
	if (~rstn) begin
		axi_AWREADY <= 1'b0;
		axi_WREADY  <= 1'b0;
		axi_BVALID  <= 1'b0;
		aw_seen     <= 1'b0;
		w_seen      <= 1'b0;
		axi_ARREADY <= 1'b0;
		axi_RVALID  <= 1'b0;
		axi_RLAST   <= 1'b0;
		axi_RDATA   <= 32'h0;
	end else begin
		// AW
		axi_AWREADY <= axi_AWVALID & ~aw_seen & ~w_seen;
		if (axi_AWVALID & ~aw_seen & ~w_seen)
			aw_seen <= 1'b1;

		// W
		axi_WREADY <= axi_WVALID & aw_seen & ~w_seen;
		if (axi_WVALID & aw_seen & ~w_seen & axi_WLAST)
			w_seen <= 1'b1;

		// B
		if (aw_seen & w_seen & ~axi_BVALID) begin
			axi_BVALID <= 1'b1;
		end else if (axi_BVALID & axi_BREADY) begin
			axi_BVALID <= 1'b0;
			aw_seen    <= 1'b0;
			w_seen     <= 1'b0;
		end

		// AR / R -- always returns 0, single beat
		axi_ARREADY <= axi_ARVALID & ~axi_RVALID;
		if (axi_ARVALID & ~axi_RVALID) begin
			axi_RVALID <= 1'b1;
			axi_RLAST  <= 1'b1;
			axi_RDATA  <= 32'h0;
		end else if (axi_RVALID & axi_RREADY) begin
			axi_RVALID <= 1'b0;
			axi_RLAST  <= 1'b0;
		end
	end

endmodule
