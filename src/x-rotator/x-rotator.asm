\ ******************************************************************
\ *	RASTER FX FRAMEWORK
\ ******************************************************************

CPU 1	; MASTER
INCLUDE "../shared_constants.asm"

PART_TIMEOUT_VSYNCS=500
SHORTEN_BY_ROWS=3
ENABLE_MUSIC=TRUE

\ ******************************************************************
\ *	OS defines
\ ******************************************************************

osfile = &FFDD
oswrch = &FFEE
osasci = &FFE3
osbyte = &FFF4
osword = &FFF1
osfind = &FFCE
osgbpb = &FFD1
osargs = &FFDA

\\ Palette values for ULA
PAL_black	= (0 EOR 7)
PAL_blue	= (4 EOR 7)
PAL_red		= (1 EOR 7)
PAL_magenta = (5 EOR 7)
PAL_green	= (2 EOR 7)
PAL_cyan	= (6 EOR 7)
PAL_yellow	= (3 EOR 7)
PAL_white	= (7 EOR 7)

\ ******************************************************************
\ *	SYSTEM defines
\ ******************************************************************

MODE1_COL0=&00
MODE1_COL1=&20
MODE1_COL2=&80
MODE1_COL3=&A0

\ ******************************************************************
\ *	MACROS
\ ******************************************************************

MACRO WAIT_CYCLES n

PRINT "WAIT",n," CYCLES"

IF n < 0
	ERROR "Can't wait negative cycles!"
ELIF n=0
	; do nothing
ELIF n=1
	EQUB $33
	PRINT "1 cycle NOP is Master only and not emulated by b-em."
ELIF (n AND 1) = 0
	FOR i,1,n/2,1
	NOP
	NEXT
ELSE
	BIT 0
	IF n>3
		FOR i,1,(n-3)/2,1
		NOP
		NEXT
	ENDIF
ENDIF

ENDMACRO

\ ******************************************************************
\ *	GLOBAL constants
\ ******************************************************************

; Default screen address
screen_addr = &3000
SCREEN_SIZE_BYTES = &8000 - screen_addr
row_bytes = 640

; Exact time for a 50Hz frame less latch load time
FramePeriod = 312*64-2

; Calculate here the timer value to interrupt at the desired line
TimerValue = 40*64 - 2*64 - 2 - 22 - 5 -64

\\ 40 lines for vblank
\\ 32 lines for vsync (vertical position = 35 / 39)
\\ interupt arrives 2 lines after vsync pulse
\\ 2 us for latch
\\ XX us to fire the timer before the start of the scanline so first colour set on column -1
\\ YY us for code that executes after timer interupt fires

\ ******************************************************************
\ *	ZERO PAGE
\ ******************************************************************

ORG &00
GUARD &7F

\\ System variables

.vsync_counter			SKIP 2		; counts up with each vsync
.escape_pressed			SKIP 1		; set when Escape key pressed

\\ FX variables

.image_y				skip 1
.table_idx				skip 1
.count					skip 1

.startx					skip 1
.starty					skip 1
.endx					skip 1
.endy					skip 1
.dx						skip 1
.dy						skip 1

.startx_dir				skip 1
.readptr				skip 2
.tmp					skip 1

\ ******************************************************************
\ *	CODE START
\ ******************************************************************

ORG &8000	  			; code origin (like P%=&2000)
GUARD &C000				; ensure code size doesn't hit start of screen memory

.start

.main_start

\ ******************************************************************
\ *	Code entry
\ ******************************************************************

