# v586 Verilator testbench

A smoke-test harness for the v586 core: instantiates
[`example/v586_example_top.v`](../example/v586_example_top.v) (which wraps
`core_rtl`'s `v586` module) against a simulation-only memory model, and
runs it under Verilator for a fixed number of cycles.

## Memory map

| Region | Address range        | Size    | R/W | Backing              |
|--------|-----------------------|---------|-----|-----------------------|
| RAM    | `0x00000` - `0x9FFFF` | 640 KiB | RW  | zero-initialized      |
| ROM    | `0xE0000` - `0xFFFFF` | 128 KiB | RO  | `rom/boot.hex`         |

(`0xA0000`-`0xDFFFF` is unmapped -- matches the classic PC memory map's
video/option-ROM window, here just reading as 0 / discarding writes.)

Anything outside both ranges reads as 0 and discards writes (see
[`rtl/axi_sim_mem.v`](rtl/axi_sim_mem.v)) so a stray access can't hang the
bus. `m01_AXI` (I/O space) is backed by [`rtl/axi_io_stub.v`](rtl/axi_io_stub.v),
which always completes immediately (writes discarded, reads return 0) --
there's no real peripheral behind it.

## Reset vector

**Confirmed: 0xFFC00.** First noticed empirically -- an early run against
a zero-filled ROM showed the core issuing a steady, unbroken sequence of
code-fetch bursts starting at physical address 0xFFC00 and incrementing
by 0x10 (one 128-bit fetch line) every 143 cycles, i.e. executing
straight through the zero bytes (`0x00 0x00` decodes as
`ADD [bx+si], al`, a harmless 2-byte fall-through) rather than crashing
or stalling.

That was then confirmed directly from the gate-level netlist. In
[`core_rtl/v586_useq.v`](../core_rtl/v586_useq.v) (the microsequencer /
instruction-fetch address generator), the `iaddr[31:0]` output is built
from 32 individual flip-flops (`addr_reg_0`..`addr_reg_31`, from line
~4903), each an async-clear `notech_reg` (resets to 0) or async-set
`notech_reg_set` (resets to 1) -- the choice of primitive per bit *is*
the reset constant:

| Bits | Primitive | Reset value |
|---|---|---|
| `[9:0]`   | `notech_reg`     | `0000000000` |
| `[19:10]` | `notech_reg_set` | `1111111111` |
| `[31:20]` | `notech_reg`     | `0` |

`0000_0000_0000_1111_1111_1100_0000_0000` = `0x000FFC00`, exactly
matching what the simulation converged on. (The `CD`/`SD` reset net
traced back to the module's general reset distribution -- it also resets
unrelated registers like `purge_cnt`/`purge`/`queue_reg_*` -- so this is
the real power-on reset value, not a coincidental read of some other
control signal.) `0xFFC00`-`0xFFFFF` is exactly 1KB, matching
`soc_rtl/axi_rom.v`'s original 1KB boot ROM size -- so the board-level
boot ROM was always meant to sit there, not at the classic 8086-style
`0xFFFF0` this testbench originally assumed.

## Boot image

[`rom/boot.hex`](rom/boot.hex) places a two-byte infinite loop
(`EB FE` = `JMP $-2`) at ROM offsets `0x1FC00` and `0x1FFF0` (physical
`0xFFC00` and `0xFFFF0` -- both candidate reset addresses, see above).
This is deliberately the simplest possible test: it only exercises
reset, instruction fetch, decode, and a relative branch, and doesn't
depend on any assumption about default data/stack segment bases (unlike
a memory-touching test would). A successful boot looks like the
code-fetch address converging on one of those two addresses and staying
there.

To test something more interesting, edit `rom/boot.hex` (any
`$readmemh`-format hex file, `@offset` directives supported) with real
machine code for whatever you want to exercise.

## Running

```sh
cd sim
make run                    # 20000 cycles, no trace
make run CYCLES=5000        # override cycle count
make run TRACE=1            # also write v586_tb.vcd
make waves                  # run with trace, then open GTKWave
make clean
```

The run prints every m00_AXI instruction-fetch address change and a
summary at the end (PASS/FAIL/INCONCLUSIVE heuristic based on whether the
fetch address converged on the reset vector).

## Known limitations

- The core RTL below each named module's port list is a synthesized
  gate-level netlist (see [`../README`](../README)), so simulation is
  comparatively slow and Verilator will emit a large number of lint
  warnings (mostly `WIDTH`/`UNOPTFLAT`/`CASEINCOMPLETE` from the
  synthesized structure) -- these are suppressed in the `Makefile`
  rather than fixed, since fixing them would mean touching the netlist
  itself.
- `axi_sim_mem.v` and `axi_io_stub.v` are simulation-only: single
  outstanding transaction, no real timing/backpressure modeling beyond
  what's needed to satisfy the AXI4 handshake. Not synthesizable, not
  meant to be.
- No test beyond the reset-vector spin loop has been run yet -- this is
  scaffolding, not a validated test suite.
