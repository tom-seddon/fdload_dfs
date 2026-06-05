;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; These addresses refer to locations in some code assembled by 64tass.
; If there's a mismatch, the 64tass error message will mention the
; correct value. Assuming the discrepancy is expected, a
; straightforward fix.

; Transition routine IRQ handler.
framework_transition_irq_handler=$267

; Vector for transition routine to be called on each vsync.
framework_transition_routine_addr=$0284

; Routine that saves the return address ready for the next
; framework_next_part call, selects the main part bank, and jumps to
; $8000.
framework_start_next_part=$295

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:

