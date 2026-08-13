// Verilator C++ driver for v586_tb_top.
//
// Drives clk/rstn directly (the DUT hierarchy generates neither), runs a
// fixed number of clock cycles, optionally dumps a VCD trace, and prints
// a [cycle N] trace line for exactly three event types:
//   - dbg_pc_out changes -- cpu's committed PC (fed back into useq's
//     pc_in), the closest thing this core exposes to a real instruction
//     pointer, but NOT reliable proof of real execution/retirement on
//     its own -- see sim/README.md and core_rtl/README.md.
//   - RAM writes (m00_AXI) -- via sim/rtl/axi_sim_mem.v's dbg_ram_*
//     outputs. A real memory-store side effect, stronger evidence of
//     execution than pc_out position alone.
//   - I/O writes (m01_AXI) to a specific port (default 0x80, the
//     classic PC "POST code" debug-output port), via
//     sim/rtl/axi_io_stub.v's dbg_io_* outputs. Override with --io-port=N.
//
// m00_AXI AR fetch activity and dbg_useq_ptr are still tracked (for the
// run summary) but not printed per-event -- fetch/prefetch traffic can
// touch an address the CPU never actually executes from, so it's noise
// for a trace focused on real execution evidence.
//
// See sim/rom/boot.hex, sim/README.md and core_rtl/README.md for the
// current reset-vector / execution-pointer investigation and known
// limitations.
//
// Usage: v586_sim [--cycles=N] [--trace[=file.vcd]] [--quiet] [--io-port=N]

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "Vv586_tb_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// One expected (or forbidden) dbg_pc_out value, plus whether the run
// actually hit it and when. Used for both --expect-pc and
// --expect-not-pc; the two differ only in how `seen` is judged.
struct Expect {
	uint32_t addr;
	bool     seen;
	uint64_t first_cycle;
	explicit Expect(uint32_t a) : addr(a), seen(false), first_cycle(0) {}
};

// Core input clock: 33 MHz. The Makefile builds with `--timescale
// 1ns/1ps`, so simulation time (and every VCD dump timestamp, which is
// passed in timeprecision units) is in picoseconds -- keep the two in
// sync if either changes.
//
// 1/33MHz = 30303.0303... ps, which is not a whole picosecond. Rounding
// to 30303 ps makes the modelled clock 33.000033 MHz (~1 ppm fast),
// which is far below anything this testbench is used to measure. The
// leftover 0.03 ps/cycle is still never accumulated: edge times below
// are computed from the cycle index rather than by repeated addition,
// so a multi-million-cycle run can't drift.
static const uint64_t CLK_PERIOD_PS = 30303;

// ---- I/O port decode -------------------------------------------------
// The core word-addresses I/O space: `OUT 0x80, AX` appears on m01_AXI at
// byte address 0x200 (= 0x80 << 2). Matching the raw bus address against
// the port number therefore never fired, which is why every earlier run
// reported "IO writes to port 0x80 : 0" -- a measurement bug that would
// have masked a real write even when the core performed one.
//
// IO_PORT_MASK is the classic 10-bit ISA decode: period PC hardware only
// decoded the low 10 address lines, so ports alias every 0x400 (0x480 is
// the same device as 0x80). Applied to both sides of the comparison.
//
// CAUTION: the shift is inferred from a single observed mapping
// (0x80 -> 0x200). The raw bus address is printed alongside the decoded
// port so a wrong assumption here stays visible rather than silently
// re-creating the same class of bug.
static const unsigned IO_ADDR_SHIFT = 2;
static const uint32_t IO_PORT_MASK  = 0x3FF;

static uint32_t io_bus_addr_to_port(uint32_t bus_addr) {
	return (bus_addr >> IO_ADDR_SHIFT) & IO_PORT_MASK;
}

static vluint64_t g_time = 0;

