# Verilator testbench for the v586 core.
#
# Builds sim/tb/v586_tb_top.v (which instantiates example/v586_example_top.v
# -> core_rtl's v586) against a simulation-only AXI4 RAM/ROM/IO model, and
# a C++ driver that runs a fixed cycle count and logs code-fetch activity.
#
#   make run            - build (if needed) and run, no trace
#   make run TRACE=1    - build and run with a VCD trace (sim/v586_tb.vcd)
#   make run CYCLES=N   - override the cycle count (default 20000)
#   make run IO_PORT=N  - log writes to a different I/O port (default 0x80)
#   make waves          - run with TRACE=1 then open GTKWave on the result
#   make view           - open an already-generated VCD in GTKWave, without
#                         re-running the sim (use this to re-open a trace
#                         from a long run instead of paying for it again)
#   make view VCD=other.vcd - open some other trace file
#   make clean          - remove build output and traces
#
# The core clock is modelled at 33MHz -- see the --timescale flag below
# and CLK_PERIOD_PS in cpp/sim_main.cpp, which have to stay in agreement.
#
# JOBS controls C++ build parallelism (default 4). The generated model
# is large (v586's gate-level netlist is ~74k lines) and each parallel
# g++ job on it can use well over 1GB of RAM, so this default is a RAM
# ceiling, not a core count -- don't raise it to nproc without the RAM
# to back it. Measured on the 8-core/5GB box this was developed on:
# `-j 8` drove free memory to ~290MB with 8 cc1plus processes live and
# got OOM-killed (`g++: fatal error: Killed signal terminated program
# cc1plus` is the tell); `-j 3` completed in 3:04 with a 1.6GB peak RSS.
# The default of 4 sits between those two and has NOT been measured --
# drop to `make run JOBS=3` (known good here) or `JOBS=1` if it OOMs.

VERILATOR ?= verilator

CORE_RTL := ../core_rtl
GATE_RTL := ../gate_rtl
EXAMPLE  := ../example

SIM_SRCS := \
	tb/v586_tb_top.v \
	rtl/axi_sim_mem.v \
	rtl/axi_io_stub.v \
	$(EXAMPLE)/v586_example_top.v \
	$(CORE_RTL)/v586_top.v \
	$(CORE_RTL)/v586_core.v \
	$(CORE_RTL)/v586_cpu.v \
	$(CORE_RTL)/v586_useq.v \
	$(CORE_RTL)/v586_vliw.v \
	$(CORE_RTL)/v586_decode.v \
	$(CORE_RTL)/v586_itlb.v \
	$(CORE_RTL)/v586_dtlb.v \
	$(CORE_RTL)/v586_biu32_axi.v \
	$(CORE_RTL)/acu.v \
	$(CORE_RTL)/arithbox.v \
	$(CORE_RTL)/datacache.v \
	$(CORE_RTL)/realign.v \
	$(CORE_RTL)/shiftbox.v \
	$(CORE_RTL)/synthetic_op.v \
	$(wildcard $(GATE_RTL)/*.v)

TOP    := v586_tb_top
OBJDIR := obj_dir
BIN    := $(OBJDIR)/V$(TOP)

CYCLES  ?= 20000
TRACE   ?=
IO_PORT ?= 0x80

# Deliberately NOT nproc/all-cores: see the RAM warning in the header
# comment above. Raise it if you have RAM to spare, or drop to 1 if the
# build still gets OOM-killed.
JOBS    ?= 4

# Trace file and the saved GTKWave signal layout applied to it. VCD is
# overridable so `make view` can open a trace generated elsewhere (e.g.
# copied back from the remote build box, see README).
GTKWAVE ?= gtkwave
VCD     ?= v586_tb.vcd
GTKW    := waves.gtkw

RUN_ARGS := --cycles=$(CYCLES) --io-port=$(IO_PORT)
ifeq ($(TRACE),1)
RUN_ARGS += --trace=$(VCD)
endif

# No source file carries a `timescale directive, so set the default here.
# 1ps precision is what the 33MHz core clock needs: its period is
# 30303.03 ps, which isn't a whole number of ns (see CLK_PERIOD_PS in
# cpp/sim_main.cpp, which must agree with the precision set here -- VCD
# dump timestamps are passed in precision units).
VERILATOR_FLAGS := \
	--timescale 1ns/1ps \
	-Wno-fatal \
	-Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-COMBDLY \
	-Wno-MULTIDRIVEN -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-IMPLICIT \
	-Wno-INITIALDLY -Wno-BLKANDNBLK

.PHONY: verilate run waves view clean

verilate: $(BIN)

$(BIN): $(SIM_SRCS) cpp/sim_main.cpp
	$(VERILATOR) --cc --exe --build -j $(JOBS) --trace \
		$(VERILATOR_FLAGS) \
		--top-module $(TOP) \
		--Mdir $(OBJDIR) \
		$(SIM_SRCS) cpp/sim_main.cpp \
		-o V$(TOP)

run: $(BIN)
	./$(BIN) $(RUN_ARGS)

waves: TRACE := 1
waves: run
	$(GTKWAVE) -a $(GTKW) $(VCD) &

# Open an existing trace without re-running the sim. Fails with a usable
# hint rather than letting GTKWave open an empty window on a missing file.
view:
	@test -f $(VCD) || { \
		echo "make view: no trace at '$(VCD)'"; \
		echo "  generate one with:  make waves        (run + open)"; \
		echo "                 or:  make run TRACE=1  (run only)"; \
		echo "  or point at another file:  make view VCD=path/to.vcd"; \
		exit 1; \
	}
	$(GTKWAVE) -a $(GTKW) $(VCD) &

clean:
	rm -rf $(OBJDIR) $(VCD)
