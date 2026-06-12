All paths relative to working copy root.

Add new folder in `./src/` to hold the code.

Add line to `build` target in `./Makefile`. (The existing ones would
serve as an example.) The process should produce file(s) in `./build/`
with a DFS-style name: `$.WHATEVS` if uncompressed, or `Z.WHATEVS` if
compressed with zx02tool.

Modify the `ssd_create.py` invocation to add the file(s). The files
are added to the disk in the order given.

Modify `./src/common/framework_bank.asm` to load the new part. See
`demo_loop`. Follow one of the existing examples.

# Testing for transition completion

Currently: monitor `transition_current_state`. When bit 7 is set, the
screen is filled with a solid colour, visually speaking. Bits 0-3 are
the index of that colour.

This reflects the state of the screen, visually speaking, rather than
necessarily display contents.

For example: if the palette pulse transition effect is running, and
reports the screen is fully black, that's because it's set all palette
entries to 0. Display memory could be full of junk and require
clearing.

Alternatively: if the snake transition effect is running, and reports
the screen is fully black, that's because it's cleared all display RAM
to $00.

Once transition end detected, call `jsr framework_stop_transition`. 
