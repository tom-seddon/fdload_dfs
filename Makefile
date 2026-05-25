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
TASS:=$(TASS_EXE) -Wall --case-sensitive --cbm-prg $(if $(VERBOSE),,--quiet) --long-branch --m65c02 --verbose-list
ZX02TOOL:=$(PYTHON) "$(BIN)/zx02tool.py"
export ZX02
export BEEBASM
export TASS
export ZX02TOOL

##########################################################################
##########################################################################

.PHONY:build
build: _build_dependencies
	$(TASS) -L "$(BUILD)/zx02_decomp_basic_tester.lst" -o "$(BUILD)/zx02_decomp_basic_tester.prg" "src/common/zx02_decomp_basic_tester.s65"
	$(PYTHON) "$(BEEB_BIN)/prg2bbc.py" --io "$(BUILD)/zx02_decomp_basic_tester.prg" "$(BEEBLINK)/Z/$$.ZX02"

##########################################################################
##########################################################################

.PHONY:clean
clean: _clean_dependencies
	$(SHELLCMD) rm-tree "$(BUILD)"

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

.PHONY:_clean_dependencies
_clean_dependencies:
ifneq ($(UNAME),Windows_NT)
	cd "dependencies/zx02" && $(RECENT_GNU_MAKE) clean
	rm -f "$(ZX02)"
	cd "dependencies/beebasm/src" && $(RECENT_GNU_MAKE) clean VERBOSE=$(VERBOSE)
	rm -f "$(BEEBASM)"
	cd "dependencies/tass64-code.r3243" && $(MAKE) clean
	rm -f "$(TASS)"
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
	$(MAKE)

