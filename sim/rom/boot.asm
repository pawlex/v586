org 0xE0000                 ; Base address of the 128KiB ROM (sim/tb/v586_tb_top.v's ROM_BASE)

; =====================================================================
; Main ROM Area (Padded with NOPs)
; =====================================================================

; Pad with NOPs from the start up to absolute address 0xFFFF0
; 0xFFFF0 - 0xE0000 = 131056 bytes (0x1FFF0) from the origin ($$)
times 0x10000 db 0x90

rom_start:
xor ax, ax
mov ds, ax
mov word dx, [ds:0xbeef]
mov word dx, [ds:0xbabe]
mov ax, 0xbeef
out 0x80, ax

; Pad with NOPs from the start up to absolute address 0xFFFF0
; 0xFFFF0 - 0xE0000 = 131056 bytes (0x1FFF0) from the origin ($$)
times 0x1FFF0 - ($ - $$) db 0x90

; =====================================================================
; Target Location: 0xFFFF0 (Standard x86 Reset Vector)
; =====================================================================
reset_vector:
mov ax, 0xd00d
out 0x80, ax
jmp 0x000F:rom_start       ; Typical far jump to your main BIOS code
mov ax, 0xdead
out 0x80, ax

; Pad the remaining bytes to the absolute end of the 128KiB ROM (0x100000)
times 0x20000 - ($ - $$) db 0x90

