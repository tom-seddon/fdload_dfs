;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; These addresses refer to locations in some code assembled by 64tass.
; The addresses can't be auto-generated, because two of the 64tass
; source files are mutually dependent.
; 
; If there's a mismatch, the 64tass error message will mention the
; correct value. Assuming the discrepancy is expected, a
; straightforward fix.

framework_select_bank=$229

; default IRQ handler.
framework_default_irq_handler=$277

; Vector for transition routine to be called on each vsync.
framework_transition_routine_addr=$02c2

; Routine that saves the return address ready for the next
; framework_next_part call, selects the main part bank, and jumps to
; $8000.
framework_start_next_part=$267

; address of an RTS instruction in page 2.
framework_page02_rts=$228

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:

