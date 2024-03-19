-- TODO: try adding mouse support to vis 1.7
require('vis')

local accursed = {}
accursed.options = {
	mouse = true
}

vis:option_register("mouse", "bool", function(value, toggle)
	accursed.options.mouse = toggle and not accursed.options.mouse or value
	io.write("\x1b[?1003l")
	if (accursed.options.mouse) then
		io.write("\x1b[?1003h")
	end
	io.flush()
end, "Enable tracking mouse events")

-- activate mouse detection...
vis.events.subscribe(vis.events.START, function ()
	if (accursed.options.mouse) then
		--io.write("\x1b[?1002h") -- just button presses
		io.write("\x1b[?1003h") --report any mouse movement
		io.flush()
	end
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

	-- TODO emit more specific events for user friendly extension
	if (event == EVENT.PRESSED) then
		-- TODO detect special clicks using lastclick & lastmouse
		-- a "double click" is defined as clicking the exact same screen space twice.
		-- this is fine in terminals since "same space" is actually an entire character.
		if (lastclick.button == button
			and lastclick.col == col
			and lastclick.line == line) then
			double_click(mouse)
		else
			single_click(mouse)
		end
		mouse.pressed = mouse.pressed + 1
	elseif (event == EVENT.DRAGGED) then
		dragged(mouse)
	elseif (event == EVENT.RELEASED) then
		mouse.pressed = mouse.pressed - 1
		if (mouse.pressed <= 0) then
			-- no buttons are being pressed
			mouse.pressed = 0
			mouse.dragging = 0
		end
	end
end

-- TODO perform special double click actions
function double_click(mouse)
	-- double clicking, by default, selects the WORD under the cursor
	-- If the cursor is on column 1, start a line selection
	-- same if the cursor is on a newline
	local win = vis.win
	local guessedpos = guess_mouse_pos(mouse)
	local charatpos = win.file:content(guessedpos, 1)
	if (mouse.col == 1 or charatpos == "\n") then
		win.selection.pos = guessedpos
		vis.mode = vis.modes.VISUAL_LINE
	else
		vis.mode = vis.modes.VISUAL
		win.selection.range = win.file:text_object_longword(guessedpos)
	end
	lastclick = mouse
end

-- perform actions for single clicks
function single_click(mouse)
	-- wheel scrolling counts as a press, but shouldn't register as a "click"
	if (mouse.button == BUTTON.WHEELUP) then
		vis:feedkeys("<C-y>")
		return
	elseif (mouse.button == BUTTON.WHEELDOWN) then
		vis:feedkeys("<C-e>")
		return
	end

	vis.win.selection.pos = guess_mouse_pos(mouse)
	vis.mode = vis.modes.NORMAL
	vis.win.selection.anchored = false

	-- record this click
	lastclick = mouse
end

-- perform actions for when the mouse is moved with at least one button held down
function dragged(mouse)
	if (lastmouse.event == EVENT.PRESSED) then
		-- just started dragging
		if (not vis.mode == vis.modes.VISUAL
			or not vis.mode == vis.modes.VISUAL_LINE) then
			vis.mode = vis.modes.VISUAL
		end
		vis.win.selection.anchored = true
	end
	mouse.dragging = button
	vis.win.selection.pos = guess_mouse_pos(mouse)
	-- TODO set system Primary selection to be the contents of vis.win.selection
	-- TODO make sure VISUAL LINE is being handled correctly...
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

	--vis:info(mouse.line..":"..mouse.col)

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

return accursed
