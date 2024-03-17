-- TODO: try adding mouse support to vis 1.7
require('vis')

-- activate mouse detection...
vis.events.subscribe(vis.events.START, function ()
	--io.write("\x1b[?1002h") -- just button presses
	io.write("\x1b[?1003h") --report any mouse movement
	io.flush()
end)

vis.events.subscribe(vis.events.QUIT, function ()
	--io.write("\x2b[?1002l")
	io.write("\x1b[?1003l")
	io.flush()
end)

-- mouse event constants used by libtermkey
local EVENT = {
	UNKNOWN = 0,
	PRESSED = 1,
	DRAGGED = 2,
	RELEASE = 3, -- also used when the mouse is moved w/o any buttons when reporting all movement
}

-- common mouse buttons
local BUTTON = {
	NONE = 0,
	LEFT = 1,
	MIDDLE = 2,
	RIGHT = 3,
	WHEELUP = 4,
	WHEELDOWN = 5,
}

-- Store the current mouse state
local mouse = {
	event = EVENT.UNKNOWN,
	button = BUTTON.NONE,
	line = 1,
	col = 1,
	dragging = 0, -- button of in-progress dragging event
	pressed = 0, -- number of buttons pressed
	lastclick = {},
	lastevent = {}
}

-- store the previous state
local lastmouse = mouse

-- the last button that was clicked
local lastclick = mouse

function update_mouse_state(event, button, line, col)
	lastmouse = mouse
	mouse = {}
	mouse.event = event
	mouse.button = button
	mouse.line = line
	mouse.col = col
	mouse.pressed = lastmouse.pressed
	mouse.dragging = lastmouse.dragging
	-- TODO: actually do something with button presses
	-- figure out double clicking, mouse chording and all that, too

	-- low hanging fruit: scrolling and jumping!
	if (button == BUTTON.WHEELUP) then
		vis:feedkeys("<C-y>")
		mouse.pressed = mouse.pressed + 1
	elseif (button == BUTTON.WHEELDOWN) then
		vis:feedkeys("<C-e>")
		mouse.pressed = mouse.pressed + 1
	elseif (event == EVENT.PRESSED) then
		-- below works really well... On the first screenful, only.
		-- Might be good for me to tinker with this some more later.

		-- IDEA: calculate the topmost line, which should be simple,
		-- since the status bar shows it... Then add it to the coords
		-- this should be easy to do using lua's string.gmatch? hmm

		-- Feature request: some easy way of translating between abs.
		-- file position and line/col.
		--vis.win.selection:to(line, col)

		-- clear existing selections and exit visual mode?
		vis.mode = vis.modes.NORMAL
		vis.win.selection.anchored = false
		-- TODO delete non-primary selections
		-- TODO special behaviour in INSERT mode- just jump

		-- IT WORKS
		vis.win.selection.pos = guess_mouse_pos(mouse)
		mouse.pressed = mouse.pressed + 1
		lastclick = mouse -- used to detect double clicks...?
	elseif (event == EVENT.DRAGGED) then
		-- TODO: The big one... Selections.
		if (lastmouse.event == EVENT.PRESSED) then
			-- we just started, anchor the selection and switch to visual mode
			vis.mode = vis.modes.VISUAL
			vis.win.selection.anchored = true
			mouse.dragging = button
		end
		vis.win.selection.pos = guess_mouse_pos(mouse)
	end

	if (event == EVENT.RELEASED) then
		mouse.pressed = mouse.pressed - 1
	end
end

-- calculate the approximate closest file position to the cursor
-- FIXME hacky and flaky (can anything be done???)
-- FIXME support multiple windows!
function guess_mouse_pos(mouse)
	local win = vis.win
	local visible = win.file:content(win.viewport)

	-- take note of options that affect cursor coordinates
	-- TODO line numbers and status bars
	-- NOTE: win.width is visual width, not viewport width!!!
	local tw = win.options.tabwidth
	local wc = win.options.wrapcolumn
	if (wc == 0) then wc = win.width end

	local lineschecked = 1
	local linestart = 0 -- the first character of the line the cursor is on
	local lastnewline = 0 -- record the last newline found...
	local charsprinted = 0 -- how many characters have been printed, visually

	-- find where the current line starts
	while (lineschecked < mouse.line
		and linestart < visible:len()) do
		linestart = linestart + 1
		charsprinted = charsprinted + 1

		-- adjust for tabstop
		if (visible:sub(linestart, linestart) == '\t') then
			charsprinted = charsprinted + (tw - (charsprinted % tw))
		end

		-- detect newlines/column wraps
		if (visible:sub(linestart, linestart) == '\n'
			or (charsprinted) >= wc) then
			lastnewline = linestart
			lineschecked = lineschecked + 1
			charsprinted = 0
		end
	end

	-- FIXME re-implement column guessing...

	local guess = win.viewport.start + linestart
	if (guess < win.viewport.start) then guess = win.viewport.start end
	if (guess > win.viewport.finish) then guess = win.viewport.finish end

	return guess
end

vis.events.subscribe(vis.events.MOUSE, update_mouse_state)

local evtest=0
vis.events.subscribe(vis.events.WIN_HIGHLIGHT, function()
	if (not vis.win) then return end
	-- draw test cursor
	local style = vis.win.STYLE_SELECTION -- use a default for now
	local guess = guess_mouse_pos(mouse)
	vis.win:style(style, guess, guess)
	
	--debug
	--evtest = evtest + 1
	--vis:info(evtest)
end)