.main
{
	\\ Notes.
	\\ Transition is writing to the screen, so can only decomp the first
	\\ one to whichever screen is not currently being displayed.
	\\ Then wait for transition to end, hide screen, switch to other bank
	\\ decomp into the other bank, then start the effect.

	\\ Happens with interrupts on, so the system's IRQ1 handles the music playback.
	JSR fx_init_function

	\\ Set interrupts

	SEI							; disable interupts
	LDA #&7F					; A=01111111
	STA &FE4E					; R14=Interrupt Enable (disable all interrupts)
	STA &FE43					; R3=Data Direction Register "A" (set keyboard data direction)
	LDA #&E2					; A=11000010 T1 + T2 + vsync
	STA &FE4E					; R14=Interrupt Enable (enable main_vsync and timer interrupt)

	lda #%00100000:trb &FE4B	; T2=timed interrupt

	\\ Initalise system vars

	LDA #0
	STA vsync_counter
	STA vsync_counter+1
	STA escape_pressed

	\\ Already in HF mode.

	\\ Set MODE 1 ULA CONTROL
	lda #$d8        ; mode 1
	sta &FE20		; ULA CONTROL

	\\ TODO: Set palette.
	\\ TODO: When is it safe to change CRTC regs?

	\\ Shift hsync - IMPORTANT!

	lda #2:sta &fe00
	lda #95:sta &fe01

	\\ Ensure the CRTC column counter is incrementing starting from a
	\\ known state with respect to the cycle stretching. Because the vsync
	\\ signal is reported via the VIA, which is a 1MHz device, the timing
	\\ could be out by 0.5 usec in 2MHz modes.
	\\
	\\ To fix: set R0=0, wait 256 cycles to ensure the horizontal counter
	\\ is stuck at 0, then set the horizontal counter to its correct
	\\ value. The 6845 is always accessed at 1MHz so the cycle counter
	\\ starts running on a 1MHz boundary.
	\\
	\\ Note: when R0=0, DRAM refresh is off. Don't delay too long.
;	lda #0
;	sta $fe00:sta $fe01
;	ldx #2:jsr cycles_wait_scanlines
;	sta $fe00:lda #127:sta $fe01

	\\ Initialise system modules here!

	\ ******************************************************************
	\ *	DEMO START - from here on out there are no interrupts enabled!!
	\ ******************************************************************

	\\ Exact cycle VSYNC by Hexwab + Tom Seddon
	.find_vsync_edge
	\\{
		lda #2
		.vsync1
		bit &FE4D
		beq vsync1 \ wait for vsync

		\now we're within 10 cycles of vsync having hit

		\delay just less than one frame - now using T2!
		.syncloop
		sta &FE4D \ 4(stretched), ack vsync							; 5/6c

		t2val=((39936-46) DIV 2) -2 ; subtract 48c between T2 read and T2 set.
									; -1us for T2 counter to load.
									; -1us so we're actually less than a frame!

		lda #LO(t2val):sta &FE48	; set T2L						; 8c
		lda #HI(t2val):sta &FE49	; set T2H and start counting	; 8c

		; Do work!
		IF ENABLE_MUSIC
		jsr framework_update_music		; takes a variable amount of time...
		ENDIF

		; wait for T2<256
		.wait_t2h_loop:lda &FE49:bne wait_t2h_loop

		; wait for T2 nearly done
		.wait_t2l_loop:lda &FE48
		cmp #9:bcs wait_t2l_loop									; 4c
		asl a														; 2c
		tax															; 2c
		jmp (dejitter_routines,x)									; 6c

		\ remaining T2 counter cycles eaten by the nops.
		.dejitter_9:nop
		.dejitter_8:nop
		.dejitter_7:nop
		.dejitter_6:nop
		.dejitter_5:nop
		.dejitter_4:nop
		.dejitter_3:nop
		.dejitter_2:nop
		.dejitter_1:nop
		.dejitter_0:EQUB $33										; 1c

		lda #2														; 2c
		bit &FE4D \4(stretched)										; 5/6c
		bne syncloop \ +3											; 3c
		\ 46 total cycles between T2 counter read and T2 counter set

		\ ne means vsync has hit
		\ loop until it hasn't hit
		\ now we're synced to vsync
	\\}

	\\ Set up Timers

	.set_timers
	; Write T1 low now (the timer will not be written until you write the high byte)
    LDA #LO(TimerValue):STA &FE44
    ; Get high byte ready so we can write it as quickly as possible at the right moment
    LDA #HI(TimerValue):STA &FE45             		; start T1 counting		; 4c +1/2c 

  	; Latch T1 to interupt exactly every 50Hz frame
	LDA #LO(FramePeriod):STA &FE46
	LDA #HI(FramePeriod):STA &FE47

	\ ******************************************************************
	\ *	MAIN LOOP
	\ ******************************************************************

.main_loop

	\\  Do useful work during vblank (vsync will occur at some point)
	{
		INC vsync_counter
		BNE no_carry
		INC vsync_counter+1
		.no_carry
	}

	\\ Service any system modules here!

	\\ Check for timeout of part.
	lda vsync_counter+1
	cmp #HI(PART_TIMEOUT_VSYNCS)
	bcc continue
	lda vsync_counter+0
	cmp #LO(PART_TIMEOUT_VSYNCS)
	bcc continue
	ldx #&ff
	stx escape_pressed
	.continue

	\\ Wait for Timer 1.
	{
		LDA #&40
		.waitTimer1
		BIT &FE4D				; 4c + 1/2c
		BEQ waitTimer1         	; poll timer1 flag

		\\ Stabilise the raster.
		{
			\\ Reading the T1 low order counter also resets the T1 interrupt flag in IFR.
			lda &fe44

			\\ New stable raster NOP slide thanks to VectorEyes 8)
			; Extract lowest 3 bits, use result to control a NOP slide. This corrects for timer jitter and provides stable raster.
			and #7
			eor #7
			sta branch+1
			.branch
			bpl branch \always
			.slide
			; Note: this slide delays (CPU cycles) by TWICE the 'input' to the slide, which is
			; what we want because the T1 counter is 1MHz, but the CPU runs at 2MHz.
			nop:nop:nop:nop
			nop:nop:cmp &33
			.stable
		}
	}

	\\ Check if Escape pressed

	LDA escape_pressed
	BMI call_kill

	\\ FX draw callback here!

	.call_draw
	JSR fx_draw_function

	\\ FX update callback here!

	.call_update
	JSR fx_update_function

	\\ Keep music player polled.
	IF ENABLE_MUSIC
	jsr framework_update_music
	ENDIF

	JMP main_loop

	\\ Get current module to return CRTC to known state

	.call_kill
	JSR fx_kill_function

	\\ Exit gracefully (in theory)
	CLI
	jmp framework_set_default_irq_handler

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

