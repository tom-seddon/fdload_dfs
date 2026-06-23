; 65c02
CPU 1

; VGC player flags.
ENABLE_HUFFMAN=FALSE
ENABLE_VGM_FX=TRUE
ENABLE_LZ_INLINE=TRUE

; other constants
ACCCON=$fe34
OSWRCH=$ffee
VIA=$fe60

svia_ifr=$fe4d

palette=$fe21

; 1-byte, 1-cycle NOP
MACRO CMOS_NOP_1B_1C
EQUB $03
ENDMACRO

; 3-byte, 8-cycle NOP
MACRO CMOS_NOP_3B_8C
EQUB $5c,$00,$00
ENDMACRO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ORG $00
INCLUDE "../../dependencies/vgm-player-bbc/lib/vgcplayer.h.asm"
GUARD $90

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ORG $1100
GUARD $3000

.code_begin
; check for hardware requirements
lda ACCCON:and #%11000000:beq master:brk:equb 255:equs "Master only":brk
.master

; select mode 2 and whatnot
ldx #0:.init_prints_loop:lda init_prints,X:jsr OSWRCH:inx:cpx #init_prints_end-init_prints:bne init_prints_loop

; eliminate interlace, cursor, and any *TV adjustment
lda #5:sta $fe00:stz $fe01		  ; no total adjust
lda #8:sta $fe00:lda #%11000000:sta $fe01 ; no interlace, no cursor

; initialise VGM player
lda #hi(vgm_buffer_start)
ldx #lo(vgc_data):ldy #hi(vgc_data)
sec ; enable looping
jsr vgm_init

;
sei

jsr wait_for_vsync

jsr delay_8192
; now somewhere around the top of the visible area, exact location
; unimportant
;jmp test_music
;jmp test_timing
jmp test_via_poll

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

t2val=(39936 DIV 2)-18

.test_via_poll
{
lda #%00100000:trb VIA+11	; T2=timed interrupt

.loop
lda #LO(t2val):sta VIA+8	; set T2L
lda #HI(t2val):sta VIA+9	; set T2H and start counting

lda #(0<<4) OR (2 EOR 7):sta palette
jsr vgm_update
lda #(0<<4) OR (0 EOR 7):sta palette

; wait for T2<256
.wait_t2h_loop:lda VIA+9:bne wait_t2h_loop

; wait for T2 nearly done
.wait_t2l_loop:lda VIA+8:cmp #9:bcs wait_t2l_loop

asl a
tax
jmp (dejitter_routines,x)

.dejitter_9:nop
.dejitter_8:nop
.dejitter_7:nop
.dejitter_6:nop
.dejitter_5:nop
.dejitter_4:nop
.dejitter_3:nop
.dejitter_2:nop
.dejitter_1:nop
.dejitter_0

CMOS_NOP_1B_1C			; JMP is an annoying 3 cycles...
jmp loop

.dejitter_routines:
EQUW dejitter_0
EQUW dejitter_1
EQUW dejitter_2
EQUW dejitter_3
EQUW dejitter_4
EQUW dejitter_5
EQUW dejitter_6
EQUW dejitter_7
EQUW dejitter_8
EQUW dejitter_9
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; hand-counted 39,936 cycle loop
.test_timing
lda #(0<<4) OR (4 EOR 7):sta palette ; 0=blue
jsr delay_128
lda #(0<<4) OR (0 EOR 7):sta palette ; 0=black
; (+ 6 128 6)140
; (+ 0 140)140

jsr delay_16384
jsr delay_16384
jsr delay_4096
jsr delay_2048
jsr delay_512
jsr delay_256
jsr delay_96
; (+ 16384 16384 4096 2048 512 256 96)39776
; (- 39936 (+ 140 39776))20
FOR i,1,8:nop:NEXT
CMOS_NOP_1B_1C:jmp test_timing

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; all delays are in 2 MHz cycles

.delay_16384:jsr delay_8192
.delay_8192:jsr delay_4096
.delay_4096:jsr delay_2048
.delay_2048:jsr delay_1024
.delay_1024:jsr delay_512
.delay_512:jsr delay_256
.delay_256:jsr delay_128
.delay_128
CMOS_NOP_3B_8C
.delay_120
jsr delay_24
.delay_96:jsr delay_48
.delay_48:jsr delay_24
.delay_24:jsr delay_12
.delay_12:rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.test_music
jsr wait_for_vsync
jsr vgm_update
bra test_music

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.wait_for_vsync
{
lda #2
.loop
bit svia_ifr
CMOS_NOP_1B_1C
beq loop
sta svia_ifr
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE "../../dependencies/vgm-player-bbc/lib/vgcplayer_opt.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.vgc_data
INCBIN "U_LOADER.vgc"

.init_prints
EQUB 22,2
EQUB 48,10,13
EQUB 48+1,10,13
EQUB 48+2,10,13
EQUB 48+3,10,13
EQUB 48+4,10,13
EQUB 48+5,10,13
EQUB 48+6,10,13
EQUB 48+7,10,13
EQUB 48+8,10,13
EQUB 48+9,10,13
.init_prints_end

.code_end

ALIGN 256
.vgm_buffer_start:SKIP 8*256:.vgm_buffer_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SAVE "$.POLL",code_begin,code_end,code_begin OR $ff0000,code_begin OR $ff0000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
