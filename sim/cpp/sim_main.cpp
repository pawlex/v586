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

#include "Vv586_tb_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t g_time = 0;

double sc_time_stamp() { return static_cast<double>(g_time); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);

	uint64_t max_cycles = 20000;
	bool trace_on = false;
	bool quiet = false;
	std::string vcd_path = "v586_tb.vcd";
	uint32_t io_watch_port = 0x80;

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
		}
	}

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
	bool pc_out_hit_ffc00 = false;
	bool pc_out_hit_fffF0 = false;
	bool pc_out_hit_f00000 = false;
	uint64_t pc_out_ffc00_first_cycle = 0;
	uint64_t pc_out_f00000_first_cycle = 0;

	uint8_t last_useq_ptr = 0xFF;

	uint64_t io_watch_port_writes = 0;
	uint64_t ram_writes = 0;
	uint8_t  last_writeio_req = 0;
	uint64_t writeio_req_pulses = 0;

	uint64_t cycle = 0;
	const uint64_t reset_cycles = 10;

	while (cycle < max_cycles) {
		// Falling edge
		top->clk = 0;
		top->eval();
		if (tfp) tfp->dump(g_time);
		g_time++;

		if (cycle == reset_cycles) top->rstn = 1;

		// Rising edge
		top->clk = 1;
		top->eval();
		if (tfp) tfp->dump(g_time);
		g_time++;

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
			if (last_pc_out == 0x000FFC00) {
				if (!pc_out_hit_ffc00) pc_out_ffc00_first_cycle = cycle;
				pc_out_hit_ffc00 = true;
			}
			if (last_pc_out == 0x000FFFF0) pc_out_hit_fffF0 = true;
			if (last_pc_out == 0x00F00000) {
				if (!pc_out_hit_f00000) pc_out_f00000_first_cycle = cycle;
				pc_out_hit_f00000 = true;
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

		if (top->rstn && top->mon_io_wr_valid && top->mon_io_waddr == io_watch_port) {
			io_watch_port_writes++;
			if (!quiet) {
				printf("[cycle %6llu] IO WRITE port 0x%02x <= 0x%02x\n",
				       static_cast<unsigned long long>(cycle), io_watch_port,
				       top->mon_io_wdata & 0xFF);
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
	printf("m00_AXI AR beats seen    : %llu\n", static_cast<unsigned long long>(ar_transactions));
	printf("last fetch address      : 0x%08x\n", last_araddr);
	printf("dbg_pc_out changes seen  : %llu\n", static_cast<unsigned long long>(pc_out_changes));
	printf("last dbg_pc_out value    : 0x%08x (static for last %llu cycles)\n",
	       last_pc_out, static_cast<unsigned long long>(cycles_since_pc_out_change));
	printf("final debug[4:0]         : 0x%x\n", top->mon_debug);
	printf("RAM writes               : %llu\n", static_cast<unsigned long long>(ram_writes));
	printf("IO writes to port 0x%02x  : %llu\n", io_watch_port,
	       static_cast<unsigned long long>(io_watch_port_writes));
	printf("writeio_req pulses       : %llu\n", static_cast<unsigned long long>(writeio_req_pulses));
	if (trace_on) printf("trace written to        : %s\n", vcd_path.c_str());

	if (ar_transactions == 0) {
		printf("RESULT: FAIL -- core never issued a code-fetch (AR) transaction after reset.\n");
		delete top;
		return 1;
	}

	printf("\n---- reset-vector / long-jump-trap disambiguation ----\n");
	printf("dbg_pc_out ever == 0xFFFF0   (confirmed reset vector) : %s\n",
	       pc_out_hit_fffF0 ? "yes" : "no");
	printf("dbg_pc_out ever == 0xFFC00   (trap address)           : %s\n",
	       pc_out_hit_ffc00 ? "yes" : "no");
	printf("dbg_pc_out ever == 0xF00000  (long-jump target)       : %s\n",
	       pc_out_hit_f00000 ? "yes" : "no");

	if (pc_out_hit_f00000) {
		printf("  first reached at cycle %llu\n",
		       static_cast<unsigned long long>(pc_out_f00000_first_cycle));
		printf("RESULT: dbg_pc_out reached 0x00F00000 -- a deliberately unmapped, otherwise\n"
		       "unreachable address. This is unambiguous confirmation that real execution hit\n"
		       "the trap at 0xFFC00 and executed the long jump (not fetch-bus/prefetch\n"
		       "traffic -- nothing else in this design could produce this exact PC value).\n");
	} else if (pc_out_hit_ffc00) {
		printf("  0xFFC00 first reached at cycle %llu, but never jumped to 0xF00000\n",
		       static_cast<unsigned long long>(pc_out_ffc00_first_cycle));
		printf("RESULT: dbg_pc_out reached 0xFFC00 but the long jump never fired -- the 6-byte\n"
		       "'66 E9' encoding may not be decoded as expected by this core (e.g. no 0x66\n"
		       "operand-size prefix support, or a different opcode-length assumption than\n"
		       "used here). Inspect the trace around cycle %llu byte-by-byte.\n",
		       static_cast<unsigned long long>(pc_out_ffc00_first_cycle));
	} else {
		printf("RESULT: dbg_pc_out never reached 0xFFC00 at all -- last value 0x%08x.\n",
		       last_pc_out);
	}

	delete top;
	return 0;
}
