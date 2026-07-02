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

	$(TASS) --nostart -L "$(BUILD)/framework_bank.loader.lst" -o "$(BUILD)/framework_bank.loader.dat" "framework_bank.loader.s65" --labels-root=framework_bank_exports "--labels=$(BUILD)/framework_bank.loader.exports.asm" "--dump-labels" "--labels=$(BUILD)/framework_bank.loader.all.sym"
	$(ZX02TOOL) pack "$(BUILD)/framework_bank.loader.dat" -o "$(BUILD)/framework_bank.loader.dat.zx02"

# separate the loader labels into labels always applicable, and labels
# only applicable when the loader is resident. (If I'd thought of this
# when writing the code, maybe I'd have structured it a bit
# differently...)
	$(PYTHON) "$(BEEB_BIN)/filter_64tass_labels.py" -o "$(BUILD)/framework_bank.loader.sym" --dump-labels-input --dump-labels-output --value-range None 0x800 --value-range 0x1000 None "$(BUILD)/framework_bank.loader.all.sym" 
	$(PYTHON) "$(BEEB_BIN)/filter_64tass_labels.py" -o "$(BUILD)/framework_bank.loader.main_ram.sym" --dump-labels-input --dump-labels-output --value-range 0x800 0x1000 "$(BUILD)/framework_bank.loader.all.sym" 

	$(TASS) --cbm-prg -L "$(BUILD)/boot.lst" -o "$(BUILD)/boot.prg" "boot.s65" --dump-labels "--labels=$(BUILD)/boot.sym"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/boot.prg" "$(BEEBLINK)/Z/$$.!BOOT"

	$(BEEBASM) -w -i "framework_bank.asm" -o "$(BUILD)/framework_bank.dat" > "$(BUILD)/framework_bank.txt"
	$(ZX02TOOL) pack "$(BUILD)/framework_bank.dat" -o "$(BUILD)/Z.FW"

