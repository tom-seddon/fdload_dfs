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

ROOT:=$(shell $(PYTHON) "$(SHELLCMD_PY)" realpath .)
export ROOT

# How to run shellcmd.py.
SHELLCMD:=$(PYTHON) "$(ROOT)/$(SHELLCMD_PY)"
export SHELLCMD

##########################################################################
##########################################################################

# Folder paths.
BIN:=$(ROOT)/bin
BEEB_BIN:=$(ROOT)/dependencies/beeb/bin
BUILD:=$(ROOT)/build
BEEBLINK:=$(ROOT)/tests/beeblink/fdload_dfs
export BIN
export BEEB_BIN
export BUILD

# Names of executable files for tools. No extension and no args.
ZX02_EXE:=$(BIN)/zx02
BEEBASM_EXE:=$(BIN)/beebasm
TASS_EXE:=$(BIN)/64tass

# How to run tools. May include command line options.
ZX02:=$(ZX02_EXE)
BEEBASM:=$(BEEBASM_EXE)
TASS:=$(TASS_EXE) -Wall --case-sensitive $(if $(VERBOSE),,--quiet) --long-branch --m65c02 --verbose-list
ZX02TOOL:=$(PYTHON) "$(BIN)/zx02tool.py"
export ZX02
export BEEBASM
export TASS
export ZX02TOOL

##########################################################################
##########################################################################

.PHONY:build
build: _build_dependencies
	$(SHELLCMD) mkdir "$(BUILD)" "$(BEEBLINK)/Z"

	$(TASS) --cbm-prg -L "$(BUILD)/zx02_decomp_basic_tester.lst" -o "$(BUILD)/zx02_decomp_basic_tester.prg" "src/common/zx02_decomp_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/zx02_decomp_basic_tester.prg" "$(BEEBLINK)/Z/$$.ZX02"

	$(TASS) --cbm-prg -L "$(BUILD)/fdload_basic_tester.lst" -o "$(BUILD)/fdload_basic_tester.prg" "src/common/fdload_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/fdload_basic_tester.prg" "$(BEEBLINK)/Z/$$.FDLOAD"

	$(TASS) --cbm-prg -L "$(BUILD)/dfs_basic_tester.lst" -o "$(BUILD)/dfs_basic_tester.prg" "src/common/dfs_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/dfs_basic_tester.prg" "$(BEEBLINK)/Z/$$.DFS"

	$(TASS) --nostart -L "$(BUILD)/framework_bank.lst" -o "$(BUILD)/framework_bank.dat" "src/common/framework_bank.s65" --labels-root=framework_bank_exports "--labels=$(BUILD)/framework_bank.exports.s65"
	$(ZX02TOOL) pack "$(BUILD)/framework_bank.dat" -o "$(BUILD)/framework_bank.dat.zx02"

	$(TASS) --nostart -L "$(BUILD)/framework_page02.lst" -o "$(BUILD)/framework_page02.dat" "src/common/framework_page02.s65"
	$(ZX02TOOL) pack "$(BUILD)/framework_page02.dat" -o "$(BUILD)/framework_page02.dat.zx02"

	$(TASS) --cbm-prg -L "$(BUILD)/boot.lst" -o "$(BUILD)/boot.prg" "src/common/boot.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/boot.prg" "$(BEEBLINK)/Z/$$.!BOOT"

	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR0" -o "$(BEEBLINK)/Z/Z.SCR0"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR1" -o "$(BEEBLINK)/Z/Z.SCR1"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR2" -o "$(BEEBLINK)/Z/Z.SCR2"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR3" -o "$(BEEBLINK)/Z/Z.SCR3"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR4" -o "$(BEEBLINK)/Z/Z.SCR4"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR5" -o "$(BEEBLINK)/Z/Z.SCR5"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR6" -o "$(BEEBLINK)/Z/Z.SCR6"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR7" -o "$(BEEBLINK)/Z/Z.SCR7"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR8" -o "$(BEEBLINK)/Z/Z.SCR8"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR9" -o "$(BEEBLINK)/Z/Z.SCR9"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR10" -o "$(BEEBLINK)/Z/Z.SCR10"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR11" -o "$(BEEBLINK)/Z/Z.SCR11"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR12" -o "$(BEEBLINK)/Z/Z.SCR12"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR13" -o "$(BEEBLINK)/Z/Z.SCR13"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR14" -o "$(BEEBLINK)/Z/Z.SCR14"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR15" -o "$(BEEBLINK)/Z/Z.SCR15"
	$(ZX02TOOL) pack "$(BEEBLINK)/1/$$.SCR16" -o "$(BEEBLINK)/Z/Z.SCR16"

	$(PYTHON) "$(BEEB_BIN)/ssd_create.py" --opt4 2 -o "$(BUILD)/screens.0.ssd" "$(BEEBLINK)/Z/$$.!BOOT" "$(BEEBLINK)/Z/Z.SCR0" "$(BEEBLINK)/Z/Z.SCR1" "$(BEEBLINK)/Z/Z.SCR2" "$(BEEBLINK)/Z/Z.SCR3" "$(BEEBLINK)/Z/Z.SCR4" "$(BEEBLINK)/Z/Z.SCR5" "$(BEEBLINK)/Z/Z.SCR6" "$(BEEBLINK)/Z/Z.SCR7" "$(BEEBLINK)/Z/Z.SCR8" "$(BEEBLINK)/Z/Z.SCR9" "$(BEEBLINK)/Z/Z.SCR10" "$(BEEBLINK)/Z/Z.SCR11" "$(BEEBLINK)/Z/Z.SCR12" "$(BEEBLINK)/Z/Z.SCR13" "$(BEEBLINK)/Z/Z.SCR14" "$(BEEBLINK)/Z/Z.SCR15"
	$(PYTHON) "$(BEEB_BIN)/dsd_create.py" -o "$(BUILD)/screens.dsd" -0 "$(BUILD)/screens.0.ssd"

