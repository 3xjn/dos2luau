--!strict
--!native
local CPU = require(script.Parent.Parent.CPUState)
local Interpreter = require(script.Parent.Parent.Interpreter)
local blocks: {[number]: (any, any, number) -> (number, number)} = {}
blocks[256] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, 32767)
	cpu.ip = 259
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 0, 16, CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 16), 1, 16))
	cpu.ip = 262
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 3, 16, 65535)
	cpu.ip = 265
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 3, 16, CPU.alu(cpu, "inc", CPU.getReg(cpu, 3, 16), 1, 16))
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[259] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 16), 1, 16))
	cpu.ip = 262
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 3, 16, 65535)
	cpu.ip = 265
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 3, 16, CPU.alu(cpu, "inc", CPU.getReg(cpu, 3, 16), 1, 16))
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[262] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 3, 16, 65535)
	cpu.ip = 265
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 3, 16, CPU.alu(cpu, "inc", CPU.getReg(cpu, 3, 16), 1, 16))
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[265] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	if budget >= 2 then
	CPU.setReg(cpu, 3, 16, CPU.getReg(cpu, 3, 16) + 1)
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
else
	CPU.setReg(cpu, 3, 16, CPU.alu(cpu, "inc", CPU.getReg(cpu, 3, 16), 1, 16))
	cpu.ip = 266
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end
end

blocks[266] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local cmpA = CPU.getReg(cpu, 0, 16)
	local cmpB = 32768
	local _result = CPU.alu(cpu, "cmp", cmpA, cmpB, 16)
	cpu.ip = 269
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	if cmpA ~= cmpB then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[269] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local f = cpu.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local zf = bit32.band(f, 64) ~= 0
	local sf = bit32.band(f, 128) ~= 0
	local of = bit32.band(f, 2048) ~= 0
	if not zf then cpu.ip = 274 else cpu.ip = 271 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[271] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, CPU.alu(cpu, "xor", CPU.getReg(cpu, 0, 16), 43605, 16))
	cpu.ip = 274
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[274] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	bus:writeSeg16(cpu.ds, 768, CPU.getReg(cpu, 0, 16))
	cpu.ip = 277
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[277] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 1, 16, 5)
	cpu.ip = 280
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	CPU.setReg(cpu, 1, 16, CPU.alu(cpu, "dec", CPU.getReg(cpu, 1, 16), 1, 16))
	cpu.ip = 281
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[280] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 1, 16, CPU.alu(cpu, "dec", CPU.getReg(cpu, 1, 16), 1, 16))
	cpu.ip = 281
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[281] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local f = cpu.flags
	local cf = bit32.band(f, 1) ~= 0
	local pf = bit32.band(f, 4) ~= 0
	local zf = bit32.band(f, 64) ~= 0
	local sf = bit32.band(f, 128) ~= 0
	local of = bit32.band(f, 2048) ~= 0
	if not zf then cpu.ip = 280 else cpu.ip = 283 end
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[283] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end
return blocks
