include "../shared_constants.asm"
include "../../build/framework_bank.loader.exports.asm"

VERBOSE=1
cpu 1				; 65c02

org framework_bank_transitions_begin
guard framework_bank_transitions_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; transition effect notes
; =======================

; transition effects have 2 routines: init and update. The init
; routine is called in a non-interrupt context when the transition is
; started, with the transition_zp region cleared and interrupts
; disabled; once the init routine finishes, arrangements will be made
; for the update routine to run.

; the update routine is called on the vsync interrupt (via a preamble
; that saves/restores relevant state). There will probably be disk
; loading ongoing, and the non-interrupt code will be decompressing
; stuff. So it should ideally do as little as possible...

; there is no deinit routine. The new effect will just overwrite
; IRQ1V.

; the preamble saves/restores all 6502 registers, and does a CLD on
; entry, so that's all covered.

; the preamble saves/restores ACCCON, so the ACCCON shadow bits can be
; modified as required. The disk NMI routine doesn't require any
; specific paging settings.

; transition effects are expected not to modify ROMSEL, because
; they're running out of ROM.

; definitely set ?transition_current_state to reflect (somehow...) the
; visual state of the transition. The intend is that the incoming
; effect can poll this, then cancel the transition once some desired
; state is visible.
;
; For example, the wipe down effects set bit 7 when the screen is a
; solid colour, with bits 0-6 being the value written AND %01010101.

; maybe monitor ?transition_state_request to put the transition in
; some specific state in a timely fashion. For example, the wipe down
; effect will read this to determine the next colour to use.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Entry points. A list of JMPs.

