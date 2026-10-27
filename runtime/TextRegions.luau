--!strict
--!native
local font = require(script.Parent.CP437Font)
local Tracker = {}
Tracker.__index = Tracker

type Region = { text: string, x: number, y: number, width: number, height: number, digit: number? }
type Context = { regions: { Region }, choices: { number }, continuePrompt: boolean, menu: boolean, generation: number }
local function blank(generation: number): Context
	return { regions = {}, choices = {}, continuePrompt = false, menu = false, generation = generation }
end
function Tracker.new(bus: any, _options: any?): any
	return setmetatable({ bus = bus, generation = -1, context = blank(-1) }, Tracker)
end
function Tracker.clear(self: any)
	self.generation = -1
	self.context = blank(-1)
end
local function append(context: Context, text: string, x: number, y: number, width: number, height: number)
	text = string.match(text, "^%s*(.-)%s*$") or ""
	if text == "" then
		return
	end
	local region: Region = { text = text, x = x, y = y, width = width, height = height }
	local digit = string.match(text, "^([1-9])[%.%)]%s+%S")
	if digit then
		local n = tonumber(digit) :: number
		region.digit = n
		table.insert(context.choices, n)
		context.menu = true
	end
	local lower = string.lower(text)
	if lower:find("space", 1, true) or lower:find("continue", 1, true) then
		context.continuePrompt = true
	end
	table.insert(context.regions, region)
end
function Tracker.record(self: any, text: string, x: number, y: number, w: number, h: number)
	append(self.context, text, x, y, w, h)
end
-- Build bounding boxes for the built-in font. The comparison allows a small
-- pixel difference for compatible 8x8 bitmap fonts; it does not invent labels.
local templates: { [number]: { rows: { number }, width: number, height: number } } = {}
for code = 33, 126 do
	local minx, maxx, miny, maxy = 8, -1, 8, -1
	for y = 0, 7 do
		local bits = buffer.readu8(font, code * 8 + y)
		for x = 0, 7 do
			if bit32.band(bits, bit32.rshift(128, x)) ~= 0 then
				minx = math.min(minx, x)
				maxx = math.max(maxx, x)
				miny = math.min(miny, y)
				maxy = math.max(maxy, y)
			end
		end
	end
	if maxx >= minx then
		local rows: { number } = {}
		for y = miny, maxy do
			local bits = buffer.readu8(font, code * 8 + y)
			local row = 0
			for x = minx, maxx do
				row = row * 2 + (if bit32.band(bits, bit32.rshift(128, x)) ~= 0 then 1 else 0)
			end
			table.insert(rows, row)
		end
		templates[code] = { rows = rows, width = maxx - minx + 1, height = maxy - miny + 1 }
	end
end
-- Common BGI 8-pixel digit forms, normalized to the ink bounding box.
-- Additional fonts may differ; never infer a digit from menu position.
local bgiDigits = {
	{ 12, 60, 12, 12, 12, 12, 63 },
	{ 62, 99, 3, 14, 56, 96, 127 },
	{ 62, 99, 3, 30, 3, 99, 62 },
	{ 6, 14, 30, 54, 102, 127, 6 },
	{ 126, 96, 126, 3, 3, 99, 62 },
	{ 62, 96, 126, 99, 99, 99, 62 },
}
for n, source in ipairs(bgiDigits) do
	local minx, maxx = 7, -1
	for _, bits in ipairs(source) do
		for x = 0, 6 do
			if bit32.band(bits, bit32.lshift(1, 6 - x)) ~= 0 then
				minx = math.min(minx, x)
				maxx = math.max(maxx, x)
			end
		end
	end
	local rows: { number } = {}
	for _, bits in ipairs(source) do
		local row = 0
		for x = minx, maxx do
			row = row * 2 + (if bit32.band(bits, bit32.lshift(1, 6 - x)) ~= 0 then 1 else 0)
		end
		table.insert(rows, row)
	end
	templates[48 + n] = { rows = rows, width = maxx - minx + 1, height = 7 }
