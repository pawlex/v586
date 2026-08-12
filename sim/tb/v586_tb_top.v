//------------------------------------------------------------------------
// v586_tb_top -- Verilator testbench top.
//
// Instantiates example/v586_example_top.v (the verified passthrough
// wrapper around core_rtl's v586 module) and backs its two AXI4 master
// ports with simulation-only memory models:
//
//   m00_AXI (code fetch + data) -> axi_sim_mem: RAM at 0x0-0x8FFF,
//                                   ROM at 0xE0000-0xFFFFF (128KiB)
//   m01_AXI (I/O space)         -> axi_io_stub: always-completing sink
//
// No interrupts are driven (int_pic tied low, ivect tied to 0). clk and
// rstn are driven by the C++ driver (sim/cpp/sim_main.cpp), not
// generated here, so the driver controls simulation timing directly.
//------------------------------------------------------------------------

module v586_tb_top (
	input  wire        clk,
	input  wire        rstn,

	// Monitor-only outputs for the C++ driver -- not part of v586's own
	// interface, just re-exported internal signals so sim_main.cpp can
	// observe boot progress via plain top-level ports instead of having
	// to guess internal hierarchical signal names.
	output wire [31:0] mon_m00_ARADDR,
	output wire        mon_m00_ARVALID,
	output wire        mon_m00_ARREADY,
	output wire        mon_m00_RVALID,
	output wire [31:0] mon_m00_AWADDR,
	output wire        mon_m00_AWVALID,
	output wire [4:0]  mon_debug,
	output wire        mon_iack
);

	wire [31:0] m00_AXI_AWADDR;
	wire        m00_AXI_AWVALID;
	wire        m00_AXI_AWREADY;
	wire [1:0]  m00_AXI_AWBURST;
	wire [7:0]  m00_AXI_AWLEN;
	wire [2:0]  m00_AXI_AWSIZE;
	wire [31:0] m00_AXI_ARADDR;
	wire        m00_AXI_ARVALID;
	wire        m00_AXI_ARREADY;
	wire [1:0]  m00_AXI_ARBURST;
	wire [7:0]  m00_AXI_ARLEN;
	wire [2:0]  m00_AXI_ARSIZE;
	wire [31:0] m00_AXI_WDATA;
	wire        m00_AXI_WVALID;
	wire        m00_AXI_WREADY;
	wire [3:0]  m00_AXI_WSTRB;
	wire        m00_AXI_WLAST;
	wire [31:0] m00_AXI_RDATA;
	wire        m00_AXI_RVALID;
	wire        m00_AXI_RREADY;
	wire        m00_AXI_RLAST;
	wire        m00_AXI_BVALID;
	wire        m00_AXI_BREADY;

	wire [31:0] m01_AXI_AWADDR;
	wire        m01_AXI_AWVALID;
	wire        m01_AXI_AWREADY;
	wire [1:0]  m01_AXI_AWBURST;
	wire [7:0]  m01_AXI_AWLEN;
	wire [2:0]  m01_AXI_AWSIZE;
	wire [31:0] m01_AXI_ARADDR;
	wire        m01_AXI_ARVALID;
	wire        m01_AXI_ARREADY;
	wire [1:0]  m01_AXI_ARBURST;
	wire [7:0]  m01_AXI_ARLEN;
	wire [2:0]  m01_AXI_ARSIZE;
	wire [31:0] m01_AXI_WDATA;
	wire        m01_AXI_WVALID;
	wire        m01_AXI_WREADY;
	wire [3:0]  m01_AXI_WSTRB;
	wire        m01_AXI_WLAST;
	wire [31:0] m01_AXI_RDATA;
	wire        m01_AXI_RVALID;
	wire        m01_AXI_RREADY;
	wire        m01_AXI_RLAST;
	wire        m01_AXI_BVALID;
	wire        m01_AXI_BREADY;

	wire        iack;
	wire [4:0]  debug;

	v586_example_top u_dut (
		.clk             (clk),
		.rstn            (rstn),

		.m00_AXI_AWADDR  (m00_AXI_AWADDR),
		.m00_AXI_AWVALID (m00_AXI_AWVALID),
		.m00_AXI_AWREADY (m00_AXI_AWREADY),
		.m00_AXI_AWBURST (m00_AXI_AWBURST),
		.m00_AXI_AWLEN   (m00_AXI_AWLEN),
		.m00_AXI_AWSIZE  (m00_AXI_AWSIZE),
		.m00_AXI_ARADDR  (m00_AXI_ARADDR),
		.m00_AXI_ARVALID (m00_AXI_ARVALID),
		.m00_AXI_ARREADY (m00_AXI_ARREADY),
		.m00_AXI_ARBURST (m00_AXI_ARBURST),
		.m00_AXI_ARLEN   (m00_AXI_ARLEN),
		.m00_AXI_ARSIZE  (m00_AXI_ARSIZE),
		.m00_AXI_WDATA   (m00_AXI_WDATA),
		.m00_AXI_WVALID  (m00_AXI_WVALID),
		.m00_AXI_WREADY  (m00_AXI_WREADY),
		.m00_AXI_WSTRB   (m00_AXI_WSTRB),
		.m00_AXI_WLAST   (m00_AXI_WLAST),
		.m00_AXI_RDATA   (m00_AXI_RDATA),
		.m00_AXI_RVALID  (m00_AXI_RVALID),
		.m00_AXI_RREADY  (m00_AXI_RREADY),
		.m00_AXI_RLAST   (m00_AXI_RLAST),
		.m00_AXI_BVALID  (m00_AXI_BVALID),
		.m00_AXI_BREADY  (m00_AXI_BREADY),

		.m01_AXI_AWADDR  (m01_AXI_AWADDR),
		.m01_AXI_AWVALID (m01_AXI_AWVALID),
		.m01_AXI_AWREADY (m01_AXI_AWREADY),
		.m01_AXI_AWBURST (m01_AXI_AWBURST),
		.m01_AXI_AWLEN   (m01_AXI_AWLEN),
		.m01_AXI_AWSIZE  (m01_AXI_AWSIZE),
		.m01_AXI_ARADDR  (m01_AXI_ARADDR),
		.m01_AXI_ARVALID (m01_AXI_ARVALID),
		.m01_AXI_ARREADY (m01_AXI_ARREADY),
		.m01_AXI_ARBURST (m01_AXI_ARBURST),
		.m01_AXI_ARLEN   (m01_AXI_ARLEN),
		.m01_AXI_ARSIZE  (m01_AXI_ARSIZE),
		.m01_AXI_WDATA   (m01_AXI_WDATA),
		.m01_AXI_WVALID  (m01_AXI_WVALID),
		.m01_AXI_WREADY  (m01_AXI_WREADY),
		.m01_AXI_WSTRB   (m01_AXI_WSTRB),
		.m01_AXI_WLAST   (m01_AXI_WLAST),
		.m01_AXI_RDATA   (m01_AXI_RDATA),
		.m01_AXI_RVALID  (m01_AXI_RVALID),
		.m01_AXI_RREADY  (m01_AXI_RREADY),
		.m01_AXI_RLAST   (m01_AXI_RLAST),
		.m01_AXI_BVALID  (m01_AXI_BVALID),
		.m01_AXI_BREADY  (m01_AXI_BREADY),

		.int_pic         (1'b0),
		.iack            (iack),
		.ivect           (8'h0),
		.debug           (debug)
	);

	axi_sim_mem #(
		.RAM_BYTES (32'h000A_0000),
		.ROM_BASE  (32'h000E_0000),
		.ROM_BYTES (32'h0002_0000),
		.ROM_FILE  ("rom/boot.hex")
	) u_mem (
		.clk          (clk),
		.rstn         (rstn),
		.axi_AWADDR   (m00_AXI_AWADDR),
		.axi_AWVALID  (m00_AXI_AWVALID),
		.axi_AWREADY  (m00_AXI_AWREADY),
		.axi_WDATA    (m00_AXI_WDATA),
		.axi_WVALID   (m00_AXI_WVALID),
		.axi_WREADY   (m00_AXI_WREADY),
		.axi_WSTRB    (m00_AXI_WSTRB),
		.axi_WLAST    (m00_AXI_WLAST),
		.axi_BVALID   (m00_AXI_BVALID),
		.axi_BREADY   (m00_AXI_BREADY),
		.axi_ARADDR   (m00_AXI_ARADDR),
		.axi_ARVALID  (m00_AXI_ARVALID),
		.axi_ARREADY  (m00_AXI_ARREADY),
		.axi_ARLEN    (m00_AXI_ARLEN),
		.axi_ARBURST  (m00_AXI_ARBURST),
		.axi_RDATA    (m00_AXI_RDATA),
		.axi_RVALID   (m00_AXI_RVALID),
		.axi_RREADY   (m00_AXI_RREADY),
		.axi_RLAST    (m00_AXI_RLAST)
	);

	axi_io_stub u_io (
		.clk          (clk),
		.rstn         (rstn),
		.axi_AWADDR   (m01_AXI_AWADDR),
		.axi_AWVALID  (m01_AXI_AWVALID),
		.axi_AWREADY  (m01_AXI_AWREADY),
		.axi_WDATA    (m01_AXI_WDATA),
		.axi_WVALID   (m01_AXI_WVALID),
		.axi_WREADY   (m01_AXI_WREADY),
		.axi_WSTRB    (m01_AXI_WSTRB),
		.axi_WLAST    (m01_AXI_WLAST),
		.axi_BVALID   (m01_AXI_BVALID),
		.axi_BREADY   (m01_AXI_BREADY),
		.axi_ARADDR   (m01_AXI_ARADDR),
		.axi_ARVALID  (m01_AXI_ARVALID),
		.axi_ARREADY  (m01_AXI_ARREADY),
		.axi_RDATA    (m01_AXI_RDATA),
		.axi_RVALID   (m01_AXI_RVALID),
		.axi_RREADY   (m01_AXI_RREADY),
		.axi_RLAST    (m01_AXI_RLAST)
	);

	assign mon_m00_ARADDR  = m00_AXI_ARADDR;
	assign mon_m00_ARVALID = m00_AXI_ARVALID;
	assign mon_m00_ARREADY = m00_AXI_ARREADY;
	assign mon_m00_RVALID  = m00_AXI_RVALID;
	assign mon_m00_AWADDR  = m00_AXI_AWADDR;
	assign mon_m00_AWVALID = m00_AXI_AWVALID;
	assign mon_debug       = debug;
	assign mon_iack        = iack;

endmodule
