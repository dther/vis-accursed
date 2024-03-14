# vis-accursed
> acme-inspired ghost (cursor) in the shell

This plugin is a proof of concept for mouse integration
in [vis][martanne/vis].
It requires a patched vis 1.7, which will be available in a branch
of my vis fork (eventually).
I hope to expand it into a complete API that can, like Plan 9's Acme,
be used to create basic TUI interfaces from within a vis window!

The patch adds a new Vis core event, `MOUSE`, and makes it accessible
to the API via `Vis.events.MOUSE`, with the following definition:

```
mouse(event, button, line, col)
	A mouse CSI sequence has been detected and parsed.
	Mouse sequences are only sent if they are initialised
	by first sending the appropriate DECSET sequence.

	Parameters:
		event: (int) Whether the mouse was pressed, dragged or released(TODO: this is better as a string (it's based on termkey constants))
		button: (int) The button that was pressed, 0 if unknown/none
		line: the visual line the mouse was on, initialised at 1
		col: the visual column, initialised at 1

```

Using the `MOUSE` event and window settings, vis-accursed then reconstructs
the viewport in a Lua table, and attempts to match the current mouse location
to the closest byte position on the file.

Finally, this "guess" is drawn on the screen as what I call the "ghost cursor",which represents vis-accursed's best guess as to where the mouse pointer is
in terms of absolute file position. Under "normal" conditions,
it's never more than about 8 characters off, and is surprisingly robust,
with zero noticeable lag on a small file with a reasonably modern system.

> NOTE: at the moment, "normal conditions" means...
>  - Less than ~5 linebreaks caused by long lines (adds one line)
>  - Less than 3 levels of tab indentation (adds tw columns each)
>  - No inline tabs
>  - "number" set to false (adds 3+ columns)
>
> I'm still working on it.

Despite the caveats, vis-accursed is perfectly usable for basic mouse
functions! These include:

 - Jumping to a specific line
 - Entering VISUAL mode and creating a selection
 - Scroll wheel integration
 - Assigning special behaviour to double-clicks and simple mouse chording

In other words: Just about any mouse function you'd want from a
keyboard-driven visual editor running in a virtual Unix terminal!
(Temper your expectations accordingly.)

My end goal is to implement `acme` inspired mouse navigation and
plumbing to external programs, including *basic* chording behaviour.
