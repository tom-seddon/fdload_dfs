;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; must be palatable to both BeebAsm and 64tass
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Main RAM address assignment is deliberately mostly a manual process.
;
; Ranges are denoted by pairs of symbols, X_begin and X_end. _begin is
; inclusive and _end is exclusive.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ROM bank assignments.
framework_bank=7

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Zero page
;
effect_zp_begin=$00
effect_zp_end=$a0

; 
transition_zp_begin=$a0
transition_zp_end=$be

; indicates current state of transition, visually speaking, in some
; transition-dependent fashion.
transition_current_state=$be

; value reserved for requesting something of the transition, again in
; some transition-dependent fashion.
transition_state_request=$bf

; 
music_zp_begin=$c0
music_zp_end=$e0

; 
framework_zp_begin=$e0
framework_zp_end=$100

loader_decomp_src=$e0
loader_decomp_dest=loader_decomp_src+2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Framework bank layout.
;

; Where the catalogue buffers are stored. 256 bytes/sector*2
; sectors/catalogue*2 catalogues=1024 ($400) bytes. Top of the bank
; simplifies layout of the rest.
framework_bank_cat_buffers=$bc00

; Where the framework bank transition code goes.
framework_bank_transitions_begin=$8000
framework_bank_transitions_end=$b800

; Where the framework bank loader code goes. 
framework_bank_loader_code_begin=$b700
framework_bank_loader_code_end=$bc00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Loader's main RAM layout.
;

loader_main_ram_begin=$900
loader_main_ram_end=$e00

loader_main_ram_sector_buffer_0=$900 ; uses the entire page
loader_main_ram_sector_buffer_1=$a00 ; uses the entire page

loader_main_ram_code_begin=$b00
loader_main_ram_code_end=$e00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Page 2 entry points.
;

; Routines promise to preserve only any registers explicitly as
; preserved.
; 
; These are entry points rather than vectors.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Loader stuff

; Load a file from disk. Copies the loader routines into main RAM,
; seeks to the right place, then loads+uncompresses the data.
;
; Paging must be set up so that the parameter block can be read from
; and the load region can be written to.
;
; Parameter block for the load:
;
; - word: load address ($0000 means use load address from catalogue)
; - byte: drive number (0 or 2)
; - string: file name, terminated with a 13
;
; The file name is English case insensitive, as per DFS: 'A'-'Z'
; inclusive and 'a'-'z' inclusive are considered equivalent.
;
; The file name is the name part of the DFS name only. Any file with
; that name will be found, regardless of directory.
;
; If the found file's directory is Z, the file is assumed to be
; compressed with zx02, and will be unpacked automatically. Otherwise,
; it will be loaded verbatim.
;
; Entry: Y (MSB)/X (LSB) points to parameter block
loader_load_file=$200

; Select the framework ROM bank.
;
; Exit: Y = previously selected ROM bank
framework_select_bank=$202

; $204 isn't free for use (it's IRQ1V)

; Decompress data. Copies the loader routines into main RAM, then
; uncompresses the data.
;
; Entry: (loader_decomp_src)=address to unpack from
;        (loader_decomp_dest)=address to unpack to
loader_decomp_data=$206

; Decompress data. Just as loader_decomp_data, for use when the loader
; routine has already been copied into main RAM.
loader_decomp_data_2=$208

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; These addresses refer to locations in some code assembled by 64tass.
; If there's a mismatch, the 64tass error message will mention the
; correct value. Assuming the discrepancy is expected, a
; straightforward fix.

; Address of transition routine to be called on each vsync.
framework_transition_routine_addr=$0276

; Address of transition routine IRQ handler.
framework_transition_irq_handler=$259

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:

