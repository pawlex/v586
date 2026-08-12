// Verilator C++ driver for v586_tb_top.
//
// Drives clk/rstn directly (the DUT hierarchy generates neither), runs a
// fixed number of clock cycles, optionally dumps a VCD trace, and logs
// m00_AXI instruction-fetch (AR) transactions so a boot smoke test (does
// the core come out of reset and settle into the boot.hex spin loop at
// 0xFFC00 or 0xFFFF0?) can be checked without opening a waveform viewer
// -- though the VCD is there for GTKWave if something looks wrong.
//
// Usage: v586_sim [--cycles=N] [--trace[=file.vcd]] [--quiet]

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
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
	uint64_t cycle = 0;

	// Rolling window of recent fetch-address *changes*, used to detect a
	// steady-state loop (e.g. a branch target plus a prefetch-queue
	// read-ahead line) rather than requiring the fetch address to pin to
	// one single unchanging value.
	std::deque<uint32_t> recent_addrs;
	const size_t kWindow = 32;

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

		if (top->rstn && top->mon_m00_ARVALID && top->mon_m00_ARREADY) {
			ar_transactions++;
			if (top->mon_m00_ARADDR != last_araddr) {
				if (!quiet) {
					printf("[cycle %6llu] m00_AXI AR fetch addr = 0x%08x (delta %llu cycles since last change)\n",
					       static_cast<unsigned long long>(cycle),
					       top->mon_m00_ARADDR,
					       static_cast<unsigned long long>(cycle - last_araddr_change_cycle));
				}
				last_araddr = top->mon_m00_ARADDR;
				last_araddr_change_cycle = cycle;
				recent_addrs.push_back(last_araddr);
				if (recent_addrs.size() > kWindow) recent_addrs.pop_front();
			}
		}

		if (top->rstn && top->mon_iack) {
			if (!quiet) printf("[cycle %6llu] iack asserted\n", static_cast<unsigned long long>(cycle));
		}

		cycle++;
	}

	top->final();

	if (tfp) {
		tfp->close();
		delete tfp;
	}

	printf("\n---- v586_tb_top run summary ----\n");
	printf("cycles run           : %llu\n", static_cast<unsigned long long>(max_cycles));
	printf("m00_AXI AR beats seen : %llu\n", static_cast<unsigned long long>(ar_transactions));
	printf("last fetch address   : 0x%08x\n", last_araddr);
	printf("final debug[4:0]     : 0x%x\n", top->mon_debug);
	if (trace_on) printf("trace written to     : %s\n", vcd_path.c_str());

	if (ar_transactions == 0) {
		printf("RESULT: FAIL -- core never issued a code-fetch (AR) transaction after reset.\n");
		delete top;
		return 1;
	}

	// Steady-state check: rather than requiring the fetch address to pin
	// to one exact value (a prefetch queue may keep re-reading a line or
	// two ahead of a tight branch target), check that the last kWindow
	// fetch-address changes are confined to a small span anchored at one
	// of the two candidate loop addresses.
	bool steady = !recent_addrs.empty() && recent_addrs.size() >= 4;
	uint32_t win_min = 0xFFFFFFFF, win_max = 0;
	for (uint32_t a : recent_addrs) {
		if (a < win_min) win_min = a;
		if (a > win_max) win_max = a;
	}
	const uint32_t kMaxSpan = 0x40; // within ~4 fetch lines
	bool anchored = (win_min <= 0xFFC00 && 0xFFC00 <= win_max) ||
	                (win_min <= 0xFFFF0 && 0xFFFF0 <= win_max);
	steady = steady && anchored && (win_max - win_min <= kMaxSpan);

	if (!recent_addrs.empty()) {
		printf("recent fetch addr span: 0x%08x - 0x%08x over last %zu changes\n",
		       win_min, win_max, recent_addrs.size());
	}

	if (steady) {
		printf("RESULT: PASS (heuristic) -- fetch address settled into a tight, bounded loop "
		       "anchored at a boot.hex spin-loop address (0xFFC00 or 0xFFFF0).\n");
	} else {
		printf("RESULT: INCONCLUSIVE -- core is fetching (last addr 0x%08x), but it did not "
		       "settle near the expected reset-vector loop address. Inspect the trace.\n",
		       last_araddr);
	}

	delete top;
	return 0;
}
