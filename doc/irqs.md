# Default IRQ handler

The IRQ setup is a 2-stage affair involving the system VIA CA1/vsync IRQ, and system VIA T2.

1. vsync handled by seting a T2 interrupt for ~260 scanlines' time

2. T2 interrupt handled by calling music update then transition
   routine update

The T2 timer is timed so that the transition routine update starts at
about the last row of a 256 scanline screen.

TODO: there is currently no adjustment to ensure the transition effect
always runs outside the visible area, but I think it will be possible
to do this by polling T2.

# Other/no IRQ handler

If using another IRQ handler, set IRQ1V as normal. If using none, just
`sei` and then do whatever. The only thing that needs to happen
continually is `framework_update_music`, which must be called at 50 Hz
to keep the music going.

To reinstate the default IRQ handler, do `jsr
framework_set_default_irq_handler`. This will install the handler,
disable all system VIA and user VIA IRQs and re-enable system VIA
CA1/T2 only.

# Timing of IRQ routine switches

TODO: there may need to be a bit of care taken over the timing of the
switching of IRQ routines, to ensure that you don't end up waiting for
too long (or not enough) between music updates.
