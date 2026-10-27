--!strict
local CPU = require(script.Parent.CPUState)
local Interpreter = require(script.Parent.Interpreter)
local VFS = require(script.Parent.VFS)
local CP437Font = require(script.Parent.CP437Font)
local HLE = {}
HLE.__index = HLE
local function r(c: any, n: number): number
	return CPU.getReg(c, n, 16)
end
local function w(c: any, n: number, v: number)
	CPU.setReg(c, n, 16, bit32.band(v, 0xffff))
end
local function byte(c: any, n: number): number
	return CPU.getReg(c, n, 8)
end
local function setbyte(c: any, n: number, v: number)
	CPU.setReg(c, n, 8, bit32.band(v, 255))
end
local function addr(seg: number, off: number): number
	return seg * 16 + bit32.band(off, 0xffff)
end
local function readstr(bus: any, seg: number, off: number, term: number?): string
	local out = {}
	for i = 0, 65535 do
		local b = bus:read8(addr(seg, off + i))
		if b == (term or 0) then
			break
		end
		table.insert(out, string.char(b))
	end
	return table.concat(out)
end
local function iret(c: any, bus: any)
	if c.mode32 then
		local sp = CPU.getReg(c, 4, 32)
		local a = ((c.segmentBases and c.segmentBases[c.ss]) or 0) + sp
		c.ip = bus:read32(a)
		c.cs = bit32.band(bus:read32(a + 4), 0xffff)
		c.flags = bus:read32(a + 8)
		CPU.setReg(c, 4, 32, sp + 12)
	else
		local sp = r(c, 4)
		c.ip = bus:readSeg16(c.ss, sp)
		c.cs = bus:readSeg16(c.ss, sp + 2)
		c.flags = bus:readSeg16(c.ss, sp + 4)
		w(c, 4, sp + 6)
	end
	c.currentBlockKey = CPU.key(c)
end
function HLE.new(bus: any, options: any?): any
	options = options or {}
	bus:write16(0x410, 0x0021) -- floppy present, color 80-column display
	bus:write16(0x413, 640)
	bus:load(0xf8000, CP437Font)
	local self = setmetatable({
		vfs = options.vfs or VFS.new(),
		video = options.video or bus.video,
		audio = options.audio,
		input = options.input,
		clock = options.clock,
		dtaSegment = nil,
		dtaOffset = 0x80,
		searches = {},
		blocks = nil,
		mouseX = 0,
		mouseY = 0,
		mouseMinX = 0,
		mouseMaxX = 639,
		mouseMinY = 0,
		mouseMaxY = 199,
		mouseButtons = 0,
		descriptors = {},
		nextSelector = 8,
		linearBlocks = {},
		nextLinearHandle = 1,
	}, HLE)
	bus.hle = self
	local rom = buffer.create(0x505)
	for v = 0, 255 do
		bus:write16(v * 4, 0x100 + v * 4)
		bus:write16(v * 4 + 2, 0xf000)
		buffer.writeu8(rom, v * 4, 0xcf)
	end
	buffer.writeu8(rom, 0x500, 0xcf)
	buffer.writeu8(rom, 0x504, 0xcf)
	bus:load(0xf0100, rom)
	if bus:read16(0x41a) == 0 then
		bus:write16(0x41a, 0x1e)
		bus:write16(0x41c, 0x1e)
	end
	return self
end
function HLE.patchSavedFlags(self: any, c: any, bus: any, mask: number, value: number)
	if c.mode32 then
		local a = ((c.segmentBases and c.segmentBases[c.ss]) or 0) + CPU.getReg(c, 4, 32) + 8
		local flags = bus:read32(a)
		bus:write32(a, bit32.bor(bit32.band(flags, bit32.bnot(mask)), bit32.band(value, mask)))
	else
		local sp = r(c, 4)
		local flags = bus:readSeg16(c.ss, sp + 4)
		bus:writeSeg16(c.ss, sp + 4, bit32.bor(bit32.band(flags, bit32.bnot(mask)), bit32.band(value, mask)))
	end
end
local function status(self: any, c: any, bus: any, err: number?)
	self:patchSavedFlags(c, bus, 1, if err then 1 else 0)
	if err then
		w(c, 0, err)
	end
end
local function key(bus: any, consume: boolean): number?
	local head, tail = bus:read16(0x41a), bus:read16(0x41c)
	if head == tail then
		return nil
	end
	local v = bus:read16(0x400 + head)
	if consume then
		head += 2
		if head >= 0x3e then
			head = 0x1e
		end
		bus:write16(0x41a, head)
	end
	return v
