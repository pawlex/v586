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

## Building and running

### On this machine (Verilator already installed)

```sh
cd sim
make run                    # build (if needed) + run, 20000 cycles, no trace
make run CYCLES=200000      # override the cycle count
make run TRACE=1            # also write v586_tb.vcd
make run IO_PORT=0x3F8      # log writes to a different I/O port (default 0x80)
make waves                  # run with trace, then open GTKWave with waves.gtkw loaded
make clean                  # remove build output and traces
```

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

`JOBS` controls C++ build parallelism (default 2). The generated model is
large (the gate-level netlist is ~74k lines); each parallel `g++` job can
use well over 1GB of RAM. On a memory-constrained machine, raise it if
you have RAM to spare, or drop to `JOBS=1` if the build gets OOM-killed
(`g++: fatal error: Killed signal terminated program cc1plus` is the
tell):

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
via VCD parsing. To open it manually against a trace generated some
other way:

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