end
local function recognize(rows: { number }, width: number, height: number, first: number, last: number): (string, number)
	local best, bestScore = "?", math.huge
	for code = first, last do
		local t = templates[code]
		if t and math.abs(t.width - width) <= 1 and math.abs(t.height - height) <= 1 then
			for dx = -1, 1 do
				for dy = -1, 1 do
					local score = 0
					for y = 0, math.max(height, t.height) - 1 do
						for x = 0, math.max(width, t.width) - 1 do
							local a = if y < height and x < width
								then bit32.band(rows[y + 1], bit32.lshift(1, width - 1 - x)) ~= 0
								else false
							local tx = x + dx
							local ty = y + dy
							local b = if tx >= 0
									and tx < t.width
									and ty >= 0
									and ty < t.height
								then bit32.band(t.rows[ty + 1], bit32.lshift(1, t.width - 1 - tx)) ~= 0
								else false
							if a ~= b then
								score += 1
							end
						end
					end
					if score < bestScore then
						best = string.char(code)
						bestScore = score
					end
				end
			end
		end
	end
	return best, bestScore
end
local function scanGraphics(self: any, video: any, context: Context)
	local pixels: buffer = video.pixels
	local w: number = video.width
	local h: number = video.height
	-- Only a dominant solid background and an independently chosen foreground are
	-- used, avoiding annotations over arbitrary multicolour artwork.
	local counts: { [number]: number } = {}
	for y = 0, h - 1, 2 do
		for x = 0, w - 1, 2 do
			local c = buffer.readu32(pixels, (y * w + x) * 4)
			counts[c] = (counts[c] or 0) + 1
		end
	end
	local bg, bgCount = 0, 0
	for c, n in pairs(counts) do
		if n > bgCount then
			bg, bgCount = c, n
		end
	end
	local fg, fgCount = 0, 0
	for c, n in pairs(counts) do
		if c ~= bg and n > fgCount then
			fg, fgCount = c, n
		end
	end
	if bgCount < w * h / 16 or fgCount < 10 then
		return
	end
	local y = 0
	while y < h do
		local occupied = 0
		for x = 0, w - 1 do
			if buffer.readu32(pixels, (y * w + x) * 4) == fg then
				occupied += 1
			end
		end
		if occupied < 3 then
			y += 1
			continue
		end
		local top = y
		local last = y
		while y < h do
			local n = 0
			for x = 0, w - 1 do
				if buffer.readu32(pixels, (y * w + x) * 4) == fg then
					n += 1
				end
			end
			if n == 0 then
				break
			end
			last = y
			y += 1
		end
		local height = last - top + 1
		if height < 5 or height > 8 then
			continue
		end
		local parts: { { left: number, right: number, top: number, bottom: number, rows: { number } } } = {}
		local x = 0
		while x < w do
			local exists = false
			for gy = top, last do
				if buffer.readu32(pixels, (gy * w + x) * 4) == fg then
					exists = true
					break
				end
			end
			if not exists then
				x += 1
				continue
			end
			local left = x
			local bottom = top
			local upper = last
			while x < w do
				local hit = false
				for gy = top, last do
					if buffer.readu32(pixels, (gy * w + x) * 4) == fg then
						hit = true
						upper = math.min(upper, gy)
						bottom = math.max(bottom, gy)
					end
				end
				if not hit then
					break
				end
				x += 1
			end
			local right = x - 1
			local glyphRows: { number } = {}
			if right - left + 1 <= 8 then
				for gy = upper, bottom do
					local row = 0
					for gx = left, right do
						row = row * 2 + (if buffer.readu32(pixels, (gy * w + gx) * 4) == fg then 1 else 0)
					end
					table.insert(glyphRows, row)
				end
				table.insert(parts, { left = left, right = right, top = upper, bottom = bottom, rows = glyphRows })
			end
		end
		-- Recognize normal text lines as well as numbered choices, so a
		-- visible SPACE or continue instruction can be exposed to the router.
		if #parts >= 4 then
			local chars: { string } = {}
			local previous = parts[1].left
			local confident = 0
			for index, part in ipairs(parts) do
				if index > 1 and part.left - previous > 10 then
					table.insert(chars, " ")
				end
				local ch, score = recognize(part.rows, part.right - part.left + 1, part.bottom - part.top + 1, 33, 126)
				if score <= 5 then
					confident += 1
				else
					ch = "?"
				end
				table.insert(chars, ch)
				previous = part.right
			end
			local line = table.concat(chars)
			local lower = string.lower(line)
			if confident >= 4 and (string.find(lower, "space", 1, true) or string.find(lower, "continue", 1, true)) then
				append(
					context,
					line,
					parts[1].left / w,
					top / h,
					(parts[#parts].right - parts[1].left + 1) / w,
					height / h
				)
			end
		end
		-- A menu requires a digit, a small punctuation mark, and a substantive
		-- label on the same baseline; all bounding boxes derive from visible ink.
		for i = 1, #parts - 3 do
			local a, b = parts[i], parts[i + 1]
			local aw = a.right - a.left + 1
			local ah = a.bottom - a.top + 1
			if
				aw >= 3
				and ah >= 5
				and b.right - b.left + 1 <= 3
				and b.bottom - b.top + 1 <= 3
				and b.left - a.right <= 6
				and parts[i + 2].left - b.right <= 20
			then
				local digit, err = recognize(a.rows, aw, ah, 49, 57)
				if err <= 3 then
					local stop = i + 2
					while stop < #parts and parts[stop + 1].left - parts[stop].right <= 15 do
						stop += 1
					end
					if stop >= i + 3 then
						local chars: { string } = { digit, ".", " " }
						local recognized = 0
						local prev = parts[i + 2].left
						for j = i + 2, stop do
							local q = parts[j]
							if j > i + 2 and q.left - prev > 10 then
								table.insert(chars, " ")
							end
							local ch, score = recognize(q.rows, q.right - q.left + 1, q.bottom - q.top + 1, 33, 126)
							if score <= 10 then
								recognized += 1
							else
								ch = "?"
							end
							table.insert(chars, ch)
							prev = q.right
						end
						if recognized >= 1 then
							append(
								context,
								table.concat(chars),
								a.left / w,
								top / h,
								(parts[stop].right - a.left + 1) / w,
								height / h
							)
						end
						break
					end
				end
			end
		end
	end
end
-- Expand only visible numbered rows. Original ink rectangles remain the
-- reference for every neighbor so that the result is independent of order.
local function expandChoices(context: Context, width: number, height: number)
	local original: { { x: number, y: number, right: number, bottom: number } } = {}
	for _, r in ipairs(context.regions) do
		table.insert(original, { x = r.x, y = r.y, right = r.x + r.width, bottom = r.y + r.height })
	end
	local padX = 8 / width
	local padY = 2 / height
	for i, r in ipairs(context.regions) do
		if r.digit then
			local a = original[i]
			local left = math.max(0, a.x - padX)
			local right = math.min(1, a.right + padX)
			local top = math.max(0, a.y - padY)
			local bottom = math.min(1, a.bottom + padY)
			for j, b in ipairs(original) do
				if i ~= j then
					local horizontalOverlap = a.x < b.right and b.x < a.right
					local verticalOverlap = a.y < b.bottom and b.y < a.bottom
					if horizontalOverlap then
						if b.bottom <= a.y + 1e-10 then
							top = math.max(top, (b.bottom + a.y) / 2)
						elseif b.y >= a.bottom - 1e-10 then
							bottom = math.min(bottom, (a.bottom + b.y) / 2)
						end
					end
					if verticalOverlap then
						if b.right <= a.x + 1e-10 then
							left = math.max(left, (b.right + a.x) / 2)
						elseif b.x >= a.right - 1e-10 then
							right = math.min(right, (a.right + b.x) / 2)
						end
					end
				end
			end
			r.x = left
			r.y = top
			r.width = right - left
			r.height = bottom - top
		end
	end
end
function Tracker.refresh(self: any, video: any): Context
	local generation = video.frameGeneration or 0
	if self.generation == generation then
		return self.context
	end
	local context = blank(generation)
	if video.mode == 3 then
		local bus = self.bus
		for row = 0, 24 do
			local chars: { string } = {}
			local left, right = 80, -1
			for col = 0, 79 do
				local ch = bus:read8(0xb8000 + (row * 80 + col) * 2)
				if ch >= 32 and ch <= 126 then
					table.insert(chars, string.char(ch))
					if ch ~= 32 then
						left = math.min(left, col)
						right = col
					end
				else
					table.insert(chars, " ")
				end
			end
			if right >= left then
				append(context, table.concat(chars), left / 80, row / 25, (right - left + 1) / 80, 1 / 25)
			end
		end
	else
		scanGraphics(self, video, context)
	end
	expandChoices(context, video.width, video.height)
	self.generation = generation
	self.context = context
	return context
end
function Tracker.getContext(self: any): Context
	return self.context
end
return Tracker