double sc_time_stamp() { return static_cast<double>(g_time); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);

	uint64_t max_cycles = 20000;
	bool trace_on = false;
	bool quiet = false;
	std::string vcd_path = "v586_tb.vcd";
	uint32_t io_watch_port = 0x80;

	// Expectations. Any --expect-* flag puts the run in "test mode": the
	// exit status becomes pass/fail rather than just "did it run", and a
	// verdict block is printed. With no expectations given, behaviour is
	// exactly as before (exploratory run, exit 0).
	std::vector<Expect> expect_pc;      // pc_out must reach each of these
	std::vector<Expect> expect_not_pc;  // ...and must never reach these
	bool     have_expect_io  = false;
	uint64_t expect_io       = 0;
	bool     have_expect_ram = false;
	uint64_t expect_ram      = 0;
	bool     have_expect_wio = false;
	uint64_t expect_wio      = 0;

	for (int i = 1; i < argc; i++) {
		std::string arg = argv[i];
		if (arg.rfind("--cycles=", 0) == 0) {
			max_cycles = strtoull(arg.c_str() + 9, nullptr, 0);
		} else if (arg.rfind("--trace=", 0) == 0) {
			trace_on = true;
			vcd_path = arg.substr(8);
		} else if (arg == "--trace") {
			trace_on = true;
		} else if (arg == "--quiet") {
			quiet = true;
		} else if (arg.rfind("--io-port=", 0) == 0) {
			io_watch_port = static_cast<uint32_t>(strtoul(arg.c_str() + 10, nullptr, 0));
		} else if (arg.rfind("--expect-pc=", 0) == 0) {
			expect_pc.push_back(Expect(
				static_cast<uint32_t>(strtoul(arg.c_str() + 12, nullptr, 0))));
		} else if (arg.rfind("--expect-not-pc=", 0) == 0) {
			expect_not_pc.push_back(Expect(
				static_cast<uint32_t>(strtoul(arg.c_str() + 16, nullptr, 0))));
		} else if (arg.rfind("--expect-io=", 0) == 0) {
			have_expect_io = true;
			expect_io = strtoull(arg.c_str() + 12, nullptr, 0);
		} else if (arg.rfind("--expect-ram=", 0) == 0) {
			have_expect_ram = true;
			expect_ram = strtoull(arg.c_str() + 13, nullptr, 0);
		} else if (arg.rfind("--expect-writeio=", 0) == 0) {
			have_expect_wio = true;
			expect_wio = strtoull(arg.c_str() + 17, nullptr, 0);
		} else if (arg.rfind("+", 0) == 0) {
			// Verilator plusarg (e.g. +rom=...), consumed by
			// Verilated::commandArgs above -- not ours to parse.
		} else if (arg.rfind("--", 0) == 0) {
			fprintf(stderr, "unknown option: %s\n", arg.c_str());
			return 2;
		}
	}

	const bool test_mode = !expect_pc.empty() || !expect_not_pc.empty() ||
	                       have_expect_io || have_expect_ram || have_expect_wio;

	Vv586_tb_top *top = new Vv586_tb_top;

	VerilatedVcdC *tfp = nullptr;
	if (trace_on) {
		Verilated::traceEverOn(true);
		tfp = new VerilatedVcdC;
		top->trace(tfp, 99);
		tfp->open(vcd_path.c_str());
	}

	// Reset: hold rstn low for 10 clock periods, then release.
	top->clk = 0;
	top->rstn = 0;

	uint32_t last_araddr = 0xFFFFFFFF;
	uint64_t last_araddr_change_cycle = 0;
	uint64_t ar_transactions = 0;

	uint32_t last_pc_out = 0xFFFFFFFF;
	uint64_t last_pc_out_change_cycle = 0;
	uint64_t pc_out_changes = 0;

	uint8_t last_useq_ptr = 0xFF;

	uint64_t io_watch_port_writes = 0;
	uint64_t ram_writes = 0;
	uint8_t  last_writeio_req = 0;
	uint64_t writeio_req_pulses = 0;

	uint64_t cycle = 0;
	const uint64_t reset_cycles = 10;

	while (cycle < max_cycles) {
		// Computed from the cycle index, not accumulated, so the sub-ps
		// rounding in CLK_PERIOD_PS can't drift over a long run.
		const uint64_t t_fall = cycle * CLK_PERIOD_PS;
		const uint64_t t_rise = t_fall + CLK_PERIOD_PS / 2;

		// Falling edge
		top->clk = 0;
		g_time = t_fall;
		top->eval();
		if (tfp) tfp->dump(t_fall);

		if (cycle == reset_cycles) top->rstn = 1;

		// Rising edge
		top->clk = 1;
		g_time = t_rise;
		top->eval();
		if (tfp) tfp->dump(t_rise);

		// Tracked silently for the summary -- not printed per-event, since
		// fetch/prefetch traffic can touch an address the CPU never
		// actually executes from (noise for a trace focused on real
		// execution evidence).
		if (top->rstn && top->mon_m00_ARVALID && top->mon_m00_ARREADY) {
			ar_transactions++;
			if (top->mon_m00_ARADDR != last_araddr) {
				last_araddr = top->mon_m00_ARADDR;
				last_araddr_change_cycle = cycle;
			}
		}
		if (top->rstn && top->mon_useq_ptr != last_useq_ptr) {
			last_useq_ptr = top->mon_useq_ptr;
		}

		if (top->rstn && top->mon_pc_out != last_pc_out) {
			if (!quiet) {
				printf("[cycle %6llu] dbg_pc_out = 0x%08x\n",
				       static_cast<unsigned long long>(cycle), top->mon_pc_out);
			}
			last_pc_out = top->mon_pc_out;
			last_pc_out_change_cycle = cycle;
			pc_out_changes++;
			for (size_t e = 0; e < expect_pc.size(); e++) {
				if (!expect_pc[e].seen && expect_pc[e].addr == last_pc_out) {
					expect_pc[e].seen = true;
					expect_pc[e].first_cycle = cycle;
				}
			}
			for (size_t e = 0; e < expect_not_pc.size(); e++) {
				if (!expect_not_pc[e].seen && expect_not_pc[e].addr == last_pc_out) {
					expect_not_pc[e].seen = true;
					expect_not_pc[e].first_cycle = cycle;
				}
			}
		}

		if (top->rstn && top->mon_ram_wr_valid) {
			ram_writes++;
			if (!quiet) {
				printf("[cycle %6llu] RAM WRITE addr 0x%08x <= 0x%08x\n",
				       static_cast<unsigned long long>(cycle),
				       top->mon_ram_waddr, top->mon_ram_wdata);
			}
		}

		if (top->rstn && top->mon_writeio_req && !last_writeio_req) {
			writeio_req_pulses++;
			if (!quiet) {
				printf("[cycle %6llu] writeio_req (core->biu32_axi) data=0x%08x\n",
				       static_cast<unsigned long long>(cycle), top->mon_writeio_data);
			}
		}
		last_writeio_req = top->mon_writeio_req;

		if (top->rstn && top->mon_io_wr_valid) {
			const uint32_t port = io_bus_addr_to_port(top->mon_io_waddr);
			if (port == (io_watch_port & IO_PORT_MASK)) {
				io_watch_port_writes++;
				if (!quiet) {
					// Raw bus address included deliberately -- see the
					// IO_ADDR_SHIFT note above.
					printf("[cycle %6llu] IO WRITE port 0x%03x <= 0x%04x "
					       "(m01_AXI addr 0x%08x, data 0x%08x)\n",
					       static_cast<unsigned long long>(cycle), port,
					       top->mon_io_wdata & 0xFFFF,
					       top->mon_io_waddr, top->mon_io_wdata);
				}
			}
		}

		cycle++;
	}

	top->final();

	if (tfp) {
		tfp->close();
		delete tfp;
	}

	uint64_t cycles_since_pc_out_change = cycle > last_pc_out_change_cycle
	                                           ? cycle - last_pc_out_change_cycle
	                                           : 0;

	printf("\n---- v586_tb_top run summary ----\n");
	printf("cycles run              : %llu\n", static_cast<unsigned long long>(max_cycles));
	printf("simulated time          : %.3f us @ %.3f MHz\n",
	       static_cast<double>(max_cycles) * CLK_PERIOD_PS / 1e6,
	       1e6 / static_cast<double>(CLK_PERIOD_PS));
	printf("m00_AXI AR beats seen    : %llu\n", static_cast<unsigned long long>(ar_transactions));
	printf("last fetch address      : 0x%08x\n", last_araddr);
	printf("dbg_pc_out changes seen  : %llu\n", static_cast<unsigned long long>(pc_out_changes));
	printf("last dbg_pc_out value    : 0x%08x (static for last %llu cycles)\n",
	       last_pc_out, static_cast<unsigned long long>(cycles_since_pc_out_change));
	printf("final debug[4:0]         : 0x%x\n", top->mon_debug);
	printf("RAM writes               : %llu\n", static_cast<unsigned long long>(ram_writes));
	printf("IO writes to port 0x%03x : %llu\n", io_watch_port & IO_PORT_MASK,
	       static_cast<unsigned long long>(io_watch_port_writes));
	printf("writeio_req pulses       : %llu\n", static_cast<unsigned long long>(writeio_req_pulses));
	if (trace_on) printf("trace written to        : %s\n", vcd_path.c_str());

	if (ar_transactions == 0) {
		printf("RESULT: FAIL -- core never issued a code-fetch (AR) transaction after reset.\n");
		delete top;
		return 1;
	}

	// No --expect-* flags: exploratory run, nothing to judge.
	if (!test_mode) {
		delete top;
		return 0;
	}

	// ---- Expectations -------------------------------------------------
	// Each line prints its own pass/fail so a failing test says exactly
	// which assertion broke, rather than just a non-zero exit status.
	int failures = 0;
	printf("\n---- expectations ----\n");

	for (size_t e = 0; e < expect_pc.size(); e++) {
		const bool ok = expect_pc[e].seen;
		if (!ok) failures++;
		printf("[%s] pc_out reaches 0x%08x", ok ? "PASS" : "FAIL", expect_pc[e].addr);
		if (ok) printf(" (first at cycle %llu)",
		               static_cast<unsigned long long>(expect_pc[e].first_cycle));
		printf("\n");
	}
	for (size_t e = 0; e < expect_not_pc.size(); e++) {
		const bool ok = !expect_not_pc[e].seen;
		if (!ok) failures++;
		printf("[%s] pc_out never reaches 0x%08x", ok ? "PASS" : "FAIL",
		       expect_not_pc[e].addr);
		if (!ok) printf(" (but hit it at cycle %llu)",
		                static_cast<unsigned long long>(expect_not_pc[e].first_cycle));
		printf("\n");
	}
	if (have_expect_io) {
		const bool ok = (io_watch_port_writes == expect_io);
		if (!ok) failures++;
		printf("[%s] IO writes to port 0x%03x == %llu (got %llu)\n",
		       ok ? "PASS" : "FAIL", io_watch_port & IO_PORT_MASK,
		       static_cast<unsigned long long>(expect_io),
		       static_cast<unsigned long long>(io_watch_port_writes));
	}
	if (have_expect_ram) {
		const bool ok = (ram_writes == expect_ram);
		if (!ok) failures++;
		printf("[%s] RAM writes == %llu (got %llu)\n", ok ? "PASS" : "FAIL",
		       static_cast<unsigned long long>(expect_ram),
		       static_cast<unsigned long long>(ram_writes));
	}
	if (have_expect_wio) {
		const bool ok = (writeio_req_pulses == expect_wio);
		if (!ok) failures++;
		printf("[%s] writeio_req pulses == %llu (got %llu)\n", ok ? "PASS" : "FAIL",
		       static_cast<unsigned long long>(expect_wio),
		       static_cast<unsigned long long>(writeio_req_pulses));
	}

	printf("RESULT: %s (%d failed)\n", failures ? "FAIL" : "PASS", failures);
	delete top;
	return failures ? 1 : 0;
}
