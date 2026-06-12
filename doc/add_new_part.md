All paths relative to working copy root.

Add new folder in `./src/` to hold the code.

Add line to `build` target in `./Makefile`. (The existing ones would
serve as an example.) The process should produce file(s) in `./build/`
with a DFS-style name: `$.WHATEVS` if uncompressed, or `Z.WHATEVS` if
compressed with zx02tool.

Modify the `ssd_create.py` invocation to add the file(s). The files
are added to the disk in the order given.

Modify `./src/common/framework_bank.asm` to load the new part. See
`demo_loop`. The demo loop should be 
