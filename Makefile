MAKEFLAGS+=--no-print-directory $(if $(VERBOSE),,--silent)

##########################################################################
##########################################################################

ifeq ($(OS),Windows_NT)
UNAME:=Windows_NT
PYTHON:=py -3
else
UNAME:=$(shell uname -s)
PYTHON:=/usr/bin/python3
endif

export PYTHON

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

# busybox-type Python script that provides a consistent syntax for
# this or that across Windows, macOS and Linux.
#
# Follow the existing examples. Or run it manually - it responds to
# --help.
SHELLCMD_PY:=dependencies/shellcmd.py/shellcmd.py

ROOT:=$(shell $(PYTHON) "$(SHELLCMD_PY)" realpath .)
export ROOT

# How to run shellcmd.py.
SHELLCMD:=$(PYTHON) "$(ROOT)/$(SHELLCMD_PY)"
export SHELLCMD

##########################################################################
##########################################################################

BIN:=$(ROOT)/bin
BEEB_BIN:=$(ROOT)/dependencies/beeb/bin
BEEBLINK:=$(ROOT)/tests/beeblink/fdload_dfs
export BIN
export BEEB_BIN
export BEEBLINK

# Absolute path for build byproducts of all kinds.
BUILD:=$(ROOT)/build
export BUILD

# Names of executable files for tools. No extension and no args.
ZX02_EXE:=$(BIN)/zx02
BEEBASM_EXE:=$(BIN)/beebasm
TASS_EXE:=$(BIN)/64tass

# How to run tools. May include command line options.
ZX02:=$(ZX02_EXE)
BEEBASM:=$(BEEBASM_EXE)		#TODO should this have -w?
TASS:=$(TASS_EXE) -Wall --case-sensitive $(if $(VERBOSE),,--quiet) --m65c02 --verbose-list --line-numbers
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

	$(MAKE) -C src/common
	$(MAKE) -C src/screens1
	$(MAKE) -C src/music

	$(PYTHON) "$(BEEB_BIN)/ssd_create.py" --strict --opt4 2 -o "$(BUILD)/screens.0.ssd" "$(BEEBLINK)/Z/$$.!BOOT" "$(BUILD)/Z.FW" "$(BUILD)/Z.MUSIC" "$(BUILD)/Z.SCRNS11" "$(BUILD)/Z.SCRNS15"

	$(PYTHON) "$(BEEB_BIN)/dsd_create.py" -o "$(BUILD)/screens.dsd" -0 "$(BUILD)/screens.0.ssd"
	$(SHELLCMD) copy-file "$(BUILD)/screens.dsd" "$(BEEBLINK)/Z/D.SCREENS"

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
	test -f "$(TASS_EXE)" || (cd "dependencies/64tass/tass64-code.r3243" && $(MAKE) 64tass && cp "64tass" "$(TASS_EXE)")
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
	cd "dependencies/64tass/tass64-code.r3243" && $(MAKE) clean
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
# deliberately doesn't change working folder.
	$(MAKE) -f "tests/tom/Makefile"

##########################################################################
##########################################################################

.PHONY:test_cycle_exact_via_poll
test_cycle_exact_via_poll: _build_dependencies
	$(MAKE) -C "tests/cycle_exact_via_poll"
