; sim/rom/boot.asm -- v586 non-looping retirement-lag test ROM.
;
; Replaces the earlier closed 8-instruction loop (trap_0xFFC00 <->
; reset_vector_0xFFFF0, see core_rtl/README.md's investigation log) with
; a straight-line NOP sled that is walked exactly once, so a long
; simulation run explores genuinely new, previously-unfetched bytes the
; whole way instead of re-treading the same handful of addresses. This
; is core_rtl/README.md TODO items 1 and 4.
;
;   0xE0000            : sled_start -- landing point for the one-time
;                         far jump below; start of the NOP sled.
;   0xFFB00            : end_marker -- reached only after the ~126KiB
;                         sled has been walked once.
;   0xFFC00            : trap_0xFFC00 -- confirmed real hardware reset
;                         vector (core_rtl/README.md's iaddr reset-value
;                         finding). The only true entry point; jumps to
;                         sled_start exactly once per run.
;
; The reset vector (0xFFC00) sits only ~1KiB below the ROM/1MB ceiling,
; so a sled walking *forward* from there alone would run out of mapped
; ROM almost immediately (sim/README.md's "Known limitations" -- no
; 20-bit real-mode wraparound, so falling off 0xFFFFF hits unmapped
; space instead of wrapping to 0x00000). Landing the one-time far jump
; back at 0xE0000 (ROM base) instead gives the sled the full ~126KiB of
; room between there and end_marker, all still safely inside mapped ROM.
;
; Each marker writes a distinct 16-bit value to I/O port 0x80 (`out
; 0x80, ax`) so sim_main.cpp's --io-port=0x80 write logging gives an
; unambiguous "this point was really reached and retired" signal --
; see core_rtl/README.md's note that PC advancement alone is not proof
; of real execution.
;
; Earlier sections of this file (the CS<<16|IP fetch-address encoding
; verification via far jumps to code_0xF0000, and the classic 0xFFFF0
; reset vector) answered their questions -- see core_rtl/README.md --
; and were retired to keep this file focused on the retirement-lag test.

org 0xE0000                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)

; =====================================================================
; 0xE0000 : sled_start -- landing point for the far jump from
; trap_0xFFC00 below. Marks that the jump worked, then falls into a
; long straight-line NOP sled with no jumps, loops, or self-modifying
; code anywhere in it -- every byte from here to end_marker is fetched
; and (if retirement keeps up) retired exactly once.
; =====================================================================
sled_start:
mov ax, 0x5eed
out 0x80, ax

times (0xFFB00 - 0xE0000) - ($ - $$) db 0x90

; =====================================================================
; 0xFFB00 : end_marker -- only reachable by walking the entire sled
; above once. Fires a distinct marker, then parks in a tight
; jump-to-self spin. (HLT was tried previously and confirmed NOT to
; stop this core -- see core_rtl/README.md's trap experiments -- so a
; spin loop is the reliable way to stop making forward progress once
; we have our answer, rather than relying on HLT.)
; =====================================================================
end_marker:
mov ax, 0xfeed
out 0x80, ax
spin_end:
jmp spin_end

; pad up to 0xFFC00 -- dead code, never reached (spin_end above never
; falls through), kept as NOPs purely so the address layout below stays
; exact and self-documenting.
times (0xFFC00 - 0xE0000) - ($ - $$) db 0x90

; =====================================================================
; 0xFFC00 : trap_0xFFC00 -- confirmed real hardware reset vector. The
; only true entry point into this ROM; everything above is reached
; solely via the far jump below, executed exactly once per run.
; =====================================================================
trap_0xFFC00:
mov ax, 0xc00c
out 0x80, ax
jmp 0x000E:sled_start        ; EA far jump (confirmed-reliable
                              ; mechanism, see core_rtl/README.md) to
                              ; 0x000E:0x0000 = physical 0xE0000 under
                              ; the confirmed CS<<16|IP fetch-address
                              ; encoding

; pad to the end of the 128KiB ROM (0x100000) -- dead code, never
; reached (the far jump above never falls through).
times 0x20000 - ($ - $$) db 0x90
