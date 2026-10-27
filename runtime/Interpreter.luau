--!strict
--!native
local CPU = require(script.Parent.CPUState)
local I = {}
local OPS = { "add", "or", "adc", "sbb", "and", "sub", "xor", "cmp" }
local function push(c: any, b: any, v: any, width: any?)
	width = width or 16
	local sw = if c.mode32 then 32 else 16
	local sp = (CPU.getReg(c, 4, sw) - width / 8) % 2 ^ sw
	CPU.setReg(c, 4, sw, sp)
	if c.mode32 then
		local a = ((c.segmentBases and c.segmentBases[c.ss]) or 0) + sp
		if width == 32 then
			b:write32(a, v)
		else
			b:write16(a, v)
		end
	else
		b:writeSeg16(c.ss, sp, v)
		if width == 32 then
			b:writeSeg16(c.ss, (sp + 2) % 65536, math.floor(v / 65536))
		end
	end
end
local function pop(c: any, b: any, width: any?)
	width = width or 16
	local sw = if c.mode32 then 32 else 16
	local sp = CPU.getReg(c, 4, sw)
	local v
	if c.mode32 then
		local a = ((c.segmentBases and c.segmentBases[c.ss]) or 0) + sp
		v = if width == 32 then b:read32(a) else b:read16(a)
	else
		v = b:readSeg16(c.ss, sp)
		if width == 32 then
			v += b:readSeg16(c.ss, (sp + 2) % 65536) * 65536
		end
	end
	CPU.setReg(c, 4, sw, sp + width / 8)
	return v
end
function I.interrupt(c: any, b: any, v: any)
	local w = if c.mode32 then 32 else 16
	push(c, b, c.flags, w)
	push(c, b, c.cs, w)
	push(c, b, c.ip, w)
	c.flags = bit32.band(c.flags, bit32.bnot(0x300))
	local target = if c.mode32 and c.protectedVectors then c.protectedVectors[v] else nil
	if target then
		c.ip = target.offset % 4294967296
		c.cs = target.selector % 65536
	else
		c.ip = b:read16(v * 4)
		c.cs = b:read16(v * 4 + 2)
	end
	c.halted = false
	c.currentBlockKey = CPU.key(c)
end
local function signed(v: any, w: any)
	if v >= 2 ^ (w - 1) then
		return v - 2 ^ w
	else
		return v
	end
end
local function phys(c: any, s: any, off: any): number
	if c.mode32 then
		return (((c.segmentBases and c.segmentBases[s]) or 0) + off) % 4294967296
	else
		return (s * 16 + off) % 1048576
	end
end
local function fetch(c: any, b: any): number
	local v = b:read8(phys(c, c.cs, c.ip))
	c.ip = (c.ip + 1) % (if c.mode32 then 4294967296 else 65536)
	return v
end
local function word(c: any, b: any): number
	local lo = fetch(c, b)
	return lo + fetch(c, b) * 256
end
local function imm(c: any, b: any, width: number): number
	if width == 8 then
		return fetch(c, b)
	elseif width == 16 then
		return word(c, b)
	else
		local lo = word(c, b)
		return lo + word(c, b) * 65536
	end
end
local function fail(op: any, cs: any, ip: any)
	error(string.format("Unsupported instruction %02X at %04X:%04X", op, cs, ip), 0)
end
local function modrm(c: any, b: any, seg: any, addr32: any, width: any): (number, any, any, any, any)
	local m = fetch(c, b)
	local mode = math.floor(m / 64)
	local reg = math.floor(m / 8) % 8
	local rm = m % 8
	if mode == 3 then
		return reg, rm, nil, nil, nil
	end
	local base = 0
	local usesBP = false
	if addr32 then
		if rm == 4 then
			local sib = fetch(c, b)
			local scale = 2 ^ math.floor(sib / 64)
			local index = math.floor(sib / 8) % 8
			local basereg = sib % 8
			if index ~= 4 then
				base += CPU.getReg(c, index, 32) * scale
			end
			if basereg == 5 and mode == 0 then
				base += imm(c, b, 32)
			else
				base += CPU.getReg(c, basereg, 32)
				usesBP = basereg == 4 or basereg == 5
			end
		elseif rm == 5 and mode == 0 then
			base = imm(c, b, 32)
		else
			base = CPU.getReg(c, rm, 32)
			usesBP = rm == 5
		end
		if mode == 1 then
			base += signed(fetch(c, b), 8)
		elseif mode == 2 then
			base += signed(imm(c, b, 32), 32)
		end
	else
		local bx = CPU.getReg(c, 3, 16)
		local bp = CPU.getReg(c, 5, 16)
		local si = CPU.getReg(c, 6, 16)
		local di = CPU.getReg(c, 7, 16)
		base = if rm == 0
			then bx + si
			elseif rm == 1 then bx + di
			elseif rm == 2 then bp + si
			elseif rm == 3 then bp + di
			elseif rm == 4 then si
			elseif rm == 5 then di
			elseif rm == 6 then bp
			else bx
		usesBP = rm == 2 or rm == 3 or (rm == 6 and mode ~= 0)
		if mode == 0 and rm == 6 then
			base = word(c, b)
		elseif mode == 1 then
			base += signed(fetch(c, b), 8)
		elseif mode == 2 then
			base += signed(word(c, b), 16)
		end
	end
	local addressMod = if addr32 then 4294967296 else 65536
	local off = base % addressMod
	local s = seg or (if usesBP then c.ss else c.ds)
	return reg, nil, s, off, addressMod
