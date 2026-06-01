include "../shared_constants.asm"

VERBOSE=1
cpu 1				; 65c02

org framework_bank_transitions_begin
guard framework_bank_transitions_end

lda #0
sta 0

save "",framework_bank_transitions_begin,P%

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
