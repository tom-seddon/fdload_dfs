MACRO do_symbol_group index,cmd
pha
lda #index:sta b2_debug_data
lda #cmd:sta b2_debug_cmd
pla
ENDMACRO

MACRO enable_symbol_group index
do_symbol_group index,b2DebugCommand_EnableSymbolGroup
ENDMACRO

MACRO disable_symbol_group index
do_symbol_group index,b2DebugCommand_DisableSymbolGroup
ENDMACRO

; for use when overwriting the loader main RAM area at
; loader_main_ram_begin...loader_main_ram_end.
MACRO disable_loader_symbol_group
disable_symbol_group symbol_group_main_ram_loader
ENDMACRO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
