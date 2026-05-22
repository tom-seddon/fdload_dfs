# Build

## Prerequisites

### Windows

- Python 3.x

### Linux

- C/C++ compilers
- Python 3.x
- GNU Make

### macOS

- Xcode
- GNU Make 4+ (install from
  [MacPorts](https://ports.macports.org/port/gmake/) or
  [Homebrew](https://formulae.brew.sh/formula/make))

## Clone the repo

**This repo has submodules**. Clone it with `--recursive`:

    git clone --recursive https://github.com/tom-seddon/fdload_adfsl
	
If you already cloned it without reading that: don't worry. You can
fix it. Change to the working copy and do this:

	git submodule update --init --recursive

## Build the code

Change to the working copy and run `make`.

The output is not very interesting... yet.

