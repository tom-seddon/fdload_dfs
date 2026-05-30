;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ROM bank assignments.
framework_bank=7

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; page 2 entry points.
;
; Routines promise to preserve only the registers noted.

;
; These are entry points rather than vectors.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Loader stuff

; Load a file from disk. Will copy the loader routine into main RAM,
; seek to the right place, then load+uncompress the data.
;
; Follow the jsr with the following data:
;
; - word: load address ($0000 means use load address from catalogue)
; - byte: drive number (0 or 2)
; - name: terminated with a 13
;
; entry:
loader_load_file=$200

; $202 isn't free for use (it's BRKV)
; $204 isn't free for use (it's IRQ1V)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