.main_end

\ ******************************************************************
\ *	FX MODULE
\ ******************************************************************

.fx_start

\ ******************************************************************
\ Initialise FX
\
\ The initialise function is used to set up all variables, tables and
\ any precalculated screen memory etc. required for the FX.
\
\ This function will be called during vblank
\ The CRTC registers will be set to default MODE 0,1,2 values
\
\ The function can take as long as is necessary to initialise.
\ ******************************************************************

.fx_init_function
{
	lda &fe34
	and #1			; 1=SHADOW displayed, 0=MAIN displayed
	eor #1			; flip
	asl a:asl a		; write to opposite bank
	sta tmp

	lda &fe34
	and #255-4
	ora tmp
	sta &fe34		; the screen not displayed.

	lda #LO(widths1_zx02)
    sta framework_decomp_src+0
	lda #HI(widths1_zx02)
    sta framework_decomp_src+1

	lda #LO(screen_addr)
    sta framework_decomp_dest+0
	lda #HI(screen_addr)
    sta framework_decomp_dest+1

    jsr framework_decomp_data

	\\ Wait for transition to end.

.transition_finished_loop
	bit transition_current_state
	bpl transition_finished_loop

    jsr framework_stop_transition

	\\ TODO: Hide the other screen whilst we decomp.

	lda &fe34
	eor #5			; flip RAM
	sta &fe34

	lda #LO(widths2_zx02)
    sta framework_decomp_src+0
	lda #HI(widths2_zx02)
    sta framework_decomp_src+1

	lda #LO(screen_addr)
    stz framework_decomp_dest+0
	lda #HI(screen_addr)
    sta framework_decomp_dest+1

    jsr framework_decomp_data

	lda #1:sta startx_dir

	lda #0:sta startx
	lda #64:sta endx

	lda #64:sta starty
	lda #192:sta endy

	\rts
	; fall through
}