##########################################################################
##########################################################################

.PHONY:clean
clean:
	$(SHELLCMD) rm-tree "$(BUILD)"
	$(SHELLCMD) rm-tree "$(BEEBLINK)/Z"

##########################################################################
##########################################################################

.PHONY:clean_everything
clean_everything: clean clean_zx02_cache clean_dependencies

##########################################################################
##########################################################################

.PHONY:clean_zx02_cache
clean_zx02_cache:
	$(SHELLCMD) rm-tree ".zx02_cache"

##########################################################################
##########################################################################

.PHONY:zx02_repack
zx02_repack:
	$(ZX02TOOL) repack

##########################################################################
##########################################################################

.PHONY:_build_dependencies
_build_dependencies:
ifneq ($(UNAME),Windows_NT)
# build/zx02 zx02 if required.
	test -f "$(ZX02_EXE)" || (cd "dependencies/zx02" && $(RECENT_GNU_MAKE) all && cp "build/zx02" "$(ZX02_EXE)")

# Build BeebAsm if required.
	test -f "$(BEEBASM_EXE)" || (cd "dependencies/beebasm/src" && $(MAKE) code VERBOSE=$(VERBOSE) && cp "../beebasm" "$(BEEBASM_EXE)")

# Build 64tass if required.
	test -f "$(TASS_EXE)" || (cd "dependencies/tass64-code.r3243" && $(MAKE) 64tass && cp "64tass" "$(TASS_EXE)")
endif

##########################################################################
##########################################################################

.PHONY:clean_dependencies
clean_dependencies:
ifneq ($(UNAME),Windows_NT)
	cd "dependencies/zx02" && $(RECENT_GNU_MAKE) clean
	rm -f "$(ZX02_EXE)"
	cd "dependencies/beebasm/src" && $(RECENT_GNU_MAKE) clean VERBOSE=$(VERBOSE)
	rm -f "$(BEEBASM_EXE)"
	cd "dependencies/tass64-code.r3243" && $(MAKE) clean
	rm -f "$(TASS_EXE)"
endif

##########################################################################
##########################################################################

# Intended for manual invocation.

# Invoke from a VC++ command line tools prompt.
.PHONY:make_windows_zx02
make_windows_zx02: _SRC:=$(ROOT)/dependencies/zx02/src
make_windows_zx02:
	$(SHELLCMD) mkdir "$(BUILD)"
	cd /d "$(BUILD)" && cl /W4 /Zi /O2 "/Fe$(ROOT)/bin/zx02.exe" "$(_SRC)/compress.c" "$(_SRC)/memory.c" "$(_SRC)/optimize.c" "$(_SRC)/zx02.c"

##########################################################################
##########################################################################

.PHONY:test_zx02tool
test_zx02tool: _build_dependencies
	$(MAKE) -C "tests/test_zx02tool"

##########################################################################
##########################################################################

.PHONY:_tom
_tom:
	$(MAKE) -f "tests/tom/Makefile"
