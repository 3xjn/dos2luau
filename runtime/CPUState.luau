--!strict
--!native
local CPU = {}
local byteOffsets = { 0, 2, 4, 6, 1, 3, 5, 7 }
function CPU.new(loadSegment: any)
	local c = {
		regs = buffer.create(16),
		regsHigh = buffer.create(16),
		es = 0,
		cs = 0,
		ss = 0,
		ds = 0,
		fs = 0,
		gs = 0,
		ip = 0,
		flags = 2,
		loadSegment = loadSegment or 0,
		currentBlockKey = 0,
		halted = false,
		waitingForKey = false,
		yieldRequested = false,
		fpu = {},
		fpuTop = 0,
		discoveredBlocks = {},
	}
	c.currentBlockKey = CPU.key(c)
	return c
end
function CPU.key(c: any)
	if c.mode32 then
		return c.ip
	end
	return bit32.bor(bit32.lshift(bit32.band(c.cs - c.loadSegment, 65535), 16), bit32.band(c.ip, 65535))
end
function CPU.getReg(c: any, i: any, w: any)
	if w == 8 then
		return buffer.readu8(c.regs, byteOffsets[i + 1])
	elseif w == 16 then
		return buffer.readu16(c.regs, i * 2)
	else
		return buffer.readu16(c.regs, i * 2) + buffer.readu16(c.regsHigh, i * 2) * 65536
	end
end
function CPU.setReg(c: any, i: any, w: any, v: any)
	v = v % 2 ^ w
	if w == 8 then
		buffer.writeu8(c.regs, byteOffsets[i + 1], v)
	elseif w == 16 then
		buffer.writeu16(c.regs, i * 2, v)
	else
		buffer.writeu16(c.regs, i * 2, v % 65536)
		buffer.writeu16(c.regsHigh, i * 2, math.floor(v / 65536))
	end
end
local function set(f: any, mask: any, on: any)
	if on then
		return bit32.bor(f, mask)
	else
		return bit32.band(f, bit32.bnot(mask))
	end
end
function CPU.alu(c: any, op: any, a: any, b: any, w: any)
	local mod = 2 ^ w
	local sign = mod / 2
	a = a % mod
	b = b % mod
	local carry = if (op == "adc" or op == "sbb") and bit32.band(c.flags, 1) ~= 0 then 1 else 0
	local raw = 0
	local arithmetic = true
	local sub = op == "sub" or op == "sbb" or op == "cmp" or op == "dec"
	if op == "add" or op == "adc" then
		raw = a + b + carry
	elseif sub then
		raw = a - b - carry
	elseif op == "inc" then
		raw = a + 1
	elseif op == "and" or op == "test" then
		raw = bit32.band(a, b)
		arithmetic = false
	elseif op == "or" then
		raw = bit32.bor(a, b)
		arithmetic = false
	elseif op == "xor" then
		raw = bit32.bxor(a, b)
		arithmetic = false
	else
		error("Unknown ALU operation " .. tostring(op))
	end
	if op == "dec" then
		raw = a - 1
		b = 1
	elseif op == "inc" then
		b = 1
	end
	local result = raw % mod
	local f = c.flags
	if op ~= "inc" and op ~= "dec" then
		f = set(f, 1, if sub then raw < 0 else raw >= mod)
	end
	if arithmetic then
		f = set(f, 16, bit32.band(bit32.bxor(a, b, result), 16) ~= 0)
		local overflow = if sub
			then bit32.band(bit32.bxor(a, b), bit32.bxor(a, result), sign) ~= 0
			else bit32.band(bit32.bnot(bit32.bxor(a, b)), bit32.bxor(a, result), sign) ~= 0
		f = set(f, 2048, overflow)
	else
		f = bit32.band(f, bit32.bnot(1 + 2048))
	end
	f = set(f, 64, result == 0)
	f = set(f, 128, result >= sign)
	local x = result % 256
	local n = 0
	for _ = 1, 8 do
		n += x % 2
		x = math.floor(x / 2)
	end
	f = set(f, 4, n % 2 == 0)
	c.flags = bit32.bor(f, 2)
	return result
end
return CPU