.reset_readptr
{
	lda #lo(projection_list)
	sta readptr
	lda #hi(projection_list)
	sta readptr+1
	rts
}

\ ******************************************************************
\ Update FX
\
\ The update function is used to update / tick any variables used
\ in the FX. It may also prepare part of the screen buffer before
\ drawing commenses but note the strict timing constraints!
\
\ This function will be called during vblank, after any system
\ modules have been polled.
\
\ The function MUST COMPLETE BEFORE TIMER 1 REACHES 0, i.e. before
\ raster line 0 begins. If you are late then the draw function will
\ be late and your raster timings will be wrong!
\ ******************************************************************

.fx_update_function
{
	ldx #0
	lda #12:sta &fe00	; 8c
	lda screen_HI, x:sta &fe01	; 10c

	lda #13:sta &fe00	; 8c
	lda screen_LO, x:sta &fe01	; 10c

	lda (readptr)
	cmp #128
	bne loop

	jsr reset_readptr

	.loop
	ldy #0
	lda (readptr), y
	beq done_loop

	sta startx
	iny
	lda (readptr), y
	sta starty
	iny
	lda (readptr), y
	sta endx
	iny
	lda (readptr), y
	sta endy

	clc
	lda readptr
	adc #4
	sta readptr
	bcc no_carry
	inc readptr+1
	.no_carry

	jsr drawline
	bra loop
	.done_loop

	inc readptr
	bne ok
	inc readptr+1
	.ok

	lda table_image_y+1
	sta image_y

	RTS
}

\ ******************************************************************
\ Draw FX
\
\ The draw function is the main body of the FX.
\
\ This function will be exactly at the start* of raster line -1 with
\ a stablised raster. VC=0 HC=0|1 SC=0
\
\ This means that a new CRTC cycle has just started! If you didn't
\ specify the registers from the previous frame then they will be
\ the default MODE 0,1,2 values as per initialisation.
\
\ If messing with CRTC registers, THIS FUNCTION MUST ALWAYS PRODUCE
\ A FULL AND VALID 312 line PAL signal before exiting!
\ ******************************************************************