end
local function readOperand(c: any, b: any, width: number, reg: any, seg: any, off: any, mod: any): number
	if reg ~= nil then
		return CPU.getReg(c, reg, width)
	end
	local v = 0
	for i = 0, width / 8 - 1 do
		v += b:read8(phys(c, seg, (off + i) % mod)) * 2 ^ (8 * i)
	end
	return v
end
local function writeOperand(c: any, b: any, width: number, reg: any, seg: any, off: any, mod: any, v: number)
	if reg ~= nil then
		CPU.setReg(c, reg, width, v)
	else
		for i = 0, width / 8 - 1 do
			b:write8(phys(c, seg, (off + i) % mod), math.floor(v / 2 ^ (8 * i)) % 256)
		end
	end
end
local function fpGet(c: any, i: number): number
	local v = c.fpu[(c.fpuTop + i) % 8 + 1]
	if v == nil then
		error("x87 stack underflow", 0)
	end
	return v
end
local function fpPut(c: any, i: number, v: number)
	c.fpu[(c.fpuTop + i) % 8 + 1] = v
end
local function fpPush(c: any, v: number)
	c.fpuTop = (c.fpuTop - 1) % 8
	fpPut(c, 0, v)
end
local function fpPop(c: any)
	local v = fpGet(c, 0)
	c.fpu[c.fpuTop + 1] = nil
	c.fpuTop = (c.fpuTop + 1) % 8
	return v
end
local function fpCompare(c: any, a: number, v: number)
	c.fpuStatus = bit32.band(c.fpuStatus or 0, bit32.bnot(0x4500))
	if a ~= a or v ~= v then
		c.fpuStatus = bit32.bor(c.fpuStatus, 0x4500)
	elseif a < v then
		c.fpuStatus = bit32.bor(c.fpuStatus, 0x100)
	elseif a == v then
		c.fpuStatus = bit32.bor(c.fpuStatus, 0x4000)
	end
end
local function cond(c: any, n: any)
	local f = c.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local z = bit32.band(f, 64) ~= 0
	local s = bit32.band(f, 128) ~= 0
	local o = bit32.band(f, 2048) ~= 0
	if n == 0 then
		return o
	elseif n == 1 then
		return not o
	elseif n == 2 then
		return cf
	elseif n == 3 then
		return not cf
	elseif n == 4 then
		return z
	elseif n == 5 then
		return not z
	elseif n == 6 then
		return cf or z
	elseif n == 7 then
		return not cf and not z
	elseif n == 8 then
		return s
	elseif n == 9 then
		return not s
	elseif n == 10 then
		return pf
	elseif n == 11 then
		return not pf
	elseif n == 12 then
		return s ~= o
	elseif n == 13 then
		return s == o
	elseif n == 14 then
		return z or s ~= o
	else
		return not z and s == o
	end
