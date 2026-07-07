ifndef TASS
$(error to be run only from top-level Makefile)
endif

.PHONY:default
default:
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR0" -o "$(BUILD)/screens1.screen0.mode1.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR1" -o "$(BUILD)/screens1.screen1.mode1.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR2" -o "$(BUILD)/screens1.screen2.mode1.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR3" -o "$(BUILD)/screens1.screen3.mode1.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR4" -o "$(BUILD)/screens1.screen4.mode1.dat.zx02"

	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/3/$$.SCR0" -o "$(BUILD)/screens1.screen0.mode5.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/3/$$.SCR1" -o "$(BUILD)/screens1.screen1.mode5.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/3/$$.SCR2" -o "$(BUILD)/screens1.screen2.mode5.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/3/$$.SCR3" -o "$(BUILD)/screens1.screen3.mode5.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/3/$$.SCR4" -o "$(BUILD)/screens1.screen4.mode5.dat.zx02"

	$(TASS) --nostart -L "$(BUILD)/screens1.mode1.lst" -o "$(BUILD)/screens1.mode1.dat" --vice-labels "--labels=$(BUILD)/screens1.mode1.sym" "screens1.s65" -D MODE=1
	$(TASS) --nostart -L "$(BUILD)/screens1.mode5.lst" -o "$(BUILD)/screens1.mode5.dat" --vice-labels "--labels=$(BUILD)/screens1.mode5.sym" "screens1.s65" -D MODE=5

# since it's 99% compressed data, it's not really worth compressing
#	$(SHELLCMD) copy-file "$(BUILD)/screens1.dat" "$(BUILD)/$$.SCRNS1"
	$(ZX02TOOL) pack "$(BUILD)/screens1.mode5.dat" -o "$(BUILD)/Z.SCRNS15"
	$(ZX02TOOL) pack "$(BUILD)/screens1.mode1.dat" -o "$(BUILD)/Z.SCRNS11"
