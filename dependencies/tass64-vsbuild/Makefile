MAKEFLAGS+=--no-print-directory $(if $(VERBOSE),,--silent)

##########################################################################
##########################################################################

# only tested on Windows/VS2022 so far, though...

ifeq ($(OS),Windows_NT)
UNAME:=Windows_NT
PYTHON:=py -3
else
UNAME:=$(shell uname -s)
PYTHON:=/usr/bin/python3
endif

##########################################################################
##########################################################################

SHELLCMD:=$(PYTHON) "../shellcmd.py/shellcmd.py"

BUILD:=../../build.tass64

##########################################################################
##########################################################################

.PHONY:default
default:
	$(error Specify target)

##########################################################################
##########################################################################

.PHONY:init_vs2022
init_vs2022:
	$(MAKE) _init_vs VSVER=17 VSYEAR=2022

##########################################################################
##########################################################################

.PHONY:_init_vs
_init_vs: VSVER=$(error Must specify VSVER)
_init_vs: VSYEAR=$(error Must specify VSYEAR)
_init_vs: 
	$(MAKE) _init_vs_2 "CMAKE_PATH=$(shell "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -version $(VSVER) -property installationPath)/common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe"

.PHONY:_init_vs_2
_init_vs_2: _BUILD:=$(BUILD)/vs$(VSYEAR)
_init_vs_2:
	$(SHELLCMD) rm-tree "$(_BUILD)"
	"$(CMAKE_PATH)" -G "Visual Studio $(VSVER) $(VSYEAR)" -B "$(_BUILD)" -S .

##########################################################################
##########################################################################