org framework_bank_boot:jmp boot		; boot
org framework_bank_init_transition:jmp init_transition	; init_transition

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.boot
{
ldx #lo(load_music):ldy #hi(load_music):jsr framework_load_file


lda ula_values+2:sta $fe20
ldx #12:.init_crtc_loop:stx $fe00:lda crtc_20KB,x:sta $fe01:dex:bpl init_crtc_loop
jsr scroll_20KB
lda #1:tsb $fe34		; display shadow RAM
jsr init_4bpp_palette

lda #2:sta $fe4d
.wait_for_vsync_loop:bit $fe4d:beq wait_for_vsync_loop
sta $fe4d

lda #8:sta $fe00:stz $fe01

ldx #6:jsr $8003

cli

.load_loop
ldx #LO(load_p0):ldy #HI(load_p0):jsr framework_load_file
bra load_loop
; jsr framework_start_next_part

; leave 
.halt:jmp halt

.load_music
equw $8000			; load address
equw music_bank_init		; exec address
equb music_bank			; ROM bank
equb 0				; drive
equs "MUSIC",0			; name

.load_p0
equw $8000			; load address
equw NO_FILE_EXEC_ADDRESS	; no exec address
equb part_main_bank		; ROM bank
equb 0				; drive
equs "SCRNS11",0		; name
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.init_4bpp_palette
{
lda #0
clc
.loop
eor #7
sta $fe21
eor #7
adc #$11
bcc loop
rts
}

.scroll_20KB:lda #%10000 OR 4:bra scroll_NKB
.scroll_16KB:lda #%00000 OR 4:bra scroll_NKB
.scroll_10KB:lda #%11000 OR 4:bra scroll_NKB
.scroll_8KB:lda #%01000 OR 4
.scroll_NKB
sta $fe40			; set latch B4
lsr a				; put latch B5 into value bit 3
eor #(4>>1) EOR 5		; fix up latch bit index
sta $fe40
rts

.ula_values
equb $9c			; Mode 0
equb $d8			; Mode 1
equb $f4			; Mode 2
equb $9c			; Mode 3
equb $88			; Mode 4
equb $c4			; Mode 5
equb $88			; Mode 6
equb $00			; Mode 8

.crtc_10KB
equb 63			    ; R0 - H total
equb 40			    ; R1 - H displayed
equb 49			    ; R2 - H sync position
equb $42		    ; R3 - Sync timings
equb 38			    ; R4 - V total
equb 0			    ; R5 - V total adjust
equb 32			    ; R6 - V displayed
equb 34			    ; R7 - V sync position
equb $30		    ; R8 - Interlace ($30 = display disabled)
equb 7			    ; R9 - Scanlines per row
equb $20		    ; R10 - Cursor start/type ($20 = disabled)
equb $00		    ; R11 - Cursor end
equb LO($5800/8)	    ; R13 - Start LSB
equb HI($5800/8)	    ; R12 - Start MSB

.crtc_20KB
equb 127		    ; R0 - H total
equb 80			    ; R1 - H displayed
equb 98			    ; R2 - H sync position
equb $82		    ; R3 - Sync timings
equb 38			    ; R4 - V total
equb 0			    ; R5 - V total adjust
equb 32			    ; R6 - V displayed
equb 34			    ; R7 - V sync position
equb $30		    ; R8 - Interlace ($30 = display disabled)
equb 7			    ; R9 - Scanlines per row
equb $20		    ; R10 - Cursor start/type ($20 = disabled)
equb $00		    ; R11 - Cursor end
equb HI($3000/8)	    ; R12 - Start MSB
equb LO($3000/8)	    ; R13 - Start LSB

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.init_transition
{
php
sei
lda transition_init_lsbs,x:sta call_init+1
lda transition_init_msbs,x:sta call_init+2

; set up T2 routine.
lda transition_update_t2_lsbs,x:sta framework_page02_transition_t2_routine_addr+0
lda transition_update_t2_msbs,x:sta framework_page02_transition_t2_routine_addr+1

; set up vsync routine, skipping it if it's null.
lda transition_update_vsync_lsbs,x:sta framework_page02_transition_vsync_routine_addr+0
lda transition_update_vsync_msbs,x:sta framework_page02_transition_vsync_routine_addr+1
ldx #$80			; BRA rel - assume skipped
ora framework_page02_transition_vsync_routine_addr+0:beq got_skip_vsync_opcode
ldx #$02			; NOP #imm - execute vsync routine
.got_skip_vsync_opcode:stx framework_page02_bra_skip_vsync

ldx #transition_zp_end-1-transition_zp_begin
.clear_zp_loop:stz transition_zp_begin,x:dex:bpl clear_zp_loop
.call_init:jsr $ffff
jsr framework_set_default_irq_handler
plp
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MACRO transition table,init,update_t2,update_vsync
IF table==0:EQUB LO(init)
ELIF table==1:EQUB HI(init)
ELIF table==2:EQUB LO(update_t2)
ELIF table==3:EQUB HI(update_t2)
ELIF table==4:EQUB LO(update_vsync)
ELIF table==5:EQUB HI(update_vsync)
ELSE:ERROR "transition: bad table"
ENDIF
ENDMACRO

; the TOC is generated by a macro, so that it can generate 4 tables.
; Add new entries following the existing examples.
MACRO transition_toc table
transition table,init_null,update_null,0		      ; 0
transition table,wipe_down_init_640,wipe_down_update_main,0   ; 1
transition table,wipe_down_init_640,wipe_down_update_shadow,0 ; 2
transition table,snake_init_rows,snake_update,0		      ; 3
transition table,snake_init_columns,snake_update,0	      ; 4
transition table,snake_init_rows_bnf,snake_update,0	      ; 5
transition table,snake_init_columns_bnf,snake_update,0	      ; 6
ENDMACRO

.transition_init_lsbs:transition_toc 0
.transition_init_msbs:transition_toc 1
.transition_update_t2_lsbs:transition_toc 2
.transition_update_t2_msbs:transition_toc 3
.transition_update_vsync_lsbs:transition_toc 4
.transition_update_vsync_msbs:transition_toc 5

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Null effect - does nothing.
; 
.init_null
.update_null
rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Wipe down effect - fills screen memory with a constant value, top to
; bottom. 

wipe_down_addr=transition_zp_begin+0
;wipe_down_stride=transition_zp_begin+2
;wipe_down_count=transition_zp_begin+4 ; number of 64 byte regions to fill
wipe_down_colour=transition_zp_begin+6
wipe_down_reset_addr=transition_zp_begin+7
wipe_down_value=transition_zp_begin+9

.wipe_down_init_640
lda #1:sta wipe_down_colour
stz wipe_down_reset_addr+0:lda #$30:sta wipe_down_reset_addr+1
;lda #LO(640):sta wipe_down_stride+0:lda #HI(640):sta wipe_down_stride+1
;lda #640 DIV 64:sta wipe_down_count
ldx #0:stx wipe_down_colour
.reset_wipe_down_addr
lda wipe_down_reset_addr+0:sta wipe_down_addr+0
lda wipe_down_reset_addr+1:sta wipe_down_addr+1
rts

.wipe_down_update_main
lda #2:trb $fe34		; page in main RAM
bra update_wipe_down

.wipe_down_update_shadow
lda #2:tsb $fe34		; page in shadow RAM
; fall through to update_wipe_down

.update_wipe_down
ldx wipe_down_colour:lda colour_table,x:asl a:ora colour_table,x
sta wipe_down_value
.wipe_down_one_row_loop
jsr wipe_down_fill_part
jsr wipe_down_fill_part
jsr wipe_down_fill_part
jsr wipe_down_fill_part
jsr wipe_down_fill_part
; assume screen not filled with single colour
stz transition_current_state
lda wipe_down_addr+1:bpl wipe_down_done
jsr reset_wipe_down_addr
lda wipe_down_colour:ora #$80:sta transition_current_state
inc a:and #7:sta wipe_down_colour
.wipe_down_done
rts

.wipe_down_fill_part
{
lda wipe_down_value
ldy #0
clc
.loop
sta (wipe_down_addr),y:iny
sta (wipe_down_addr),y
sta (wipe_down_addr),y:iny
sta (wipe_down_addr),y:iny
bpl loop
clc
lda wipe_down_addr+0:adc #128:sta wipe_down_addr+0:bcc done
inc wipe_down_addr+1
.done
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Snake effect - divides screen into a 10x16 grid.
;
snake_index=transition_zp_begin+0
snake_pattern=transition_zp_begin+1
snake_head_colour_a=transition_zp_begin+3
snake_head_colour_b=transition_zp_begin+4
snake_tail_colour_a=transition_zp_begin+5
snake_tail_colour_b=transition_zp_begin+6

snake_byte_a=transition_zp_begin+7
snake_byte_b=transition_zp_begin+8
snake_plot_addr_a=transition_zp_begin+9
snake_plot_addr_b=transition_zp_begin+11
; +13

.snake_init_rows:ldx #LO(snake_pattern_rows):ldy #HI(snake_pattern_rows):bra snake_init_generic
.snake_init_rows_bnf:ldx #LO(snake_pattern_rows_bnf):ldy #HI(snake_pattern_rows_bnf):bra snake_init_generic
.snake_init_columns:ldx #LO(snake_pattern_columns):ldy #HI(snake_pattern_columns):bra snake_init_generic
.snake_init_columns_bnf:ldx #LO(snake_pattern_columns_bnf):ldy #HI(snake_pattern_columns_bnf):bra snake_init_generic

.snake_init_generic
{
stx snake_pattern+0:sty snake_pattern+1

stz snake_index
lda #7:sta snake_head_colour_a
lda #0:sta snake_head_colour_b

lda #1:sta snake_tail_colour_a
lda #1:sta snake_tail_colour_b
rts
}

.snake_update
{
ldy snake_index:cpy #160:bcs done_head
ldx #snake_head_colour_a:jsr snake_plot
.done_head
ldy snake_index:beq done_tail
dey:ldx #snake_tail_colour_a:jsr snake_plot
.done_tail
inc snake_index
lda snake_index
cmp #160+1
bcc done
stz snake_index
ldx #snake_tail_colour_a:jsr next_colour
inx:jsr next_colour
.done
rts

.next_colour
lda 0,x:inc a:and #7:sta 0,x
rts
}

; (snake_pattern),y=location
; X=colour a/b ZP address
.snake_plot
{
lda (snake_pattern),y:tay
lda snake_table_lsbs,y:sta snake_plot_addr_a+0
clc:adc #LO(640):sta snake_plot_addr_b+0
lda snake_table_msbs,y:sta snake_plot_addr_a+1
adc #HI(640):sta snake_plot_addr_b+1
; form %abababab; X=%0a0a0a0a
ldy 0,x:lda colour_table,y:asl a:ldy 1,x:ora colour_table,y:sta snake_byte_a
lda colour_table,y:asl a:ldy 0,x:ora colour_table,y:sta snake_byte_b
ldy #63:lda snake_byte_a:jsr plot2
ldy #62:lda snake_byte_b
.plot2
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey:dey
bpl plot2
rts
}
; tax:ldy snake_table_msbs,x:sta snake_plot_addr_a+1
; and #3:tax:lda snake_table_lsbs,x:sta snake_plot_addr_a+0
; clc:adc #LO(640):sta snake_plot_addr_b+0
; lda snake_plot_addr_a+1:adc #HI(640):sta snake_plot_addr_b+1
; ldx snake_plot_colour:lda colour_table,x:asl a:ora colour_table,x
; ldy #63
; .fill_loop
; sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
; sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
; sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
; sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
; bpl fill_loop
; rts
; }

MACRO snake_table_entry index,shift
ASSERT shift==0 OR shift==8
ASSERT index>=0 AND index<160
EQUB (($3000+(index MOD 10)*64+(index DIV 10)*1280)>>shift)AND$ff
ENDMACRO

.snake_table_lsbs:FOR i,0,159:snake_table_entry i,0:NEXT
.snake_table_msbs:FOR i,0,159:snake_table_entry i,8:NEXT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.snake_pattern_rows
FOR y,0,15
FOR x,0,9
EQUB y*10+x
NEXT
NEXT
ASSERT P%-snake_pattern_rows==160

.snake_pattern_rows_bnf
FOR y,0,15
FOR x,0,9
IF (y AND 1)==0:EQUB y*10+x:ELSE:EQUB y*10+(9-x):ENDIF
NEXT
NEXT
ASSERT P%-snake_pattern_rows_bnf==160

.snake_pattern_columns
FOR x,0,9
FOR y,0,15
EQUB y*10+x
NEXT
NEXT
ASSERT P%-snake_pattern_columns==160

.snake_pattern_columns_bnf
FOR x,0,9
FOR y,0,15
IF (x AND 1)==0:EQUB y*10+x:ELSE:EQUB (15-y)*10+x:ENDIF
NEXT
NEXT
ASSERT P%-snake_pattern_columns_bnf==160

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.colour_table
equb %00000000
equb %00000001
equb %00000100
equb %00000101
equb %00010000
equb %00010001
equb %00010100
equb %00010101
equb %01000000
equb %01000001
equb %01000100
equb %01000101
equb %01010000
equb %01010001
equb %01010100
equb %01010101

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

save "",framework_bank_transitions_begin,P%

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