.fx_draw_function
\{
	\\ Enter fn at 64us before first raster line
	\\ <=== start of scanline -1 HCC=0 LVC=0 VCC=0

	WAIT_CYCLES 128-36	; 92c

	\\ <== 92c

	lda #7:sta &fe00	; 8c
	lda #&ff:sta &fe01	; 8c

	\\ <== 108c

	.fx_draw_here
	clc					; 2c
	ldy image_y			; 3c next scanline
	nop					; 2c
	stz &fe00			; 5c

	lda #95				; 2c

	\\ <== 122c
	
	sta &FE01				; 6c R0=95 horizontal total = 96
	\\ <== 128c/0c

	\\ <=== start of scanline 0 HCC=0 LVC=0 VCC=0
	\\ start segment 0 [0-99]

	lda #4: sta &fe00				; 8c
	stz &FE01						; 6c R4=0 vertical total = 1
	\\ <== 14c

	\\ Before end of segmnet 0 need to set R12/R13/R9

	\\ The rule is, set R9 at the start of a displayed line as follows:
	\\ R9 = this_line_number + 15 - next_line_number
	\\ or, conveniently:
	\\ R9 = (next_line_number EOR 15) + this_line_number (edited) 

	\\ Eg. 0->7: 0+15-7 = 8 = (7^15)+0
	\\ Eg. 7->0: 7+15-0 = 22 = (0^15)+7

	\\ Set R9
	LDA #9:STA &fe00				; 8c
	LDA y_to_scanline, Y			; 4c
	sta fx_draw_prev_line+1			; 4c
	eor #15							; 2c
	\\ First scanline always 0
	STA &fe01						; 6c
	\\ <== 38c

	\\ Set R12/R13
	LDA #12:STA &fe00				; 8c
	LDA screen_HI, Y:STA &fe01		; 10c		X=1

	LDA #13:STA &fe00				; 8c
	LDA screen_LO, Y:STA &fe01		; 10c		X=1
	\\ <== 74c

	\\ X=raster Y
	ldx #1							; 2c

	WAIT_CYCLES 6

	\\ <== 82c

	\\ start segment 1..
	stz &fe00						; 6c
	lda #1							; 2c
	sta &fe01						; R0=1 horizontal total = 2
	\\ This has to be bang on 96c on real hw
	\\ <== 96c

	lda #6:sta &fe00
	lda #1:sta &fe01				; R6=1 vertical displayed <-- could this be moved to update?
	\\ <== 112c

	stz &fe00						; 6c
	NOP								; 2c

	\\ <== 120c

	\\ Start of scanline 1 <phew>
	\\ X is the raster line we want to display
	\\ Use Y to look up a table to increment X

	.fx_draw_loop
	\\ <== 120c

	lda #95							; 2c
	sta &FE01						; 8c R0=95 horizontal total = 96
	\\ This must be on start of scanline.
	\\ <== 128c/0c

	lda table_image_y, X			; 4c
	tay								; 2c
	lda #0							; 2c
	sta table_image_y, X			; 4c	wipe table here to save vblank cycles

	WAIT_CYCLES 6

	\\ Screen start address = screen[image_y]
	lda #13:sta &fe00				; 8c
	lda screen_LO, y				; 4c	Y=image y
	sta &fe01						; 6c

	lda #12:sta &fe00				; 8c	shouldn't affect carry?
	lda screen_HI, Y				; 4c    Y=image y
	sta &fe01						; 6c

	\\ <== 54c

	\\ Set R9=image_y AND 7
	lda #9:sta &fe00				; 8c

	lda y_to_scanline, Y			; 4c	Y=image Y
	tay								; 2c	Y=image scanline
	eor #15							; 2c
	.fx_draw_prev_line
	adc #0							; 2c	SELF-MOD CODE
	sta &fe01						; 6c

	\\ Need to reset prev_line for next time
	sty fx_draw_prev_line+1			; 4c

	\\ Available 20+26+36 = 82c to set R9/12/13 note minimum overhead of 3x14c = 42c to select and set registers
	\\ <== 82c

	\\ Set horizontal total
	stz &fe00						; 6c
	lda #1							; 2c
	sta &fe01						; 6c R0=1 horizontal total = 2
	\\ This has to be bang on 96c!
	\\ <== 96c

	WAIT_CYCLES 9

	\\ Toggle MAIN/SHADOW for dither effect.
	txa								; 2c
	and #1							; 2c
	sta &fe34						; 4c

	inx								; 2c
	cpx #255-(SHORTEN_BY_ROWS*8)				   ; 2c
	bne fx_draw_loop				; 3c
	\\ <== 120c

	.fx_draw_done

	\\ start of scanline 255
	NOP

	\\ Need to get scanlines & character rows back in sync...
	\\ So if finish on scanline count N
	\\ Set R9 to get us back to 0 on next scanline

	lda #95							; 2c
	sta &FE01						; 6c R0=95 horizontal total = 96
	\\ <== 128c/0c

	\\ Set R9 so we get back to scanline 0 next line
	LDA #9:STA &fe00				; 8c
	clc								; 2c
	LDA #15							; 2c
	ADC fx_draw_prev_line+1				; 4c
	STA &fe01						; 6c
	\\ <== 22c

	WAIT_CYCLES 60

	\\ <== 82c

	\\ Set horizontal total
	stz &fe00
	\\ <== 88c
	lda #1							; 2c
	sta &fe01						; 6c R0=1 horizontal total = 2
	\\ <== 96c

	\\ segments 3-14 [100-127]
	WAIT_CYCLES 22
	NOP

	\\ <== 120c

	\\ Should be start of scanline 256!

	\\ got to catch this before 2c!
	lda #127
	sta &fe01				; R0=127 back to a full width line!
	\\ <== 128c/0c

	lda #9:sta &fe00
	lda #7:sta &fe01		; R9=7 scanlines per row = 8
	\\ 16c

	lda #4:sta &fe00
	lda #6+SHORTEN_BY_ROWS:sta &fe01		; R4=7 more character rows total 39
	\\ 16c

	lda #7:sta &fe00
	lda #2+SHORTEN_BY_ROWS:sta &fe01		; R7=vsync at row 34
	\\ 16c

	lda #6:sta &fe00
	lda #0:sta &fe01		; R6=1 vertical displayed
	\\ 16c

    RTS

IF HI(fx_draw_loop) <> HI(fx_draw_loop)
	ERROR "WARNING: fx_draw_loop crossed page boundary!!"
ENDIF
\}

