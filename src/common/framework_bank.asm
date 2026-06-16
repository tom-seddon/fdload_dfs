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

ldx #2:jsr reset_mode

lda #1:tsb $fe34		; display shadow RAM

lda #2:sta $fe4d
.wait_for_vsync_loop:bit $fe4d:beq wait_for_vsync_loop
sta $fe4d

lda #8:sta $fe00:stz $fe01

cli

.demo_loop

; Part 0

ldx #5:jsr $8003
ldx #LO(load_p0):ldy #HI(load_p0):jsr framework_load_file
jsr start_next_part

ldx #5:jsr $8003    ; TODO: Wat dis? Transition?

ldx #LO(load_p1):ldy #HI(load_p1):jsr framework_load_file
jsr start_next_part

jmp demo_loop

; ldx #6:jsr $8003
; .p0_done_loop
; lda transition_current_state
; cmp #$80
; bne p0_done_loop

; jmp demo_loop

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

.load_p1
equw $8000			; load address
equw NO_FILE_EXEC_ADDRESS	; no exec address
equb part_main_bank	; ROM bank
equb 0				; drive
equs "XROT",0		; name

.start_next_part
{
ldx #effect_zp_end-effect_zp_begin
.loop
stz [effect_zp_begin-1 AND $ff],x
dex
bne loop
jmp framework_page02_start_next_part
}
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.reset_mode
{
ldy crtc_tables_offsets,x
phx
ldx #0
.reset_crtc_loop
stx $fe00
lda crtc_tables,y:sta $fe01
iny
inx
cpx #13:bne reset_crtc_loop
}
.reset_mode_2			; not at all a reusable entry point
{
plx

ldy palette_tables_offsets,x
phx
ldx #16
.reset_palette_loop
lda palette_tables,y:sta $fe21
iny
dex
bne reset_palette_loop
plx

lda ula_values,x
sta $fe20

lda scroll_values,x
sta $fe40			; set latch B4
lsr a				; put latch B5 into value bit 3
eor #(4>>1) EOR 5		; fix up latch bit index
sta $fe40

rts
}

.update_mode
{
ldy crtc_tables_offsets,x
phx
ldx #0
.reset_crtc_loop
stx $fe00
sta crtc_tables,x:sta $fe01
iny
iny
cpx #4:bne reset_crtc_loop
bra reset_mode_2
}

; .scroll_20KB:lda #%10000 OR 4:bra scroll_NKB
; .scroll_16KB:lda #%00000 OR 4:bra scroll_NKB
; .scroll_10KB:lda #%11000 OR 4:bra scroll_NKB
; .scroll_8KB:lda #%01000 OR 4
; .scroll_NKB
; sta $fe40			; set latch B4
; lsr a				; put latch B5 into value bit 3
; eor #(4>>1) EOR 5		; fix up latch bit index
; sta $fe40
; rts

SCROLL_20KB=%10000 OR 4
SCROLL_16KB=%00000 OR 4
SCROLL_10KB=%11000 OR 4
SCROLL_8KB=%01000 OR 4

.scroll_values
equb SCROLL_20KB		; Mode 0
equb SCROLL_20KB		; Mode 1
equb SCROLL_20KB		; Mode 2
equb SCROLL_20KB		; 
equb SCROLL_10KB		; Mode 4
equb SCROLL_10KB		; Mode 5
equb SCROLL_10KB		; 
equb SCROLL_10KB		; Mode 8

.ula_values
equb $9c			; Mode 0
equb $d8			; Mode 1
equb $f4			; Mode 2
equb $9c			; 
equb $88			; Mode 4
equb $c4			; Mode 5
equb $88			; 
equb $00			; Mode 8

.crtc_tables_offsets
equb crtc_20KB-crtc_tables	; Mode 0
equb crtc_20KB-crtc_tables	; Mode 1
equb crtc_20KB-crtc_tables	; Mode 2
equb crtc_20KB-crtc_tables	; 
equb crtc_10KB-crtc_tables	; Mode 4
equb crtc_10KB-crtc_tables	; Mode 5
equb crtc_10KB-crtc_tables	; 
equb crtc_10KB-crtc_tables	; Mode 8

.palette_tables_offsets
equb palette_1bpp-palette_tables	; Mode 0
equb palette_2bpp-palette_tables	; Mode 1
equb palette_4bpp-palette_tables	; Mode 2
equb palette_1bpp-palette_tables	; 
equb palette_1bpp-palette_tables	; Mode 4
equb palette_2bpp-palette_tables	; Mode 5
equb palette_1bpp-palette_tables	; 
equb palette_4bpp-palette_tables	; Mode 8

