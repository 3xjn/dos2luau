--!strict
--!native
local CPU = require(script.Parent.Parent.CPUState)
local Interpreter = require(script.Parent.Parent.Interpreter)
local blocks: {[number]: (any, any, number) -> (number, number)} = {}
blocks[256] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[257] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[258] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, 19)
	cpu.ip = 261
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[261] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[263] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, 40960)
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[266] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[268] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 8, 182)
	cpu.ip = 270
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[270] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[272] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[274] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 8, CPU.alu(cpu, "or", CPU.getReg(cpu, 0, 8), 3, 8))
	cpu.ip = 276
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[276] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[278] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	do
	CPU.setReg(cpu, 6, 16, 339)
	end
	cpu.ip = 281
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 3, 8, 1)
	end
	cpu.ip = 283
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[281] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 3, 8, 1)
	cpu.ip = 283
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[283] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[284] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[286] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 8, CPU.getReg(cpu, 4, 8))
	cpu.ip = 288
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[288] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[290] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local _result = CPU.alu(cpu, "cmp", CPU.getReg(cpu, 6, 16), 355, 16)
	cpu.ip = 294
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[294] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local f = cpu.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local zf = bit32.band(f, 64) ~= 0
	local sf = bit32.band(f, 128) ~= 0
	local of = bit32.band(f, 2048) ~= 0
	if cf then cpu.ip = 299 else cpu.ip = 296 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[296] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	do
	CPU.setReg(cpu, 6, 16, 339)
	end
	cpu.ip = 299
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 7, 16, CPU.alu(cpu, "xor", CPU.getReg(cpu, 7, 16), CPU.getReg(cpu, 7, 16), 16))
	end
	cpu.ip = 301
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 1, 16, 64000)
	end
	cpu.ip = 304
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 0, 8, CPU.getReg(cpu, 3, 8))
	end
	cpu.ip = 306
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[299] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	do
	CPU.setReg(cpu, 7, 16, CPU.alu(cpu, "xor", CPU.getReg(cpu, 7, 16), CPU.getReg(cpu, 7, 16), 16))
	end
	cpu.ip = 301
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 1, 16, 64000)
	end
	cpu.ip = 304
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 0, 8, CPU.getReg(cpu, 3, 8))
	end
	cpu.ip = 306
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[301] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	do
	CPU.setReg(cpu, 1, 16, 64000)
	end
	cpu.ip = 304
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 0, 8, CPU.getReg(cpu, 3, 8))
	end
	cpu.ip = 306
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[304] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 8, CPU.getReg(cpu, 3, 8))
	cpu.ip = 306
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[306] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[308] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[310] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 4, 8, 1)
	cpu.ip = 312
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[312] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[314] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local f = cpu.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local zf = bit32.band(f, 64) ~= 0
	local sf = bit32.band(f, 128) ~= 0
	local of = bit32.band(f, 2048) ~= 0
	if zf then cpu.ip = 283 else cpu.ip = 316 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[316] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 4, 8, 0)
	cpu.ip = 318
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[318] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[320] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local cmpA = CPU.getReg(cpu, 0, 8)
	local cmpB = 27
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 8)
	cpu.ip = 322
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 335 else cpu.ip = 324 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[322] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local f = cpu.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local zf = bit32.band(f, 64) ~= 0
	local sf = bit32.band(f, 128) ~= 0
	local of = bit32.band(f, 2048) ~= 0
	if not zf then cpu.ip = 335 else cpu.ip = 324 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[324] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[326] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 8, CPU.alu(cpu, "and", CPU.getReg(cpu, 0, 8), 252, 8))
	cpu.ip = 328
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[328] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[330] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, 19456)
	cpu.ip = 333
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[333] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[335] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 3, 8, CPU.getReg(cpu, 0, 8))
	cpu.ip = 337
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[337] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	cpu.ip = 283
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end
return blocks
