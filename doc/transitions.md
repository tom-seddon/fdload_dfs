N.B., this document is 99% lies.

# Transition stuff

The transitions serve to provide some (simple, cheap...) visual effect
while the next part loads and initialises. The transition runs on an
interrupt, starting roughly at the end of the visible display, so it
can, in theory, just do its thing in the background.

# Transitions that write to display RAM

The assumption is that these will be single-buffered, on the basis
that the upcoming part will probably want to use the other RAM
(whichever it is).

Probably want 2 versions of each such transition, one for main RAM and
one for shadow RAM (it'll need to know which so that it can page the
right one in).

## Part exit state

Each part should leave the screen in a standard Mode 2 or Mode 8 setup:

- 80 (Mode 2)/40 (Mode 8) CRTC columns
- 32 CRTC rows
- 8 scanlines per CRTC row
- Start address $3000 (Mode 2)/$5800 (Mode 8)
- Wrap size 20 KB (Mode 2)/10 KB (Mode 8)
- Default palette

The framework looks after starting the transition.

## Part entry state

As above. The transition will be ongoing. Poll
`transition_current_state` - when bit 7 is set, the screen is
currently filled with a solid colour, and bits 0-3 are the index of
that colour.

[[TODO: Set `transition_state_request` to `$80|colour` to have the transition
fill the screen with colour index `colour`. The transition will read
this value in due course, and the result will come to pass
eventually - poll `transition_current_state` as above to monitor
progress.]]

Once the transition reaches the requested state, it'll stop.

# Transitions that just change the palette

For use when the upcoming part wants to fill all of shadow RAM and
main RAM. This effect set palette entries 0-15 the same colour, so
display contents are irrelevant.

## Part exit state

No specific screen setup requirements.

The part should fill the screen to a solid colour.

## Part entry state

The transition will be ongoing. Poll `transition_current_state`, as
above - it'll be updated every frame.

[[TODO: Set `transition_state_request` to `$80|colour` to have the transition
set all entries to colour index `colour`. The transition doesn't clear
this value; once set, it will remain in force.]]

# Stopping the transition

Call `framework_stop_transition`.

If reusing the standard IRQ handler: will probably need a page 2 entry
point for this. A blocking call, it'll wait for vsync, then reset the
transition vector, then return.

If setting a part-specific IRQ handler, no problem. 
