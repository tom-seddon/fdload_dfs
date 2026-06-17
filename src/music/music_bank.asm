;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CPU 1				; 65c02
INCLUDE "../shared_constants.asm"

; VGC player flags.
ENABLE_HUFFMAN=FALSE
ENABLE_VGM_FX=TRUE
ENABLE_LZ_INLINE=TRUE

ORG music_zp_begin
GUARD music_zp_end
INCLUDE "../../dependencies/vgm-player-bbc/lib/vgcplayer.h.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Put the buffers at the end of the ROM.
vgm_buffer_start=$b800
vgm_buffer_end=$c000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ORG $8000
GUARD vgm_buffer_start

.music_bank_start

ORG music_bank_init:jmp init
ORG music_bank_update:jmp update

.init
{
lda #hi(vgm_buffer_start)
ldx #lo(vgc_data)
ldy #hi(vgc_data)
sec				; enable looping
jmp vgm_init
}

.update
{
bra vgm_update
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


INCLUDE "../../dependencies/vgm-player-bbc/lib/vgcplayer.asm"

.vgc_data
INCBIN "../../build/U_LOADER.vgc"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.music_bank_end
SAVE "",music_bank_start,music_bank_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
