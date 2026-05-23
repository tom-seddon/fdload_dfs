# Build goals

1. Build on Windows, macOS and Linux

2. Require only a few easily-installed dependencies (that you might
   expect a software developer to have installed already)
   
3. Don't require a C++ compiler on Windows
   
4. Produce bit-identical results on all platforms

# Build notes

macOS and Linux are similar enough that they both come into the same
category ("POSIX-type"). Windows is its own thing.

On POSIX-type systems, build dependencies from source as part of the
build process. (See existing examples: beebasm, 64tass, and zx02.)
After building, copy the executable into the `bin` folder.

On Windows, supply any dependencies as prebuilt exes. Put them into
the `bin` folder, same name as the POSIX-type executable.

(This way, the same path can be used on all platforms, without
necessarily needing to have a variable for it. Don't forget to use `/`
as the path separator.)

# Updating dependencies for Windows

A slightly manual process. Try to ensure the versions are about the
same on all platforms, but any issues will come out in the wash.

After updating the dependencies, commit changes to the EXEs in `bin`.

## GNU Make

Copy appropriate GNU Make exe into `bin\gmake.exe`.

## 64tass

Download appropriate zip from
https://sourceforge.net/projects/tass64/files/binaries/ and copy its
`64tass.exe` into `bin\64tass.exe`.

## BeebAsm

Load `dependencies\beebasm\src\VS2010\BeebAsm.sln` into Visual Studio.
Let it upgrade everything.

Build `Release` configuration. Any warnings are benign... hopefully.

Copy `dependencies\beebasm\beebasm.exe` into `bin\beebasm.exe`.

Quit Visual Studio and revert all the changes to the submodule's
working copy.

## zx02

Run `x64 Native Tools Command Prompt`.

Change to working copy folder.

Run `make make_windows_zx02` to recreate `bin\zx02.exe` and
`bin\zx02.pdb` (which may not prove useful). Any warnings are
benign... hopefully.
