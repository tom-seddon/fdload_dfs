;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; must be palatable to both BeebAsm and 64tass
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Main RAM address assignment is deliberately mostly a manual process.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ROM bank assignments.
framework_bank=7

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Zero page
;
loader_decomp_src=$e0
loader_decomp_dest=loader_decomp_src+2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Framework bank layout.
;

; Where the catalogue buffers are stored. 256 bytes/sector*2
; sectors/catalogue*2 catalogues=1024 ($400) bytes.
framework_bank_cat_buffers=$bc00

; Where the framework bank shared code goes.
framework_bank_code_begin=$b800	; inclusive
framework_bank_code_end=$bc00	; exclusive

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Loader's main RAM layout.
;

loader_main_ram_begin=$900	; inclusive
loader_main_ram_end=$e00	; exclusive

loader_main_ram_sector_buffer_0=$900 ; uses the entire page
loader_main_ram_sector_buffer_1=$a00 ; uses the entire page

loader_main_ram_code_begin=$b00	; inclusive
loader_main_ram_code_end=$e00	; exclusive

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Page 2 entry points.
;

; Routines promise to preserve only the registers noted.
; 
; These are entry points rather than vectors.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Loader stuff

; Load a file from disk. Copies the loader routines into main RAM,
; seeks to the right place, then loads+uncompresses the data.
;
; Parameter block for the load:
;
; - word: load address ($0000 means use load address from catalogue)
; - byte: drive number (0 or 2)
; - string: file name, terminated with a 13
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
; Local Variables:
; mode: beebasm
; End:
