//------------------------------------------------------------------------
// v586_example_top -- minimal, board-agnostic example instantiation of
// the v586 core (core_rtl/v586_top.v, module `v586`).
//
// This is a plain passthrough wrapper: every v586 port is brought straight
// out to the top level, unmodified. It shows the full interface a real
// integration needs to provide and is not tied to any vendor IP (unlike
// the board_specific_files/*/TOP_SYS.v tops, which also instantiate a
// Xilinx MIG/DDR controller, clocking wizard, SPI flash, UART, etc.).
//
// v586 exposes two independent AXI4 master interfaces:
//   m00_AXI_* -- code fetch + data (memory-mapped) accesses. Bursting,
//                up to 128-bit code fetch lines. Connect this to your
//                main memory (DDR controller, BRAM, etc.) via an AXI4
//                slave or interconnect.
//   m01_AXI_* -- I/O-space accesses (x86 IN/OUT instructions). Always
//                single-beat, byte-lane-0 writes. Connect this to your
//                peripheral/IO subsystem (see soc_rtl/ for example
//                peripherals: uart_16750, tiny_spi, periph, v8042_stub).
//
// Interrupts: int_pic/ivect/iack form a simple vectored interrupt
// handshake -- drive int_pic when an interrupt controller has a pending
// vector, present it on ivect, and the core pulses iack once it has
// taken the vector. debug is a 5-bit core status output.
//
// Both AXI masters and the core run from a single clock/reset pair
// (m00_AXI_CLK/m00_AXI_RSTN internally) -- there is no separate clock
// for m01.
//------------------------------------------------------------------------

module v586_example_top (
	input  wire        clk,
	input  wire        rstn,

	// AXI4 master 0 -- code fetch + data
	output wire [31:0] m00_AXI_AWADDR,
	output wire        m00_AXI_AWVALID,
	input  wire        m00_AXI_AWREADY,
	output wire [1:0]  m00_AXI_AWBURST,
	output wire [7:0]  m00_AXI_AWLEN,
	output wire [2:0]  m00_AXI_AWSIZE,
	output wire [31:0] m00_AXI_ARADDR,
	output wire        m00_AXI_ARVALID,
	input  wire        m00_AXI_ARREADY,
	output wire [1:0]  m00_AXI_ARBURST,
	output wire [7:0]  m00_AXI_ARLEN,
	output wire [2:0]  m00_AXI_ARSIZE,
	output wire [31:0] m00_AXI_WDATA,
	output wire        m00_AXI_WVALID,
	input  wire        m00_AXI_WREADY,
	output wire [3:0]  m00_AXI_WSTRB,
	output wire        m00_AXI_WLAST,
	input  wire [31:0] m00_AXI_RDATA,
	input  wire        m00_AXI_RVALID,
	output wire        m00_AXI_RREADY,
	input  wire        m00_AXI_RLAST,
	input  wire        m00_AXI_BVALID,
	output wire        m00_AXI_BREADY,

	// AXI4 master 1 -- I/O space
	output wire [31:0] m01_AXI_AWADDR,
	output wire        m01_AXI_AWVALID,
	input  wire        m01_AXI_AWREADY,
	output wire [1:0]  m01_AXI_AWBURST,
	output wire [7:0]  m01_AXI_AWLEN,
	output wire [2:0]  m01_AXI_AWSIZE,
	output wire [31:0] m01_AXI_ARADDR,
	output wire        m01_AXI_ARVALID,
	input  wire        m01_AXI_ARREADY,
	output wire [1:0]  m01_AXI_ARBURST,
	output wire [7:0]  m01_AXI_ARLEN,
	output wire [2:0]  m01_AXI_ARSIZE,
	output wire [31:0] m01_AXI_WDATA,
	output wire        m01_AXI_WVALID,
	input  wire        m01_AXI_WREADY,
	output wire [3:0]  m01_AXI_WSTRB,
	output wire        m01_AXI_WLAST,
	input  wire [31:0] m01_AXI_RDATA,
	input  wire        m01_AXI_RVALID,
	output wire        m01_AXI_RREADY,
	input  wire        m01_AXI_RLAST,
	input  wire        m01_AXI_BVALID,
	output wire        m01_AXI_BREADY,

	// Interrupt controller interface
	input  wire        int_pic,
	output wire        iack,
	input  wire [7:0]  ivect,

	output wire [4:0]  debug
);

	v586 u_v586 (
		.m00_AXI_RSTN    (rstn),
		.m00_AXI_CLK     (clk),

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

		.int_pic         (int_pic),
		.iack            (iack),
		.ivect           (ivect),
		.debug           (debug)
	);

endmodule
