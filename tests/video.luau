--!strict
local Bus = require("../runtime/Bus")
local Video = require("../runtime/Video")
local Tracker = require("../runtime/TextRegions")
local font = require("../runtime/CP437Font")
local count = 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, name .. ": " .. tostring(err))
	count += 1
	print("PASS", name)
end
local function rgba(p: buffer, x: number, y: number, width: number): number
	return buffer.readu32(p, (y * width + x) * 4)
end
local function rgb(r: number, g: number, b: number): number
	return 0xff000000 + r + g * 256 + b * 65536
end
local function make(): (any, any)
	local bus: any = Bus.new()
	return bus, Video.new(bus, { headless = true })
end
check("linear VGA uses indexed palette and alpha", function()
	local bus, v = make()
	v:setMode(0x13)
	v:setPalette(42, 63, 31, 0)
	bus:write8(0xa0000, 42)
	bus:write8(0xa0000 + 63999, 42)
	local p = v:render()
	assert(rgba(p, 0, 0, 320) == rgb(255, 125, 0))
	assert(rgba(p, 319, 199, 320) == rgb(255, 125, 0))
end)
check("Mode X reads four planes in pixel order", function()
	local bus, v = make()
	v:setMode(0x13)
	bus:out8(0x3c4, 4)
	bus:out8(0x3c5, 0)
	for i = 0, 3 do
		v:setPalette(i + 1, i * 10, 0, 0)
		bus:out8(0x3c4, 2)
		bus:out8(0x3c5, bit32.lshift(1, i))
		bus:write8(0xa0000, i + 1)
	end
	local p = v:render()
	for i = 0, 3 do
		assert(rgba(p, i, 0, 320) == rgb(math.floor(i * 10 * 255 / 63), 0, 0))
	end
end)
check("CGA color modes decode bytes and palette select", function()
	local bus, v = make()
	for _, mode in ipairs({ 4, 5 }) do
		v:setMode(mode)
		bus:write8(0xb8000, 0x1b)
		bus:out8(0x3d9, 0x20)
		local p = v:render()
		for i, index in ipairs({ 0, 3, 5, 7 }) do
			assert(rgba(p, i - 1, 0, 320) == buffer.readu32(v.paletteRGBA, index * 4))
		end
		bus:out8(0x3d9, 0x10)
		p = v:render()
		for i, index in ipairs({ 0, 10, 12, 14 }) do
			assert(rgba(p, i - 1, 0, 320) == buffer.readu32(v.paletteRGBA, index * 4))
		end
	end
end)
check("CGA mono pixels use interleaved scanline banks", function()
	local bus, v = make()
	v:setMode(6)
	bus:write8(0xb8000, 0x80)
	bus:write8(0xba000, 0x01)
	local p = v:render()
	assert(rgba(p, 0, 0, 640) == rgb(255, 255, 255))
	assert(rgba(p, 1, 0, 640) == rgb(0, 0, 0))
	assert(rgba(p, 7, 1, 640) == rgb(255, 255, 255))
end)
check("text glyph blink and cursor match foreground and background", function()
	local bus, v = make()
	v:setMode(3)
	bus:write8(0xb8000, 65)
	bus:write8(0xb8001, 0x9e)
	bus:write16(0x460, 0x2000)
	v.blinkPhase = false
	local p = v:render()
	local bg = buffer.readu32(v.paletteRGBA, 4)
	for y = 0, 7 do
		for x = 0, 7 do
			assert(rgba(p, x, y, 640) == bg)
		end
	end
	v.blinkPhase = true
	p = v:render()
	local fg = buffer.readu32(v.paletteRGBA, 14 * 4)
	for y = 0, 7 do
		local bits = buffer.readu8(font, 65 * 8 + y)
		for x = 0, 7 do
			assert(rgba(p, x, y, 640) == (if bit32.band(bits, bit32.rshift(128, x)) ~= 0 then fg else bg))
		end
	end
	bus:write16(0x460, 0x0607)
	p = v:render()
	for x = 0, 7 do
		assert(rgba(p, x, 6, 640) == fg and rgba(p, x, 7, 640) == fg)
	end
end)
check("text regions track menu and clearing after scroll", function()
	local bus, v = make()
	v:setMode(3)
	local s = "1. Start"
	for i = 1, #s do
		bus:write8(0xb8000 + (i - 1) * 2, string.byte(s, i))
	end
	v:render()
	local c = v:getInputContext()
	assert(c.menu and c.choices[1] == 1)
	local r = c.regions[1]
	assert(r.x == 0 and r.y == 0 and r.width > #s / 80 and r.height > 1 / 25)
	v:scrollWindow(0, false, 0, 0, 24, 79, 7)
	v:render()
	c = v:getInputContext()
	assert(not c.menu and #c.choices == 0)
end)
check("graphics prompt recognition observes current frame and cache generation", function()
	local bus = Bus.new()
	local tracker = Tracker.new(bus)
	local pixels = buffer.create(320 * 200 * 4)
	for i = 0, 320 * 200 - 1 do
		buffer.writeu32(pixels, i * 4, 0xff000000)
	end
	local s = "PRESS SPACE TO CONTINUE"
	for i = 1, #s do
		local ch = string.byte(s, i)
		for y = 0, 7 do
			local bits = buffer.readu8(font, ch * 8 + y)
			for x = 0, 7 do
				if bit32.band(bits, bit32.rshift(128, x)) ~= 0 then
					buffer.writeu32(pixels, ((40 + y) * 320 + 10 + (i - 1) * 8 + x) * 4, 0xffffffff)
				end
			end
		end
	end
	local v: any = { mode = 0x13, width = 320, height = 200, pixels = pixels, frameGeneration = 1 }
	local c = tracker:refresh(v)
	assert(c.continuePrompt and #c.regions == 1)
	assert(tracker:refresh(v) == c)
	for i = 0, 320 * 200 - 1 do
		buffer.writeu32(pixels, i * 4, 0xff000000)
	end
	v.frameGeneration = 2
	c = tracker:refresh(v)
	assert(not c.continuePrompt and #c.regions == 0)
end)
check("display settings persist and integer scale uses viewport", function()
	local bus: any = Bus.new()
	local v: any = Video.new(bus, { headless = true, viewport = { width = 1000, height = 750 } })
	assert(v.appliedSettings.aspectMode == "stretch" and v.appliedSettings.resampleMode == "Pixelated")
	v:setMode(0x13)
	v:setDisplaySettings({ aspectMode = "integer", resampleMode = "Default" })
	assert(v.appliedSettings.scale == 3 and v.appliedSettings.width == 960 and v.appliedSettings.height == 600)
	v:setDisplaySettings({ viewport = { width = 640, height = 400 } })
	assert(v.appliedSettings.scale == 2 and v.appliedSettings.width == 640 and v.appliedSettings.height == 400)
	v:setMode(3)
	assert(
		v.appliedSettings.scale == 1
			and v.appliedSettings.aspectMode == "integer"
			and v.appliedSettings.resampleMode == "Default"
	)
	v:setDisplaySettings({ aspectMode = "4:3" })
	assert(v.appliedSettings.aspectMode == "4:3")
	v:setDisplaySettings({ aspectMode = "16:10" })
	assert(v.appliedSettings.aspectMode == "16:10")
	v:setDisplaySettings({ aspectMode = "stretch" })
	assert(v.appliedSettings.width == 640 and v.appliedSettings.height == 400)
	v:destroy()
end)
check("choice hitboxes include padding without overlapping adjacent rows", function()
	local bus, v = make()
	v:setMode(3)
	local function put(row: number, col: number, text: string)
		for i = 1, #text do
			bus:write8(0xb8000 + (row * 80 + col + i - 1) * 2, string.byte(text, i))
		end
	end
	put(5, 10, "1. First")
	put(6, 10, "2. Second")
	put(24, 74, "3. End")
	v:render()
	local c = v:getInputContext()
	assert(#c.choices == 3)
	local a, b, d = c.regions[1], c.regions[2], c.regions[3]
	assert(a.x < 10 / 80 and a.x + a.width > (10 + 8) / 80)
	assert(a.y + a.height <= b.y + 1e-10)
	assert(d.x >= 0 and d.y >= 0 and d.x + d.width <= 1 and d.y + d.height <= 1)
end)
print(`{count} video tests passed`)