\ ******************************************************************
\ Kill FX
\
\ The kill function is used to tidy up any craziness that your FX
\ might have created and return the system back to the expected
\ default state, ready to initialise the next FX.
\
\ This function will be exactly at the start* of raster line 0 with
\ a maximum jitter of up to +10 cycles.
\
\ This means that a new CRTC cycle has just started! If you didn't
\ specify the registers from the previous frame then they will be
\ the default MODE 0,1,2 values as per initialisation.
\
\ THIS FUNCTION MUST ALWAYS ENSURE A FULL AND VALID 312 line PAL
\ signal will take place this frame! The easiest way to do this is
\ to simply call crtc_reset.
\
\ ******************************************************************

.fx_kill_function
{
	\\ Set all CRTC registers back to their defaults for MODE 0,1,2

	LDX #13
	.loop
	STX &FE00
	LDA crtc_regs_default,X
	STA &FE01
	DEX
	BPL loop

	RTS
}

\ ******************************************************************
\ *	Not really drawing lines but drawing widths into the Y buffer.
\ ******************************************************************

.drawline
{
	; don't need a screen address
	; calc screen row of starty
	LDY starty
	
	; calc pixel within byte of startx
	LDX startx

	; calc dx = ABS(startx - endx)
	SEC
	LDA startx
	SBC endx
	BCS posdx
	EOR #255
	ADC #1
	.posdx
	STA dx
	
	; C=0 if dir of startx -> endx is positive, otherwise C=1
	PHP
	
	\\ We should be able to guarantee endy>starty for this FX
	; calc dy = ABS(starty - endy)
	SEC
	LDA starty
	SBC endy
	BCS posdy
	EOR #255
	ADC #1
	.posdy
	STA dy
	
	; C=0 if dir of starty -> endy is positive, otherwise C=1
	PHP
	
	; Coincident start and end points exit early
	ORA dx
	BEQ exitline
	
	; determine which type of line it is
	LDA dy
	CMP dx
	BCC shallowline
		
.steepline

	; self-modify code so that line progresses according to direction remembered earlier
	PLP
	lda #&c8		; INY	\\ going down
	BCC P%+4
	lda #&88		; DEY	\\ going up
	sta branchupdown
	
	PLP
	lda #&e8		; INX	\\ going right
	BCC P%+4
	lda #&ca		; DEX	\\ going left
	sta branchleftright

	sty steep_write+1

	lda endy
	sta steep_check+1

	; initialise accumulator for 'steep' line
	LDA dy
	LSR A

.steeplineloop

	\\ Keep accum in A
	
	; plot 'pixel'
	.steep_write
	stx table_image_y		; 4c	SELF-MOD low byte

	; check if done
	.steep_check
	cpy #&ff				; 2c
	BEQ exitline			; 2c

	.branchupdown
	nop						; 2c	SELF-MOD INY/DEY
	sty steep_write+1		; 4c
	
	; check move to next pixel column
	.movetonextcolumn
	SEC						; 2c
	\\ Keep accum in A
	SBC dx					; 3c
	BCS steeplineloop		; 2c
	ADC dy					; 3c
	
	.branchleftright
	nop						; 2c	SELF-MOD INX/DEX
	BRA steeplineloop		; 3c

	.exitline
	RTS
	
.shallowline

	; self-modify code so that line progresses according to direction remembered earlier
	PLP
	lda #&c8		; INY	\\ going down
	BCC P%+4
	lda #&88		; DEY	\\ going up
	sta branchupdown2

	PLP
	lda #&e8		; INX	\\ going right
	BCC P%+4
	lda #&ca		; DEX	\\ going left
	sta branchleftright2

	sty shallow_write+1

	; initialise accumulator for 'shadllow' line
	LDA dx
	STA count
	LSR A

	INC count

.shallowlineloop

	; plot 'pixel'
	.shallow_write
	stx table_image_y		; SELF-MOD low byte

	; check if done
	DEC count
	beq exitline

	.branchleftright2
	nop						; SELF-MOD INX/DEX
	
	; check whether we move to the next line
	.movetonextline
	SEC
	SBC dy
	BCS shallowlineloop
	ADC dx

	.branchupdown2
	nop						; SELF-MOD INY/DEY
	sty shallow_write+1

	BRA shallowlineloop		; always taken
}

