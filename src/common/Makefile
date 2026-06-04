ifndef TASS
$(error to be run only from top-level Makefile)
endif

##########################################################################
##########################################################################

.PHONY:default
default:
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(TASS) --cbm-prg -L "$(BUILD)/zx02_decomp_basic_tester.lst" -o "$(BUILD)/zx02_decomp_basic_tester.prg" "zx02_decomp_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/zx02_decomp_basic_tester.prg" "$(BEEBLINK)/Z/$$.ZX02"

	$(TASS) --cbm-prg -L "$(BUILD)/fdload_basic_tester.lst" -o "$(BUILD)/fdload_basic_tester.prg" "fdload_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/fdload_basic_tester.prg" "$(BEEBLINK)/Z/$$.FDLOAD"

	$(TASS) --cbm-prg -L "$(BUILD)/dfs_basic_tester.lst" -o "$(BUILD)/dfs_basic_tester.prg" "dfs_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/dfs_basic_tester.prg" "$(BEEBLINK)/Z/$$.DFS"

	$(TASS) --nostart -L "$(BUILD)/framework_bank.loader.lst" -o "$(BUILD)/framework_bank.loader.dat" "framework_bank.loader.s65" --labels-root=framework_bank_exports "--labels=$(BUILD)/framework_bank.loader.exports.asm"
	$(ZX02TOOL) pack "$(BUILD)/framework_bank.loader.dat" -o "$(BUILD)/framework_bank.loader.dat.zx02"

	$(TASS) --nostart -L "$(BUILD)/framework_page02.lst" -o "$(BUILD)/framework_page02.dat" "framework_page02.s65"
	$(ZX02TOOL) pack "$(BUILD)/framework_page02.dat" -o "$(BUILD)/framework_page02.dat.zx02"

	$(TASS) --cbm-prg -L "$(BUILD)/boot.lst" -o "$(BUILD)/boot.prg" "boot.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/boot.prg" "$(BEEBLINK)/Z/$$.!BOOT"

	$(BEEBASM) -w -i "framework_bank.asm" -o "$(BUILD)/framework_bank.dat" > "$(BUILD)/framework_bank.txt"
	$(ZX02TOOL) pack "$(BUILD)/framework_bank.dat" -o "$(BUILD)/Z.FW"

#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR0" -o "$(BEEBLINK)/Z/Z.SCR0"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR1" -o "$(BEEBLINK)/Z/Z.SCR1"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR2" -o "$(BEEBLINK)/Z/Z.SCR2"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR3" -o "$(BEEBLINK)/Z/Z.SCR3"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR4" -o "$(BEEBLINK)/Z/Z.SCR4"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR5" -o "$(BEEBLINK)/Z/Z.SCR5"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR6" -o "$(BEEBLINK)/Z/Z.SCR6"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR7" -o "$(BEEBLINK)/Z/Z.SCR7"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR8" -o "$(BEEBLINK)/Z/Z.SCR8"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR9" -o "$(BEEBLINK)/Z/Z.SCR9"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR10" -o "$(BEEBLINK)/Z/Z.SCR10"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR11" -o "$(BEEBLINK)/Z/Z.SCR11"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR12" -o "$(BEEBLINK)/Z/Z.SCR12"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR13" -o "$(BEEBLINK)/Z/Z.SCR13"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR14" -o "$(BEEBLINK)/Z/Z.SCR14"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR15" -o "$(BEEBLINK)/Z/Z.SCR15"
#	$(ZX02TOOL) pack --optimal "$(BEEBLINK)/1/$$.SCR16" -o "$(BEEBLINK)/Z/Z.SCR16"
