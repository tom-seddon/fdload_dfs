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

# zx02tool draft notes

`bin/zx02tool.py` wraps zx02, hopefully making it a bit easier to use
as part of a build process that runs a simple sequence of commands (as
opposed to using, say, GNU Make's dependency handling). It maintains a
persistent on-disk cache that maps uncompressed data to the compressed
version, meaning that getting zx02tool to compress a file that has
previously been compressed is cheap. You can get zx02tool to compress
assembled output files (say) on every build, and if the output is the
same as the previous build, it'll take hardly any time at all.

The basic assumption here is that you're generally iterating on one or
two specific things, so the number of files that change from build to
build is typically quite small. On an initial build, and/or possibly
after a `git pull` that changed a bunch of stuff, a bunch of files get
recompressed in series, and maybe it'll be time for a cup of tea - but
when iterating, only the (1? Maybe 2?) changed files get recompressed,
and hopefully it's not too tedious.

## repack

With average iteration time in mind: zx02tool always runs zx02 in
non-optimal mode, as that's so much quicker. But, as a manual step,
zx02tool can repack all the files in its cache in zx02 optimal mode,
which it can do as a multi-core process.

As the cache is keyed off the uncompressed contents, future zx02tool
uses will pick up the now optimally-compressed version of the file. 

The expected workflow is that you'll do a repack when you have a spare
moment, but we might have to tweak this if/when disk space becomes
tight enough that non-optimal compression just ain't enough.

## zx02tool is entirely optional

The zx02tool output is exactly the same as you'd get from zx02, just
produced a bit more quickly in the best case. zx02 can be run some
other way, and the output can be used just the same!

# Folder structure

- `bin` - any generic binaries/tools for general use for building
- `build` (gitignored) - all build output
- `.zx02_cache` (gitignored) - zx02tool cache
- `dependencies` - any 3rd party stuff not specific to this project,
  be it submodules or copies of upstream repo or whatever
- `doc` - any docs
- `src` - source code
- `tests` - misc grab bag of ad-hoc nonsense. The build mustn't depend
  on anything in this folder. Though it may write to it, as it has a
  BeebLink volume in there... so this may still need some tidying up
  
Notes:

- `build` and `.zx02_cache` are separate to simplify having them
  cleaned independently
