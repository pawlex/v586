# v586 Verilator testbench

A smoke-test / experimentation harness for the v586 core: instantiates
[`example/v586_example_top.v`](../example/v586_example_top.v) (which wraps
`core_rtl`'s `v586` module) against a simulation-only memory model, and
runs it under Verilator for a fixed number of cycles.

For the current state of the reset-vector/execution-pointer investigation
this testbench has been used for (what's confirmed, what's open, next
steps), see [`../core_rtl/README.md`](../core_rtl/README.md) -- that's
the living status document. This file covers how to actually build, run,
and extend the testbench.

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

**Known gap:** no 20-bit real-mode address wraparound -- addresses are
flat 32-bit here, but real 8086/286-class real-mode hardware wraps at
the 1MB boundary (`0xFFFFF + 1 -> 0x00000`). The fetch-bus address has
been observed climbing steadily past `0x100000` into unmapped space
without wrapping. `rom/boot.asm` works around this by keeping all of
its code within the mapped ROM window (`0xE0000`-`0xFFFFF`) rather than
fixing it in the memory model (see below).

## Make targets

Two makefiles: [`sim/Makefile`](Makefile) builds and runs the simulation,
[`sim/rom/Makefile`](rom/Makefile) assembles the boot ROM. You rarely
need the second one directly -- `make run` regenerates the ROM itself
when `boot.asm` changes.

### `sim/Makefile`

| Target     | What it does                                                          |
|------------|-----------------------------------------------------------------------|
| `verilate` | Build `obj_dir/Vv586_tb_top` and stop. **This is what bare `make` does** -- there's no `all` target, and `verilate` is first. |
| `run`      | Build if needed, re-assemble the ROM if `rom/boot.asm` changed, then run. |
| `test`     | Run the frozen ROM test suite (`rom/tests/*.asm`). `make test TEST=<name>` runs one. |
| `waves`    | `run` with `TRACE=1`, then open the result in GTKWave.                  |
| `view`     | Open an **existing** VCD in GTKWave without re-running the sim.        |
| `clean`    | Remove `obj_dir/` and the VCD. Leaves `rom/` alone.                    |

```sh
cd sim
make run                    # build (if needed) + run, 20000 cycles, no trace
make run CYCLES=200000      # override the cycle count
make run TRACE=1            # also write v586_tb.vcd
make run QUIET=1            # summary only, no per-event lines
make run IO_PORT=0x3F8      # log writes to a different I/O port (default 0x80)
make waves                  # run with trace, then open GTKWave with waves.gtkw loaded
make view                   # open an existing v586_tb.vcd -- no re-run
make view VCD=other.vcd     # ...or some other trace file
make clean                  # remove build output and traces
```

Variables (all overridable on the command line, e.g. `make run CYCLES=1000`):

| Variable    | Default        | Meaning                                                    |
|-------------|----------------|------------------------------------------------------------|
| `CYCLES`    | `20000`        | Clock cycles to simulate.                                   |
| `TRACE`     | unset          | `TRACE=1` writes a VCD to `$(VCD)`.                         |
| `QUIET`     | unset          | `QUIET=1` passes `--quiet`: run summary only, no per-event lines. |
| `IO_PORT`   | `0x80`         | I/O port whose writes get logged.                           |
| `JOBS`      | `4`            | C++ build parallelism -- a RAM ceiling, see below.          |
| `VCD`       | `v586_tb.vcd`  | Trace filename, read by `waves`/`view`/`clean`.             |
| `GTKW`      | `waves.gtkw`   | Saved GTKWave signal layout applied by `waves`/`view`.      |
| `GTKWAVE`   | `gtkwave`      | GTKWave binary.                                             |
| `VERILATOR` | `verilator`    | Verilator binary.                                           |
| `NASM`      | `nasm`         | Assembler used when `run` re-generates the ROM.             |

### `sim/rom/Makefile`

| Target  | What it does                                                             |
|---------|--------------------------------------------------------------------------|
| `all`   | Default. `boot.asm` --(`nasm -f bin`)--> `boot.bin` --(`od`)--> `boot.hex`. |
| `clean` | Delete `boot.bin` and `boot.hex`.                                        |

| Variable | Default     | Meaning                                    |
|----------|-------------|---------------------------------------------|
| `NASM`   | `nasm`      | Assembler binary.                            |
| `FLAGS`  | `-f bin`    | NASM flags -- flat binary, no object format. |
| `SRC`    | `boot.asm`  | Source.                                      |
| `OUTPUT` | `boot.bin`  | Flat 128KiB intermediate.                    |
| `HEXOUT` | `boot.hex`  | `$readmemh` image the testbench loads.       |

**Careful with `make -C rom clean`:** it deletes `boot.hex`, which is
*committed* (so the sim runs on a fresh clone without needing `nasm`).
Restore it with `make -C rom` if you have `nasm`, or
`git checkout sim/rom/boot.hex` if you don't.

## Test suite

`make test` runs the frozen ROM suite in [`rom/tests/`](rom/tests). Each
test is one self-describing `.asm`: the program and the expectations
about it live in the same file, so there's no manifest to keep in sync.

```
PASS   cs_ip_encoding         [fetch] far jump target uses CS<<16|IP, not real-mode CS*16+IP
XFAIL  io_marker_retires      [retire] out 0x80,ax at the reset vector produces a real IO write
```

All tests share **one compiled model**. The ROM is selected at runtime
via a `+rom=<path>` plusarg (see `axi_sim_mem.v`), so adding a test costs
an assemble, not a ~3-minute re-elaboration. You can drive it by hand
too:

```sh
./obj_dir/Vv586_tb_top +rom=rom/tests/cs_ip_encoding.hex --cycles=400 \
    --expect-pc=0x000E1234 --expect-not-pc=0x0000F314
```

### `fetch` vs `retire` -- the distinction that matters

Every test declares a `CLASS`, and it is the most important field in the
file:

- **`fetch`** asserts where the fetch/PC pointer goes. These pass today.
- **`retire`** asserts that an instruction produced a real bus side
  effect (an IO write, a RAM store, a `writeio_req` pulse). These are
  marked `XFAIL` -- they encode the central open question from
  [`../core_rtl/README.md`](../core_rtl/README.md), not a regression.

Conflating the two is the single most expensive mistake made in this
investigation: `pc_out` advancing correctly past an instruction is **not**
evidence that it executed. Keep a test's assertions consistent with its
class, and never "fix" a red `retire` test by weakening it into a `fetch`
assertion -- that would delete the finding.

An `XFAIL` that starts passing is reported as **XPASS** and fails the
suite deliberately, with a banner. That is the signal the retirement
investigation is waiting for, and it must not scroll past unnoticed.

### Adding a test

Drop a `.asm` in `rom/tests/` -- the build and runner pick it up with no
other edits. Directives are read from the leading comment block:

| Directive        | Meaning                                             |
|------------------|-----------------------------------------------------|
| `CLASS:`         | `fetch` or `retire` (see above).                    |
| `DESC:`          | One-line description shown in the results.          |
| `CYCLES:`        | How long to run (default 20000).                    |
| `XFAIL:`         | `yes` -- expected to fail today.                    |
| `EXPECT-PC:`     | `pc_out` must reach this address. Repeatable.       |
| `EXPECT-NOT-PC:` | `pc_out` must never reach it. Repeatable.           |
| `EXPECT-IO:`     | Exact count of IO writes to the watched port.       |
| `EXPECT-RAM:`    | Exact count of RAM writes.                          |
| `EXPECT-WRITEIO:`| Exact count of `writeio_req` pulses.                |

A test with no `EXPECT-*` directives is reported as an `ERROR`, not a
pass -- an assertion-free test would otherwise always succeed.

Make the assertion *discriminating*: pick expectations that only hold if
the behaviour under test is real. `cs_ip_encoding` targets
`0x000E:0x1234` rather than the reset vector precisely because a jump
landing back on `0xFFC00` would "pass" just by being where execution
already was.

### How the two makefiles fit together

`rom/boot.hex` is read by `$readmemh` when the **simulation starts**,
not when the model is compiled -- so it's a prerequisite of `run`, not
of the Verilator build. `make run` therefore re-assembles the ROM when
`rom/boot.asm` is newer, and *without* that dependency, editing
`boot.asm` and re-running would silently simulate the previous ROM
image. If `boot.asm` is newer but `nasm` isn't installed, `run` warns
and simulates the committed `boot.hex` rather than failing:

```
warning: rom/boot.asm is newer than rom/boot.hex, but 'nasm' is
         not installed -- simulating the committed rom/boot.hex as-is.
```

## Building and running

The trace prints exactly three `[cycle NNN] ...` line types (everything
else -- `useq_ptr` toggling, `m00_AXI` AR fetch activity, `iack` -- is
still tracked silently for the run summary, just not printed per-event,
since fetch/prefetch traffic isn't evidence of real execution):

- `dbg_pc_out = 0xXXXXXXXX` on every change.
- `RAM WRITE addr 0xXXXXXXXX <= 0xXXXXXXXX` on every real write to the
  RAM region seen on `m00_AXI` (`axi_sim_mem.v`'s
  `dbg_ram_wr_valid`/`waddr`/`wdata`).
- `IO WRITE port 0xXX <= 0xXX` on every write to `IO_PORT` (default
  `0x80`, the classic PC "POST code" debug port) seen on `m01_AXI`
  (`axi_io_stub.v`'s `dbg_io_wr_valid`/`waddr`/`wdata`).

All three are suppressed by `--quiet`/`QUIET=1`, and all three get a
count in the run summary regardless. There's also a fourth debug signal,
`writeio_req`/`writeio_data` (`v586_top.v`'s `dbg_writeio_req`/
`dbg_writeio_data` -- the internal core<->biu32_axi I/O-write handshake,
verified to be the literal same net as `vliw`'s own output ports with no
intermediate logic), printed the same way when it pulses; see
`core_rtl/README.md` for why that one exists.

These are all testbench-only additions (`rtl/axi_sim_mem.v`,
`rtl/axi_io_stub.v`, plus `core_rtl/v586_top.v`'s `dbg_writeio_*` ports
for the one that reaches into `core_rtl`) -- see "Adding a new debug
trace point" below to add your own.

`make run` builds `obj_dir/Vv586_tb_top` from `core_rtl/*.v` + `gate_rtl/*.v`
+ `example/v586_example_top.v` + this directory's `tb/`/`rtl/`/`cpp/`
sources, then runs it. Rebuilds happen automatically when any source file
changes (standard Make dependency tracking).

`JOBS` controls C++ build parallelism (default 2). The generated model
is large (the gate-level netlist is ~74k lines) and each parallel `g++`
job can use well over 1GB of RAM, so treat this as a **RAM ceiling, not
a core count** -- don't raise it to `nproc` without the memory to back
it. Measured on the 8-core/5GB machine this was developed on:

| `-j` | Result                                                     |
|------|------------------------------------------------------------|
| 8    | OOM-killed -- free memory hit ~290MB with 8 `cc1plus` live |
| 4    | OOM-killed                                                 |
| 3    | Completed in 3:04, 1.6GB peak RSS, on an otherwise idle box |
| 2    | Current default                                            |

The tell is:

```
g++: fatal error: Killed signal terminated program cc1plus
```

`-j 3` did complete once, but only with ~3.7GB free and nothing else
running -- it's close enough to the edge that the default sits one
below. How much headroom you have depends on what else is on the
machine; drop further if needed:

```sh
make run JOBS=1
```

### On a remote machine over SSH (no rsync available)

This was developed partly on a separate Linux box (`debiamond`) reached
over plain SSH, since Verilator/GTKWave live there but the editing
happens elsewhere. `rsync` wasn't installed on the remote end, so sync
with `tar` over an SSH pipe instead of `scp -r`/`rsync -a`:

```sh
# from the repo root, on the machine with the edited source
COPYFILE_DISABLE=1 tar czf - --exclude='obj_dir' --exclude='.DS_Store' \
  core_rtl gate_rtl example sim | ssh <host> 'mkdir -p ~/v586 && tar xzf - -C ~/v586'

ssh <host> 'cd ~/v586/sim && make run CYCLES=200000 JOBS=1 2>&1 | tail -100'
```

`COPYFILE_DISABLE=1` avoids macOS writing `._*` AppleDouble resource-fork
files into the tarball, which a Linux GNU `tar` on the other end will
otherwise complain about (harmlessly) or, worse, extract as junk files.
Always `make clean` before syncing (or `--exclude='obj_dir'`) --
Verilator's build output is architecture-specific and shouldn't cross
machines.

### Inspecting waveforms offline (GTKWave)

`make waves` runs a traced sim and opens `v586_tb.vcd` in GTKWave with
[`waves.gtkw`](waves.gtkw) pre-loaded -- a saved signal layout covering
the testbench's `mon_*` monitor ports plus the deeper internal
useq/purge/code_addr signals this investigation has been tracing by hand
via VCD parsing.

`make view` opens an already-generated trace with the same layout but
*without* re-running the simulation -- use it to re-open the trace from
a long run (a traced 2M-cycle run takes ~30s and writes a large VCD)
rather than paying for it again, or to inspect a trace copied back from
the remote build box:

```sh
make view                   # opens ./v586_tb.vcd
make view VCD=path/to.vcd   # opens some other trace
```

Both are just wrappers around:

```sh
gtkwave -a waves.gtkw v586_tb.vcd
```

If you add new debug ports (see "Adding a new debug trace point"
below), add their VCD hierarchical path to `waves.gtkw` too -- get the
exact path with e.g.:

```sh
grep -E '^\s*\$var' v586_tb.vcd | grep <signal_name>
```

(the scope nesting shown by `$scope`/`$upscope` lines above a `$var`
line gives the full dotted path, e.g.
`TOP.v586_tb_top.u_dut.u_v586.ucore.i_useq.purge`).

## Clock and timescale

The core input clock is modelled at **33 MHz**. Verilator is invoked
with `--timescale 1ns/1ps` (nothing in the RTL carries its own
`` `timescale ``), so simulation time and every VCD timestamp are in
picoseconds, and GTKWave shows a real time axis instead of the
meaningless one you get from the 1ps/1ps default.

33 MHz has a period of 30303.0303... ps, which is not a whole
picosecond. `cpp/sim_main.cpp`'s `CLK_PERIOD_PS` rounds it to 30303 ps
-- a modelled 33.000033 MHz, ~1 ppm fast, far below anything this
testbench measures. That rounding is never accumulated: clock-edge
times are computed from the cycle index (`cycle * CLK_PERIOD_PS`) rather
than by repeated addition, so a multi-million-cycle run cannot drift.

`CLK_PERIOD_PS` and the Makefile's `--timescale` precision have to stay
in agreement -- VCD dump timestamps are passed in timeprecision units.
The run summary reports simulated wall-clock time (e.g. `simulated time
: 30.303 us @ 33.000 MHz`), which is the quick way to confirm both are
still lined up.

## Boot image (`rom/boot.hex`)

The ROM default-fills as a flat NOP (`0x90`) sled across the whole
128KiB window (see `axi_sim_mem.v`'s init loop). `rom/boot.asm` is
NASM-assembled (`rom/Makefile`) into a full 128KiB flat binary that
overrides the whole image -- see the header comment in `rom/boot.asm`
for the current layout in detail, but in short:

```
0xFFC00 : trap_0xFFC00  -- confirmed real hardware reset vector; start
                           marker, then a one-time far jump (0xEA) to
                           sled_start
0xE0000 : sled_start    -- landing marker, then a straight-line,
                           non-repeating NOP sled
0xFFB00 : end_marker    -- reached once the whole sled has been walked;
                           fires a marker, then parks in a spin loop
```

This replaced an earlier version that far-jumped `trap_0xFFC00` back to
a classic-reset-vector section at `0xFFFF0`, forming a closed
8-instruction loop -- see `core_rtl/README.md`'s investigation log for
why that couldn't rule out "retirement lags prefetch" (a closed loop
can't explore new bytes no matter how long it runs) and what the
non-looping replacement above has shown so far. `sled_start` lands at
ROM base rather than continuing forward from `0xFFC00` because the
reset vector alone only has ~1KiB of forward room before the ROM/1MB
ceiling (see the wraparound gap above); landing at `0xE0000` instead
gives the sled the full ~126KiB down to `end_marker` to walk, all still
inside mapped ROM.

### Adding your own test code

Edit `rom/boot.asm` (NASM syntax, `org 0xE0000` matching ROM base) and
run `make -C rom` (or just `make run` from `sim/`, which rebuilds
`boot.hex` automatically via `make`'s dependency tracking) -- no more
hand-encoding bytes. `rom/Makefile` assembles it with `nasm -f bin` into
a flat 128KiB `boot.bin`, then converts that to a `$readmemh`-compatible
one-byte-per-line `boot.hex` via `od`/`tr`/`grep` (not `xxd`, which
isn't installed on every machine this has been developed on).

Far jumps (`0xEA`, `JMP ptr16:16`) are the confirmed-reliable way to
redirect execution -- see `core_rtl/README.md`'s major finding that the
fetch address is a raw `{CS,IP}` concatenation, not real-mode segment
math, so `jmp segment:label` in NASM (which just truncates the label to
its low 16 bits for the offset field) lines up with actual hardware
behavior here. A `0x66`-prefixed 32-bit near jump was tried once and
did not land where intended (see the disambiguation-trap finding) --
prefer `0xEA` far jumps for new traps/tests.

### Adding a new debug trace point

To expose another internal signal as a top-level monitor port (the
`dbg_useq_ptr`/`dbg_pc_out` pattern), thread it through the hierarchy:
add an output port at the signal's home module, then re-expose it at
each level up to `core_rtl/v586_core.v` -> `core_rtl/v586_top.v` ->
`example/v586_example_top.v` -> `sim/tb/v586_tb_top.v` (as a `mon_*`
port there, `assign`ed from the threaded-through wire). See
`core_rtl/v586_core.v`'s `dbg_useq_ptr`/`dbg_pc_out` additions for the
exact pattern to copy.

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
- No 20-bit real-mode address wraparound (see "Memory map" above).
- `dbg_pc_out` is **not reliable evidence of real execution** during at
  least the first several thousand cycles after reset -- see
  `core_rtl/README.md` for why. Don't trust an early `dbg_pc_out` value
  without corroborating it against `dbg_useq_ptr` and/or a byte-level
  trace of what's actually being decoded.
- No test beyond the reset-vector/trap experiments has been run yet --
  this is scaffolding and an active investigation, not a validated test
  suite.
