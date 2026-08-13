; io_write_retires -- OUT produces a real bus write (instruction retirement).
;
; CLASS:      retire
; DESC:       OUT retires and reaches m01_AXI with correct data
; CYCLES:     2000
; EXPECT-PC:  0x000FFC00
; EXPECT-IO:  3
;
; Replaces `io_marker_retires`, which was marked XFAIL on the belief that
; this core never retires an instruction with an observable side effect.
; That belief was wrong on two counts, both defects outside the core:
;
;   1. The monitor compared the raw m01_AXI byte address against the port
;      number, but I/O is word-addressed (port = addr>>2), so the counter
;      could never match. See sim/cpp/sim_main.cpp.
;   2. v586_top.v never drives m01_AXI_BREADY, so the I/O write-response
;      channel never completes and the bus deadlocks after exactly ONE
;      write. The testbench supplies the acknowledge instead (see
;      tb/v586_tb_top.v); the DUT is left untouched.
;
; The old test also assembled as 16-bit code, which mis-decodes on a core
; whose default operand size is 32-bit from reset -- so it would have
; failed even with both defects fixed. This version is 32-bit and uses
; the `out dx,eax` form that the vendor's own boot.mem uses.

org 0xE0000                 ; ROM base
times (0xFFC00 - 0xE0000) db 0x90

bits 32
reset_vector:
    mov edx, 0x80
    mov eax, 0x11110000
    out dx, eax
    mov eax, 0x22220000
    out dx, eax
    mov eax, 0x33330000
    out dx, eax
spin:
    jmp spin                ; HLT does not stop this core -- park instead

times 0x20000 - ($ - $$) db 0x90
