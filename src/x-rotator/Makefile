ifndef TASS
$(error to be run only from top-level Makefile)
endif

.PHONY:default
default:
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(ZX02TOOL) pack --optimal "assets/width1.bin" -o "$(BUILD)/x-rotator.width1.bin.zx02"
	$(ZX02TOOL) pack --optimal "assets/width2.bin" -o "$(BUILD)/x-rotator.width2.bin.zx02"

	$(BEEBASM) -v -i "x-rotator.asm" -o "$(BUILD)/x-rotator.dat" > "$(BUILD)/x-rotator.txt"
	$(ZX02TOOL) pack "$(BUILD)/x-rotator.dat" -o "$(BUILD)/Z.XROT"
