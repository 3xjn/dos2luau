--!strict
local Bus = {}
Bus.__index = Bus
function Bus.new(size: any)
	local self = setmetatable({}, Bus)
	self.ram = buffer.create(size or 1048576)
	self.codePageBitmap = {}
	self.invalidatedPages = {}
	self.ports = {}
	return self
end
function Bus.segOffToPhys(seg: any, off: any)
	return (seg * 16 + (off % 65536)) % 1048576
end
function Bus.read8(self: any, addr: any)
	addr = addr % buffer.len(self.ram)
	if self.memoryReadHook then
		local v = (self.memoryReadHook :: any)(addr)
		if v ~= nil then
			return bit32.band(v, 255)
		end
	end
	return buffer.readu8(self.ram, addr)
end
function Bus.read16(self: any, addr: any): number
	return self:read8(addr) + self:read8(addr + 1) * 256
end
function Bus.read32(self: any, addr: any): number
	return self:read16(addr) + self:read16(addr + 2) * 65536
end
function Bus.write8(self: any, addr: any, val: any)
	addr = addr % buffer.len(self.ram)
	val = bit32.band(val, 255)
	if addr >= 0xF0000 and addr < 0x100000 then
		return
	end
	if self.codePageBitmap[math.floor(addr / 4096)] then
		self.invalidatedPages[math.floor(addr / 4096)] = true
	end
	if self.memoryWriteHook and (self.memoryWriteHook :: any)(addr, val) then
		return
	end
	buffer.writeu8(self.ram, addr, val)
	if self.video and addr >= 0xA0000 and addr < 0xC0000 then
		self.video.vramDirty = true
	end
end
function Bus.write16(self: any, addr: any, val: any)
	self:write8(addr, val)
	self:write8(addr + 1, bit32.rshift(val, 8))
end
function Bus.write32(self: any, addr: any, val: any)
	self:write16(addr, val)
	self:write16(addr + 2, bit32.rshift(val, 16))
end
function Bus.readSeg16(self: any, seg: any, off: any): number
	return self:read8(self.segOffToPhys(seg, off % 65536)) + self:read8(self.segOffToPhys(seg, (off + 1) % 65536)) * 256
end
function Bus.writeSeg16(self: any, seg: any, off: any, val: any)
	self:write8(self.segOffToPhys(seg, off % 65536), val)
	self:write8(self.segOffToPhys(seg, (off + 1) % 65536), bit32.rshift(val, 8))
end
function Bus.markCode(self: any, addr: any, length: any)
	for i = 0, length - 1 do
		self.codePageBitmap[math.floor(((addr + i) % buffer.len(self.ram)) / 4096)] = true
	end
end
function Bus.load(self: any, addr: any, data: any)
	for i = 0, buffer.len(data) - 1 do
		buffer.writeu8(self.ram, (addr + i) % buffer.len(self.ram), buffer.readu8(data, i))
	end
end
function Bus.registerPortHandler(self: any, port: any, readFn: any, writeFn: any)
	self.ports[port % 65536] = { read = readFn, write = writeFn }
end
function Bus.in8(self: any, port: any)
	local h = self.ports[port % 65536]
	return if h and h.read then bit32.band((h.read :: any)(), 255) else 255
end
function Bus.out8(self: any, port: any, val: any)
	local h = self.ports[port % 65536]
	if h and h.write then
		(h.write :: any)(bit32.band(val, 255))
	end
end
return Bus