.fx_end

\ ******************************************************************
\ *	SYSTEM DATA
\ ******************************************************************

.data_start

.crtc_regs_default
{
	EQUB 127				; R0  horizontal total
	EQUB 80					; R1  horizontal displayed
	EQUB 98					; R2  horizontal position
	EQUB &28				; R3  sync width 40 = &28
	EQUB 38					; R4  vertical total
	EQUB 0					; R5  vertical total adjust
	EQUB 32					; R6  vertical displayed
	EQUB 34					; R7  vertical position; 35=top of screen
	EQUB &0					; R8  interlace; &30 = HIDE SCREEN
	EQUB 7					; R9  scanlines per row
	EQUB 32					; R10 cursor start
	EQUB 8					; R11 cursor end
	EQUB HI(screen_addr/8)	; R12 screen start address, high
	EQUB LO(screen_addr/8)	; R13 screen start address, low
}

\ ******************************************************************
\ *	FX DATA
\ ******************************************************************

ALIGN &100

.screen_LO
FOR n,0,255,1
y=n
row = y DIV 8
EQUB LO((screen_addr + row * row_bytes)/8)
NEXT

.screen_HI
FOR n,0,255,1
y=n
row = y DIV 8
EQUB HI((screen_addr + row * row_bytes)/8)
NEXT

.y_to_scanline
EQUB 0
FOR n,1,255,1
y = n
line = y MOD 8
EQUB line
NEXT

MIN_W=52
MAX_W=304
ERR=1e-7

cz=-160
oz=100
vp_scale=256		; was 160
centre_x=160
centre_y=128

MACRO PROJECT_EDGE x1,y1,z1,x2,y2,z2,colour
{
	s1x = centre_x + vp_scale * x1 / (z1 + oz - cz)
	s1y = centre_y + vp_scale * y1 / (z1 + oz - cz)
	s2x = centre_x + vp_scale * x2 / (z2 + oz - cz)
	s2y = centre_y + vp_scale * y2 / (z2 + oz - cz)

;	PRINT "LINE FROM y=",s1y,"to",s2y
	w1 = (s1x - centre_x) * 2
	w2 = (s2x - centre_x) * 2
;	PRINT "WIDTH FROM ",w1,"to",w2

	IF s2y<s1y
		PRINT "CULL EDGE"
	ELSE

		IF w1<MIN_W
			EQUB colour+1
		ELIF w1>MAX_W
			EQUB colour+127
		ELSE
			EQUB colour+(INT(w1)-MIN_W)/2
		ENDIF

		\\ startx,starty, endx,endy
		EQUB INT(s1y)
		
		IF w2<MIN_W
			EQUB colour+1
		ELIF w2>MAX_W
			EQUB colour+127
		ELSE
			EQUB colour+(INT(w2)-MIN_W)/2
		ENDIF
		
		EQUB INT(s2y)
	ENDIF
}
ENDMACRO

