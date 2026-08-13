; io_marker_retires -- an OUT instruction produces a real bus write.
;
; CLASS:        retire
; XFAIL:        yes
; DESC:         out 0x80,ax at the reset vector produces a real IO write
; CYCLES:       5000
; EXPECT-PC:    0x000FFC00
; EXPECT-IO:    1
; EXPECT-WRITEIO: 1
;
; This test asserts what the core is SUPPOSED to do and currently does
; not: retire an instruction with an observable side effect. It is
; expected to fail (XFAIL) -- it encodes the central open question from
; core_rtl/README.md, not a regression.
;
; If this test ever PASSES, that is the breakthrough, not a fluke:
; something in vliw's decode-to-execute path started dispatching. The
; suite reports an unexpectedly-passing XFAIL loudly for exactly that
; reason.
;
; Deliberately minimal -- three instructions at the reset vector, no far
; jumps, no sled, nothing that could be blamed for masking the result.
; pc_out is asserted only to confirm the program was actually reached;
; the real assertions are the IO/writeio ones, which are the only
; unambiguous "this executed" evidence this testbench has (PC advancing
; past an instruction is NOT proof -- see core_rtl/README.md).

org 0xE0000                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)

; Pad from ROM base up to the reset vector.
times (0xFFC00 - 0xE0000) db 0x90

; =====================================================================
; 0xFFC00 : reset vector -- the only entry point.
; =====================================================================
reset_vector:
mov ax, 0xc00c
out 0x80, ax                ; the assertion: this must reach m01_AXI
spin:
jmp spin                    ; park (HLT does not stop this core)

; Pad to the end of the 128KiB ROM.
times 0x20000 - ($ - $$) db 0x90
