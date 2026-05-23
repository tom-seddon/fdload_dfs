MAKEFLAGS+=--no-print-directory

##########################################################################
##########################################################################

ifeq ($(OS),Windows_NT)
UNAME:=Windows_NT
PYTHON:=py -3
else
UNAME:=$(shell uname -s)
PYTHON:=/usr/bin/python3
endif

ifeq ($(UNAME),Darwin)
# The GNU Make supplied with Xcode is old. The one from Homebrew or
# MacPorts is better, but it's called gmake.
RECENT_GNU_MAKE:=gmake
else
RECENT_GNU_MAKE:=$(MAKE)
endif

##########################################################################
##########################################################################

ifeq ($(VERBOSE),)
.SILENT:
endif

# Use $(__VERBOSE) to supply --verbose only when made with VERBOSE=1.
__VERBOSE:=$(if $(VERBOSE),--verbose,)

##########################################################################
##########################################################################

SHELLCMD_PY:=dependencies/shellcmd.py/shellcmd.py

PWD:=$(shell $(PYTHON) "$(SHELLCMD_PY)" realpath .)
export PWD

# How to run shellcmd.py.
SHELLCMD:=$(PYTHON) "$(PWD)/$(SHELLCMD_PY)"
export SHELLCMD

##########################################################################
##########################################################################

# Folder paths.
BIN:=$(PWD)/bin
BUILD:=$(PWD)/build

# Executable paths.
ZX02:=$(BIN)/zx02
BEEBASM:=$(BIN)/beebasm
TASS:=$(BIN)/64tass

##########################################################################
##########################################################################

.PHONY:build
build:
ifneq ($(UNAME),Windows_NT)
# Build zx02 if required.
	test -f "$(ZX02)" || (cd "dependencies/zx02" && $(RECENT_GNU_MAKE) all && cp "build/zx02" "$(ZX02)")

# Build BeebAsm if required.
	test -f "$(BEEBASM)" || (cd "dependencies/beebasm/src" && $(MAKE) code VERBOSE=$(VERBOSE) && cp "../beebasm" "$(BEEBASM)")

# Build 64tass if required.
	test -f "$(TASS)" || (cd "dependencies/tass64-code.r3243" && $(MAKE) 64tass && cp "64tass" "$(TASS)")
endif
	$(BEEBASM) --help
	$(TASS) --help
	-$(ZX02) -h

##########################################################################
##########################################################################

.PHONY:clean
clean:
	$(SHELLCMD) rm-tree "$(BUILD)"
ifneq ($(UNAME),Windows_NT)
	cd "dependencies/zx02" && $(RECENT_GNU_MAKE) clean
	rm -f "$(BIN)/zx02"
	cd "dependencies/beebasm/src" && $(RECENT_GNU_MAKE) clean VERBOSE=$(VERBOSE)
	rm -f "$(BIN)/beebasm"
	cd "dependencies/tass64-code.r3243" && $(MAKE) clean
	rm -f "$(BIN)/64tass"
endif

##########################################################################
##########################################################################

# Intended for manual invocation.

# Invoke from a VC++ command line tools prompt.
.PHONY:make_windows_zx02
make_windows_zx02: _SRC:=$(PWD)/dependencies/zx02/src
make_windows_zx02:
	$(SHELLCMD) mkdir "$(BUILD)"
	cd /d "$(BUILD)" && cl /W4 /Zi /O2 "/Fe$(PWD)/bin/zx02.exe" "$(_SRC)/compress.c" "$(_SRC)/memory.c" "$(_SRC)/optimize.c" "$(_SRC)/zx02.c"

.PHONY:test_zx02tool
test_zx02tool:
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN0"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN1"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN2"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN3"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN4"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN5"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN6"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN7"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN8"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN9"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN10"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN11"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN12"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN13"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN14"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN15"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN16"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN17"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN18"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN19"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN20"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN21"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN22"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN23"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN24"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN25"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN26"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN27"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN28"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN29"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN30"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN31"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN32"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN33"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN34"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN35"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN36"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN37"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN38"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN39"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN40"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN41"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN42"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN43"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN44"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN45"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN46"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN47"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN48"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN49"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN50"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN51"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN52"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN53"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN54"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN55"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN56"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN57"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN58"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN59"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN60"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN61"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN62"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN63"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN64"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN65"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN66"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN67"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN68"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN69"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN70"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN71"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN72"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN73"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN74"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN75"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN76"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN77"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN78"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN79"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN80"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN81"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN82"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN83"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN84"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN85"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN86"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN87"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN88"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN89"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN90"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN91"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN92"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN93"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN94"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN95"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN96"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN97"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN98"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN99"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN100"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN101"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN102"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN103"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN104"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN105"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN106"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN107"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN108"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN109"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN110"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN111"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN112"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN113"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN114"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN115"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN116"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN117"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN118"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN119"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN120"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN121"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN122"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN123"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN124"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN125"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN126"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN127"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN128"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN129"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN130"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN131"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN132"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN133"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN134"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN135"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN136"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN137"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN138"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN139"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN140"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN141"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN142"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN143"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN144"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN145"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN146"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN147"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN148"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN149"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN150"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN151"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN152"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN153"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN154"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN155"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN156"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN157"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN158"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN159"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN160"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN161"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN162"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN163"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN164"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN165"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN166"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN167"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN168"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN169"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN170"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN171"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN172"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN173"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN174"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN175"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN176"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN177"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN178"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN179"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN180"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN181"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN182"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN183"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN184"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN185"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN186"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN187"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN188"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN189"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN190"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN191"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN192"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN193"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN194"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN195"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN196"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN197"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN198"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN199"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN200"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN201"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN202"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN203"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN204"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN205"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN206"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN207"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN208"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN209"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN210"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN211"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN212"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN213"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN214"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN215"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN216"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN217"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN218"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN219"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN220"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN221"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN222"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN223"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN224"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN225"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN226"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN227"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN228"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN229"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN230"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN231"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN232"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN233"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN234"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN235"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN236"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN237"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN238"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN239"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN240"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN241"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN242"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN243"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN244"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN245"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN246"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN247"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN248"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN249"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN250"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN251"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN252"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN253"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN254"
	$(PYTHON) "bin/zx02tool.py" pack "tests/screens/$$.SCREEN255"