.palette_tables
.palette_4bpp
equb $00 OR ($0 EOR 7)
equb $10 OR ($1 EOR 7)
equb $20 OR ($2 EOR 7)
equb $30 OR ($3 EOR 7)
equb $40 OR ($4 EOR 7)
equb $50 OR ($5 EOR 7)
equb $60 OR ($6 EOR 7)
equb $70 OR ($7 EOR 7)
equb $80 OR ($8 EOR 7)
equb $90 OR ($9 EOR 7)
equb $a0 OR ($a EOR 7)
equb $b0 OR ($b EOR 7)
equb $c0 OR ($c EOR 7)
equb $d0 OR ($d EOR 7)
equb $e0 OR ($e EOR 7)
equb $f0 OR ($f EOR 7)
.palette_2bpp
equb $00 OR ($0 EOR 7)
equb $10 OR ($0 EOR 7)
equb $20 OR ($1 EOR 7)
equb $30 OR ($1 EOR 7)
equb $40 OR ($0 EOR 7)
equb $50 OR ($0 EOR 7)
equb $60 OR ($1 EOR 7)
equb $70 OR ($1 EOR 7)
equb $80 OR ($2 EOR 7)
equb $90 OR ($2 EOR 7)
equb $a0 OR ($3 EOR 7)
equb $b0 OR ($3 EOR 7)
equb $c0 OR ($2 EOR 7)
equb $d0 OR ($2 EOR 7)
equb $e0 OR ($3 EOR 7)
equb $f0 OR ($3 EOR 7)
.palette_1bpp
equb $00 OR ($0 EOR 7)
equb $10 OR ($0 EOR 7)
equb $20 OR ($0 EOR 7)
equb $30 OR ($0 EOR 7)
equb $40 OR ($0 EOR 7)
equb $50 OR ($0 EOR 7)
equb $60 OR ($0 EOR 7)
equb $70 OR ($0 EOR 7)
equb $80 OR ($7 EOR 7)
equb $90 OR ($7 EOR 7)
equb $a0 OR ($7 EOR 7)
equb $b0 OR ($7 EOR 7)
equb $c0 OR ($7 EOR 7)
equb $d0 OR ($7 EOR 7)
equb $e0 OR ($7 EOR 7)
equb $f0 OR ($7 EOR 7)

.crtc_tables
.crtc_10KB
equb 63			    ; R0 - H total
equb 40			    ; R1 - H displayed
equb 49			    ; R2 - H sync position
equb $24		    ; R3 - Sync timings
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
equb $28		    ; R3 - Sync timings
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

