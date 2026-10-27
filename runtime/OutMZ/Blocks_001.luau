--!strict
--!native
local CPU = require(script.Parent.Parent.CPUState)
local Interpreter = require(script.Parent.Parent.Interpreter)
local blocks: {[number]: (any, any, number) -> (number, number)} = {}
blocks[0] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[3] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[5] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	do
	CPU.setReg(cpu, 0, 16, 7)
	end
	cpu.ip = 8
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	if budget <= 0 then return cpu.currentBlockKey, budget end
	do
	CPU.setReg(cpu, 0, 16, CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 16), 8, 16))
	end
	cpu.ip = 11
	cpu.currentBlockKey = CPU.key(cpu)
	budget -= 1
	return cpu.currentBlockKey, budget
end

blocks[8] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 16, CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 16), 8, 16))
	cpu.ip = 11
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[11] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	bus:writeSeg16(cpu.ds, 768, CPU.getReg(cpu, 0, 16))
	cpu.ip = 14
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[14] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end
return blocks
