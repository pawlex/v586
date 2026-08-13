; far_jump_absolute -- EA takes a 32-bit ABSOLUTE target; selector ignored.
;
; CLASS:         fetch
; DESC:          EA jumps to a flat 32-bit target; the selector is ignored
; CYCLES:        300
; EXPECT-PC:     0x00123456
; EXPECT-NOT-PC: 0xBF013456
;
; Replaces the earlier `cs_ip_encoding` test, which asserted that the
; fetch address encodes {CS,IP} as CS<<16|IP. That finding was WRONG --
; see the retraction in ../../../core_rtl/README.md. Every test that
; "confirmed" it used the 16-bit EA encoding, whose operand bytes are
; [off16][sel16]; read as one little-endian dword that is bit-identical
; to sel<<16|off, so the two models cannot be told apart by any 16-bit
; far jump.
;
; This test uses the 32-bit encoding (EA off32 sel16), which separates
; them, and a selector that cannot hide:
;
;   EA 56 34 12 00 EF BE   =  jmp 0xBEEF:0x00123456
;
;   4-byte absolute     -> 0x00123456   <- this core
;   sel<<16 + offset    -> 0xBF013456
;   real x86 (sel<<4)   -> 0x001E2346
;
; EXPECT-NOT-PC pins the sel<<16 prediction so a regression back to the
; old (incorrect) model would fail loudly rather than silently pass.

org 0xE0000                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)
times (0xFFC00 - 0xE0000) db 0x90

bits 32
reset_vector:               ; core resets here (iaddr = 0x000FFC00)
jmp 0xBEEF:0x00123456

times 0x20000 - ($ - $$) db 0x90