.transition_acccon_values
equb %00001000		  ; page in HAZEL, page in main, show main
equb %00001101		  ; page in HAZEL, page in shadow, show shadow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.init_transition
{
sei

lda transition_init_lsbs,x:sta call_init+1
lda transition_init_msbs,x:sta call_init+2

; set up T2 routine, skipping it if it's null.
lda transition_update_t2_lsbs,x:ora transition_update_t2_msbs,x
beq null_update_routine		; taken if update routine is 0

; non-null update routine.

; figure out appropriate ACCCON value and poke it in.
lda #$a9					; LDA immediate
sta framework_page02_transition_t2_lda_acccon+0
lda $fe34:and #1:tay:lda transition_acccon_values,y
sta framework_page02_transition_t2_lda_acccon+1 ; the actual value

; sort out the routine address.
lda transition_update_t2_lsbs,x:sta framework_page02_transition_t2_routine_addr+0
lda transition_update_t2_msbs,x:sta framework_page02_transition_t2_routine_addr+1
bra init_vsync

.null_update_routine
lda #$80					; BRA relative
sta framework_page02_transition_t2_lda_acccon+0
lda #framework_page02_transition_t2_done-(framework_page02_transition_t2_lda_acccon+2) ; BRA delta
sta framework_page02_transition_t2_lda_acccon+1

.init_vsync
; set up vsync routine, skipping it if it's null.
lda transition_update_vsync_lsbs,x:sta framework_page02_transition_vsync_routine_addr+0
lda transition_update_vsync_msbs,x:sta framework_page02_transition_vsync_routine_addr+1
ldx #$80			; BRA rel - assume skipped
ora framework_page02_transition_vsync_routine_addr+0:beq got_skip_vsync_opcode
ldx #$02			; NOP #imm - execute vsync routine
.got_skip_vsync_opcode:stx framework_page02_bra_skip_vsync

; clear transition effect zero page.
ldx #transition_zp_end-1-transition_zp_begin
.clear_zp_loop:stz transition_zp_begin,x:dex:bpl clear_zp_loop
stz transition_current_state
; leave transition_state_request... for now

; init transition effect, and set up default IRQ handler.
.call_init:jsr $ffff
jsr framework_set_default_irq_handler
cli
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; init: routine to call when transition is initialised
; 
; update_t2: routine to call on T2 timeout, at bottom of visible
; display area (may be 0 if no such)
;
; update_vsync: routine to call on vsync (may be 0 if no such)

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
transition table,init_null,0,0		      ; 0
transition table,wipe_down_init_640,wipe_down_update_main,0   ; 1
transition table,wipe_down_init_640,wipe_down_update_shadow,0 ; 2
transition table,snake_init_rows,snake_update,0		      ; 3
transition table,snake_init_columns,snake_update,0	      ; 4
transition table,snake_init_rows_bnf,snake_update,0	      ; 5
transition table,snake_init_columns_bnf,snake_update,0	      ; 6
transition table,palette_pulse_init,update_null,palette_pulse_update ; 7
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
snake_head_index=transition_zp_begin+0
snake_draw_colour=transition_zp_begin+1

snake_tail_index=transition_zp_begin+2
snake_erase_colour=transition_zp_begin+3

snake_pattern=transition_zp_begin+4 ; word
snake_byte=transition_zp_begin+6
snake_plot_addr_a=transition_zp_begin+7 ; word
snake_plot_addr_b=transition_zp_begin+9 ; word

; bit 7 = stopped
snake_flags=transition_zp_begin+11
snake_counter=transition_zp_begin+12

.snake_init_rows:ldx #LO(snake_pattern_rows):ldy #HI(snake_pattern_rows):bra snake_init_generic
.snake_init_rows_bnf:ldx #LO(snake_pattern_rows_bnf):ldy #HI(snake_pattern_rows_bnf):bra snake_init_generic
.snake_init_columns:ldx #LO(snake_pattern_columns):ldy #HI(snake_pattern_columns):bra snake_init_generic
.snake_init_columns_bnf:ldx #LO(snake_pattern_columns_bnf):ldy #HI(snake_pattern_columns_bnf):bra snake_init_generic

.snake_init_generic
stx snake_pattern+0:sty snake_pattern+1
.reinit_snake
stz snake_head_index
lda #7:sta snake_draw_colour

stz snake_tail_index
lda #0:sta snake_erase_colour

lda #20:sta snake_counter

rts

.snake_update
{
bit snake_flags
bmi done			; taken if no longer animating

; assume screen not filled
stz transition_current_state

ldx #snake_head_index:jsr plot

lda snake_counter:beq erase_tail ; taken if tail index moving too
dec a:sta snake_counter:rts

.erase_tail
ldx #snake_tail_index:jsr plot
bcc done			; taken if screen not fully erased

; indicate screen filled
lda snake_erase_colour:ora #$80:sta transition_current_state

; set it going again
jsr reinit_snake

.done:rts

; entry: (0,x) = pattern index
;        (1,x) = colour
; exit: C=1 if done
.plot
ldy 0,x:cpy #160:bcs plot_done ; taken if index out of range
lda (snake_pattern),y:tay	 ; Y = screen position

; form (snake_plot_addr_a) and (snake_plot_addr_b)
lda snake_table_lsbs,y:sta snake_plot_addr_a+0
clc:adc #LO(640):sta snake_plot_addr_b+0
lda snake_table_msbs,y:sta snake_plot_addr_a+1
adc #HI(640):sta snake_plot_addr_b+1

ldy 1,x:lda colour_table,y:asl a:ora colour_table,y ; C=0 now
ldy #63
.plot_loop
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
sta (snake_plot_addr_a),y:sta (snake_plot_addr_b),y:dey
bpl plot_loop
inc 0,x
; C=0 from above
.plot_done
rts
}

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

palette_pulse_index=transition_zp_begin

.palette_pulse_init
rts

.palette_pulse_update
{
ldx palette_pulse_index
lda palette_pulse_pattern,x	; assume index was valid
cpx #palette_pulse_pattern_end-palette_pulse_pattern
bcc set				; taken if index not actually valid
lda #0				; colour 0
.set
ora #$80			; display is always a solid colour
sta transition_current_state
eor #$87			; also unset bit 7
clc
.loop
sta $fe21
adc #$10
bcc loop
.done
inx:txa:and #31:sta palette_pulse_index
rts
}

.palette_pulse_pattern
equb 4,1,5,2,6,3
equb 7
equb 3,6,2,5,1,4
.palette_pulse_pattern_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

save "",framework_bank_transitions_begin,P%

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Local Variables:
; mode: beebasm
; End:
