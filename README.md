# v586

586 compatible soft core for FPGA in verilog with AXI4 interface

---

## Compatibility findings

Results from driving this core under the Verilator testbench in
[`sim/`](sim/). Short version: **the core executes correctly, but it has
no segmentation, so it cannot run real-mode x86 software such as DOS.**
It behaves as a flat 32-bit machine, which is also how the vendor's own
boot ROM ([`soc_rtl/boot.mem`](soc_rtl/boot.mem)) uses it.

### The core does work

Worth stating plainly, because two integration defects (below) initially
made it look otherwise. Verified by direct measurement:

- Executes a long `LOOP` with exact arithmetic — `CX` counts down
  `0xFFFE, 0xFFFD, 0xFFFC, …` monotonically, one decrement per iteration,
  sustained over 70,000+ I/O writes and 57 ms of simulated time at 33 MHz
- Memory writes and reads work, round-tripped through the testbench RAM
  array (`mov [addr],eax` then `mov eax,[addr]` returns the stored value,
  with the register provably clobbered in between)
- I/O writes reach the bus with correct port and data
- `MOV CR0,EAX` sticks — `CR0` reads back with `PE` set
- Segment registers load and read back correctly (`8E D8` / `8C D8`)

### Why real-mode / DOS compatibility is not achievable

**Segment registers do not participate in address generation.** They are
loadable and readable architectural state, but contribute nothing to the
computed address — in either mode:

| `CR0.PE` | `DS` | access | landed at | real x86 would give |
|---|---|---|---|---|
| 0 | untouched | `mov [0x3000]` | `0x00003000` | `0x00003000` |
| 0 | `0x0008` | `mov [0x100]` | `0x00000100` | `0x00000180` |
| 0 | `0x0100` | `mov [0x0]` | `0x00000000` | `0x00001000` |
| 1 | `0x0100` | `mov [0x0]` | `0x00000000` | `0x00001000` |

The base contribution is zero in every case — not `<<4`, not `<<16`, no
shift at all. There is no segment-base adder in the data path.

**No descriptor machinery.** Loading `DS = 0x0100` in protected mode with
`GDTR` uninitialised (limit 0) is a guaranteed `#GP` on real x86. Here it
does not fault, and reads back cleanly. The core performs no descriptor
lookup and no limit check, so `LGDT` has nothing to feed.

**Far jumps ignore the selector.** `EA` reads the four bytes following
the opcode as a flat 32-bit absolute target:

| encoding | bytes after `EA` | landed at |
|---|---|---|
| `jmp 0xF000:0xE05B` (16-bit) | `5B E0 00 F0` | `0xF000E05B` |
| `jmp 0x0001:0x00020000` (32-bit) | `00 00 02 00` | `0x00020000` |
| `jmp 0xBEEF:0x00123456` (32-bit) | `56 34 12 00` | `0x00123456` |

Real x86 would put the first at `0x000FE05B`. The selector is discarded.

**Default operand size is 32-bit from reset.** `boot.mem` opens with
`B8 01 00 00 00`, which only parses as `mov eax,1`. 16-bit real-mode
binaries mis-decode from their first instruction.

### Consequences

- **Real mode, unreal / "big real" mode, and virtual-8086 are all
  impossible.** Each requires `base = selector << 4` hardware that does
  not exist here, in any mode.
- **A custom BIOS cannot bridge the gap.** DOS's own binaries
  (`MSDOS.SYS`, `COMMAND.COM`, applications) are full of far calls,
  segment loads, and segment arithmetic. Those are not under the
  integrator's control.
- **Paging cannot substitute.** It is 4 KB-granular and passes the low 12
  address bits through unchanged, while real-mode segmentation is 16-byte
  granular. Only selectors that are multiples of `0x100` would be
  expressible; the other 255/256 are unreachable by any page table.

None of this makes the core defective — it is a coherent flat 32-bit
design. `boot.mem` sets `CR0.PE`, far-jumps with selector `0x0000`, and
never loads a segment register at all (zero `8E` opcodes in the image).
The design is used flat by its own firmware. It simply is not an x86 in
the sense DOS requires.

### Why this isn't practically fixable

