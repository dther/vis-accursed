-- Basic and extensible mouse support for vis development build
require('vis')

local mouse = {}
mouse.options = {
	mouse = true,
}

-- mouse event constants used by libtermkey
local MOUSE_EVENT = {
	UNKNOWN = 0,
	PRESSED = 1,
	DRAGGED = 2,
	RELEASED = 3, -- also used when the mouse is moved w/o any buttons when reporting all movement
}
mouse.MOUSE_EVENT = MOUSE_EVENT

-- common mouse buttons
local BUTTON = {
	NONE = 0,
	LEFT = 1,
	MIDDLE = 2,
	RIGHT = 3,
	WHEELUP = 4,
	WHEELDOWN = 5,
}
mouse.BUTTON = BUTTON

-- Store the mouse state as it changes
local state = {}
mouse.state = state

state.current = {
	event = MOUSE_EVENT.UNKNOWN,
	button = BUTTON.NONE,
	line = 1,
	col = 1,
	dragging = 0, -- button of in-progress dragging event
	chordbase = 0, -- the first button clicked in a chord event
}

-- store the immediately previous state
state.last = state.current

-- the last button that was clicked
state.lastclick = state.current

-- Maintained map of currently pressed buttons
state.pressed = {
	[BUTTON.LEFT] = false,
	[BUTTON.MIDDLE] = false,
	[BUTTON.RIGHT] = false,
}

-- Custom events
local events = {
	PRESS = "mousepress",
	DRAG = "mousedrag",
	RELEASE = "mouserelease",
	DOUBLE_CLICK = "mousedoubleclick",
	CHORD_PRESS = "mousechordpress",
	CHORD_RELEASE = "mousechordrelease",
}
mouse.events = events

vis:option_register("mouse", "bool", function(value, toggle)
	mouse.options.mouse = toggle and not mouse.options.mouse or value
	mouse.deactivate()
	if (mouse.options.mouse) then
		mouse.activate()
	end
end, "Enable tracking mouse events")

-- activate mouse detection
function mouse.activate()
	io.write("\x1b[?1003h") --report any mouse movement
	io.write("\x1b[?1006h") --report button release
	io.flush()
end

vis.events.subscribe(vis.events.START, mouse.activate)

-- deactivate mouse detection
function mouse.deactivate()
	io.write("\x1b[?1003l")
	io.write("\x1b[?1006l")
	io.flush()
end

vis.events.subscribe(vis.events.QUIT, mouse.deactivate)

-- set mouse.state appropriately and emit vis events for common operations
function update_mouse_state(event, button, line, col)
	state.last = state.current
	state.current = {}
	state.current.event = event
	state.current.button = button
	state.current.line = line
	state.current.col = col
	state.current.dragging = state.last.dragging
	state.current.chordbase = state.last.chordbase

	if (event == MOUSE_EVENT.PRESSED) then
		-- wheel movements don't produce release events
		if (button ~= BUTTON.WHEELUP
			and button ~= BUTTON.WHEELDOWN) then
			state.pressed[button] = true
			if (state.current.chordbase == 0) then
				state.current.chordbase = button
			end
		end

		if (state.lastclick.button == button
			and state.lastclick.col == col
			and state.lastclick.line == line) then
			vis.events.emit(events.DOUBLE_CLICK, state)
		elseif (state.current.chordbase ~= button
			and button ~= BUTTON.WHEELUP
			and button ~= BUTTON.WHEELDOWN) then
			vis.events.emit(events.CHORD_PRESS, state)
		else
			vis.events.emit(events.PRESS, state)
		end

		-- After executing appropriate action
		if (button ~= BUTTON.WHEELUP
			and button ~= BUTTON.WHEELDOWN) then
			state.lastclick = state.current
		end
	elseif (event == MOUSE_EVENT.DRAGGED) then
		state.current.dragging = button
		vis.events.emit(events.DRAG, state)
	elseif (event == MOUSE_EVENT.RELEASED) then
		state.pressed[button] = false
		if (button ~= state.current.chordbase) then
			vis.events.emit(events.CHORD_RELEASE, state)
		else
			vis.events.emit(events.RELEASE, state)
			state.current.chordbase = 0
		end
		if (button == state.current.dragging) then
			state.current.dragging = 0
		end
	end
end

-- perform special double click actions
function mouse.double_click(state)
	if (state.current.button == BUTTON.WHEELUP or state.current.button == BUTTON.WHEELDOWN) then return end
	-- double clicking, by default, selects the WORD under the cursor
	-- If the cursor is on column 1, start a line selection
	-- same if the cursor is on a newline
	local win = vis.win
	local guessedpos = guess_mouse_pos(state.current)
	local charatpos = win.file:content(guessedpos, 1)

	-- TODO: if double clicking inside an active visual selection,
	-- turn into VISUAL_LINE

	if (state.current.col == 1 or charatpos == "\n") then
		win.selection.pos = guessedpos
		vis.mode = vis.modes.VISUAL_LINE
		vis:feedkeys("0$") -- ensure it always selects the clicked line
	else
		vis.mode = vis.modes.VISUAL
		win.selection.range = win.file:text_object_longword(guessedpos)
	end
end

-- called on mouse chord begin
function mouse.chord(mouse)
	if (mouse.button == BUTTON.WHEELUP or mouse.button == BUTTON.WHEELDOWN) then return end
	-- Do nothing. See mouse.chord_release instead.
	vis:info("chord detect")
