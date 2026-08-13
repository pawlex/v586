; cs_ip_encoding -- the fetch address is {CS,IP}, not real-mode CS*16+IP.
;
; CLASS:         fetch
; DESC:          far jump target uses CS<<16|IP, not real-mode CS*16+IP
; CYCLES:        400
; EXPECT-PC:     0x000E1234
; EXPECT-NOT-PC: 0x0000F314
;
; Freezes core_rtl/README.md's major finding as an executable assertion.
;
; The jump must land somewhere that ONLY one of the two candidate models
; predicts, and it must not be the address it started from -- a jump from
; 0xFFC00 to 0x000F:0xFC00 would land back on 0xFFC00 and "pass" purely
; because that is the reset vector, proving nothing. So the target here
; is a different segment AND a non-zero offset, giving two clearly
; distinct predictions:
;
;   CS<<16 | IP = 0x000E0000 | 0x1234 = 0x000E1234   <- this core
;   CS*16  + IP = 0x000E0    + 0x1234 = 0x0000F314   <- real-mode x86
;
; 0x000E1234 is inside the mapped ROM (NOP fill), so on a correct landing
; the PC simply walks forward from there. 0x0000F314 is in RAM, which
; reads as zeros -- a landing there would be unmistakable in a trace.
;
; This is a FETCH-class test: it asserts where the fetch/PC pointer goes,
; NOT that anything retired. Do not add marker/IO assertions here -- see
; the retire-class tests for that, and core_rtl/README.md for why the two
; must never be conflated.

org 0xE0000                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)

; Pad from ROM base up to the reset vector.
times (0xFFC00 - 0xE0000) db 0x90

; =====================================================================
; 0xFFC00 : reset vector -- the only entry point.
; =====================================================================
reset_vector:
jmp 0x000E:0x1234           ; EA 34 12 0E 00

; Pad to the end of the 128KiB ROM. Never reached: the far jump above
; does not fall through.
times 0x20000 - ($ - $$) db 0x90