In principle the gap is an ordinary design change: add segment-base
addition to the address path and give the segment registers somewhere to
feed. **If this core shipped as behavioral RTL, that would be tractable
work** — a bounded change to a known part of the datapath, with the
testbench here to verify it.

It doesn't. Every block that would have to change is delivered as a
synthesized gate-level netlist, with no surviving behavioral structure —
identifiers like `n_36919`, ~74k lines total:

| block | file | form |
|---|---|---|
| `useq` — code-path address generation | `core_rtl/v586_useq.v` | netlist |
| `Dtlb` — data-path translation | `core_rtl/v586_dtlb.v` | netlist |
| `vliw` — execution datapath | `core_rtl/v586_vliw.v` | netlist |

The readable behavioral files (`acu.v`, `arithbox.v`, `datacache.v`,
`realign.v`, `shiftbox.v`, `synthetic_op.v`) are all peripheral to this.
`acu.v` is the closest tease: it's the address-calculation unit and it
*is* readable — but it only computes the effective address
(base + index + displacement) and emits a 3-bit `seg_src` naming which
segment register to use. It never adds a segment base. The part you'd
need to modify is downstream, in the netlist.

Adding a functional unit to a synthesized netlist means reconstructing
the surrounding logic well enough to splice into it correctly, then
re-verifying a core you don't have a golden model for. That's a
reverse-engineering project in its own right, not a patch — and the
payoff would be a core that still needs every other x86 behavior
validated from scratch (flags, BCD, string ops, interrupts, prefixes,
protected mode). Proven open cores like ao486 already clear that bar.

So this is a **won't-fix, not a can't-understand**. The behavior is fully
characterized and reproducible; it just isn't worth the surgery.

### Integration defects found

Both are in hand-written wrapper RTL, not the netlist, and both will bite
anyone bringing this core up:

- **`m01_AXI_BREADY` is never driven.** It appears only in the port list
  and declaration of [`core_rtl/v586_top.v`](core_rtl/v586_top.v); the
  memory-port equivalent *is* tied high (`assign m00_AXI_BREADY = 1'b1;`).
  The I/O write-response channel therefore never completes, and the bus
  deadlocks after **exactly one I/O write** against any AXI-compliant
  slave. Present in the original monolithic `v586.v` too, so it was not
  introduced by the module split. The testbench works around it without
  modifying the DUT.
- **I/O ports are word-addressed on the bus.** `OUT 0x80, AX` appears on
  `m01_AXI` at byte address `0x200`; `OUT DX,EAX` with `DX=0x3F8` at
  `0xFE0`. Decode with `port = (addr >> 2) & 0x3FF`.

### A retracted earlier finding

Earlier investigation in this repo concluded the fetch address encoded
`{CS, IP}` as `CS<<16 | IP`, "confirmed" across six tests. **That was an
artifact.** All six used the 16-bit `EA` encoding, whose operand bytes
are `[off16][sel16]` — read as one little-endian dword, that is
bit-identical to `sel<<16 | off`. The two models cannot be distinguished
by any 16-bit far jump. The 32-bit encoding separates them, and shows the
selector is simply ignored. See [`core_rtl/README.md`](core_rtl/README.md)
for the full investigation log.

### Reproducing

```sh
cd sim
make test          # frozen ROM regression suite
make run           # exploratory run
```

See [`sim/README.md`](sim/README.md) for the testbench, the ROM build
flow, and how to add test payloads.

## Last-gasp: is there any use case for this core?

DOS is out (above). But the core *does* execute, and it was already in
hand — so before abandoning it, it was evaluated for a different job:
**a chipset validation test bed**, driving a 386SX/486 local bus on an
FPGA board to exercise memory, I/O and peripheral logic. That role needs
correct loads, stores and bus cycles, but *not* x86 fidelity — so the
missing segmentation would not have disqualified it.

Three questions: size, performance, and function. It wins the first two
and still loses.

### Size and performance

Synthesised and placed with the fully open-source flow — **yosys 0.68 +
nextpnr-ecp5** from OSS CAD Suite, no vendor tools. Target **LFE5U-85F**,
CABGA381, speed grade 7, `--out-of-context` (the core's own placement and
timing, without inventing a pinout it would never have).

