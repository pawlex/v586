; sim/rom/boot.asm -- v586 test ROM, one file, four labeled sections at
; their real physical addresses, NOP (0x90) padding computed between them
; so nothing has to be hand-counted. See sim/README.md and
; core_rtl/README.md for the investigation this supports.
;
;   0xE0000 - 0xEFFFF : NOP padding (64KiB)
;   0xF0000            : code_0xF0000        -- general test code
;   0xFFC00            : trap_0xFFC00         -- confirmed real hardware
;                                                reset vector (see
;                                                core_rtl/README.md's
;                                                iaddr reset-value finding)
;   0xFFFF0            : reset_vector_0xFFFF0 -- classic 8086-style
;                                                reset vector (not what
;                                                this core actually uses,
;                                                but a standard address
;                                                worth testing too)
;
; Each section writes a distinct 16-bit marker to I/O port 0x80
; (`out 0x80, ax`) before doing anything else, so sim_main.cpp's
; --io-port=0x80 write logging gives an unambiguous "this section was
; really reached and retired" signal -- see core_rtl/README.md's note
; that PC advancing past an instruction is NOT by itself proof of real
; execution (an earlier out 0x80 never fired despite pc_out correctly
; stepping past both instructions).

org 0xE0000                 ; ROM base (sim/tb/v586_tb_top.v's ROM_BASE)

; =====================================================================
; 0xE0000 - 0xEFFFF : NOP padding
; =====================================================================
times 0x10000 db 0x90

; =====================================================================
; 0xF0000 : general test code
; =====================================================================
code_0xF0000:
xor ax, ax
mov ds, ax
mov word [ds:0xbeef], ax
mov word [ds:0xbabe], ax
mov ax, 0xbeef
out 0x80, ax

; pad up to 0xFFC00
times (0xFFC00 - 0xE0000) - ($ - $$) db 0x90

; =====================================================================
; 0xFFC00 : trap -- confirmed real hardware reset vector
; =====================================================================
trap_0xFFC00:
mov ax, 0xc00c
out 0x80, ax
cpuid                        ; whatever EAX naturally holds at reset -- no
                              ; 0x66 prefix needed/used, keeps this test
                              ; independent of the earlier operand-size-
                              ; prefix mismatch finding

; pad up to 0xFFFF0
times (0xFFFF0 - 0xE0000) - ($ - $$) db 0x90

; =====================================================================
; 0xFFFF0 : classic 8086-style reset vector
; =====================================================================
reset_vector_0xFFFF0:
mov ax, 0xd00d
out 0x80, ax
;jmp 0x000F:code_0xF0000
jmp 0x000F:trap_0xFFC00
mov ax, 0xdead              ; unreachable if the far jump above works
out 0x80, ax

; pad to the end of the 128KiB ROM (0x100000)
times 0x20000 - ($ - $$) db 0x90
