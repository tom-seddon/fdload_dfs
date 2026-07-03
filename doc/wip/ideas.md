# Random ideas for FX to try.

## Kieran

### X-rotator

Proof-of-concept already added.
- Pre-generated screen buffers containing 128 screen centred symmetrical spans (approx 64 to 320 width in steps of 2).
- Two colours stored in top / bottom half of the screen.
- Alternative dither pattern stored in main / shadow RAM.
- Precalculated tables list the visible face edges of a symmetrical spinning cuboid rotating around the X axis.
- The table stores X (width),Y values which are walked with Bresenham at runtime to write into a Y buffer (width X on line Y).
- Animation lasts 256 frames (one rotation).

In general any scene could be computed offline, including depth with occulsion.
- For frame N display span of width X on line Y.
- For a 3D 'scene' compute the width after perspective projection.
- For occluding objects, use a Z buffer to display the 'nearest' span.
- These must be fully occluding (e.g. all objects are the same world space width) as we cannot display more than one span on the same line.
- Best example is Ghost NOP (Amstrad CPC): https://youtu.be/wCJUk4PVHCo?si=u6ssOtmK-uzSMpBP (timecode 55s)

### Wide image panned horizontally

C64-type effect, typically the group or demo logo as a wide (e.g. 2x screen width) image that is panned over horizontally in a smooth motion.

- Without any vertical motion just requires a Vertical Rupture per row to select screen start address character.
- Mostly requires RAM to achieve maximum horizontal resolution.
- 2x screen width should be trivial with main & SHADOW buffers (e.g. 640x256 in MODE 1)
- Scrolling limited to character resolution unless more RAM is used for offsets.
- Could be combined with an overscan widescreen MODE configuration (e.g. 96x27 chars = 384x216 in MODE 1) for added effect?
- Show off would be to add software sprite(s) over the top, e.g. a static logo in the corner.
- Extra show off would be to use animated main/SHADOW cutouts over the top of the panned image, e.g. to simulate a spotlight. This would require maximum RAM (2x copies of the wider image).

### Tall image panned vertically

C64-type effect, typically a very impressive image that is single single screen width but many screens tall. Pan up the image slowly showing the impressive artwork (from the artist that we don't have yet :)

- Similar to the above, this mostly requires lots of RAM to achieve maximum vertical resolution.
- Use vertical adjust trick to single scanline scroll the viewport, requires Vertical Rupture.
- Alternative could be to use RVI to select specific RAM line to display every scanline but burns a lot of cycles.
- Show off would be to unpack additional screen data on the fly to allow much taller vertical resolution (rather than having it all expanded in RAM.)
- Extra show off would be to stream from disk to allow an effectively infinite height scroll.
- Could be combined with the main/SHADOW cutout idea, as above.
- Could be combined with software sprite(s) over the top, as above.
- Could be combined with MODE 1 8 colour palette code to show a 'full colour high res' picture (photo).

### Steal stuff from Funky Fresh

- Frak path zoomer most obviously.
- Textured twister.

### Revisit stuff from Twisted Brain

- Parallax bars redux.
