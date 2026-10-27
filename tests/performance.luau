--!strict
local CPU = require("../runtime/CPUState")
local Bus = require("../runtime/Bus")
local Interpreter = require("../runtime/Interpreter")
local Video = require("../runtime/Video")

local function eq(a: any, b: any, message: string)
	assert(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function setup(op: number, rep: number, df: boolean, fast: boolean): (any, any)
	local c: any = CPU.new()
	local b: any = Bus.new()
	c.cs = 0x1000
	c.ds = 0x2000
	c.es = 0x2000
	c.flags = if df then 0x402 else 2
	CPU.setReg(c, 0, 16, 0x1234)
	CPU.setReg(c, 1, 16, 37)
	CPU.setReg(c, 6, 16, 0xffee)
	CPU.setReg(c, 7, 16, 0xfff2)
	b:write8(0x10000, rep)
	b:write8(0x10001, op)
	for i = 0, 65535 do
		buffer.writeu8(b.ram, 0x20000 + i, (i * 17) % 256)
	end
	b.fastRepEnabled = fast
	return c, b
end
local function finish(c: any, b: any)
	repeat
		Interpreter.step(c, b)
	until c.ip ~= 0
end
local function parity(a: any, x: any, b: any, y: any, label: string)
	eq(a.ip, b.ip, label .. " IP")
	eq(a.flags, b.flags, label .. " flags")
	for r = 0, 7 do
		eq(CPU.getReg(a, r, 32), CPU.getReg(b, r, 32), label .. " register " .. r)
	end
	eq(buffer.tostring(x.ram), buffer.tostring(y.ram), label .. " RAM")
end

for _, op in ipairs({ 0xa4, 0xa5, 0xa6, 0xa7, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf }) do
	for _, df in ipairs({ false, true }) do
		for _, rep in ipairs({ 0xf2, 0xf3 }) do
			local c, b = setup(op, rep, df, false)
			local fast, bfast = setup(op, rep, df, true)
			finish(c, b)
			Interpreter.step(fast, bfast)
			parity(c, b, fast, bfast, string.format("%02x/%02x/%s", op, rep, tostring(df)))
		end
	end
end
print("PASS REP parity for all string forms, prefixes, directions, overlap and 16-bit wrap")

-- Compare repeats stop on the first mismatch/match, not merely at count zero.
for _, op in ipairs({ 0xa6, 0xa7, 0xae, 0xaf }) do
	for _, rep in ipairs({ 0xf2, 0xf3 }) do
		local function make(fast: boolean): (any, any)
			local c, b = setup(op, rep, false, fast)
			CPU.setReg(c, 1, 16, 8)
			CPU.setReg(c, 6, 16, 0x100)
			CPU.setReg(c, 7, 16, 0x200)
			CPU.setReg(c, 0, 16, 0x1111)
			for i = 0, 15 do
				b:write8(0x20100 + i, 0x11)
				b:write8(0x20200 + i, 0x11)
			end
			if rep == 0xf3 then
				b:write8(0x20204, 0x22)
			else
				for i = 0, 3 do
					b:write8(0x20200 + i, 0x22)
				end
			end
			return c, b
		end
		local c, b = make(false)
		local f, g = make(true)
		finish(c, b)
		Interpreter.step(f, g)
		parity(c, b, f, g, "compare early termination")
		assert(CPU.getReg(f, 1, 16) > 0)
	end
end
print("PASS REP compare early termination")

local c, b = setup(0xaa, 0xf3, false, true)
c.es = 0xf000
CPU.setReg(c, 7, 16, 0)
CPU.setReg(c, 1, 16, 6)
local writes = 0
b.memoryWriteHook = function(_addr: number, _value: number): boolean
	writes += 1
	return true
end
Interpreter.step(c, b)
eq(writes, 0, "ROM hook")
eq(b:read8(0xf0000), 0, "ROM byte")
c.ip = 0
c.es = 0x3000
CPU.setReg(c, 7, 16, 0)
CPU.setReg(c, 1, 16, 6)
Interpreter.step(c, b)
eq(writes, 6, "unknown hook count")
eq(b:read8(0x30000), 0, "consumed hook")
b.memoryWriteHook = nil
c.ip = 0
CPU.setReg(c, 7, 16, 0)
CPU.setReg(c, 1, 16, 6)
b:markCode(0x30000, 6)
Interpreter.step(c, b)
assert(b.invalidatedPages[0x30])
eq(b:read8(0x30000), 0x34, "written code")
print("PASS ROM, arbitrary hook and code invalidation")

local pc, pb = setup(0xaa, 0xf3, false, true)
local video: any = Video.new(pb, { headless = true })
video:setMode(0x13)
video.seq[4] = 0
video.seq[2] = 5
pc.es = 0xa000
CPU.setReg(pc, 7, 16, 0)
CPU.setReg(pc, 1, 16, 3)
Interpreter.step(pc, pb)
eq(buffer.readu8(video.planes[1], 0), 0x34, "plane 0")
eq(buffer.readu8(video.planes[2], 0), 0, "plane 1")
eq(buffer.readu8(video.planes[3], 2), 0x34, "plane 2")
eq(buffer.readu8(pb.ram, 0xa0000), 0, "planar RAM")
assert(video.vramDirty)
print("PASS planar Mode X uses video hook")

local dc, db = setup(0xab, 0xf3, false, true)
CPU.setReg(dc, 1, 16, 1200)
CPU.setReg(dc, 7, 16, 0)
db.executionDeadline = os.clock() - 1
Interpreter.step(dc, db)
eq(CPU.getReg(dc, 1, 16), 688, "deadline count")
eq(CPU.getReg(dc, 7, 16), 1024, "deadline offset")
eq(dc.ip, 0, "deadline resumable IP")
db.executionDeadline = nil
Interpreter.step(dc, db)
eq(CPU.getReg(dc, 1, 16), 0, "resumed count")
eq(dc.ip, 2, "resumed IP")
print("PASS deadline bounded chunks and resumption")
