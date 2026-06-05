ifndef TASS
$(error to be run only from top-level Makefile)
endif

.PHONY:default
default:
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR0" -o "$(BUILD)/screens1.screen0.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR1" -o "$(BUILD)/screens1.screen1.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR2" -o "$(BUILD)/screens1.screen2.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR3" -o "$(BUILD)/screens1.screen3.dat.zx02"
	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR4" -o "$(BUILD)/screens1.screen4.dat.zx02"
	$(TASS) --nostart -L "$(BUILD)/screens1.lst" -o "$(BUILD)/screens1.dat" "screens1.s65"

# since it's 99% compressed data, it's not really worth compressing
#	$(SHELLCMD) copy-file "$(BUILD)/screens1.dat" "$(BUILD)/$$.SCRNS1"
	$(ZX02TOOL) pack "$(BUILD)/screens1.dat" -o "$(BUILD)/Z.SCRNS1"
