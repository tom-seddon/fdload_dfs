# Build goals

1. Build on Windows and POSIX-type systems (in this case: macOS and
   Linux)

2. Require only a few easily-installed dependencies (that you might
   expect a software developer to have installed already)
   
3. Don't require a C++ compiler on Windows
   
4. Produce bit-identical results on all platforms

# Build targets

## `build`

Default targets. Builds everything.

## `clean`

Deletes 6502-related output only.

## `clean_zx02_cache`

Deletes zx02 cache. You may be in for a bit of a wait on the next
build.

## `clean_dependencies` (no-op on Windows)

Clean dependencies' build byproducts.

## `clean_everything`

Do all of the above: `clean`, `clean_zx02_cache` and
`clean_dependencies`.

# Build notes

macOS and Linux are similar enough that they both come into the same
category. Windows is its own thing.

On POSIX-type systems, build dependencies from source as part of the
build process. (See existing examples: beebasm, 64tass, and zx02.)
After building, copy the executable into the `bin` folder.

On Windows, supply any dependencies as prebuilt exes. Put them into
the `bin` folder, same name as the POSIX-type executable.

(This way, the same path can be used on all platforms, without
necessarily needing to have a variable for it. Don't forget to use `/`
as the path separator.)

## `$(BUILD)`

## `$(SHELLCMD)`

There are various references in the Makefile to `$(SHELLCMD)` - this
is some janky Python script that I've been adding to for years, that
provides consistent syntax for things that would otherwise be
different across Windows, macOS and Linux.

You can run this script manually. It responds to `--help`.

# Folder structure

- `bin` - any generic binaries/tools for general use for building
- `build` (gitignored) - all build output
- `.zx02_cache` (gitignored) - zx02tool cache
- `dependencies` - any 3rd party stuff not specific to this project,
  be it submodules or copies of upstream repo or whatever
- `doc` - any docs
- `src` - source code
- `tests` - misc grab bag of ad-hoc nonsense. The build shouldn't
  depend on anything in this folder, though for now... it does
  
Notes:

- `build` and `.zx02_cache` are separate to simplify having them
  cleaned independently
