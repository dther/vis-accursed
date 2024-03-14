-- TODO: try adding mouse support to vis 1.7
require('blah')

-- activate mouse detection...
blah.events.subscribe(blah.events.START, function ()
	--io.write("\x1b[?1002h") -- just button presses
	io.write("\x1b[?1003h") --report any mouse movement
	--io.write("\x1b[?9h")
	io.flush()
end)

blah.events.subscribe(blah.events.QUIT, function ()
	--io.write("\x2b[?1002l")
	io.write("\x1b[?1003l")
	--io.write("\x1b[?9l")
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

-- Store the mouse state
local mouse = {
	event = EVENT.UNKNOWN,
	button = BUTTON.NONE,
	line = 1,
	col = 1,
}

-- store the previous state, for chording calculations
local lastmouse = mouse

function update_mouse_state(event, button, line, col)
	lastmouse = mouse
	mouse = {}
	mouse.event = event
	mouse.button = button
	mouse.line = line
	mouse.col = col
	-- TODO: actually do something with button presses
	-- figure out double clicking, mouse chording and all that, too

	-- low hanging fruit: scrolling and jumping!
	if (button == BUTTON.WHEELUP) then
		vis:feedkeys("<C-y>")
	elseif (button == BUTTON.WHEELDOWN) then
		vis:feedkeys("<C-e>")
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
	elseif (event == EVENT.DRAGGED) then
		-- TODO: The big one... Selections.
		if (lastmouse.event == EVENT.PRESSED) then
			-- we just started, anchor the selection and switch to visual mode
			vis.mode = vis.modes.VISUAL
			vis.win.selection.anchored = true
		end
		vis.win.selection.pos = guess_mouse_pos(mouse)
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
	
	-- FIXME might be smart to split the viewport content by lines and
	-- iterate over that- much more predictable.

	-- TODO account for tabwidth affecting wrapcolumn
	-- find where the current line starts
	while (lineschecked < mouse.line
		and linestart < visible:len()) do
		linestart = linestart + 1

		-- detect newlines/column wraps
		if (visible:sub(linestart, linestart) == '\n'
			or (linestart - lastnewline) >= wc) then
			lastnewline = linestart
			lineschecked = lineschecked + 1
		end
	end

	-- TODO account for line wrap in columns
	-- move to the column
	local lineend = visible:find("\n", linestart+1)

	-- special cases. I'm off by 1 somewhere...
	if (lineend == nil) then
		return win.viewport.finish
	elseif (lineschecked == 1) then
		lineend = lineend + 1
	end

	local linetext = visible:sub(linestart, lineend)

	-- special case for eof
	if (linetext == nil or lineend == nil) then return win.viewport.finish end

	local guesscol = mouse.col-1

	-- TODO account for tabstops
	for c = 0, linetext:len() do
		if (linetext:sub(c, c) == "\t") then
			guesscol = guesscol - (tw-1)
		end
	end
	if (guesscol < 0) then guesscol = 0 end

	-- avoid running off end of line
	if (guesscol > linetext:len() - 2) then
		guesscol = linetext:len() - 2
	end
	--vis:info(lineend)

	local guess = win.viewport.start + linestart + guesscol
	if (guess < 0) then guess = 0 end

	return guess
end
-- IT WORKS IT WORKS THE THE PROOF OF CONCEPT WORKS

-- FIXME alternative implementation of above, wherein a text buffer of the viewport is searched by line
function guess_from_viewport(mouse)
	if (not vis.win) then return end
	local win = vis.win
	local raw = win.file:content(win.viewport)

	-- take note of options that affect cursor coordinates
	-- TODO line numbers and status bars
	-- NOTE: win.width is total window width, not viewport width!!!
	local tw = win.options.tabwidth
	local wc = win.options.wrapcolumn
	if (wc == 0) then wc = win.width end

	-- turn viewport into a list of lines
	local viewport = {}
	for line in raw:gmatch("[^\n]*\n") do
		-- TODO: break lines that are greater than wc, accounting for tw and breakat

		-- FIXME: tabstop behaviour is more complex than mere replacement. Needs modulo.
		local brokenline = break_visual_lines(win, line)
		for i = 0, #brokenline do
			table.insert(viewport, brokenline[i])
		end
	end
	--vis:message(viewport[1]..viewport[2])
	--vis:message(viewport[#viewport])

	--FIXME not done here. do calculations, somehow...
	local bytesbeforeline = 0
	for i = 1, mouse.line-1 do
		-- FIXME special case: eof, where mouse.line > #viewport
		bytesbeforeline = bytesbeforeline + #viewport[i]
	end
	--vis:info(bytesbeforeline)

	vis:info(bytesbeforeline+mouse.col-1)
	-- TODO: tabwidth adjustment
end

-- Breaks "str", a single logical line, into how it would appear visually
-- as lines inside the viewport of "win". Returns a list of strings.
function break_visual_lines(win, str)
	local lines = {}
	-- TODO
	table.insert(lines, str)
	return lines
end

-- translates from bytes to logical lines (a work in progress...)
local function file_bytes_to_lines(bytes)
end

vis:command_register("test", function()
	--vis:info(mouse.event.." ".. mouse.button.." ".. mouse.line.." ".. mouse.col)
	vis:info(vis.win.width)
	guess_from_viewport(mouse)
end)

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