end
local function dta(self: any, c: any): number
	return addr(self.dtaSegment or c.pspSegment or c.ds, self.dtaOffset)
end
local function findResult(self: any, c: any, bus: any, result: any)
	local a = dta(self, c)
	for i = 0, 42 do
		bus:write8(a + i, 0)
	end
	bus:write8(a + 21, 0x20)
	bus:write16(a + 26, result.size % 65536)
	bus:write16(a + 28, math.floor(result.size / 65536))
	for i = 1, math.min(12, #result.name) do
		bus:write8(a + 29 + i - 1, string.byte(result.name, i))
	end
end
local function initBlocks(self: any, c: any)
	if self.blocks then
		return
	end
	local start = c.pspSegment or c.loadSegment
	local ending = c.memoryEndSegment or 0xa000
	local size = c.initialParagraphs or math.max(0, ending - start)
	self.blocks = { { segment = start, size = size, owner = start } }
	local freeSize = ending - start - size - 1
	if freeSize >= 0 then
		table.insert(self.blocks, { segment = start + size + 1, size = freeSize, owner = 0 })
	end
end
local function syncBlocks(self: any, bus: any)
	local blocks: { any } = self.blocks
	table.sort(blocks, function(a: any, b: any)
		return a.segment < b.segment
	end)
	local i = 1
	while i < #blocks do
		local a, b = blocks[i], blocks[i + 1]
		if a.owner == 0 and b.owner == 0 and a.segment + a.size + 1 == b.segment then
			a.size += b.size + 1
			table.remove(blocks, i + 1)
		else
			i += 1
		end
	end
	for n, b in ipairs(blocks) do
		local a = (b.segment - 1) * 16
		bus:write8(a, if n == #blocks then 0x5a else 0x4d)
		bus:write16(a + 1, b.owner)
		bus:write16(a + 3, b.size)
	end
end
function HLE.dos(self: any, c: any, bus: any): boolean
	local ah, al = byte(c, 4), byte(c, 0)
	local dx, bx, cx = r(c, 2), r(c, 3), r(c, 1)
	local vfs = self.vfs
	if ah == 0x00 or ah == 0x4c then
		c.halted = true
		c.exitCode = if ah == 0 then 0 else al
	elseif ah == 0x02 then
		if self.video then
			self.video:teletype(bit32.band(dx, 255))
		end
		setbyte(c, 0, dx)
	elseif ah == 0x06 then
		if bit32.band(dx, 255) == 255 then
			local k = key(bus, true)
			self:patchSavedFlags(c, bus, 0x40, if k then 0 else 0x40)
			setbyte(c, 0, k or 0)
		else
			if self.video then
				self.video:teletype(bit32.band(dx, 255))
			end
			setbyte(c, 0, dx)
		end
	elseif ah == 0x09 then
		local s = readstr(bus, c.ds, dx, 36)
		if self.video then
			for i = 1, #s do
				self.video:teletype(string.byte(s, i) :: number)
			end
		end
		setbyte(c, 0, 36)
	elseif ah == 0x01 or ah == 0x07 or ah == 0x08 then
		local k = key(bus, true)
		if not k then
			c.waitingForKey = true
			c.yieldRequested = true
			c.flags = bit32.bor(c.flags, 0x200)
			return false
		end
		c.waitingForKey = false
		setbyte(c, 0, k)
		if ah == 1 and self.video then
			self.video:teletype(bit32.band(k, 255))
		end
	elseif ah == 0x0a then
		local a = addr(c.ds, dx)
		local max = bus:read8(a)
		local count = bus:read8(a + 1)
		while true do
			local k = key(bus, true)
			if not k then
				c.waitingForKey = true
				c.yieldRequested = true
				c.flags = bit32.bor(c.flags, 0x200)
				return false
			end
			local ch = bit32.band(k, 255)
			if ch == 13 then
				bus:write8(a + 2 + count, 13)
				bus:write8(a + 1, count)
				c.waitingForKey = false
				break
			elseif ch == 8 and count > 0 then
				count -= 1
				bus:write8(a + 1, count)
			elseif ch ~= 0 and count < math.max(0, max - 1) then
				bus:write8(a + 2 + count, ch)
				count += 1
				bus:write8(a + 1, count)
				if self.video then
					self.video:teletype(ch)
				end
			end
		end
	elseif ah == 0x0e then
		self.drive = if byte(c, 2) < 3 then byte(c, 2) else 2
		setbyte(c, 0, 3)
	elseif ah == 0x0b then
		setbyte(c, 0, if key(bus, false) then 0xff else 0)
	elseif ah == 0x19 then
		setbyte(c, 0, self.drive or 2)
	elseif ah == 0x1a then
		self.dtaSegment = c.ds
		self.dtaOffset = dx
	elseif ah == 0x2a or ah == 0x2c then
		local t = if self.clock then (self.clock :: any)() else os.date("*t")
		if ah == 0x2a then
			w(c, 1, t.year)
			setbyte(c, 6, t.month)
			setbyte(c, 2, t.day)
			setbyte(c, 0, (t.wday - 1) % 7)
		else
			setbyte(c, 5, t.hour)
			setbyte(c, 1, t.min)
			setbyte(c, 6, t.sec)
			setbyte(c, 2, 0)
		end
	elseif ah == 0x2f then
		c.es = self.dtaSegment or c.pspSegment or c.ds
		w(c, 3, self.dtaOffset)
	elseif ah == 0x30 then
		w(c, 0, 0x0005)
		w(c, 3, 0)
		w(c, 1, 0)
	elseif ah == 0x35 then
		w(c, 3, bus:read16(al * 4))
		c.es = bus:read16(al * 4 + 2)
	elseif ah == 0x25 then
		bus:write16(al * 4, dx)
		bus:write16(al * 4 + 2, c.ds)
	elseif ah == 0x3b then
		status(self, c, bus, if vfs:chdir(readstr(bus, c.ds, dx)) then nil else 3)
	elseif ah == 0x3c or ah == 0x3d then
		local handle, err = vfs:open(readstr(bus, c.ds, dx), if ah == 0x3c then 2 else bit32.band(al, 3), ah == 0x3c)
		status(self, c, bus, err)
		if handle then
			w(c, 0, handle)
		end
	elseif ah == 0x3e then
		status(self, c, bus, if vfs:close(bx) then nil else 6)
	elseif ah == 0x3f then
		local data, err = vfs:read(bx, cx)
		status(self, c, bus, err)
		if data then
			for i = 1, #data do
				bus:write8(addr(c.ds, dx + i - 1), string.byte(data, i))
			end
			w(c, 0, #data)
		end
	elseif ah == 0x40 then
		local chars = {}
		for i = 0, cx - 1 do
			table.insert(chars, string.char(bus:read8(addr(c.ds, dx + i))))
		end
		local s = table.concat(chars)
		if bx == 1 or bx == 2 then
			if self.video then
				for i = 1, #s do
					self.video:teletype(string.byte(s, i) :: number)
				end
			end
			w(c, 0, #s)
			status(self, c, bus, nil)
		else
			local n, err = vfs:write(bx, s)
			status(self, c, bus, err)
			if n then
				w(c, 0, n)
			end
		end
	elseif ah == 0x41 then
		status(self, c, bus, if vfs:remove(readstr(bus, c.ds, dx)) then nil else 2)
	elseif ah == 0x42 then
		local offset = cx * 65536 + dx
		if offset >= 0x80000000 then
			offset -= 0x100000000
		end
		local pos, err = vfs:seek(bx, offset, al)
		status(self, c, bus, err)
		if pos then
			w(c, 0, pos % 65536)
			w(c, 2, math.floor(pos / 65536))
		end
	elseif ah == 0x43 and (al == 0 or al == 1) then
		local name = vfs:resolve(readstr(bus, c.ds, dx))
		if vfs.files[name] then
			if al == 0 then
				w(c, 1, vfs.attributes[name] or 0x20)
			else
				vfs.attributes[name] = cx
			end
			status(self, c, bus, nil)
		else
			status(self, c, bus, 2)
		end
	elseif ah == 0x44 and al == 0 then
		if bx < 5 then
			w(c, 2, 0x80d3)
			status(self, c, bus, nil)
		elseif vfs.handles[bx] then
			w(c, 2, 0)
			status(self, c, bus, nil)
		else
			status(self, c, bus, 6)
		end
	elseif ah == 0x47 then
		local path = string.sub(vfs.cwd, 2)
		for i = 1, #path do
			bus:write8(addr(c.ds, r(c, 6) + i - 1), string.byte(path, i))
		end
		bus:write8(addr(c.ds, r(c, 6) + #path), 0)
		status(self, c, bus, nil)
	elseif ah == 0x48 or ah == 0x49 or ah == 0x4a then
		initBlocks(self, c)
		local blocks: { any } = self.blocks
		if ah == 0x48 then
			local chosen: any = nil
			local largest = 0
			for _, b in ipairs(blocks) do
				if b.owner == 0 then
					largest = math.max(largest, b.size)
					if not chosen and b.size >= bx then
						chosen = b
					end
				end
			end
			if chosen then
				local remain = chosen.size - bx
				chosen.size = bx
				chosen.owner = c.pspSegment
				if remain >= 1 then
					table.insert(blocks, { segment = chosen.segment + bx + 1, size = remain - 1, owner = 0 })
				end
				w(c, 0, chosen.segment)
				status(self, c, bus, nil)
			else
				w(c, 3, largest)
				status(self, c, bus, 8)
			end
		else
			local b: any = nil
			for _, item in ipairs(blocks) do
				if item.segment == c.es then
					b = item
					break
				end
			end
			if not b then
				status(self, c, bus, 9)
			elseif ah == 0x49 then
				b.owner = 0
				status(self, c, bus, nil)
			elseif bx <= b.size then
				local remain = b.size - bx
				b.size = bx
				if remain >= 1 then
					table.insert(blocks, { segment = b.segment + bx + 1, size = remain - 1, owner = 0 })
				end
				status(self, c, bus, nil)
			else
				local neighbor: any = nil
				for _, item in ipairs(blocks) do
					if item.owner == 0 and item.segment == b.segment + b.size + 1 then
						neighbor = item
						break
					end
				end
				local available = b.size + (if neighbor then neighbor.size + 1 else 0)
				if bx <= available and neighbor then
					for i, item in ipairs(blocks) do
						if item == neighbor then
							table.remove(blocks, i)
							break
						end
					end
					b.size = bx
					local remain = available - bx
					if remain >= 1 then
						table.insert(blocks, { segment = b.segment + bx + 1, size = remain - 1, owner = 0 })
					end
					status(self, c, bus, nil)
				else
					w(c, 3, available)
					status(self, c, bus, 8)
				end
			end
		end
		syncBlocks(self, bus)
	elseif ah == 0x4e then
		local found = vfs:find(readstr(bus, c.ds, dx))
		local id = dta(self, c)
		self.searches[id] = { items = found, index = 1 }
		if #found == 0 then
			status(self, c, bus, 18)
		else
			findResult(self, c, bus, found[1])
			status(self, c, bus, nil)
		end
	elseif ah == 0x4f then
		local s = self.searches[dta(self, c)]
		if s then
			s.index += 1
		end
		if not s or not s.items[s.index] then
			status(self, c, bus, 18)
		else
			findResult(self, c, bus, s.items[s.index])
			status(self, c, bus, nil)
		end
	elseif ah == 0x56 then
		status(self, c, bus, if vfs:rename(readstr(bus, c.ds, dx), readstr(bus, c.es, r(c, 7))) then nil else 2)
	elseif ah == 0x62 or ah == 0x51 then
		w(c, 3, c.pspSegment or c.ds)
	else
		status(self, c, bus, 1)
	end
	return true
end
function HLE.dpmi(self: any, c: any, bus: any): boolean?
	local ax, bx, cx, dx = r(c, 0), r(c, 3), r(c, 1), r(c, 2)
	local descriptor = self.descriptors[bx]
	if ax == 0 then
		if cx == 0 or self.nextSelector + cx * 8 > 0xfff8 then
			status(self, c, bus, 0x8011)
			return false
		end
		local first = self.nextSelector
		for i = 0, cx - 1 do
			self.descriptors[first + i * 8] = { base = 0, limit = 0xffff, access = 0x92 }
		end
		self.nextSelector += cx * 8
		w(c, 0, first)
		status(self, c, bus, nil)
	elseif ax == 1 then
		if not descriptor then
			status(self, c, bus, 0x8022)
		else
			self.descriptors[bx] = nil
			if c.segmentBases then
				c.segmentBases[bx] = nil
			end
			status(self, c, bus, nil)
		end
	elseif ax == 6 then
		if not descriptor then
			status(self, c, bus, 0x8022)
		else
			w(c, 1, math.floor(descriptor.base / 65536))
			w(c, 2, descriptor.base % 65536)
			status(self, c, bus, nil)
		end
	elseif ax == 7 or ax == 8 or ax == 9 then
		if not descriptor then
			status(self, c, bus, 0x8022)
			return false
		end
		if ax == 7 then
			descriptor.base = cx * 65536 + dx
			c.segmentBases = c.segmentBases or {}
			c.segmentBases[bx] = descriptor.base
		elseif ax == 8 then
			descriptor.limit = cx * 65536 + dx
		else
			descriptor.access = cx
		end
		status(self, c, bus, nil)
	elseif ax == 0x100 then
		if not c.pspSegment then
			status(self, c, bus, 0x8012)
			return false
		end
		initBlocks(self, c)
		syncBlocks(self, bus)
		local blocks: { any } = self.blocks
		local chosen: any = nil
		local largest = 0
		for _, b in ipairs(blocks) do
			if b.owner == 0 then
				largest = math.max(largest, b.size)
				if not chosen and b.size >= bx then
					chosen = b
				end
			end
		end
		if not chosen or self.nextSelector > 0xfff8 then
			w(c, 3, largest)
			status(self, c, bus, 0x8012)
			return false
		end
		local remain = chosen.size - bx
		chosen.size = bx
		chosen.owner = c.pspSegment or 1
		if remain >= 1 then
			table.insert(blocks, { segment = chosen.segment + bx + 1, size = remain - 1, owner = 0 })
		end
		local selector = self.nextSelector
		self.nextSelector += 8
		self.descriptors[selector] =
			{ base = chosen.segment * 16, limit = bx * 16 - 1, access = 0x92, dosSegment = chosen.segment }
		c.segmentBases = c.segmentBases or {}
		c.segmentBases[selector] = chosen.segment * 16
		w(c, 0, chosen.segment)
		w(c, 2, selector)
		syncBlocks(self, bus)
		status(self, c, bus, nil)
	elseif ax == 0x101 then
		local selector = dx
		local d = self.descriptors[selector]
		if not d or not d.dosSegment then
			status(self, c, bus, 0x8022)
			return false
		end
		local found = false
		for _, b in ipairs(self.blocks :: { any }) do
			if b.segment == d.dosSegment then
				b.owner = 0
				found = true
				break
			end
		end
		if not found then
			status(self, c, bus, 0x8022)
			return false
		end
		self.descriptors[selector] = nil
		if c.segmentBases then
			c.segmentBases[selector] = nil
		end
		syncBlocks(self, bus)
		status(self, c, bus, nil)
	elseif ax == 0x501 then
		local size = bx * 65536 + cx
		local blocks: { any } = self.linearBlocks
		local limit = buffer.len(bus.ram)
		local start = c.memoryExtendedStart or 0x100000
		table.sort(blocks, function(a: any, b: any)
			return a.base < b.base
		end)
		for _, block in ipairs(blocks) do
			if start + size <= block.base then
				break
			else
				start = math.max(start, block.base + block.size)
			end
		end
		if size == 0 or start + size > limit or start + size > 0x2000000 then
			status(self, c, bus, 0x8012)
			return false
		end
		local handle = self.nextLinearHandle
		self.nextLinearHandle += 1
		table.insert(blocks, { base = start, size = size, handle = handle })
		w(c, 3, math.floor(start / 65536))
		w(c, 1, start % 65536)
		w(c, 6, math.floor(handle / 65536))
		w(c, 7, handle % 65536)
		status(self, c, bus, nil)
	elseif ax == 0x502 then
		local handle = r(c, 6) * 65536 + r(c, 7)
		local blocks: { any } = self.linearBlocks
		local found = false
		for i, block in ipairs(blocks) do
			if block.handle == handle then
				table.remove(blocks, i)
				found = true
				break
			end
		end
		status(self, c, bus, if found then nil else 0x8023)
	elseif ax == 0x300 then
		if not c.mode32 or cx ~= 0 or self.realCall then
			status(self, c, bus, 0x8001)
			return false
		end
		local base = ((c.segmentBases and c.segmentBases[c.es]) or 0) + CPU.getReg(c, 7, 32)
		if base < 0 or base + 50 > buffer.len(bus.ram) then
			status(self, c, bus, 0x8021)
			return false
		end
		local realSS, realSP = bus:read16(base + 48), bus:read16(base + 46)
		if realSS == 0 and realSP == 0 then
			local lo, hi = 0x9fe00, 0x9ff00
			if c.imageStart and c.imageEnd and lo < c.imageEnd and hi > c.imageStart then
				status(self, c, bus, 0x8012)
				return false
			end
			realSS = 0x9000
			realSP = 0xff00
		end
		local regs = buffer.create(16)
		local high = buffer.create(16)
		buffer.copy(regs, 0, c.regs, 0, 16)
		buffer.copy(high, 0, c.regsHigh, 0, 16)
		self.realCall = {
			base = base,
			regs = regs,
			high = high,
			cs = c.cs,
			ss = c.ss,
			ds = c.ds,
			es = c.es,
			fs = c.fs,
			gs = c.gs,
			ip = c.ip,
			flags = c.flags,
			mode32 = c.mode32,
			halted = c.halted,
			waitingForKey = c.waitingForKey,
			yieldRequested = c.yieldRequested,
		}
		for _, entry in ipairs({ { 7, 0 }, { 6, 4 }, { 5, 8 }, { 3, 16 }, { 2, 20 }, { 1, 24 }, { 0, 28 } }) do
			CPU.setReg(c, entry[1], 32, bus:read32(base + entry[2]))
		end
		c.mode32 = false
		c.es = bus:read16(base + 34)
		c.ds = bus:read16(base + 36)
		c.fs = bus:read16(base + 38)
		c.gs = bus:read16(base + 40)
		c.ss = realSS
		w(c, 4, realSP)
		c.flags = bit32.bor(bus:read16(base + 32), 2)
		c.cs = 0xf000
		c.ip = 0x604
		c.halted = false
		c.waitingForKey = false
		c.yieldRequested = false
		Interpreter.interrupt(c, bus, bit32.band(bx, 255))
		return true
	elseif ax == 0x200 then
		w(c, 1, bus:read16(bit32.band(bx, 255) * 4 + 2))
		w(c, 2, bus:read16(bit32.band(bx, 255) * 4))
		status(self, c, bus, nil)
	elseif ax == 0x202 then
		local v = (c.exceptionVectors or {})[bit32.band(bx, 255)]
		w(c, 1, if v then v.selector else 0)
		CPU.setReg(c, 2, 32, if v then v.offset else 0)
		status(self, c, bus, nil)
	elseif ax == 0x203 then
		c.exceptionVectors = c.exceptionVectors or {}
		c.exceptionVectors[bit32.band(bx, 255)] = { selector = cx, offset = CPU.getReg(c, 2, 32) }
		status(self, c, bus, nil)
	elseif ax == 0x204 then
		local v = (c.protectedVectors or {})[bit32.band(bx, 255)]
		w(c, 1, if v then v.selector else 0)
		CPU.setReg(c, 2, 32, if v then v.offset else 0)
		status(self, c, bus, nil)
	elseif ax == 0x205 then
		c.protectedVectors = c.protectedVectors or {}
		c.protectedVectors[bit32.band(bx, 255)] = { selector = cx, offset = CPU.getReg(c, 2, 32) }
		status(self, c, bus, nil)
	elseif ax == 0x201 then
		bus:write16(bit32.band(bx, 255) * 4, dx)
		bus:write16(bit32.band(bx, 255) * 4 + 2, cx)
		status(self, c, bus, nil)
	else
		status(self, c, bus, 0x8001)
	end
	return false
end
function HLE.handleTrap(self: any, c: any, bus: any): boolean
	if c.cs ~= 0xf000 then
		return false
	end
	if c.ip == 0x600 then
		iret(c, bus)
		return true
	end
	if c.ip == 0x604 and self.realCall then
		local saved = self.realCall
		local a = saved.base
		for _, entry in ipairs({ { 7, 0 }, { 6, 4 }, { 5, 8 }, { 3, 16 }, { 2, 20 }, { 1, 24 }, { 0, 28 } }) do
			bus:write32(a + entry[2], CPU.getReg(c, entry[1], 32))
		end
		bus:write16(a + 32, c.flags)
		bus:write16(a + 34, c.es)
		bus:write16(a + 36, c.ds)
		bus:write16(a + 38, c.fs)
		bus:write16(a + 40, c.gs)
		bus:write16(a + 42, c.ip)
		bus:write16(a + 44, c.cs)
		bus:write16(a + 46, r(c, 4))
		bus:write16(a + 48, c.ss)
		buffer.copy(c.regs, 0, saved.regs, 0, 16)
		buffer.copy(c.regsHigh, 0, saved.high, 0, 16)
		c.cs = saved.cs
		c.ss = saved.ss
		c.ds = saved.ds
		c.es = saved.es
		c.fs = saved.fs
		c.gs = saved.gs
		c.ip = saved.ip
		c.flags = saved.flags
		c.mode32 = saved.mode32
		c.halted = saved.halted
		c.waitingForKey = saved.waitingForKey
		c.yieldRequested = saved.yieldRequested
		self.realCall = nil
		status(self, c, bus, nil)
		iret(c, bus)
		return true
	end
	if c.ip < 0x100 or c.ip >= 0x500 or (c.ip - 0x100) % 4 ~= 0 then
		return false
	end
	local v = (c.ip - 0x100) / 4
	local ah, al = byte(c, 4), byte(c, 0)
	if v == 8 then
		local ticks = bus:read16(0x46c) + 1
		bus:write16(0x46c, ticks % 65536)
		if ticks >= 65536 then
			bus:write16(0x46e, bus:read16(0x46e) + 1)
		end
		if bus:read16(0x46e) * 65536 + bus:read16(0x46c) >= 0x1800b0 then
			bus:write16(0x46c, 0)
			bus:write16(0x46e, 0)
			bus:write8(0x470, 1)
		end
		c.ip = 0x600
		Interpreter.interrupt(c, bus, 0x1c)
		return true
	elseif v == 0x1c then
	elseif v == 0x20 then
		c.halted = true
		c.exitCode = 0
	elseif v == 0x21 then
		if not self:dos(c, bus) then
			return true
		end
	elseif v == 0x16 then
		if ah == 0 or ah == 0x10 then
			local k = key(bus, true)
			if not k then
				c.waitingForKey = true
				c.yieldRequested = true
				c.flags = bit32.bor(c.flags, 0x200)
				return true
			end
			c.waitingForKey = false
			w(c, 0, k)
		elseif ah == 1 or ah == 0x11 then
			local k = key(bus, false)
			self:patchSavedFlags(c, bus, 0x40, if k then 0 else 0x40)
			if k then
				w(c, 0, k)
			end
		elseif ah == 2 then
			setbyte(c, 0, bus:read8(0x417))
		elseif ah == 0x12 then
			setbyte(c, 0, bus:read8(0x417))
			setbyte(c, 4, bus:read8(0x418))
		end
	elseif v == 0x11 then
		w(c, 0, bus:read16(0x410))
	elseif v == 0x12 then
		w(c, 0, bus:read16(0x413))
	elseif v == 0x10 then
		local video = self.video
		if ah == 0 then
			if video then
				video:setMode(al)
			end
			bus:write8(0x449, al)
		elseif ah == 0x0e then
			if video then
				video:teletype(al)
			end
		elseif ah == 0x0f then
			setbyte(c, 0, if video then video.mode else bus:read8(0x449))
			setbyte(c, 4, 80)
			setbyte(c, 7, 0)
		elseif ah == 0x1a and al == 0 then
			setbyte(c, 0, 0x1a)
			w(c, 3, 8)
		elseif ah == 0x12 and byte(c, 3) == 0x10 then
			w(c, 3, 3)
			w(c, 1, 9)
		elseif ah == 0x11 and al == 0x30 then
			c.es = 0xf000
			w(c, 5, 0x8000)
			w(c, 1, 8)
			setbyte(c, 2, 24)
		elseif ah == 1 then
			bus:write16(0x460, r(c, 1))
			if video then
				video.vramDirty = true
			end
		elseif ah == 2 then
			local page = byte(c, 7)
			if page < 8 then
				bus:write16(0x450 + page * 2, r(c, 2))
			end
		elseif ah == 3 then
			local page = byte(c, 7)
			w(c, 2, bus:read16(0x450 + page * 2))
			w(c, 1, 0x0607)
		elseif ah == 6 or ah == 7 then
			if video and video.scrollWindow then
				(video.scrollWindow :: any)(
					video,
					al,
					ah == 7,
					byte(c, 5),
					byte(c, 1),
					byte(c, 6),
					byte(c, 2),
					byte(c, 7)
				)
				iret(c, bus)
				return true
			end
			local top, left = byte(c, 5), byte(c, 1)
			local bottom, right = math.min(24, byte(c, 6)), math.min(79, byte(c, 2))
			local lines = if al == 0 then bottom - top + 1 else math.min(al, bottom - top + 1)
			local attr = byte(c, 7)
			if top <= bottom and left <= right then
				for step = 0, bottom - top do
					local y = if ah == 6 then top + step else bottom - step
					local src = if ah == 6 then y + lines else y - lines
					for x = left, right do
						local target = 0xb8000 + (y * 80 + x) * 2
						if src >= top and src <= bottom then
							local source = 0xb8000 + (src * 80 + x) * 2
							bus:write16(target, bus:read16(source))
						else
							bus:write16(target, attr * 256 + 32)
						end
					end
				end
			end
		elseif ah == 8 then
			local pos = bus:read16(0x450 + byte(c, 7) * 2)
			local offset = (math.floor(pos / 256) * 80 + pos % 256) * 2
			w(c, 0, bus:read16(0xb8000 + offset))
		elseif ah == 9 or ah == 0x0a then
			local pos = bus:read16(0x450 + byte(c, 7) * 2)
			local start = (math.floor(pos / 256) * 80 + pos % 256) * 2
			for i = 0, r(c, 1) - 1 do
				if start + i * 2 >= 4000 then
					break
				end
				local a = 0xb8000 + start + i * 2
				bus:write8(a, al)
				if ah == 9 then
					bus:write8(a + 1, byte(c, 3))
				end
			end
		elseif ah == 0x10 and al == 0x12 and video then
			for i = 0, r(c, 1) - 1 do
				local a = addr(c.es, r(c, 2) + i * 3)
				video:setPalette((r(c, 3) + i) % 256, bus:read8(a), bus:read8(a + 1), bus:read8(a + 2))
			end
		elseif ah == 0x10 and al == 0x17 and video then
			for i = 0, r(c, 1) - 1 do
				local a = addr(c.es, r(c, 2) + i * 3)
				local red, green, blue = video:getPalette((r(c, 3) + i) % 256)
				bus:write8(a, red)
				bus:write8(a + 1, green)
				bus:write8(a + 2, blue)
			end
		elseif ah == 0x10 and al == 0x10 and video then
			video:setPalette(r(c, 3) % 256, byte(c, 6), byte(c, 5), byte(c, 1))
		elseif ah == 0x10 and al == 0x15 and video then
			local red, green, blue = video:getPalette(r(c, 3) % 256)
			setbyte(c, 6, red)
			setbyte(c, 5, green)
			setbyte(c, 1, blue)
		end
	elseif v == 0x1a then
		if ah == 0 then
			w(c, 2, bus:read16(0x46c))
			w(c, 1, bus:read16(0x46e))
			setbyte(c, 0, bus:read8(0x470))
			bus:write8(0x470, 0)
			self:patchSavedFlags(c, bus, 1, 0)
		elseif ah == 1 then
			bus:write16(0x46c, r(c, 2))
			bus:write16(0x46e, r(c, 1))
			self:patchSavedFlags(c, bus, 1, 0)
		elseif ah == 2 or ah == 4 then
			local t = if self.clock then (self.clock :: any)() else os.date("*t")
			local function bcd(x: number): number
				return math.floor(x / 10) * 16 + x % 10
			end
			if ah == 2 then
				setbyte(c, 5, bcd(t.hour))
				setbyte(c, 1, bcd(t.min))
				setbyte(c, 6, bcd(t.sec))
				setbyte(c, 2, 0)
			else
				setbyte(c, 5, bcd(math.floor(t.year / 100)))
				setbyte(c, 1, bcd(t.year % 100))
				setbyte(c, 6, bcd(t.month))
				setbyte(c, 2, bcd(t.day))
			end
			self:patchSavedFlags(c, bus, 1, 0)
		else
			self:patchSavedFlags(c, bus, 1, 1)
		end
	elseif v == 0x2f then
		setbyte(c, 0, 0)
	elseif v == 0x31 then
		if self:dpmi(c, bus) then
			return true
		end
	elseif v == 0x33 then
		local ax = r(c, 0)
		if ax == 0 then
			w(c, 0, 0xffff)
			w(c, 3, 3)
		elseif ax == 3 then
			w(c, 3, self.mouseButtons)
			w(c, 1, self.mouseX)
			w(c, 2, self.mouseY)
		elseif ax == 4 then
			self.mouseX = math.clamp(r(c, 1), self.mouseMinX, self.mouseMaxX)
			self.mouseY = math.clamp(r(c, 2), self.mouseMinY, self.mouseMaxY)
		elseif ax == 7 then
			self.mouseMinX = r(c, 1)
			self.mouseMaxX = math.max(self.mouseMinX, r(c, 2))
			self.mouseX = math.clamp(self.mouseX, self.mouseMinX, self.mouseMaxX)
		elseif ax == 8 then
			self.mouseMinY = r(c, 1)
			self.mouseMaxY = math.max(self.mouseMinY, r(c, 2))
			self.mouseY = math.clamp(self.mouseY, self.mouseMinY, self.mouseMaxY)
		elseif ax == 0x0c then
			self.mouseCallbackMask = r(c, 1)
			self.mouseCallbackSegment = c.es
			self.mouseCallbackOffset = r(c, 2)
		elseif ax == 1 or ax == 2 then
		else
			w(c, 0, 0)
		end
	end
	iret(c, bus)
	return true
end
return HLE