end
function I.step(c: any, b: any)
	if b.hle and b.hle:handleTrap(c, b) then
		c.currentBlockKey = CPU.key(c)
		return c.currentBlockKey, 1
	end
	if c.halted or c.waitingForKey then
		return CPU.key(c), 0
	end
	local start = c.ip
	local startCS = c.cs
	local ipmod = if c.mode32 then 4294967296 else 65536

	local seg = nil
	local rep = 0
	local w32 = c.mode32 == true
	local addr32 = c.mode32 == true
	local op = fetch(c, b)
	while
		op == 0x26
		or op == 0x2e
		or op == 0x36
		or op == 0x3e
		or op == 0x64
		or op == 0x65
		or op == 0x66
		or op == 0x67
		or op == 0xf2
		or op == 0xf3
		or op == 0xf0
	do
		if op == 0x26 then
			seg = c.es
		elseif op == 0x2e then
			seg = c.cs
		elseif op == 0x36 then
			seg = c.ss
		elseif op == 0x3e then
			seg = c.ds
		elseif op == 0x64 then
			seg = c.fs
		elseif op == 0x65 then
			seg = c.gs
		elseif op == 0x66 then
			w32 = not c.mode32
		elseif op == 0x67 then
			addr32 = not c.mode32
		elseif op == 0xf2 or op == 0xf3 then
			rep = op
		end
		op = fetch(c, b)
	end

	local ow = if w32 then 32 else 16
	if
		(w32 or addr32)
		and (
			(op >= 0xa0 and op <= 0xa3)
			or op == 0xe0
			or op == 0xe1
			or op == 0xe2
			or op == 0xe3
			or op == 0xca
			or op == 0xcb
			or op == 0xea
			or op == 0x9a
		)
	then
		fail(op, startCS, start)
	end

	if op <= 0x3d and op % 8 <= 5 and math.floor(op / 8) < 8 then
		local operation = OPS[math.floor(op / 8) + 1]
		local form = op % 8
		local width = if form % 2 == 0 then 8 elseif w32 then 32 else 16
		if form < 4 then
			local operandWidth = width
			local reg, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
			local a = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
			local rv = CPU.getReg(c, reg, width)
			if form >= 2 then
				a, rv = rv, a
			end
			local result = CPU.alu(c, operation, a, rv, width)
			if operation ~= "cmp" then
				if form >= 2 then
					CPU.setReg(c, reg, width, result)
				else
					writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, result)
				end
			end
		else
			local val = imm(c, b, width)
			local result = CPU.alu(c, operation, CPU.getReg(c, 0, width), val, width)
			if operation ~= "cmp" then
				CPU.setReg(c, 0, width, result)
			end
		end
	elseif op == 0x0f then
		local ext = fetch(c, b)
		if ext >= 0x80 and ext <= 0x8f then
			local d = signed(imm(c, b, ow), ow)
			if cond(c, ext % 16) then
				c.ip = (c.ip + d) % 2 ^ ow
			end
		elseif ext == 0xb6 or ext == 0xb7 or ext == 0xbe or ext == 0xbf then
			local sw = if ext % 2 == 0 then 8 else 16
			local operandWidth = sw
			local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
			local v = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
			if ext >= 0xbe then
				v = signed(v, sw)
			end
			CPU.setReg(c, r, ow, v)
		elseif ext == 0xaf then
			local operandWidth = ow
			local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
			local a = signed(CPU.getReg(c, r, ow), ow)
			local v = signed(readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod), ow)
			local product = a * v
			local low = product
			if ow == 32 then
				local ua = a % 4294967296
				local uv = v % 4294967296
				low = (
					(ua % 65536) * (uv % 65536)
					+ ((math.floor(ua / 65536) * (uv % 65536) + (ua % 65536) * math.floor(uv / 65536)) % 65536)
						* 65536
				) % 4294967296
			end
			CPU.setReg(c, r, ow, low)
			local overflow = product < -2 ^ (ow - 1) or product >= 2 ^ (ow - 1)
			c.flags = bit32.band(c.flags, bit32.bnot(2049))
			if overflow then
				c.flags = bit32.bor(c.flags, 2049)
			end
		else
			fail(op, startCS, start)
		end
	elseif op >= 0xd8 and op <= 0xdf then
		local spec = b:read8(phys(c, c.cs, c.ip))
		local mode = math.floor(spec / 64)
		local sub = math.floor(spec / 8) % 8
		local index = spec % 8

		if mode ~= 3 then
			local width = if op == 0xdd or op == 0xdc then 64 else 32
			local operandWidth = width
			local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
			if op == 0xd9 and (r == 5 or r == 7) then
				local a = phys(c, operandSeg, operandOff)
				local a2 = phys(c, operandSeg, (operandOff + 1) % operandMod)
				if r == 5 then
					c.fpuControl = b:read8(a) + 256 * b:read8(a2)
				else
					local v = c.fpuControl or 0x37f
					b:write8(a, v % 256)
					b:write8(a2, math.floor(v / 256))
				end
				c.currentBlockKey = CPU.key(c)
				return c.currentBlockKey, 1
			elseif op == 0xdd and r == 7 then
				local v = bit32.bor(bit32.band(c.fpuStatus or 0, bit32.bnot(0x3800)), bit32.lshift(c.fpuTop, 11))
				b:write8(phys(c, operandSeg, operandOff), v % 256)
				b:write8(phys(c, operandSeg, (operandOff + 1) % operandMod), math.floor(v / 256))
				c.currentBlockKey = CPU.key(c)
				return c.currentBlockKey, 1
			end
			local tmp = c.fpuScratch
			if not tmp then
				tmp = buffer.create(8)
				c.fpuScratch = tmp
			end
			for i = 0, width / 8 - 1 do
				buffer.writeu8(tmp, i, b:read8(phys(c, operandSeg, (operandOff + i) % operandMod)))
			end
			local v = if width == 32 then buffer.readf32(tmp, 0) else buffer.readf64(tmp, 0)
			if (op == 0xd9 or op == 0xdd) and r == 0 then
				fpPush(c, v)
			elseif (op == 0xd9 or op == 0xdd) and (r == 2 or r == 3) then
				if width == 32 then
					buffer.writef32(tmp, 0, fpGet(c, 0))
				else
					buffer.writef64(tmp, 0, fpGet(c, 0))
				end
				for i = 0, width / 8 - 1 do
					b:write8(phys(c, operandSeg, (operandOff + i) % operandMod), buffer.readu8(tmp, i))
				end
				if r == 3 then
					fpPop(c)
				end
			elseif op == 0xd8 or op == 0xdc then
				local a = fpGet(c, 0)
				if r == 0 then
					fpPut(c, 0, a + v)
				elseif r == 1 then
					fpPut(c, 0, a * v)
				elseif r == 2 or r == 3 then
					fpCompare(c, a, v)
					if r == 3 then
						fpPop(c)
					end
				elseif r == 4 then
					fpPut(c, 0, a - v)
				elseif r == 5 then
					fpPut(c, 0, v - a)
				elseif r == 6 then
					fpPut(c, 0, a / v)
				else
					fpPut(c, 0, v / a)
				end
			else
				fail(op, startCS, start)
			end
		else
			fetch(c, b)
			if op == 0xd9 and spec >= 0xc0 and spec <= 0xc7 then
				fpPush(c, fpGet(c, index))
			elseif op == 0xd9 and spec >= 0xc8 and spec <= 0xcf then
				local a = fpGet(c, 0)
				fpPut(c, 0, fpGet(c, index))
				fpPut(c, index, a)
			elseif op == 0xd9 and spec == 0xe8 then
				fpPush(c, 1)
			elseif op == 0xd9 and spec == 0xe9 then
				fpPush(c, math.log(10) / math.log(2))
			elseif op == 0xd9 and spec == 0xea then
				fpPush(c, 1 / math.log(2))
			elseif op == 0xd9 and spec == 0xec then
				fpPush(c, math.log(2) / math.log(10))
			elseif op == 0xd9 and spec == 0xed then
				fpPush(c, math.log(2))
			elseif op == 0xd9 and spec == 0xee then
				fpPush(c, 0)
			elseif op == 0xd9 and spec == 0xeb then
				fpPush(c, math.pi)
			elseif op == 0xd9 and spec == 0xe0 then
				fpPut(c, 0, -fpGet(c, 0))
			elseif op == 0xd9 and spec == 0xe1 then
				fpPut(c, 0, math.abs(fpGet(c, 0)))
			elseif op == 0xd9 and spec == 0xfa then
				fpPut(c, 0, math.sqrt(fpGet(c, 0)))
			elseif op == 0xd9 and spec == 0xfe then
				fpPut(c, 0, math.sin(fpGet(c, 0)))
			elseif op == 0xd9 and spec == 0xff then
				fpPut(c, 0, math.cos(fpGet(c, 0)))
			elseif op == 0xdb and spec == 0xe3 then
				table.clear(c.fpu)
				c.fpuTop = 0
				c.fpuStatus = 0
				c.fpuControl = 0x37f
			elseif op == 0xdf and spec == 0xe0 then
				CPU.setReg(c, 0, 16, bit32.bor(c.fpuStatus or 0, bit32.lshift(c.fpuTop, 11)))
			elseif op == 0xd8 then
				local a = fpGet(c, 0)
				local v = fpGet(c, index)
				if sub == 0 then
					fpPut(c, 0, a + v)
				elseif sub == 1 then
					fpPut(c, 0, a * v)
				elseif sub == 2 or sub == 3 then
					fpCompare(c, a, v)
					if sub == 3 then
						fpPop(c)
					end
				elseif sub == 4 then
					fpPut(c, 0, a - v)
				elseif sub == 5 then
					fpPut(c, 0, v - a)
				elseif sub == 6 then
					fpPut(c, 0, a / v)
				else
					fpPut(c, 0, v / a)
				end
			elseif op == 0xde and spec == 0xd9 then
				fpCompare(c, fpGet(c, 0), fpGet(c, 1))
				fpPop(c)
				fpPop(c)
			elseif (op == 0xdc or op == 0xde) and (sub == 0 or sub == 1 or sub >= 4) then
				local a = fpGet(c, index)
				local v = fpGet(c, 0)
				if sub == 0 then
					fpPut(c, index, a + v)
				elseif sub == 1 then
					fpPut(c, index, a * v)
				elseif sub == 4 then
					fpPut(c, index, v - a)
				elseif sub == 5 then
					fpPut(c, index, a - v)
				elseif sub == 6 then
					fpPut(c, index, v / a)
				else
					fpPut(c, index, a / v)
				end
				if op == 0xde then
					fpPop(c)
				end
			elseif op == 0xdd and sub == 0 then
				c.fpu[(c.fpuTop + index) % 8 + 1] = nil
			elseif op == 0xdd and (sub == 4 or sub == 5) then
				fpCompare(c, fpGet(c, 0), fpGet(c, index))
				if sub == 5 then
					fpPop(c)
				end
			elseif op == 0xdd and (sub == 2 or sub == 3) then
				fpPut(c, index, fpGet(c, 0))
				if sub == 3 then
					fpPop(c)
				end
			else
				fail(op, startCS, start)
			end
		end
	elseif op == 0xd7 then
		local aw = if addr32 then 32 else 16
		local off = (CPU.getReg(c, 3, aw) + CPU.getReg(c, 0, 8)) % 2 ^ aw
		CPU.setReg(c, 0, 8, b:read8(phys(c, seg or c.ds, off)))
	elseif op == 0x8f then
		local operandWidth = ow
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		if r ~= 0 then
			fail(op, startCS, start)
		end
		writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, pop(c, b, ow))
	elseif op == 0x8d or op == 0xc4 or op == 0xc5 then
		local operandWidth = ow
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		if operandReg ~= nil then
			fail(op, startCS, start)
		end
		if op == 0x8d then
			CPU.setReg(c, r, ow, operandOff)
		else
			local v = 0
			for i = 0, ow / 8 - 1 do
				v += b:read8(phys(c, operandSeg, (operandOff + i) % operandMod)) * 2 ^ (8 * i)
			end
			local off = (operandOff + ow / 8) % operandMod
			local selector = b:read8(phys(c, operandSeg, off))
				+ b:read8(phys(c, operandSeg, (off + 1) % operandMod)) * 256
			CPU.setReg(c, r, ow, v)
			if op == 0xc4 then
				c.es = selector
			else
				c.ds = selector
			end
		end
	elseif op == 0x60 then
		local original = CPU.getReg(c, 4, ow)
		for r = 0, 7 do
			push(c, b, if r == 4 then original else CPU.getReg(c, r, ow), ow)
		end
	elseif op == 0x61 then
		for r = 7, 0, -1 do
			local v = pop(c, b, ow)
			if r ~= 4 then
				CPU.setReg(c, r, ow, v)
			end
		end
	elseif op == 0xc8 then
		local size = word(c, b)
		local level = fetch(c, b) % 32
		push(c, b, CPU.getReg(c, 5, ow), ow)
		local sw = if c.mode32 then 32 else 16
		local frame = CPU.getReg(c, 4, sw)
		local bp = CPU.getReg(c, 5, ow)
		for _ = 1, level - 1 do
			bp = (bp - ow / 8) % 2 ^ ow
			local a = phys(c, c.ss, bp)
			push(
				c,
				b,
				if c.mode32
					then (if ow == 32 then b:read32(a) else b:read16(a))
					elseif ow == 32 then b:readSeg16(c.ss, bp) + b:readSeg16(c.ss, (bp + 2) % 65536) * 65536
					else b:readSeg16(c.ss, bp),
				ow
			)
		end
		if level > 0 then
			push(c, b, frame, ow)
		end
		CPU.setReg(c, 5, ow, frame)
		CPU.setReg(c, 4, sw, CPU.getReg(c, 4, sw) - size)
	elseif op == 0xc9 then
		local sw = if c.mode32 then 32 else 16
		CPU.setReg(c, 4, sw, CPU.getReg(c, 5, sw))
		CPU.setReg(c, 5, ow, pop(c, b, ow))
	elseif op == 0x98 then
		if ow == 16 then
			CPU.setReg(c, 0, 16, signed(CPU.getReg(c, 0, 8), 8))
		else
			CPU.setReg(c, 0, 32, signed(CPU.getReg(c, 0, 16), 16))
		end
	elseif op == 0x99 then
		CPU.setReg(c, 2, ow, if CPU.getReg(c, 0, ow) >= 2 ^ (ow - 1) then 2 ^ ow - 1 else 0)
	elseif op == 0x9f then
		CPU.setReg(c, 4, 8, bit32.band(c.flags, 0xd5) + 2)
	elseif op == 0x9e then
		c.flags = bit32.bor(bit32.band(c.flags, bit32.bnot(0xd5)), bit32.band(CPU.getReg(c, 4, 8), 0xd5), 2)
	elseif op >= 0x40 and op <= 0x4f then
		local idx = op % 8
		CPU.setReg(c, idx, ow, CPU.alu(c, if op < 0x48 then "inc" else "dec", CPU.getReg(c, idx, ow), 1, ow))
	elseif op >= 0x50 and op <= 0x57 then
		push(c, b, CPU.getReg(c, op % 8, ow), ow)
	elseif op >= 0x58 and op <= 0x5f then
		CPU.setReg(c, op % 8, ow, pop(c, b, ow))
	elseif op >= 0x70 and op <= 0x7f then
		local d = signed(fetch(c, b), 8)
		if cond(c, op % 16) then
			c.ip = (c.ip + d) % ipmod
		end
	elseif op >= 0xb0 and op <= 0xbf then
		local w = if op < 0xb8 then 8 elseif w32 then 32 else 16
		CPU.setReg(c, op % 8, w, imm(c, b, w))
	elseif op == 0x90 then
	elseif op >= 0x91 and op <= 0x97 then
		local x = CPU.getReg(c, 0, ow)
		CPU.setReg(c, 0, ow, CPU.getReg(c, op % 8, ow))
		CPU.setReg(c, op % 8, ow, x)
	elseif
		op == 0x88
		or op == 0x89
		or op == 0x8a
		or op == 0x8b
		or op == 0x86
		or op == 0x87
		or op == 0x84
		or op == 0x85
	then
		local w = if op % 2 == 0 then 8 elseif w32 then 32 else 16
		local operandWidth = w
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local a = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
		local v = CPU.getReg(c, r, w)
		if op == 0x88 or op == 0x89 then
			writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, v)
		elseif op == 0x8a or op == 0x8b then
			CPU.setReg(c, r, w, a)
		elseif op == 0x84 or op == 0x85 then
			CPU.alu(c, "test", a, v, w)
		else
			writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, v)
			CPU.setReg(c, r, w, a)
		end
	elseif op == 0x80 or op == 0x81 or op == 0x83 then
		local w = if op == 0x80 then 8 elseif w32 then 32 else 16
		local operandWidth = w
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local v = if op == 0x81 then imm(c, b, w) elseif op == 0x83 then signed(fetch(c, b), 8) else fetch(c, b)
		local result = CPU.alu(
			c,
			OPS[r + 1],
			readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod),
			v,
			w
		)
		if r ~= 7 then
			writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, result)
		end
	elseif op == 0xc6 or op == 0xc7 then
		local w = if op == 0xc6 then 8 elseif w32 then 32 else 16
		local operandWidth = w
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		if r ~= 0 then
			fail(op, startCS, start)
		end
		writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, imm(c, b, w))
	elseif op == 0x8c or op == 0x8e then
		local operandWidth = 16
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local name = if r == 0
			then "es"
			elseif r == 1 then "cs"
			elseif r == 2 then "ss"
			elseif r == 3 then "ds"
			elseif r == 4 then "fs"
			elseif r == 5 then "gs"
			else nil
		if not name or (op == 0x8e and r == 1) then
			fail(op, startCS, start)
		end
		if op == 0x8c then
			writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, c[name])
		else
			c[name] = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
		end
	elseif op == 0xa0 or op == 0xa1 or op == 0xa2 or op == 0xa3 then
		local off = word(c, b)
		local s = seg or c.ds
		local w = if op % 2 == 0 then 8 else 16
		if op < 0xa2 then
			CPU.setReg(c, 0, w, if w == 8 then b:read8(b.segOffToPhys(s, off)) else b:readSeg16(s, off))
		elseif w == 8 then
			b:write8(b.segOffToPhys(s, off), CPU.getReg(c, 0, w))
		else
			b:writeSeg16(s, off, CPU.getReg(c, 0, w))
		end
	elseif op >= 0xa4 and op <= 0xaf and op ~= 0xa8 and op ~= 0xa9 then
		local width = if op % 2 == 0 then 8 else ow
		local size = width / 8
		local aw = if addr32 then 32 else 16
		local cx = CPU.getReg(c, 1, aw)
		if rep == 0 or cx ~= 0 then
			local si = CPU.getReg(c, 6, aw)
			local di = CPU.getReg(c, 7, aw)
			local src = seg or c.ds

			local delta = if bit32.band(c.flags, 1024) ~= 0 then -size else size
			local repeatable = rep ~= 0 and b.fastRepEnabled == true
			local count = 0
			local compare = op == 0xa6 or op == 0xa7 or op == 0xae or op == 0xaf
			while true do
				-- Fast stores only when the entire chunk is a contiguous, unhooked,
				-- writable RAM span. All other cases retain ordered bus accesses.
				if repeatable and (op == 0xaa or op == 0xab) and delta > 0 then
					local n = math.min(cx, 512)
					local bytes = n * size
					local address = phys(c, c.es, di)
					local video = b.video
					local hookSafe = b.memoryWriteHook == nil
						or (video and video.directMemorySafe and b.memoryWriteHook == b.videoMemoryWriteHook)
					local planar = video and video.mode == 0x13 and bit32.band(video.seq[4] or 0, 8) == 0
					local crossesPlanar = planar and address < 0xb0000 and address + bytes > 0xa0000
					if
						hookSafe
						and not crossesPlanar
						and di + bytes <= 2 ^ aw
						and address + bytes <= buffer.len(b.ram)
						and (c.mode32 or address + bytes <= 0x100000)
						and (address >= 0x100000 or address + bytes <= 0xf0000)
					then
						local value = CPU.getReg(c, 0, width)
						if size == 1 then
							buffer.fill(b.ram, address, value, bytes)
						elseif size == 2 then
							for offset = 0, bytes - 1, 2 do
								buffer.writeu16(b.ram, address + offset, value)
							end
						else
							for offset = 0, bytes - 1, 4 do
								buffer.writeu32(b.ram, address + offset, value)
							end
						end
						for page = math.floor(address / 4096), math.floor((address + bytes - 1) / 4096) do
							if b.codePageBitmap[page] then
								b.invalidatedPages[page] = true
							end
						end
						if video and address < 0xc0000 and address + bytes > 0xa0000 then
							video.vramDirty = true
						end
						di = (di + bytes) % 2 ^ aw
						cx -= n
						count += n
						if cx == 0 then
							break
						end
						if b.executionDeadline and os.clock() >= b.executionDeadline then
							c.ip = start
							break
						end
						continue
					end
				end
				if op == 0xa4 or op == 0xa5 then
					writeOperand(c, b, width, nil, c.es, di, 2 ^ aw, readOperand(c, b, width, nil, src, si, 2 ^ aw))
				elseif op == 0xa6 or op == 0xa7 then
					CPU.alu(
						c,
						"cmp",
						readOperand(c, b, width, nil, src, si, 2 ^ aw),
						readOperand(c, b, width, nil, c.es, di, 2 ^ aw),
						width
					)
				elseif op == 0xaa or op == 0xab then
					writeOperand(c, b, width, nil, c.es, di, 2 ^ aw, CPU.getReg(c, 0, width))
				elseif op == 0xac or op == 0xad then
					CPU.setReg(c, 0, width, readOperand(c, b, width, nil, src, si, 2 ^ aw))
				else
					CPU.alu(c, "cmp", CPU.getReg(c, 0, width), readOperand(c, b, width, nil, c.es, di, 2 ^ aw), width)
				end
				if op <= 0xa7 or op == 0xac or op == 0xad then
					si = (si + delta) % 2 ^ aw
				end
				if op <= 0xab or op == 0xae or op == 0xaf then
					di = (di + delta) % 2 ^ aw
				end
				if rep == 0 then
					break
				end
				cx -= 1
				count += 1
				local z = bit32.band(c.flags, 64) ~= 0
				if cx == 0 or (compare and ((rep == 0xf3 and not z) or (rep == 0xf2 and z))) then
					break
				end
				if
					not repeatable or (count % 512 == 0 and b.executionDeadline and os.clock() >= b.executionDeadline)
				then
					c.ip = start
					break
				end
			end
			if op <= 0xa7 or op == 0xac or op == 0xad then
				CPU.setReg(c, 6, aw, si)
			end
			if op <= 0xab or op == 0xae or op == 0xaf then
				CPU.setReg(c, 7, aw, di)
			end
			if rep ~= 0 then
				CPU.setReg(c, 1, aw, cx)
			end
		end
	elseif op == 0xa8 or op == 0xa9 then
		local width = if op == 0xa8 then 8 else ow
		CPU.alu(c, "test", CPU.getReg(c, 0, width), imm(c, b, width), width)
	elseif op == 0xd0 or op == 0xd1 or op == 0xd2 or op == 0xd3 or op == 0xc0 or op == 0xc1 then
		local width = if op % 2 == 0 then 8 else ow
		local operandWidth = width
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local count = if op == 0xd0 or op == 0xd1
			then 1
			elseif op == 0xd2 or op == 0xd3 then CPU.getReg(c, 1, 8) % 32
			else fetch(c, b) % 32
		local value = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
		local initial = value
		local mod = 2 ^ width
		local sign = mod / 2
		local cf = bit32.band(c.flags, 1) ~= 0
		for _ = 1, count do
			if r == 0 then
				local high = value >= sign
				value = (value * 2) % mod + (if high then 1 else 0)
				cf = high
			elseif r == 1 then
				local low = value % 2 ~= 0
				value = math.floor(value / 2) + (if low then sign else 0)
				cf = low
			elseif r == 2 then
				local high = value >= sign
				value = (value * 2) % mod + (if cf then 1 else 0)
				cf = high
			elseif r == 3 then
				local low = value % 2 ~= 0
				value = math.floor(value / 2) + (if cf then sign else 0)
				cf = low
			elseif r == 4 or r == 6 then
				cf = value >= sign
				value = (value * 2) % mod
			elseif r == 5 then
				cf = value % 2 ~= 0
				value = math.floor(value / 2)
			else
				cf = value % 2 ~= 0
				value = math.floor(value / 2) + (if value >= sign then sign else 0)
			end
		end
		if count > 0 then
			writeOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod, value)
			c.flags = bit32.band(c.flags, bit32.bnot(1))
			if cf then
				c.flags = bit32.bor(c.flags, 1)
			end
			if r >= 4 then
				local keep = bit32.band(c.flags, 1)
				CPU.alu(c, "or", value, 0, width)
				c.flags = bit32.bor(bit32.band(c.flags, bit32.bnot(1)), keep)
			end
			if count == 1 then
				local overflow = if r == 0
						or r == 2
						or r == 4
						or r == 6
					then (value >= sign) ~= cf
					elseif r == 1 or r == 3 then (value >= sign) ~= (bit32.band(value, sign / 2) ~= 0)
					elseif r == 5 then initial >= sign
					else false
				c.flags = bit32.band(c.flags, bit32.bnot(2048))
				if overflow then
					c.flags = bit32.bor(c.flags, 2048)
				end
			end
		end
	elseif op == 0xf6 or op == 0xf7 then
		local width = if op == 0xf6 then 8 else ow
		local operandWidth = width
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local v = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
		local mod = 2 ^ width
		if r == 0 then
			CPU.alu(c, "test", v, imm(c, b, width), width)
		elseif r == 2 then
			writeOperand(
				c,
				b,
				operandWidth,
				operandReg,
				operandSeg,
				operandOff,
				operandMod,
				bit32.band(bit32.bnot(v), mod - 1)
			)
		elseif r == 3 then
			writeOperand(
				c,
				b,
				operandWidth,
				operandReg,
				operandSeg,
				operandOff,
				operandMod,
				CPU.alu(c, "sub", 0, v, width)
			)
		elseif r == 4 or r == 5 then
			local a = CPU.getReg(c, 0, width)
			local aa = if r == 5 then signed(a, width) else a
			local vv = if r == 5 then signed(v, width) else v
			local low: number
			local high: number
			if width == 32 then
				local x = math.abs(aa)
				local y = math.abs(vv)
				local x0 = x % 65536
				local x1 = math.floor(x / 65536)
				local y0 = y % 65536
				local y1 = math.floor(y / 65536)
				local p = x0 * y0
				local cross = x1 * y0 + x0 * y1 + math.floor(p / 65536)
				low = (p % 65536) + (cross % 65536) * 65536
				high = (x1 * y1 + math.floor(cross / 65536)) % 4294967296
				if (aa < 0) ~= (vv < 0) then
					low = -low % 4294967296
					high = (4294967295 - high + (if low == 0 then 1 else 0)) % 4294967296
				end
			else
				local product = aa * vv
				local bits = product % (mod * mod)
				low = bits % mod
				high = math.floor(bits / mod)
			end
			if width == 8 then
				CPU.setReg(c, 0, 16, low + high * 256)
			else
				CPU.setReg(c, 0, width, low)
				CPU.setReg(c, 2, width, high)
			end
			local overflow = if r == 4 then high ~= 0 else high ~= (if low >= mod / 2 then mod - 1 else 0)
			c.flags = bit32.band(c.flags, bit32.bnot(2049))
			if overflow then
				c.flags = bit32.bor(c.flags, 2049)
			end
		elseif r == 6 or r == 7 then
			local hi = if width == 8 then math.floor(CPU.getReg(c, 0, 16) / 256) else CPU.getReg(c, 2, width)
			local lo = if width == 8 then CPU.getReg(c, 0, 8) else CPU.getReg(c, 0, width)
			local divisor = v
			local negativeDividend = false
			local negativeDivisor = false
			if r == 7 then
				negativeDividend = hi >= mod / 2
				negativeDivisor = v >= mod / 2
				if negativeDividend then
					lo = -lo % mod
					hi = (mod - 1 - hi + (if lo == 0 then 1 else 0)) % mod
				end
				if negativeDivisor then
					divisor = mod - v
				end
			end
			local invalid = divisor == 0 or hi >= divisor
			local q = 0
			local rem = hi
			if not invalid then
				for bit = width - 1, 0, -1 do
					rem = rem * 2 + math.floor(lo / 2 ^ bit) % 2
					if rem >= divisor then
						rem -= divisor
						q += 2 ^ bit
					end
				end
			end
			if r == 7 and not invalid then
				if negativeDividend ~= negativeDivisor then
					q = -q
				end
				if negativeDividend then
					rem = -rem
				end
				invalid = q < -mod / 2 or q >= mod / 2
			end
			if invalid then
				c.ip = start
				I.interrupt(c, b, 0)
			elseif width == 8 then
				CPU.setReg(c, 0, 8, q)
				CPU.setReg(c, 4, 8, rem)
			else
				CPU.setReg(c, 0, width, q)
				CPU.setReg(c, 2, width, rem)
			end
		else
			fail(op, startCS, start)
		end
	elseif op == 0xfe or op == 0xff then
		local width = if op == 0xfe then 8 else ow
		local operandWidth = width
		local r, operandReg, operandSeg, operandOff, operandMod = modrm(c, b, seg, addr32, operandWidth)
		local v = readOperand(c, b, operandWidth, operandReg, operandSeg, operandOff, operandMod)
		if r == 0 or r == 1 then
			writeOperand(
				c,
				b,
				operandWidth,
				operandReg,
				operandSeg,
				operandOff,
				operandMod,
				CPU.alu(c, if r == 0 then "inc" else "dec", v, 1, width)
			)
		elseif op == 0xff and r == 2 then
			push(c, b, c.ip, ow)
			c.ip = v
		elseif op == 0xff and (r == 3 or r == 5) then
			if operandReg ~= nil then
				fail(op, startCS, start)
			end
			local off = (operandOff + width / 8) % operandMod
			local selector = b:read8(phys(c, operandSeg, off))
				+ 256 * b:read8(phys(c, operandSeg, (off + 1) % operandMod))
			if r == 3 then
				push(c, b, c.cs, ow)
				push(c, b, c.ip, ow)
			end
			c.cs = selector
			c.ip = v
		elseif op == 0xff and r == 4 then
			c.ip = v
		elseif op == 0xff and r == 6 then
			push(c, b, v, ow)
		else
			fail(op, startCS, start)
		end
	elseif op == 0xe8 then
		local d = signed(imm(c, b, ow), ow)
		push(c, b, c.ip, ow)
		c.ip = (c.ip + d) % 2 ^ ow
	elseif op == 0xe9 then
		local d = signed(imm(c, b, ow), ow)
		c.ip = (c.ip + d) % 2 ^ ow
	elseif op == 0xeb then
		local d = signed(fetch(c, b), 8)
		c.ip = (c.ip + d) % ipmod
	elseif op == 0xea or op == 0x9a then
		local off = word(c, b)
		local s = word(c, b)
		if op == 0x9a then
			push(c, b, c.cs)
			push(c, b, c.ip)
		end
		c.cs = s
		c.ip = off
	elseif op == 0xc3 or op == 0xc2 then
		local n = if op == 0xc2 then word(c, b) else 0
		c.ip = pop(c, b, ow)
		local sw = if c.mode32 then 32 else 16
		CPU.setReg(c, 4, sw, CPU.getReg(c, 4, sw) + n)
	elseif op == 0xcb or op == 0xca then
		local n = if op == 0xca then word(c, b) else 0
		c.ip = pop(c, b)
		c.cs = pop(c, b)
		CPU.setReg(c, 4, 16, CPU.getReg(c, 4, 16) + n)
	elseif op == 0xcd then
		I.interrupt(c, b, fetch(c, b))
	elseif op == 0xcc then
		I.interrupt(c, b, 3)
	elseif op == 0xce then
		if bit32.band(c.flags, 2048) ~= 0 then
			I.interrupt(c, b, 4)
		end
	elseif op == 0xcf then
		local iw = if c.mode32 then 32 else 16
		c.ip = pop(c, b, iw)
		c.cs = pop(c, b, iw) % 65536
		c.flags = bit32.bor(pop(c, b, iw), 2)
	elseif op == 0x9c then
		push(c, b, c.flags, ow)
	elseif op == 0x9d then
		c.flags = bit32.bor(pop(c, b, ow), 2)
	elseif op == 0x06 or op == 0x0e or op == 0x16 or op == 0x1e then
		push(c, b, (if op == 0x06 then c.es elseif op == 0x0e then c.cs elseif op == 0x16 then c.ss else c.ds))
	elseif op == 0x07 or op == 0x17 or op == 0x1f then
		local n = (if op == 0x07 then "es" elseif op == 0x17 then "ss" else "ds")
		c[n] = pop(c, b)
	elseif op == 0xf4 then
		c.halted = true
	elseif op == 0xfa then
		c.flags = bit32.band(c.flags, bit32.bnot(512))
	elseif op == 0xfb then
		c.flags = bit32.bor(c.flags, 512)
	elseif op == 0xfc then
		c.flags = bit32.band(c.flags, bit32.bnot(1024))
	elseif op == 0xfd then
		c.flags = bit32.bor(c.flags, 1024)
	elseif op == 0xf8 then
		c.flags = bit32.band(c.flags, bit32.bnot(1))
	elseif op == 0xf9 then
		c.flags = bit32.bor(c.flags, 1)
	elseif op == 0xf5 then
		c.flags = bit32.bxor(c.flags, 1)
	elseif op == 0xe0 or op == 0xe1 or op == 0xe2 or op == 0xe3 then
		local d = signed(fetch(c, b), 8)
		local cx = CPU.getReg(c, 1, 16)
		if op ~= 0xe3 then
			cx = (cx - 1) % 65536
			CPU.setReg(c, 1, 16, cx)
		end
		local z = bit32.band(c.flags, 64) ~= 0
		if
			(op == 0xe3 and cx == 0)
			or (op ~= 0xe3 and cx ~= 0 and (op == 0xe2 or (op == 0xe1 and z) or (op == 0xe0 and not z)))
		then
			c.ip = (c.ip + d) % 65536
		end
	elseif op == 0x68 or op == 0x6a then
		push(c, b, if op == 0x68 then imm(c, b, ow) else signed(fetch(c, b), 8), ow)
	elseif op == 0xe4 or op == 0xe5 or op == 0xec or op == 0xed then
		local port = if op < 0xec then fetch(c, b) else CPU.getReg(c, 2, 16)
		local w = if op % 2 == 0 then 8 else 16
		local v = b:in8(port)
		if w == 16 then
			v += b:in8((port + 1) % 65536) * 256
		end
		CPU.setReg(c, 0, w, v)
	elseif op == 0xe6 or op == 0xe7 or op == 0xee or op == 0xef then
		local port = if op < 0xee then fetch(c, b) else CPU.getReg(c, 2, 16)
		local w = if op % 2 == 0 then 8 else 16
		local v = CPU.getReg(c, 0, w)
		b:out8(port, v)
		if w == 16 then
			b:out8((port + 1) % 65536, math.floor(v / 256))
		end
	else
		fail(op, startCS, start)
	end
	c.currentBlockKey = CPU.key(c)
	return c.currentBlockKey, 1
end
function I.stepUntilCompiledBlock(c: any, b: any, blocks: any, budget: any)
	while budget > 0 and not c.halted and not c.waitingForKey and not c.yieldRequested do
		local key = CPU.key(c)
		if blocks[key] then
			break
		end
		local _, cost = I.step(c, b)
		if cost <= 0 then
			break
		end
		budget -= cost
	end
	c.currentBlockKey = CPU.key(c)
	return c.currentBlockKey, budget
end
return I
