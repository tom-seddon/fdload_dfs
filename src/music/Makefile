ifndef BEEBASM
$(error to be run only from top-level Makefile)
endif

.PHONY:default
default: $(BUILD)/U_LOADER.vgc
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(BEEBASM) -v -i "music_bank.asm" -o "$(BUILD)/music_bank.dat" > "$(BUILD)/music_bank.txt"
	$(ZX02TOOL) pack "$(BUILD)/music_bank.dat" -o "$(BUILD)/Z.MUSIC"

$(BUILD)/U_LOADER.vgc : ./vgms/U_LOADER.vgm
	$(PYTHON) "../../dependencies/vgm-packer/vgmpacker.py" "$<" -o "$@"
