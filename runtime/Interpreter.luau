--!strict
--!native
local CPU = require(script.Parent.CPUState)
local I = {}
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
	local function phys(s: any, off: any): number
		if c.mode32 then
			return (((c.segmentBases and c.segmentBases[s]) or 0) + off) % 4294967296
		else
			return (s * 16 + off) % 1048576
		end
	end
	local function fetch()
		local v = b:read8(phys(c.cs, c.ip))
		c.ip = (c.ip + 1) % ipmod
		return v
	end
	local function word()
		local lo = fetch()
		return lo + fetch() * 256
	end
	local seg = nil
	local rep = 0
	local w32 = c.mode32 == true
	local addr32 = c.mode32 == true
	local op = fetch()
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
		op = fetch()
	end
	local function fail()
		error(string.format("Unsupported instruction %02X at %04X:%04X", op, startCS, start), 0)
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
		fail()
	end
	local function imm(width: number): number
		if width == 8 then
			return fetch()
		elseif width == 16 then
			return word()
		else
			local lo = word()
			return lo + word() * 65536
		end
	end
	local function modrm(width: any): (number, any, any, any)
		local m = fetch()
		local mode = math.floor(m / 64)
		local reg = math.floor(m / 8) % 8
		local rm = m % 8
		if mode == 3 then
			return reg,
				function()
					return CPU.getReg(c, rm, width)
				end,
				function(v: any)
					CPU.setReg(c, rm, width, v)
				end,
				nil
		end
		local base = 0
		local usesBP = false
		if addr32 then
			if rm == 4 then
				local sib = fetch()
				local scale = 2 ^ math.floor(sib / 64)
				local index = math.floor(sib / 8) % 8
				local basereg = sib % 8
				if index ~= 4 then
					base += CPU.getReg(c, index, 32) * scale
				end
				if basereg == 5 and mode == 0 then
					base += imm(32)
				else
					base += CPU.getReg(c, basereg, 32)
					usesBP = basereg == 4 or basereg == 5
				end
			elseif rm == 5 and mode == 0 then
				base = imm(32)
			else
				base = CPU.getReg(c, rm, 32)
				usesBP = rm == 5
			end
			if mode == 1 then
				base += signed(fetch(), 8)
			elseif mode == 2 then
				base += signed(imm(32), 32)
			end
		else
			local bx = CPU.getReg(c, 3, 16)
			local bp = CPU.getReg(c, 5, 16)
			local si = CPU.getReg(c, 6, 16)
			local di = CPU.getReg(c, 7, 16)
			base = ({ bx + si, bx + di, bp + si, bp + di, si, di, bp, bx })[rm + 1]
			usesBP = rm == 2 or rm == 3 or (rm == 6 and mode ~= 0)
			if mode == 0 and rm == 6 then
				base = word()
			elseif mode == 1 then
				base += signed(fetch(), 8)
			elseif mode == 2 then
				base += signed(word(), 16)
			end
		end
		local addressMod = if addr32 then 4294967296 else 65536
		local off = base % addressMod
		local s = seg or (if usesBP then c.ss else c.ds)
		local function read()
			local value = 0
			for i = 0, width / 8 - 1 do
				value += b:read8(phys(s, (off + i) % addressMod)) * 2 ^ (8 * i)
			end
			return value
		end
		local function write(v: any)
			for i = 0, width / 8 - 1 do
				b:write8(phys(s, (off + i) % addressMod), math.floor(v / 2 ^ (8 * i)) % 256)
			end
		end
		return reg, read, write, { segment = s, offset = off, mod = addressMod }
	end
	local function cond(n: any)
		local f = c.flags
		local cf = bit32.band(f, 1) ~= 0
		local pf = bit32.band(f, 4) ~= 0
		local z = bit32.band(f, 64) ~= 0
		local s = bit32.band(f, 128) ~= 0
		local o = bit32.band(f, 2048) ~= 0
		local tests = {
			o,
			not o,
			cf,
			not cf,
			z,
			not z,
			cf or z,
			not cf and not z,
			s,
			not s,
			pf,
			not pf,
			s ~= o,
			s == o,
			z or s ~= o,
			not z and s == o,
		}
		return tests[n + 1]
	end
	local ops = { "add", "or", "adc", "sbb", "and", "sub", "xor", "cmp" }
	if op <= 0x3d and op % 8 <= 5 and math.floor(op / 8) < 8 then
		local operation = ops[math.floor(op / 8) + 1]
		local form = op % 8
		local width = if form % 2 == 0 then 8 elseif w32 then 32 else 16
		if form < 4 then
			local reg, read, write = modrm(width)
			local a = read()
			local rv = CPU.getReg(c, reg, width)
			if form >= 2 then
				a, rv = rv, a
			end
			local result = CPU.alu(c, operation, a, rv, width)
			if operation ~= "cmp" then
				if form >= 2 then
					CPU.setReg(c, reg, width, result)
				else
					write(result)
				end
			end
		else
			local val = imm(width)
			local result = CPU.alu(c, operation, CPU.getReg(c, 0, width), val, width)
			if operation ~= "cmp" then
				CPU.setReg(c, 0, width, result)
			end
		end
	elseif op == 0x0f then
		local ext = fetch()
		if ext >= 0x80 and ext <= 0x8f then
			local d = signed(imm(ow), ow)
			if cond(ext % 16) then
				c.ip = (c.ip + d) % 2 ^ ow
			end
		elseif ext == 0xb6 or ext == 0xb7 or ext == 0xbe or ext == 0xbf then
			local sw = if ext % 2 == 0 then 8 else 16
			local r, read = modrm(sw)
			local v = read()
			if ext >= 0xbe then
				v = signed(v, sw)
			end
			CPU.setReg(c, r, ow, v)
		elseif ext == 0xaf then
			local r, read = modrm(ow)
			local a = signed(CPU.getReg(c, r, ow), ow)
			local v = signed(read(), ow)
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
			fail()
		end
	elseif op >= 0xd8 and op <= 0xdf then
		local spec = b:read8(phys(c.cs, c.ip))
		local mode = math.floor(spec / 64)
		local sub = math.floor(spec / 8) % 8
		local index = spec % 8
		local function get(i: number): number
			local v = c.fpu[(c.fpuTop + i) % 8 + 1]
			if v == nil then
				error("x87 stack underflow", 0)
			end
			return v
		end
		local function put(i: number, v: number)
			c.fpu[(c.fpuTop + i) % 8 + 1] = v
		end
		local function fpPush(v: number)
			c.fpuTop = (c.fpuTop - 1) % 8
			put(0, v)
		end
		local function fpPop()
			local v = get(0)
			c.fpu[c.fpuTop + 1] = nil
			c.fpuTop = (c.fpuTop + 1) % 8
			return v
		end
		local function compare(a: number, v: number)
			c.fpuStatus = bit32.band(c.fpuStatus or 0, bit32.bnot(0x4500))
			if a ~= a or v ~= v then
				c.fpuStatus = bit32.bor(c.fpuStatus, 0x4500)
			elseif a < v then
				c.fpuStatus = bit32.bor(c.fpuStatus, 0x100)
			elseif a == v then
				c.fpuStatus = bit32.bor(c.fpuStatus, 0x4000)
			end
		end
		if mode ~= 3 then
			local width = if op == 0xdd or op == 0xdc then 64 else 32
			local r, _, _, address = modrm(width)
			if op == 0xd9 and (r == 5 or r == 7) then
				local a = phys(address.segment, address.offset)
				local a2 = phys(address.segment, (address.offset + 1) % address.mod)
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
				b:write8(phys(address.segment, address.offset), v % 256)
				b:write8(phys(address.segment, (address.offset + 1) % address.mod), math.floor(v / 256))
				c.currentBlockKey = CPU.key(c)
				return c.currentBlockKey, 1
			end
			local tmp = buffer.create(width / 8)
			for i = 0, width / 8 - 1 do
				buffer.writeu8(tmp, i, b:read8(phys(address.segment, (address.offset + i) % address.mod)))
			end
			local v = if width == 32 then buffer.readf32(tmp, 0) else buffer.readf64(tmp, 0)
			if (op == 0xd9 or op == 0xdd) and r == 0 then
				fpPush(v)
			elseif (op == 0xd9 or op == 0xdd) and (r == 2 or r == 3) then
				if width == 32 then
					buffer.writef32(tmp, 0, get(0))
				else
					buffer.writef64(tmp, 0, get(0))
				end
				for i = 0, width / 8 - 1 do
					b:write8(phys(address.segment, (address.offset + i) % address.mod), buffer.readu8(tmp, i))
				end
				if r == 3 then
					fpPop()
				end
			elseif op == 0xd8 or op == 0xdc then
				local a = get(0)
				if r == 0 then
					put(0, a + v)
				elseif r == 1 then
					put(0, a * v)
				elseif r == 2 or r == 3 then
					compare(a, v)
					if r == 3 then
						fpPop()
					end
				elseif r == 4 then
					put(0, a - v)
				elseif r == 5 then
					put(0, v - a)
				elseif r == 6 then
					put(0, a / v)
				else
					put(0, v / a)
				end
			else
				fail()
			end
		else
			fetch()
			if op == 0xd9 and spec >= 0xc0 and spec <= 0xc7 then
				fpPush(get(index))
			elseif op == 0xd9 and spec >= 0xc8 and spec <= 0xcf then
				local a = get(0)
				put(0, get(index))
				put(index, a)
			elseif op == 0xd9 and spec == 0xe8 then
				fpPush(1)
			elseif op == 0xd9 and spec == 0xe9 then
				fpPush(math.log(10) / math.log(2))
			elseif op == 0xd9 and spec == 0xea then
				fpPush(1 / math.log(2))
			elseif op == 0xd9 and spec == 0xec then
				fpPush(math.log(2) / math.log(10))
			elseif op == 0xd9 and spec == 0xed then
				fpPush(math.log(2))
			elseif op == 0xd9 and spec == 0xee then
				fpPush(0)
			elseif op == 0xd9 and spec == 0xeb then
				fpPush(math.pi)
			elseif op == 0xd9 and spec == 0xe0 then
				put(0, -get(0))
			elseif op == 0xd9 and spec == 0xe1 then
				put(0, math.abs(get(0)))
			elseif op == 0xd9 and spec == 0xfa then
				put(0, math.sqrt(get(0)))
			elseif op == 0xd9 and spec == 0xfe then
				put(0, math.sin(get(0)))
			elseif op == 0xd9 and spec == 0xff then
				put(0, math.cos(get(0)))
			elseif op == 0xdb and spec == 0xe3 then
				c.fpu = {}
				c.fpuTop = 0
				c.fpuStatus = 0
				c.fpuControl = 0x37f
			elseif op == 0xdf and spec == 0xe0 then
				CPU.setReg(c, 0, 16, bit32.bor(c.fpuStatus or 0, bit32.lshift(c.fpuTop, 11)))
			elseif op == 0xd8 then
				local a = get(0)
				local v = get(index)
				if sub == 0 then
					put(0, a + v)
				elseif sub == 1 then
					put(0, a * v)
				elseif sub == 2 or sub == 3 then
					compare(a, v)
					if sub == 3 then
						fpPop()
					end
				elseif sub == 4 then
					put(0, a - v)
				elseif sub == 5 then
					put(0, v - a)
				elseif sub == 6 then
					put(0, a / v)
				else
					put(0, v / a)
				end
			elseif op == 0xde and spec == 0xd9 then
				compare(get(0), get(1))
				fpPop()
				fpPop()
			elseif (op == 0xdc or op == 0xde) and (sub == 0 or sub == 1 or sub >= 4) then
				local a = get(index)
				local v = get(0)
				if sub == 0 then
					put(index, a + v)
				elseif sub == 1 then
					put(index, a * v)
				elseif sub == 4 then
					put(index, v - a)
				elseif sub == 5 then
					put(index, a - v)
				elseif sub == 6 then
					put(index, v / a)
				else
					put(index, a / v)
				end
				if op == 0xde then
					fpPop()
				end
			elseif op == 0xdd and sub == 0 then
				c.fpu[(c.fpuTop + index) % 8 + 1] = nil
			elseif op == 0xdd and (sub == 4 or sub == 5) then
				compare(get(0), get(index))
				if sub == 5 then
					fpPop()
				end
			elseif op == 0xdd and (sub == 2 or sub == 3) then
				put(index, get(0))
				if sub == 3 then
					fpPop()
				end
			else
				fail()
			end
		end
	elseif op == 0xd7 then
		local aw = if addr32 then 32 else 16
		local off = (CPU.getReg(c, 3, aw) + CPU.getReg(c, 0, 8)) % 2 ^ aw
		CPU.setReg(c, 0, 8, b:read8(phys(seg or c.ds, off)))
	elseif op == 0x8f then
		local r, _, write = modrm(ow)
		if r ~= 0 then
			fail()
		end
		write(pop(c, b, ow))
	elseif op == 0x8d or op == 0xc4 or op == 0xc5 then
		local r, _, _, a = modrm(ow)
		if not a then
			fail()
		end
		if op == 0x8d then
			CPU.setReg(c, r, ow, a.offset)
		else
			local v = 0
			for i = 0, ow / 8 - 1 do
				v += b:read8(phys(a.segment, (a.offset + i) % a.mod)) * 2 ^ (8 * i)
			end
			local off = (a.offset + ow / 8) % a.mod
			local selector = b:read8(phys(a.segment, off)) + b:read8(phys(a.segment, (off + 1) % a.mod)) * 256
			CPU.setReg(c, r, ow, v)
			if op == 0xc4 then
				c.es = selector
			else
				c.ds = selector
			end
		end
	elseif op == 0x60 then
		local original = CPU.getReg(c, 4, ow)
		for _, r in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7 }) do
			push(c, b, if r == 4 then original else CPU.getReg(c, r, ow), ow)
		end
	elseif op == 0x61 then
		for _, r in ipairs({ 7, 6, 5, 4, 3, 2, 1, 0 }) do
			local v = pop(c, b, ow)
			if r ~= 4 then
				CPU.setReg(c, r, ow, v)
			end
		end
	elseif op == 0xc8 then
		local size = word()
		local level = fetch() % 32
		push(c, b, CPU.getReg(c, 5, ow), ow)
		local sw = if c.mode32 then 32 else 16
		local frame = CPU.getReg(c, 4, sw)
		local bp = CPU.getReg(c, 5, ow)
		for _ = 1, level - 1 do
			bp = (bp - ow / 8) % 2 ^ ow
			local a = phys(c.ss, bp)
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
		local d = signed(fetch(), 8)
		if cond(op % 16) then
			c.ip = (c.ip + d) % ipmod
		end
	elseif op >= 0xb0 and op <= 0xbf then
		local w = if op < 0xb8 then 8 elseif w32 then 32 else 16
		CPU.setReg(c, op % 8, w, imm(w))
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
		local r, read, write = modrm(w)
		local a = read()
		local v = CPU.getReg(c, r, w)
		if op == 0x88 or op == 0x89 then
			write(v)
		elseif op == 0x8a or op == 0x8b then
			CPU.setReg(c, r, w, a)
		elseif op == 0x84 or op == 0x85 then
			CPU.alu(c, "test", a, v, w)
		else
			write(v)
			CPU.setReg(c, r, w, a)
		end
	elseif op == 0x80 or op == 0x81 or op == 0x83 then
		local w = if op == 0x80 then 8 elseif w32 then 32 else 16
		local r, read, write = modrm(w)
		local v = if op == 0x81 then imm(w) elseif op == 0x83 then signed(fetch(), 8) else fetch()
		local result = CPU.alu(c, ops[r + 1], read(), v, w)
		if r ~= 7 then
			write(result)
		end
	elseif op == 0xc6 or op == 0xc7 then
		local w = if op == 0xc6 then 8 elseif w32 then 32 else 16
		local r, _, write = modrm(w)
		if r ~= 0 then
			fail()
		end
		write(imm(w))
	elseif op == 0x8c or op == 0x8e then
		local r, read, write = modrm(16)
		local names = { "es", "cs", "ss", "ds", "fs", "gs" }
		local name = names[r + 1]
		if not name or (op == 0x8e and r == 1) then
			fail()
		end
		if op == 0x8c then
			write(c[name])
		else
			c[name] = read()
		end
	elseif op == 0xa0 or op == 0xa1 or op == 0xa2 or op == 0xa3 then
		local off = word()
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
			local function rd(s: any, o: any)
				local v = 0
				for i = 0, size - 1 do
					v += b:read8(phys(s, (o + i) % 2 ^ aw)) * 2 ^ (8 * i)
				end
				return v
			end
			local function wr(s: any, o: any, v: any)
				for i = 0, size - 1 do
					b:write8(phys(s, (o + i) % 2 ^ aw), math.floor(v / 2 ^ (8 * i)) % 256)
				end
			end
			if op == 0xa4 or op == 0xa5 then
				wr(c.es, di, rd(src, si))
			elseif op == 0xa6 or op == 0xa7 then
				CPU.alu(c, "cmp", rd(src, si), rd(c.es, di), width)
			elseif op == 0xaa or op == 0xab then
				wr(c.es, di, CPU.getReg(c, 0, width))
			elseif op == 0xac or op == 0xad then
				CPU.setReg(c, 0, width, rd(src, si))
			else
				CPU.alu(c, "cmp", CPU.getReg(c, 0, width), rd(c.es, di), width)
			end
			local delta = if bit32.band(c.flags, 1024) ~= 0 then -size else size
			if op <= 0xa7 or op == 0xac or op == 0xad then
				CPU.setReg(c, 6, aw, si + delta)
			end
			if op <= 0xab or op == 0xae or op == 0xaf then
				CPU.setReg(c, 7, aw, di + delta)
			end
			if rep ~= 0 then
				cx = (cx - 1) % 2 ^ aw
				CPU.setReg(c, 1, aw, cx)
				local compare = op == 0xa6 or op == 0xa7 or op == 0xae or op == 0xaf
				local z = bit32.band(c.flags, 64) ~= 0
				if cx ~= 0 and (not compare or (rep == 0xf3 and z) or (rep == 0xf2 and not z)) then
					c.ip = start
				end
			end
		end
	elseif op == 0xa8 or op == 0xa9 then
		local width = if op == 0xa8 then 8 else ow
		CPU.alu(c, "test", CPU.getReg(c, 0, width), imm(width), width)
	elseif op == 0xd0 or op == 0xd1 or op == 0xd2 or op == 0xd3 or op == 0xc0 or op == 0xc1 then
		local width = if op % 2 == 0 then 8 else ow
		local r, read, write = modrm(width)
		local count = if op == 0xd0 or op == 0xd1
			then 1
			elseif op == 0xd2 or op == 0xd3 then CPU.getReg(c, 1, 8) % 32
			else fetch() % 32
		local value = read()
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
			write(value)
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
		local r, read, write = modrm(width)
		local v = read()
		local mod = 2 ^ width
		if r == 0 then
			CPU.alu(c, "test", v, imm(width), width)
		elseif r == 2 then
			write(bit32.band(bit32.bnot(v), mod - 1))
		elseif r == 3 then
			write(CPU.alu(c, "sub", 0, v, width))
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
			fail()
		end
	elseif op == 0xfe or op == 0xff then
		local width = if op == 0xfe then 8 else ow
		local r, read, write, address = modrm(width)
		local v = read()
		if r == 0 or r == 1 then
			write(CPU.alu(c, if r == 0 then "inc" else "dec", v, 1, width))
		elseif op == 0xff and r == 2 then
			push(c, b, c.ip, ow)
			c.ip = v
		elseif op == 0xff and (r == 3 or r == 5) then
			if not address then
				fail()
			end
			local off = (address.offset + width / 8) % address.mod
			local selector = b:read8(phys(address.segment, off))
				+ 256 * b:read8(phys(address.segment, (off + 1) % address.mod))
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
			fail()
		end
	elseif op == 0xe8 then
		local d = signed(imm(ow), ow)
		push(c, b, c.ip, ow)
		c.ip = (c.ip + d) % 2 ^ ow
	elseif op == 0xe9 then
		local d = signed(imm(ow), ow)
		c.ip = (c.ip + d) % 2 ^ ow
	elseif op == 0xeb then
		local d = signed(fetch(), 8)
		c.ip = (c.ip + d) % ipmod
	elseif op == 0xea or op == 0x9a then
		local off = word()
		local s = word()
		if op == 0x9a then
			push(c, b, c.cs)
			push(c, b, c.ip)
		end
		c.cs = s
		c.ip = off
	elseif op == 0xc3 or op == 0xc2 then
		local n = if op == 0xc2 then word() else 0
		c.ip = pop(c, b, ow)
		local sw = if c.mode32 then 32 else 16
		CPU.setReg(c, 4, sw, CPU.getReg(c, 4, sw) + n)
	elseif op == 0xcb or op == 0xca then
		local n = if op == 0xca then word() else 0
		c.ip = pop(c, b)
		c.cs = pop(c, b)
		CPU.setReg(c, 4, 16, CPU.getReg(c, 4, 16) + n)
	elseif op == 0xcd then
		I.interrupt(c, b, fetch())
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
		push(c, b, ({ c.es, c.cs, c.ss, c.ds })[math.floor(op / 8) + 1])
	elseif op == 0x07 or op == 0x17 or op == 0x1f then
		local n = ({ [0x07] = "es", [0x17] = "ss", [0x1f] = "ds" })[op]
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
		local d = signed(fetch(), 8)
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
		push(c, b, if op == 0x68 then imm(ow) else signed(fetch(), 8), ow)
	elseif op == 0xe4 or op == 0xe5 or op == 0xec or op == 0xed then
		local port = if op < 0xec then fetch() else CPU.getReg(c, 2, 16)
		local w = if op % 2 == 0 then 8 else 16
		local v = b:in8(port)
		if w == 16 then
			v += b:in8((port + 1) % 65536) * 256
		end
		CPU.setReg(c, 0, w, v)
	elseif op == 0xe6 or op == 0xe7 or op == 0xee or op == 0xef then
		local port = if op < 0xee then fetch() else CPU.getReg(c, 2, 16)
		local w = if op % 2 == 0 then 8 else 16
		local v = CPU.getReg(c, 0, w)
		b:out8(port, v)
		if w == 16 then
			b:out8((port + 1) % 65536, math.floor(v / 256))
		end
	else
		fail()
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
