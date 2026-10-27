--!strict
--!native
local CPU = require(script.Parent.Parent.CPUState)
local Interpreter = require(script.Parent.Parent.Interpreter)
local blocks: {[number]: (any, any, number) -> (number, number)} = {}
blocks[65536] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 32, 2147483647)
	cpu.ip = 65541
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[65541] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 0, 32, CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 32), 1, 32))
	cpu.ip = 65546
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[65546] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	CPU.setReg(cpu, 3, 32, 131072)
	cpu.ip = 65551
	cpu.currentBlockKey = CPU.key(cpu)
	return cpu.currentBlockKey, budget - 1
end

blocks[65551] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end

blocks[65553] = function(cpu: any, bus: any, budget: number): (number, number)
	if budget <= 0 then return CPU.key(cpu), budget end
	local nextKey, cost = Interpreter.step(cpu, bus)
	cpu.currentBlockKey = nextKey
	return nextKey, budget - cost
end
return blocks
