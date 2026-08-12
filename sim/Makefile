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
#   make clean          - remove build output and traces
#
# JOBS controls C++ build parallelism (default 2). The generated model is
# large (v586's gate-level netlist is ~74k lines), and each parallel g++
# job on it can use well over 1GB of RAM -- on a memory-constrained
# machine, -j (all cores) will OOM-kill cc1plus. Lower JOBS (even to 1)
# if that happens; raise it if you have RAM to spare.

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
JOBS    ?= 2
IO_PORT ?= 0x80

RUN_ARGS := --cycles=$(CYCLES) --io-port=$(IO_PORT)
ifeq ($(TRACE),1)
RUN_ARGS += --trace=v586_tb.vcd
endif

VERILATOR_FLAGS := \
	-Wno-fatal \
	-Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-COMBDLY \
	-Wno-MULTIDRIVEN -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-IMPLICIT \
	-Wno-INITIALDLY -Wno-BLKANDNBLK

.PHONY: verilate run waves clean

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
	gtkwave -a waves.gtkw v586_tb.vcd &

clean:
	rm -rf $(OBJDIR) v586_tb.vcd