end

-- perform actions for single clicks
function mouse.single_click(state)
	-- wheel motions don't create release events and aren't clicks
	if (state.current.button == BUTTON.WHEELUP) then
		vis:feedkeys("<C-y>")
		return
	elseif (state.current.button == BUTTON.WHEELDOWN) then
		vis:feedkeys("<C-e>")
		return
	end

	local gpos = guess_mouse_pos(state.current)
	local currange = vis.win.selection.range

	-- remove anchor and enter normal if click outside the original selection
	if (gpos < currange.start or gpos > currange.finish) then
		vis.win.selection.anchored = false
		vis.mode = vis.modes.NORMAL
	end

	vis.win.selection.pos = gpos

	-- ensure visual line acts as expected
	if (vis.mode == vis.modes.VISUAL_LINE) then
		vis:feedkeys("0$")
	end
end

-- perform actions for when the mouse is moved with at least one button held down
function mouse.dragged(state)
	if (vis.win.selection.anchored == false) then
		-- just started dragging
		vis.win.selection.anchored = true
	end
	-- preserve VISUAL LINE
	if (vis.mode ~= vis.modes.VISUAL and vis.mode ~= vis.modes.VISUAL_LINE) then
		vis.mode = vis.modes.VISUAL
	end
	vis.win.selection.pos = guess_mouse_pos(state.current)
	-- make sure VISUAL LINE continues to select entire lines
	if (vis.mode == vis.modes.VISUAL_LINE) then
		vis:feedkeys('0$')
	end
end

-- perform actions on mouse release
-- i.e.: call vis-clipboard if mouse.dragging = BUTTON.LEFT
function mouse.release(state)
	-- just movement, do nothing
	if (state.current.button == 0) then return end

	local action = state.current.chordbase
	local selection = vis.win.selection
	local file = vis.win.file

	if (action == BUTTON.LEFT and selection.anchored) then
		vis:pipe(file, selection.range, "vis-clipboard --copy --selection primary")
	end
end

-- a button that was pressed while another was held down has been released
function mouse.chord_release(state)
	local chordbase = state.current.chordbase
	local button = state.lastclick.button
	local selection = vis.win.selection
	local file = vis.win.file

	-- FIXME cursor moves around in an unexpected fashion
	if (selection.anchored
		and chordbase == BUTTON.LEFT
		and button == BUTTON.RIGHT) then
		-- cut
		vis:pipe(file, selection.range, "vis-clipboard --copy")
		--[[
		-- FIXME Bah... Haven't gotten this to work right.
		local newpos = selection.pos - (selection.range.finish - selection.range.start) + 1
		file:delete(selection.range)
		selection.pos = newpos
		selection.anchored = false
		--]]
		--vis:feedkeys("d")
		vis:info("Selection copied to clipboard")
	elseif (chordbase == BUTTON.LEFT and button == BUTTON.MIDDLE) then
		-- paste (insert if not anchored)
		local _, paste = vis:pipe("vis-clipboard --paste")
		--[[if (selection.anchored) then
			vis:replace(paste)
		else
			vis:insert(paste)
		end
		]]
		local oldpos = selection.pos
		vis:insert(paste)
		local newpos = selection.pos
		-- select the pasted text
		-- XXX: Is there a way to specify cursor anchor...?
		-- It's odd that there isn't.
		-- apparently Selection.range works...
		if (oldpos ~= nil and newpos ~= nil) then
			selection.pos = oldpos
			selection.anchored = true
			selection.pos = newpos
		end

		vis.mode = vis.modes.VISUAL
		vis:info("Clipboard inserted")
	end
end

-- calculate the approximate closest file position to the cursor
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

	-- Guess column
	charsprinted = 0
	local coloffset = 0 -- bytes
	local remainingview
	if (lineschecked == 1) then
		remainingview = visible
	else
		remainingview = visible:sub(linestart + 1)
	end

	while (charsprinted < mouse.col and charsprinted < wc) do
		coloffset = coloffset + 1
		local currentchar = remainingview:sub(coloffset, coloffset)
		if (currentchar == '\n') then
			break
		elseif (currentchar == '\t') then
			charsprinted = charsprinted + (tw - (charsprinted % tw))
		else
			charsprinted = charsprinted + 1
		end
	end
	coloffset = coloffset - 1

	local guess = win.viewport.start + linestart + coloffset
	if (guess < win.viewport.start) then guess = win.viewport.start end
	if (guess > win.viewport.finish) then guess = win.viewport.finish end

	return guess
end

vis.events.subscribe(vis.events.MOUSE, update_mouse_state)
vis.events.subscribe(events.PRESS, mouse.single_click)
vis.events.subscribe(events.DOUBLE_CLICK, mouse.double_click)
vis.events.subscribe(events.DRAG, mouse.dragged)
vis.events.subscribe(events.RELEASE, mouse.release)
vis.events.subscribe(events.CHORD_RELEASE, mouse.chord_release)

vis.events.subscribe(vis.events.WIN_HIGHLIGHT, function()
	if (not vis.win) then return end
	-- draw ghost cursor
	if (vis.win.STYLE_MOUSE_CURSOR == nil) then
		vis.win.STYLE_MOUSE_CURSOR = vis.win.STYLE_SELECTION
	end
	local style = vis.win.STYLE_MOUSE_CURSOR
	local guess = guess_mouse_pos(state.current)
	vis.win:style(style, guess, guess)
end)


return mouse