\\ Verts on side of a cube (square)
v1x=64:v1y=16:v1z=64
v2x=64:v2y=-16:v2z=64
v3x=64:v3y=-16:v3z=-64
v4x=64:v4y=16:v4z=-64

PRINT "v1=(",v1y,v1z,") v2=(",v2y,v2z,") v3=",v3y,v3z,") v4=",v4y,v4z,")"

.projection_list
FOR a,0,255,2
s = SIN(2 * PI * a / 256)
c = COS(2 * PI * a / 256)
\\ Rotate around X axis
\\ Project onto screen
\\ Pick the 2x visible faces

\\ Rotate around X axis
r1y = c*v1y - s*v1z
r1z = s*v1y + c*v1z
r2y = c*v2y - s*v2z
r2z = s*v2y + c*v2z
r3y = c*v3y - s*v3z
r3z = s*v3y + c*v3z
r4y = c*v4y - s*v4z
r4z = s*v4y + c*v4z

PRINT "a=",(360*a/256)
;PRINT "r1=(",r1y,r1z,") r2=(",r2y,r2z,") r3=",r3y,r3z,") r4=",r4y,r4z,")"

\\ Sides of the square (edge of the cube looking down X axis)
l1y = r2y-r1y : l1z = r2z-r1z
l2y = r3y-r2y : l2z = r3z-r2z
l3y = r4y-r3y : l3z = r4z-r3z
l4y = r1y-r4y : l4z = r1z-r4z

\\ Normals to the edges
n1z = l4z : n2z = l1z : n3z = l2z : n4z = l3z

\\ Only edges with positive Z component of normal are visible (facing camera at +ve Z)

;PRINT "l1y=",l1y,"l2y=",l2y,"l3y=",l3y,"l4y=",l4y
;PRINT "l1z=",l1z,"l2z=",l2z,"l3z=",l3z,"l4z=",l4z

IF n1z<-ERR
	PRINT "Edge 1 visible: (",r1y,r1z,") -> (",r2y,r2z,")"
	PROJECT_EDGE v1x,r1y,r1z,v2x,r2y,r2z, 0
ENDIF
IF n2z<-ERR
	PRINT "Edge 2 visible: (",r2y,r2z,") -> (",r3y,r3z,")"
	PROJECT_EDGE v2x,r2y,r2z,v3x,r3y,r3z, 128
ENDIF
IF n3z<-ERR
	PRINT "Edge 3 visible: (",r3y,r3z,") -> (",r4y,r4z,")"
	PROJECT_EDGE v3x,r3y,r3z,v4x,r4y,r4z, 0
ENDIF
IF n4z<-ERR
	PRINT "Edge 4 visible: (",r4y,r4z,") -> (",r1y,r1z,")"
	PROJECT_EDGE v4x,r4y,r4z,v1x,r1y,r1z, 128
ENDIF

EQUB 0

NEXT

EQUB 128

.widths1_zx02
INCBIN "../../build/x-rotator.width1.bin.zx02"

.widths2_zx02
INCBIN "../../build/x-rotator.width2.bin.zx02"

ALIGN &100
.table_image_y
skip &100

.data_end

\ ******************************************************************
\ *	End address to be saved
\ ******************************************************************

.end

\ ******************************************************************
\ *	Save the code
\ ******************************************************************

SAVE "", start, end

\ ******************************************************************
\ *	Space reserved for runtime buffers not preinitialised
\ ******************************************************************

.bss_start

.bss_end


\ ******************************************************************
\ *	Memory Info
\ ******************************************************************

PRINT "------"
PRINT "X-ROTATOR"
PRINT "------"
PRINT "MAIN size =", ~main_end-main_start
PRINT "FX size = ", ~fx_end-fx_start
PRINT "DATA size =",~data_end-data_start
PRINT "BSS size =",~bss_end-bss_start
PRINT "------"
PRINT "HIGH WATERMARK =", ~P%
PRINT "FREE =", ~screen_addr-P%
PRINT "------"

\ ******************************************************************
\ *	Any other files for the disc
\ ******************************************************************
