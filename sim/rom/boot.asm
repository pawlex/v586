; sim/rom/boot.asm -- v586 non-looping retirement-lag test ROM.
ROMBASE EQU 0xE0000
org ROMBASE                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)

; /* BIOS CODE START /*
times (0xFE05B - ROMBASE) - ($ - $$) db 0x90
;JMP $

bios_start:
MOV ax, cs
xor bx, bx
mov ds, bx
mov es, bx
mov cx, 0xFFFF
.loop:
mov ax, cx
out 0x80, ax
loop .loop

; /* Reset vector and jump table */
times (0xFFFF0 - ROMBASE) - ($ - $$) db 0x90
reset_vector:
; EA on this core is a 32-bit ABSOLUTE jump: it takes the four bytes
; following the opcode as the target and ignores the selector field
; entirely (see ../../README.md). Assembled 16-bit, the operand bytes are
; [off16][sel16], so this encodes 5B E0 0F 00 = 0x000FE05B -- the address
; we actually want. The spec-correct `jmp 0xF000:0xE05B` would encode
; 5B E0 00 F0 = 0xF000E05B, which is unmapped: that experiment is what
; established the absolute-jump behaviour, and it left the core executing
; zeros. Keep this form or the demo below never runs.
jmp 0xF:0xE05B
nop
jmp $
jmp $
jmp $
jmp $
jmp $
; pad to the end of the 128KiB ROM (0x100000) -- dead code, never
; reached (the far jump above never falls through).
times 0x20000 - ($ - $$) db 0x90
