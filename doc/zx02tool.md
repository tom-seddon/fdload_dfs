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

With average iteration time in mind, zx02tool runs zx02 in non-optimal
mode by default, as that's so much quicker. But, as a manual step,
zx02tool can repack all the files in its cache in zx02 optimal mode,
which it can do as a multi-core process.

As the cache is keyed off the uncompressed contents, future zx02tool
uses will pick up the now optimally-compressed version of the file. 

The expected workflow is that you'll do a repack when you have a spare
moment, but we might have to tweak this if/when disk space becomes
tight enough that non-optimal compression just ain't enough.

## force optimal mode

For files that are known to change very rarely (or less), you can
supply `--optimal` to have zx02tool always pack in optimal mode.

## zx02tool is entirely optional

The zx02tool output is exactly the same as you'd get from zx02, just
produced a bit more quickly in the best case. zx02 can be run some
other way, and the output can be used just the same!