| core | LUT4 packed | % of 85F | DFF | BRAM | Fmax |
|---|---:|---:|---:|---:|---:|
| PicoRV32 | 1,782 | 2.1% | 573 | 0 | 111.30 MHz |
| VexRiscv Lite | 3,000 | 3.6% | 1,090 | 4 | 102.01 MHz |
| VexRiscv Debug | 3,595 | 4.3% | 1,638 | 10 | 99.06 MHz |
| **v586** | **28,846** | **34%** | 4,737 | 36 | **44.72 MHz** |
| ao486 | 37,895 | 45% | 6,584 | 12 | 32.87 MHz |

Against ao486, v586 is **24% smaller and 36% faster**. It packs far more
efficiently too (+4.4% from synthesis to placement, versus ao486's
+19.8%): it has few carry cells and **zero** distributed-RAM LUTs,
putting its arrays in BRAM instead, while ao486's async-read `altdpram`
cannot map to ECP5's sync-read EBR and is charged against the LUT budget.

None of which matters, because the comparison that decides the role is
the other one: for a job that only needs to drive bus cycles, a RISC-V
does it in **2-4% of the device at 2-3x the clock**. v586 is **8x** the
size of VexRiscv Debug and less than half its Fmax — while offering no
x86 fidelity to justify the difference, and no debug infrastructure
(below) to offset it.

Timing headroom compounds the gap. The RISC-V options sit near 100 MHz
against a bus needing ~33, so they stay closed as the device fills with
chipset logic. On a shared FPGA, tester choice also decides what is left
for the instrumentation that justifies FPGA-based validation in the first
place: ~80k LUT4 with a small core, ~46k with ao486.

### No FPU

"586" implies an integrated FPU, and both cores used exactly 4
`MULT18X18D` — a hint that neither has an 80-bit FP datapath. Tested
directly rather than inferred:

| addr | instruction | PC advance | effect |
|---|---|---|---|
| `0xFFC0B` | `FNINIT` (`DB E3`) | +2, correct | none observed |
| `0xFFC13` | `FLD1` (`D9 E8`) | +2, correct | none observed |
| `0xFFC1B` | `FSTP qword [0x1000]` (`DD 1D ...`) | +6, correct | **no RAM write** |

All three are length-decoded correctly, and the store produced nothing on
a core where stores demonstrably work. Immediately afterwards the decoder
**desyncs**, stepping through the following `MOV`'s immediate bytes one at
a time (`0xFFC21 -> 0xFFC23 -> 0xFFC24 -> 0xFFC25 ...`) instead of
advancing 5 bytes.

There is no evidence of an FPU, and x87 opcodes leave the pipeline
broken. Note the trap: `pc_out` advanced by exactly the right 6 bytes
across `FSTP`. Length-correct PC advancement is *not* execution — the
same confusion that cost this investigation months.

### No debug infrastructure

There is no TAP. Zero occurrences of `tck`, `tms`, `tdi`, `tdo`, `trst`,
`jtag`, `scan_en`, `test_mode`, `ice_` or `probe_` anywhere in
`core_rtl/`. The only native debug port, `debug[4:0]`, appears **twice in
the entire core** — in the port list and its declaration — and is
assigned nowhere. It is a dangling output, the same defect class as
`m01_AXI_BREADY`, which is why every run reports `final debug[4:0] : 0x0`.

Every bit of observability used in this investigation — `dbg_pc_out`,
`dbg_useq_ptr`, `dbg_writeio_*` — was added here by hand-threading ports
through the hierarchy. For a bring-up vehicle that is the wrong starting
point: VexRiscv's debug plugin gives JTAG and GDB attach for 4.3% of the
device.

### Verdict

No use case found. For x86-faithful work, ao486 behaves correctly and
v586 does not. For driving a bus, a RISC-V is an order of magnitude
smaller, twice as fast, and arrives with a debugger. v586 is smaller and
faster than a core that works, which is not a trade.

The exercise was not wasted: it validated the open-source ECP5 flow
end-to-end on real designs, and produced the utilization and timing
numbers the board budget is now built on.
