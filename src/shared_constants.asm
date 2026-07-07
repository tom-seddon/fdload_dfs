;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; must be palatable to both BeebAsm and 64tass
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Main RAM address assignment is deliberately mostly a manual process.
;
; Ranges are denoted by pairs of symbols, X_begin and X_end. _begin is
; inclusive and _end is exclusive.
;
; Bools must be numbers, 0 (false) or other (true). beebasm only
; accepts TRUE/FALSE, and 64tass only accepts true/false... sigh...
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; if true, enable the b2 debug stuff.
b2_debug=1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ROM bank assignments.
framework_bank=7
music_bank=6
part_other_bank=5
part_main_bank=4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

memory_clear_value=$00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Zero page
;
effect_zp_begin=$00
effect_zp_end=$a0

; reserved for use by transition effect while running. If no
; transition effect running, this whole region can be used.
transition_zp_begin=$a0
transition_zp_end=$bd

; indicates current state of transition, visually speaking, in some
; transition-dependent fashion.
;
; This location is also free if no transition effect running.
transition_current_state=$be

; value reserved for requesting something of the transition, again in
; some transition-dependent fashion.
;
; This location is also free if no transition effect running.
transition_state_request=$bf

; reserved for use by music, and not available for general use.
music_zp_begin=$c0
music_zp_end=$e0

; reserved for use by framework and loader, and not available for
; general use except as otherwise described.
framework_zp_begin=$e0
framework_zp_end=$100

; arguments for loader_decomp_data.
framework_decomp_src=$e0
framework_decomp_dest=framework_decomp_src+2

; the default IRQ handler increments this on each T2 timeout.
framework_t2_counter=$fe

; the default IRQ handler increments this on each vsync.
framework_vsync_counter=$ff


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
framework_bank_loader_code_begin=$b600
framework_bank_loader_code_end=$bd00

; framework bank entry points.
framework_bank_boot=$8000
framework_bank_init_transition=$8003

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Music bank layout.
;

; music bank entry points.
music_bank_init=$8000
music_bank_update=$8003

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Loader's main RAM layout.
;

; loader main RAM usage for disk loading.
;
; When calling loader_load_file, this entire region will be
; overwritten
loader_main_ram_begin=$900
loader_main_ram_end=$e00

loader_main_ram_sector_buffer_0=$900 ; uses the entire page
loader_main_ram_sector_buffer_1=$a00 ; uses the entire page

; loader main RAM usage for decompression only - as above, minus the
; disk buffers.
;
; When calling loader_decomp_data, this entire region will be
; overwritten.
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

; Load a file from disk. Copies the loader routines into main RAM,
; seeks to the right place, then loads+uncompresses the data. A
; blocking call that will return once the data is loaded.
;
; Parameter block for the load:
;
; - word: load address (may not be zero page) (or USE_FILE_LOAD_ADDRESS to use file's)
; - word: exec address (may not be zero page) (or USE_FILE_EXEC_ADDRESS to use file's, or NO_FILE_EXEC_ADDRESS for no exec)
; - byte: ROM bank to select during the load, or $ff to use the current value
; - byte: drive number (0 or 2)
; - string: file name, terminated with a 13
;
; The exec address, if used, is called with the requested ROM bank in
; place.
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
framework_load_file=$200

USE_FILE_LOAD_ADDRESS=$0000
USE_FILE_EXEC_ADDRESS=$0000
NO_FILE_EXEC_ADDRESS=$FF00

; stop current transition.
framework_stop_transition=$202

; $204 isn't free for use (it's IRQ1V)

; Decompress data. Copies the loader routines into main RAM, then
; uncompresses the data.
;
; Entry: (loader_decomp_src)=address to unpack from
;        (loader_decomp_dest)=address to unpack to
framework_decomp_data=$206

; Decompress data. Just as loader_decomp_data, for use when the loader
; routine has already been copied into main RAM.
framework_decomp_data_2=$208

; Update music. For use from an IRQ routine or whatever.
framework_update_music=$20a

; 
framework_set_default_irq_handler=$20c

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; b2 debug stuff.
;
; The symbol group numbers have to match those set in
; tests\tom\boot_screens_disk.json. (This is a WIP mechanism, as yet
; not very scalable.)

b2_debug_data=$fc51
b2_debug_cmd=$fc52
b2_debug_status=$fc52

; group 0 is deliberately unused.
symbol_group_screens1_mode1=1
symbol_group_screens1_mode5=2

; 
symbol_group_first_framework_group=200

; general framework bank contents, plus zero page workspace.
symbol_group_framework_bank=200

; loader code at its main RAM addresses.
symbol_group_main_ram_loader=201

; boot loader.
symbol_group_boot=202

; music bank.
symbol_group_music_bank=203

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:

