--!strict
--!native
local font = require(script.Parent.CP437Font)
local Video = {}
Video.__index = Video
-- Standard VGA DAC values from https://github.com/rust-osdev/vga/blob/master/src/colors.rs
-- MIT License; Copyright (c) 2018 Philipp Oppermann, 2015 Gerd Zellweger,
-- 2015 The libcpu Developers.
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
local defaultPalette = {
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x2a,
	0x00,
	0x2a,
	0x00,
	0x00,
	0x2a,
	0x2a,
	0x2a,
	0x00,
	0x00,
	0x2a,
	0x00,
	0x2a,
	0x2a,
	0x15,
	0x00,
	0x2a,
	0x2a,
	0x2a,
	0x15,
	0x15,
	0x15,
	0x15,
	0x15,
	0x3f,
	0x15,
	0x3f,
	0x15,
	0x15,
	0x3f,
	0x3f,
	0x3f,
	0x15,
	0x15,
	0x3f,
	0x15,
	0x3f,
	0x3f,
	0x3f,
	0x15,
	0x3f,
	0x3f,
	0x3f,
	0x00,
	0x00,
	0x00,
	0x05,
	0x05,
	0x05,
	0x08,
	0x08,
	0x08,
	0x0b,
	0x0b,
	0x0b,
	0x0e,
	0x0e,
	0x0e,
	0x11,
	0x11,
	0x11,
	0x14,
	0x14,
	0x14,
	0x18,
	0x18,
	0x18,
	0x1c,
	0x1c,
	0x1c,
	0x20,
	0x20,
	0x20,
	0x24,
	0x24,
	0x24,
	0x28,
	0x28,
	0x28,
	0x2d,
	0x2d,
	0x2d,
	0x32,
	0x32,
	0x32,
	0x38,
	0x38,
	0x38,
	0x3f,
	0x3f,
	0x3f,
	0x00,
	0x00,
	0x3f,
	0x10,
	0x00,
	0x3f,
	0x1f,
	0x00,
	0x3f,
	0x2f,
	0x00,
	0x3f,
	0x3f,
	0x00,
	0x3f,
	0x3f,
	0x00,
	0x2f,
	0x3f,
	0x00,
	0x1f,
	0x3f,
	0x00,
	0x10,
	0x3f,
	0x00,
	0x00,
	0x3f,
	0x10,
	0x00,
	0x3f,
	0x1f,
	0x00,
	0x3f,
	0x2f,
	0x00,
	0x3f,
	0x3f,
	0x00,
	0x2f,
	0x3f,
	0x00,
	0x1f,
	0x3f,
	0x00,
	0x10,
	0x3f,
	0x00,
	0x00,
	0x3f,
	0x00,
	0x00,
	0x3f,
	0x10,
	0x00,
	0x3f,
	0x1f,
	0x00,
	0x3f,
	0x2f,
	0x00,
	0x3f,
	0x3f,
	0x00,
	0x2f,
	0x3f,
	0x00,
	0x1f,
	0x3f,
	0x00,
	0x10,
	0x3f,
	0x1f,
	0x1f,
	0x3f,
	0x27,
	0x1f,
	0x3f,
	0x2f,
	0x1f,
	0x3f,
	0x37,
	0x1f,
	0x3f,
	0x3f,
	0x1f,
	0x3f,
	0x3f,
	0x1f,
	0x37,
	0x3f,
	0x1f,
	0x2f,
	0x3f,
	0x1f,
	0x27,
	0x3f,
	0x1f,
	0x1f,
	0x3f,
	0x27,
	0x1f,
	0x3f,
	0x2f,
	0x1f,
	0x3f,
	0x37,
	0x1f,
	0x3f,
	0x3f,
	0x1f,
	0x37,
	0x3f,
	0x1f,
	0x2f,
	0x3f,
	0x1f,
	0x27,
	0x3f,
	0x1f,
	0x1f,
	0x3f,
	0x1f,
	0x1f,
	0x3f,
	0x27,
	0x1f,
	0x3f,
	0x2f,
	0x1f,
	0x3f,
	0x37,
	0x1f,
	0x3f,
	0x3f,
	0x1f,
	0x37,
	0x3f,
	0x1f,
	0x2f,
	0x3f,
	0x1f,
	0x27,
	0x3f,
	0x2d,
	0x2d,
	0x3f,
	0x31,
	0x2d,
	0x3f,
	0x36,
	0x2d,
	0x3f,
	0x3a,
	0x2d,
	0x3f,
	0x3f,
	0x2d,
	0x3f,
	0x3f,
	0x2d,
	0x3a,
	0x3f,
	0x2d,
	0x36,
	0x3f,
	0x2d,
	0x31,
	0x3f,
	0x2d,
	0x2d,
	0x3f,
	0x31,
	0x2d,
	0x3f,
	0x36,
	0x2d,
	0x3f,
	0x3a,
	0x2d,
	0x3f,
	0x3f,
	0x2d,
	0x3a,
	0x3f,
	0x2d,
	0x36,
	0x3f,
	0x2d,
	0x31,
	0x3f,
	0x2d,
	0x2d,
	0x3f,
	0x2d,
	0x2d,
	0x3f,
	0x31,
	0x2d,
	0x3f,
	0x36,
	0x2d,
	0x3f,
	0x3a,
	0x2d,
	0x3f,
	0x3f,
	0x2d,
	0x3a,
	0x3f,
	0x2d,
	0x36,
	0x3f,
	0x2d,
	0x31,
	0x3f,
	0x00,
	0x00,
	0x1c,
	0x07,
	0x00,
	0x1c,
	0x0e,
	0x00,
	0x1c,
	0x15,
	0x00,
	0x1c,
	0x1c,
	0x00,
	0x1c,
	0x1c,
	0x00,
	0x15,
	0x1c,
	0x00,
	0x0e,
	0x1c,
	0x00,
	0x07,
	0x1c,
	0x00,
	0x00,
	0x1c,
	0x07,
	0x00,
	0x1c,
	0x0e,
	0x00,
	0x1c,
	0x15,
	0x00,
	0x1c,
	0x1c,
	0x00,
	0x15,
	0x1c,
	0x00,
	0x0e,
	0x1c,
	0x00,
	0x07,
	0x1c,
	0x00,
	0x00,
	0x1c,
	0x00,
	0x00,
	0x1c,
	0x07,
	0x00,
	0x1c,
	0x0e,
	0x00,
	0x1c,
	0x15,
	0x00,
	0x1c,
	0x1c,
	0x00,
	0x15,
	0x1c,
	0x00,
	0x0e,
	0x1c,
	0x00,
	0x07,
	0x1c,
	0x0e,
	0x0e,
	0x1c,
	0x11,
	0x0e,
	0x1c,
	0x15,
	0x0e,
	0x1c,
	0x18,
	0x0e,
	0x1c,
	0x1c,
	0x0e,
	0x1c,
	0x1c,
	0x0e,
	0x18,
	0x1c,
	0x0e,
	0x15,
	0x1c,
	0x0e,
	0x11,
	0x1c,
	0x0e,
	0x0e,
	0x1c,
	0x11,
	0x0e,
	0x1c,
	0x15,
	0x0e,
	0x1c,
	0x18,
	0x0e,
	0x1c,
	0x1c,
	0x0e,
	0x18,
	0x1c,
	0x0e,
	0x15,
	0x1c,
	0x0e,
	0x11,
	0x1c,
	0x0e,
	0x0e,
	0x1c,
	0x0e,
	0x0e,
	0x1c,
	0x11,
	0x0e,
	0x1c,
	0x15,
	0x0e,
	0x1c,
	0x18,
	0x0e,
	0x1c,
	0x1c,
	0x0e,
	0x18,
	0x1c,
	0x0e,
	0x15,
	0x1c,
	0x0e,
	0x11,
	0x1c,
	0x14,
	0x14,
	0x1c,
	0x16,
	0x14,
	0x1c,
	0x18,
	0x14,
	0x1c,
	0x1a,
	0x14,
	0x1c,
	0x1c,
	0x14,
	0x1c,
	0x1c,
	0x14,
	0x1a,
	0x1c,
	0x14,
	0x18,
	0x1c,
	0x14,
	0x16,
	0x1c,
	0x14,
	0x14,
	0x1c,
	0x16,
	0x14,
	0x1c,
	0x18,
	0x14,
	0x1c,
	0x1a,
	0x14,
	0x1c,
	0x1c,
	0x14,
	0x1a,
	0x1c,
	0x14,
	0x18,
	0x1c,
	0x14,
	0x16,
	0x1c,
	0x14,
	0x14,
	0x1c,
	0x14,
	0x14,
	0x1c,
	0x16,
	0x14,
	0x1c,
	0x18,
	0x14,
	0x1c,
	0x1a,
	0x14,
	0x1c,
	0x1c,
	0x14,
	0x1a,
	0x1c,
	0x14,
	0x18,
	0x1c,
	0x14,
	0x16,
	0x1c,
	0x00,
	0x00,
	0x10,
	0x04,
	0x00,
	0x10,
	0x08,
	0x00,
	0x10,
	0x0c,
	0x00,
	0x10,
	0x10,
	0x00,
	0x10,
	0x10,
	0x00,
	0x0c,
	0x10,
	0x00,
	0x08,
	0x10,
	0x00,
	0x04,
	0x10,
	0x00,
	0x00,
	0x10,
	0x04,
	0x00,
	0x10,
	0x08,
	0x00,
	0x10,
	0x0c,
	0x00,
	0x10,
	0x10,
	0x00,
	0x0c,
	0x10,
	0x00,
	0x08,
	0x10,
	0x00,
	0x04,
	0x10,
	0x00,
	0x00,
	0x10,
	0x00,
	0x00,
	0x10,
	0x04,
	0x00,
	0x10,
	0x08,
	0x00,
	0x10,
	0x0c,
	0x00,
	0x10,
	0x10,
	0x00,
	0x0c,
	0x10,
	0x00,
	0x08,
	0x10,
	0x00,
	0x04,
	0x10,
	0x08,
	0x08,
	0x10,
	0x0a,
	0x08,
	0x10,
	0x0c,
	0x08,
	0x10,
	0x0e,
	0x08,
	0x10,
	0x10,
	0x08,
	0x10,
	0x10,
	0x08,
	0x0e,
	0x10,
	0x08,
	0x0c,
	0x10,
	0x08,
	0x0a,
	0x10,
	0x08,
	0x08,
	0x10,
	0x0a,
	0x08,
	0x10,
	0x0c,
	0x08,
	0x10,
	0x0e,
	0x08,
	0x10,
	0x10,
	0x08,
	0x0e,
	0x10,
	0x08,
	0x0c,
	0x10,
	0x08,
	0x0a,
	0x10,
	0x08,
	0x08,
	0x10,
	0x08,
	0x08,
	0x10,
	0x0a,
	0x08,
	0x10,
	0x0c,
	0x08,
	0x10,
	0x0e,
	0x08,
	0x10,
	0x10,
	0x08,
	0x0e,
	0x10,
	0x08,
	0x0c,
	0x10,
	0x08,
	0x0a,
	0x10,
	0x0b,
	0x0b,
	0x10,
	0x0c,
	0x0b,
	0x10,
	0x0d,
	0x0b,
	0x10,
	0x0f,
	0x0b,
	0x10,
	0x10,
	0x0b,
	0x10,
	0x10,
	0x0b,
	0x0f,
	0x10,
	0x0b,
	0x0d,
	0x10,
	0x0b,
	0x0c,
	0x10,
	0x0b,
	0x0b,
	0x10,
	0x0c,
	0x0b,
	0x10,
	0x0d,
	0x0b,
	0x10,
	0x0f,
	0x0b,
	0x10,
	0x10,
	0x0b,
	0x0f,
	0x10,
	0x0b,
	0x0d,
	0x10,
	0x0b,
	0x0c,
	0x10,
	0x0b,
	0x0b,
	0x10,
	0x0b,
	0x0b,
	0x10,
	0x0c,
	0x0b,
	0x10,
	0x0d,
	0x0b,
	0x10,
	0x0f,
	0x0b,
	0x10,
	0x10,
	0x0b,
	0x0f,
	0x10,
	0x0b,
	0x0d,
	0x10,
	0x0b,
	0x0c,
	0x10,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
	0x00,
}
function Video.new(bus: any, options: any?): any
	options = options or {}
	local self: any = setmetatable({
		bus = bus,
		mode = 3,
		width = 640,
		height = 200,
		pixels = buffer.create(640 * 200 * 4),
		paletteRGBA = buffer.create(1024),
		palette = {},
		vramDirty = true,
		paletteDirty = true,
		planes = { buffer.create(65536), buffer.create(65536), buffer.create(65536), buffer.create(65536) },
		seqIndex = 0,
		seq = { [2] = 15, [4] = 8 },
		gcIndex = 0,
		gc = { [4] = 0 },
		crtcIndex = 0,
		crtc = {},
		dacRead = 0,
		dacWrite = 0,
		dacReadComponent = 0,
		dacWriteComponent = 0,
		status = false,
		cgaColor = 0x20,
		blinkPhase = true,
		blinkClock = options.clock or os.clock,
		lastBlink = -1,
		imageLabel = options.imageLabel,
		headless = options.headless,
		image = nil,
	}, Video)
	for i = 0, 255 do
		self:setPalette(i, defaultPalette[i * 3 + 1], defaultPalette[i * 3 + 2], defaultPalette[i * 3 + 3])
	end
	local oldRead: any = bus.memoryReadHook
	local oldWrite: any = bus.memoryWriteHook
	bus.memoryReadHook = function(addr: number): number?
		if self.mode == 0x13 and bit32.band(self.seq[4] or 0, 8) == 0 and addr >= 0xA0000 and addr < 0xB0000 then
			return buffer.readu8(self.planes[(self.gc[4] or 0) % 4 + 1], addr - 0xA0000)
		end
		if oldRead then
			return (oldRead :: any)(addr)
		end
		return nil
	end
	bus.memoryWriteHook = function(addr: number, value: number): boolean
		if self.mode == 0x13 and bit32.band(self.seq[4] or 0, 8) == 0 and addr >= 0xA0000 and addr < 0xB0000 then
			for p = 0, 3 do
				if bit32.band(self.seq[2] or 15, bit32.lshift(1, p)) ~= 0 then
					buffer.writeu8(self.planes[p + 1], addr - 0xA0000, value)
				end
			end
			self.vramDirty = true
			return true
		end
		if oldWrite then
			return (oldWrite :: any)(addr, value)
		end
		return false
	end
	local function port(n: number, read: (() -> number)?, write: ((number) -> ())?)
		bus:registerPortHandler(n, read, write)
	end
	port(0x3c4, function()
		return self.seqIndex
	end, function(v)
		self.seqIndex = v
	end)
	port(0x3c5, function()
		return self.seq[self.seqIndex] or 0
	end, function(v)
		self.seq[self.seqIndex] = v
		self.vramDirty = true
	end)
	port(0x3ce, function()
		return self.gcIndex
	end, function(v)
		self.gcIndex = v
	end)
	port(0x3cf, function()
		return self.gc[self.gcIndex] or 0
	end, function(v)
		self.gc[self.gcIndex] = v
	end)
	port(0x3d4, function()
		return self.crtcIndex
	end, function(v)
		self.crtcIndex = v
	end)
	port(0x3d5, function()
		return self.crtc[self.crtcIndex] or 0
	end, function(v)
		self.crtc[self.crtcIndex] = v
		self.vramDirty = true
	end)
	port(0x3d9, function()
		return self.cgaColor
	end, function(v)
		self.cgaColor = v
		self.vramDirty = true
	end)
	port(0x3da, function()
		self.status = not self.status
		return if self.status then 9 else 0
	end, nil)
	port(0x3c7, function()
		return 0
	end, function(v)
		self.dacRead = v
		self.dacReadComponent = 0
	end)
	port(0x3c8, function()
		return self.dacWrite
	end, function(v)
		self.dacWrite = v
		self.dacWriteComponent = 0
	end)
	port(0x3c9, function()
		local p = self.palette[self.dacRead]
		local v = p[self.dacReadComponent + 1]
		self.dacReadComponent += 1
		if self.dacReadComponent == 3 then
			self.dacReadComponent = 0
			self.dacRead = (self.dacRead + 1) % 256
		end
		return v
	end, function(v)
		local p = self.palette[self.dacWrite]
		p[self.dacWriteComponent + 1] = bit32.band(v, 63)
		self:setPalette(self.dacWrite, p[1], p[2], p[3])
		self.dacWriteComponent += 1
		if self.dacWriteComponent == 3 then
			self.dacWriteComponent = 0
			self.dacWrite = (self.dacWrite + 1) % 256
		end
	end)
	bus.video = self
	self:setMode(3)
	return self
end
function Video.setPalette(self: any, index: number, r: number, g: number, b: number)
	index = math.floor(index) % 256
	r = math.floor(r) % 64
	g = math.floor(g) % 64
	b = math.floor(b) % 64
	self.palette[index] = { r, g, b }
	local o = index * 4
	buffer.writeu8(self.paletteRGBA, o, math.floor(r * 255 / 63))
	buffer.writeu8(self.paletteRGBA, o + 1, math.floor(g * 255 / 63))
	buffer.writeu8(self.paletteRGBA, o + 2, math.floor(b * 255 / 63))
	buffer.writeu8(self.paletteRGBA, o + 3, 255)
	self.paletteDirty = true
end
function Video.getPalette(self: any, index: number): (number, number, number)
	local p = self.palette[math.floor(index) % 256]
	return p[1], p[2], p[3]
end
function Video.setMode(self: any, mode: number, preserve: boolean?)
	preserve = preserve or bit32.band(mode, 0x80) ~= 0
	mode = bit32.band(mode, 0x7f)
	assert(
		mode == 3 or mode == 4 or mode == 5 or mode == 6 or mode == 0x13,
		"unsupported video mode " .. tostring(mode)
	)
	self.mode = mode
	self.width = if mode == 3 or mode == 6 then 640 else 320
	self.height = 200
	self.seq[4] = 8
	self.seq[2] = 15
	self.pixels = buffer.create(self.width * self.height * 4)
	if self.image then
		self.image:Destroy()
		self.image = nil
	end
	if not preserve then
		local base = if mode == 3 then 0xB8000 elseif mode == 0x13 then 0xA0000 else 0xB8000
		local count = if mode == 3 then 4000 elseif mode == 0x13 then 64000 else 16384
		for i = 0, count - 1 do
			self.bus:write8(base + i, if mode == 3 and i % 2 == 1 then 7 else 0)
		end
		for _, plane in ipairs(self.planes) do
			buffer.fill(plane, 0, 0, 65536)
		end
	end
	self.bus:write8(0x449, mode)
	self.bus:write16(0x44a, if mode == 3 then 80 else 40)
	self.bus:write16(0x450, 0)
	self.bus:write16(0x460, 0x0607)
	self.bus:write16(0x463, 0x3d4)
	self.bus:write16(0x44c, if mode == 3 then 0x1000 else 0x4000)
	self.bus:write8(0x484, 24)
	self.bus:write16(0x485, 8)
	self.vramDirty = true
end
-- Scroll a rectangle in BIOS character-cell coordinates. All graphics writes
-- target guest memory (or VGA planes), including CGA's alternating banks.
function Video.scrollWindow(
	self: any,
	lines: number,
	down: boolean,
	top: number,
	left: number,
	bottom: number,
	right: number,
	attribute: number
)
	local columns = math.floor(self.width / 8)
	local rows = math.floor(self.height / 8)
	top = math.max(0, math.floor(top))
	left = math.max(0, math.floor(left))
	bottom = math.min(rows - 1, math.floor(bottom))
	right = math.min(columns - 1, math.floor(right))
	if top > bottom or left > right then
		return
	end
	local count = math.floor(lines)
	if count <= 0 or count > bottom - top + 1 then
		count = bottom - top + 1
	end
	local bus = self.bus
	if self.mode == 3 then
		local start, finish, step = if down then bottom else top, if down then top else bottom, if down then -1 else 1
		for row = start, finish, step do
			local source = if down then row - count else row + count
			for col = left, right do
				local dest = 0xb8000 + (row * 80 + col) * 2
				if source >= top and source <= bottom then
					local from = 0xb8000 + (source * 80 + col) * 2
					bus:write8(dest, bus:read8(from))
					bus:write8(dest + 1, bus:read8(from + 1))
				else
					bus:write8(dest, 32)
					bus:write8(dest + 1, attribute)
				end
			end
		end
	else
		local first, last = top * 8, (bottom + 1) * 8 - 1
		local start, finish, step = if down then last else first, if down then first else last, if down then -1 else 1
		local displacement = count * 8
		local planar = self.mode == 0x13 and bit32.band(self.seq[4] or 0, 8) == 0
		local bytesPerCell = if self.mode == 6 then 1 elseif self.mode == 4 or self.mode == 5 or planar then 2 else 8
		local fill =
			bit32.band(attribute, if self.mode == 6 then 1 elseif self.mode == 4 or self.mode == 5 then 3 else 255)
		if self.mode == 6 then
			fill *= 255
		elseif self.mode == 4 or self.mode == 5 then
			fill *= 0x55
		end
		for scan = start, finish, step do
			local source = if down then scan - displacement else scan + displacement
			local valid = source >= first and source <= last
			for column = left * bytesPerCell, (right + 1) * bytesPerCell - 1 do
				if planar then
					for plane = 1, 4 do
						local dst = scan * 80 + column
						local value = if valid then buffer.readu8(self.planes[plane], source * 80 + column) else fill
						buffer.writeu8(self.planes[plane], dst, value)
					end
				else
					local dst = if self.mode == 0x13
						then 0xa0000 + scan * 320 + column
						else 0xb8000 + math.floor(scan / 2) * 80 + (scan % 2) * 8192 + column
					local value = fill
					if valid then
						local src = if self.mode == 0x13
							then 0xa0000 + source * 320 + column
							else 0xb8000 + math.floor(source / 2) * 80 + (source % 2) * 8192 + column
						value = bus:read8(src)
					end
					bus:write8(dst, value)
				end
			end
		end
	end
	self.vramDirty = true
end
function Video.teletype(self: any, ch: number)
	local bus = self.bus
	local pos = bus:read16(0x450)
	local x = pos % 256
	local y = math.floor(pos / 256) % 256
	local columns = math.floor(self.width / 8)
	local rows = math.floor(self.height / 8)
	x = math.min(x, columns - 1)
	y = math.min(y, rows - 1)
	if ch == 13 then
		x = 0
	elseif ch == 10 then
		y += 1
	elseif ch == 8 then
		x = math.max(0, x - 1)
	elseif ch >= 32 then
		if self.mode == 3 then
			local off = 0xB8000 + (y * 80 + x) * 2
			bus:write8(off, ch)
			bus:write8(off + 1, 7)
		else
			for gy = 0, 7 do
				local bits = buffer.readu8(font, ch * 8 + gy)
				for gx = 0, 7 do
					local px = x * 8 + gx
					local py = y * 8 + gy
					local on = bit32.band(bits, bit32.rshift(128, gx)) ~= 0
					if self.mode == 0x13 then
						local value = if on then 15 else 0
						if bit32.band(self.seq[4] or 0, 8) == 0 then
							buffer.writeu8(self.planes[px % 4 + 1], py * 80 + math.floor(px / 4), value)
						else
							bus:write8(0xa0000 + py * 320 + px, value)
						end
					else
						local offset = 0xb8000
							+ math.floor(py / 2) * 80
							+ (py % 2) * 8192
							+ math.floor(px / (if self.mode == 6 then 8 else 4))
						local shift = if self.mode == 6 then 7 - px % 8 else 6 - 2 * (px % 4)
						local mask = if self.mode == 6 then 1 else 3
						local old = bus:read8(offset)
						bus:write8(
							offset,
							bit32.bor(
								bit32.band(old, bit32.bnot(bit32.lshift(mask, shift))),
								bit32.lshift(if on then mask else 0, shift)
							)
						)
					end
				end
			end
		end
		x += 1
		if x >= columns then
			x = 0
			y += 1
		end
	end
	if y >= rows then
		if self.mode == 3 then
			for i = 0, 3839 do
				bus:write8(0xB8000 + i, bus:read8(0xB8000 + i + 160))
			end
			for i = 3840, 3999 do
				bus:write8(0xB8000 + i, if i % 2 == 1 then 7 else 32)
			end
		end
		if self.mode == 0x13 then
			if bit32.band(self.seq[4] or 0, 8) == 0 then
				for _, rawPlane in ipairs(self.planes) do
					local plane = rawPlane :: buffer
					buffer.copy(plane, 0, plane, 640, (rows - 1) * 640)
					buffer.fill(plane, (rows - 1) * 640, 0, 640)
				end
			else
				for i = 0, (rows - 1) * 2560 - 1 do
					bus:write8(0xa0000 + i, bus:read8(0xa0000 + i + 2560))
				end
				for i = (rows - 1) * 2560, rows * 2560 - 1 do
					bus:write8(0xa0000 + i, 0)
				end
			end
		elseif self.mode == 4 or self.mode == 5 or self.mode == 6 then
			for scan = 0, self.height - 9 do
				for col = 0, 79 do
					local dst = 0xb8000 + math.floor(scan / 2) * 80 + (scan % 2) * 8192 + col
					local src = 0xb8000 + math.floor((scan + 8) / 2) * 80 + (scan % 2) * 8192 + col
					bus:write8(dst, bus:read8(src))
				end
			end
			for scan = self.height - 8, self.height - 1 do
				for col = 0, 79 do
					bus:write8(0xb8000 + math.floor(scan / 2) * 80 + (scan % 2) * 8192 + col, 0)
				end
			end
		end
		y = rows - 1
	end
	bus:write16(0x450, y * 256 + x)
	self.vramDirty = true
end
function Video.render(self: any): buffer
	local bus = self.bus
	local planar = self.mode == 0x13 and bit32.band(self.seq[4] or 0, 8) == 0
	-- Common Mode X timing uses vertical display end 0xdf with overflow bit 1.
	local h = if planar and self.crtc[0x12] == 0xdf and bit32.band(self.crtc[7] or 0, 2) ~= 0 then 240 else 200
	if self.height ~= h then
		self.height = h
		self.pixels = buffer.create(self.width * h * 4)
		if self.image then
			self.image:Destroy()
			self.image = nil
		end
	end
	local pixels = self.pixels
	for y = 0, self.height - 1 do
		for x = 0, self.width - 1 do
			local color: number
			if self.mode == 3 then
				local cell = 0xB8000 + (math.floor(y / 8) * 80 + math.floor(x / 8)) * 2
				local ch = bus:read8(cell)
				local attr = bus:read8(cell + 1)
				local bits = buffer.readu8(font, ch * 8 + y % 8)
				local foreground = bit32.band(bits, bit32.rshift(0x80, x % 8)) ~= 0 and (attr < 128 or self.blinkPhase)
				local cursor = bus:read16(0x450)
				local cursorShape = bus:read16(0x460)
				local start = bit32.band(bit32.rshift(cursorShape, 8), 31)
				local finish = bit32.band(cursorShape, 31)
				if
					self.blinkPhase
					and bit32.band(cursorShape, 0x2000) == 0
					and cursor % 256 == math.floor(x / 8)
					and math.floor(cursor / 256) % 256 == math.floor(y / 8)
					and y % 8 >= start
					and y % 8 <= finish
				then
					foreground = true
				end
				color = if foreground then attr % 16 else math.floor(attr / 16) % 8
			elseif self.mode == 0x13 then
				if planar then
					color = buffer.readu8(self.planes[x % 4 + 1], math.floor(y * self.width / 4) + math.floor(x / 4))
				else
					color = bus:read8(0xA0000 + y * 320 + x)
				end
			else
				local off = math.floor(y / 2) * 80 + (y % 2) * 8192
				if self.mode == 6 then
					local v = bus:read8(0xB8000 + off + math.floor(x / 8))
					color = if bit32.band(v, bit32.rshift(0x80, x % 8)) ~= 0 then 15 else 0
				else
					local v = bus:read8(0xB8000 + off + math.floor(x / 4))
					local c = bit32.band(bit32.rshift(v, 6 - 2 * (x % 4)), 3)
					local base = if bit32.band(self.cgaColor, 0x20) ~= 0
						then ({ 0, 3, 5, 7 })[c + 1]
						else ({ 0, 2, 4, 6 })[c + 1]
					color = if c == 0
						then bit32.band(self.cgaColor, 15)
						else base + (if bit32.band(self.cgaColor, 0x10) ~= 0 then 8 else 0)
				end
			end
			buffer.writeu32(pixels, (y * self.width + x) * 4, buffer.readu32(self.paletteRGBA, color * 4))
		end
	end
	self.vramDirty = false
	self.paletteDirty = false
	if not self.headless and self.imageLabel then
		if not self.image then
			local assetService = game:GetService("AssetService")
			self.image = assetService:CreateEditableImage({ Size = Vector2.new(self.width, self.height) })
			if self.image then
				self.imageLabel.ImageContent = Content.fromObject(self.image)
				self.imageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
				local aspect = self.imageLabel:FindFirstChildOfClass("UIAspectRatioConstraint")
					or Instance.new("UIAspectRatioConstraint")
				aspect.AspectRatio = 4 / 3
				aspect.Parent = self.imageLabel
			end
		end
		if self.image then
			self.image:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(self.width, self.height), pixels)
		else
			self.vramDirty = true
		end
	end
	return pixels
end
function Video.present(self: any, now: number?)
	local phase = math.floor((now or self.blinkClock()) * 2)
	if phase ~= self.lastBlink then
		self.lastBlink = phase
		self.blinkPhase = phase % 2 == 0
		if self.mode == 3 then
			self.vramDirty = true
		end
	end
	if self.vramDirty or self.paletteDirty then
		self:render()
	end
end
return Video
