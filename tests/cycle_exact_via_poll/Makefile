ifndef TASS
$(error to be run only from top-level Makefile)
endif

_BEEBLINK:=$(BEEBLINK)/T
_SSD:=$(BUILD)/cycle_exact_via_poll.ssd

.PHONY:default
default:
	$(SHELLCMD) echo-emacs-compilation-mode-marker

	$(BEEBASM) -v -i "cycle_exact_via_poll.asm" -boot POLL -do "$(_SSD)" > "$(BUILD)/cycle_exact_via_poll.txt"

	$(SHELLCMD) rm-tree "$(_BEEBLINK)"
	$(PYTHON) "../../dependencies/beeb/bin/ssd_extract.py" "$(_SSD)" -0 -o "$(_BEEBLINK)"
