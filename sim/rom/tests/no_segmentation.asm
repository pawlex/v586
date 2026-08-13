; no_segmentation -- the segment base does not reach address generation.
;
; CLASS:      fetch
; DESC:       DS contributes nothing to the computed address
; CYCLES:     2000
; EXPECT-IO:  2
; EXPECT-RAM: 1
;
; Freezes the central compatibility finding: segment registers on this
; core are loadable, readable architectural state that never participates
; in address generation. Not sel<<4, not sel<<16 -- no base at all.
;
; The assertion works by choosing a selector whose base, IF it were
; applied, would push the store OUTSIDE the 640KiB RAM region and so out
; of the RAM-write log entirely:
;
;   DS = 0xF000, store to offset 0
;     base ignored -> 0x00000000   in RAM      -> 1 RAM write  <- this core
;     base = sel<<4 -> 0x000F0000  above RAM   -> 0 RAM writes
;     base = sel<<16 -> 0xF0000000 unmapped    -> 0 RAM writes
;
; So EXPECT-RAM: 1 passes only if the base was ignored. The two markers
; (EXPECT-IO: 2) bracket the store, proving the segment load did not
; fault and the store instruction actually executed -- without them a
; crash before the store would look identical to "base applied".
;
; No 0x66 operand-size prefixes anywhere: this core's prefix handling was
; found unreliable, and a prefix bug would confound the result.

org 0xE0000                 ; ROM base
times (0xFFC00 - 0xE0000) db 0x90

bits 32
reset_vector:
    mov edx, 0x80
    mov eax, 0x0000F000
    mov ds, eax             ; 8E D8 -- DS = 0xF000
    mov eax, 0x11110000
    out dx, eax             ; marker 1: segment load did not fault
    mov eax, 0xDEADBEEF
    mov [0x00000000], eax   ; THE TEST
    mov eax, 0x22220000
    out dx, eax             ; marker 2: store executed
spin:
    jmp spin

times 0x20000 - ($ - $$) db 0x90
