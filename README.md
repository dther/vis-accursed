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
 - Tmux integration! Just put `:set mouse on` in your tmux.conf!
   - ... And patch in/wait patiently for tmux/tmux#3919 for chording to work.

In other words: Just about any mouse function you'd want from a
keyboard-driven visual editor running in a virtual Unix terminal!
(Temper your expectations accordingly.)

My end goal is to implement `acme` inspired mouse navigation and
plumbing to external programs, including *basic* chording behaviour.

## DIFFERENCES FROM ACME

 - Acme is designed around Plan 9's three button mouse, with the middle button being used to
   execute commands and the right button being used to open files and search for text.
   Middle and right are also used for copying and pasting, respectively.
   **vis-accursed reverses this.** It uses the right click to execute commands and the mouse wheel to open files.
   - Rationale: the modern mouse wheel literally didn't exist at the time of
     Acme's conception. It only became available to the consumer market in 1995,
     and didn't become part of the standard Windows desktop computer in 1996,
     **almost two years after Acme's public release in 1994.**
   - Since then, the mouse wheel is now not only ubiquitous, but closely tied with
     "movement" in common design UI. On browsers, it opens tabs,
     and on X11, it pastes the primary selection.
     In other words, moving and pasting- what Acme uses right-click for.
   - Secondly: "right click performs special actions" is now also ubiquitous.

## Why?
why not

### no really
In an ideal world, I'd never need to leave the home row,
every program would have excellent vi-key support with
mouse support for positional jumping and range selection,
and the mouse pointer would warp instantly to wherever my eyeball was focused.
Or, barring that, every keyboard would have a comfy pointing stick.

But, alas, we live in a world where I have to use *web applications and GUIs*,
with my editor open in another window, with next to no common control system.
I might have HTML documentation open,
or edit/read a Google Doc maintained by non-programmers,
while still handling plaintext data (e.g., writing code to fit a living spec).

Like it or not, I'm forced to "mode switch".
I often have sequences in which I make a flurry of ^C^V mouse sweeps,
in which I may only make one or two editing keystrokes,
followed by maybe ten minutes of typing, in which I make heavy use of Vi's excellent
modal editing tools.

Vis, in my experience, has the absolute best visual selection integration in a vi-clone
I've used thus far, owing to the strength of `sam`'s line-agnostic command language.
Which is why it baffles me that mouse support has been largely ignored-
visual selections are the one thing that mice are almost universally superior at.

In giving Vis almost all of the mouse capabilities of Acme,
I get the best of both worlds- a comfortable vi-like editor that slots into a workflow
that requires the mouse just as often as the keyboard.
My goal is to make all of the tips given in [Wily's Idioms][oz:wily:idioms] broadly applicable
to `vis` instances running inside a tiled window manager.

### Why not `wily` or plan9port `acme`?
Acme, to me, is fascinating on an academic level, but is very much a product of its environment.
It doesn't make good use of common Unix/Linux interfaces,
simply because it's designed for an environment that doesn't use them.
If the modern web infrastructure had been built around 9fs
and Apple and Microsoft hadn't gone All In on the Desktop Metaphor back in '95,
we'd be in a very different computer ecosystem indeed.

## FEATURE TODO

 - support multiple windows (important)
 - test on large files, disable if too slow
 - adjust for window decoration
 - clickable status bar, a la acme's tag bar
 - primary selection integration
 - "Minimal" version that removes all the weird acme fluff
 - xdotool mouse warping? (this is going to be WACKY)
   - it would be easier to patch st than implement this.
   (Add a special signal to warp the mouse cursor to the terminal cursor.)
     - NOTE: terminal cursor requires PR #953, hasn't been merged. help out?
   - Low priority, all things considered.
   Mouse warping tends to be distracting at the best of times.

[oz:wily:idioms]: http://www.cs.yorku.ca/~oz/wily/idioms.html
[martanne/vis]: https://github.com/martanne/vis
