--!strict
-- Optional local compatibility probe. Fetch/compile game assets first; excluded
-- from the self-contained test suite and from the source distribution.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local DOS = require("../runtime/DOS")
local CPU = require("../runtime/CPUState")
local meta = require("../runtime/OutOregon/Program_Meta")
local blocks = require("../runtime/OutOregon/Blocks")
local assets = require("../runtime/OutOregon/VFS_Assets")
local interpreted = process.args[1] == "--interpreted"
local machine: any = DOS.new({
	headless = true,
	meta = meta,
	blocks = if interpreted then {} else blocks,
	assets = assets,
	programPath = "C:\\OREGON.EXE",
	frameBudgetSeconds = 1,
	maxInstructionsPerFrame = 20000,
	clock = function()
		return { year = 1990, month = 10, day = 26, hour = 12, min = 0, sec = 0, wday = 6 }
	end,
})
-- Rasterize only checkpoints during the compatibility probe.
machine.scheduler.video = nil
local dosCalls: { any } = {}
local originalDOS = machine.hle.dos
machine.hle.dos = function(self: any, c: any, b: any): boolean
	local record: any = {
		ax = CPU.getReg(c, 0, 16),
		bx = CPU.getReg(c, 3, 16),
		cx = CPU.getReg(c, 1, 16),
		dx = CPU.getReg(c, 2, 16),
		es = c.es,
		ds = c.ds,
		cs = c.cs,
		ip = c.ip,
	}
	local result = originalDOS(self, c, b)
	record.resultAX = CPU.getReg(c, 0, 16)
	record.resultBX = CPU.getReg(c, 3, 16)
	record.flags = b:readSeg16(c.ss, CPU.getReg(c, 4, 16) + 4)
	table.insert(dosCalls, record)
	return result
end
local ok, err = pcall(function()
	local function advance()
		for frame = 1, 2000 do
			machine:step(1 / 18.2065)
			if frame % 100 == 0 then
				print(
					"Oregon",
					frame,
					machine.scheduler.executedInstructions,
					machine.cpu.cs,
					machine.cpu.ip,
					machine.video.mode,
					machine.cpu.waitingForKey
				)
			end
			if machine.cpu.waitingForKey or machine.cpu.halted then
				break
			end
		end
	end
	advance()
	for _, keyName in ipairs(process.args) do
		if keyName ~= "--interpreted" then
			machine.scheduler:keyEvent(keyName, true)
			machine.scheduler:keyEvent(keyName, false)
			advance()
		end
	end
end)
local pixels = machine.video:render()
fs.writeFile(".local-games/oregon-frame.rgba", buffer.tostring(pixels))
fs.writeFile(".local-games/oregon.ram", buffer.tostring(machine.bus.ram))
fs.writeFile(".local-games/oregon-dos.json", serde.encode("json", dosCalls, true))
local state = {
	ok = ok,
	error = if ok then nil else tostring(err),
	cs = machine.cpu.cs,
	ip = machine.cpu.ip,
	flags = machine.cpu.flags,
	regs = {},
	halted = machine.cpu.halted,
	waitingForKey = machine.cpu.waitingForKey,
	mode = machine.video.mode,
	width = machine.video.width,
	height = machine.video.height,
	instructions = machine.scheduler.executedInstructions,
	exitCode = machine.cpu.exitCode,
	trace = machine:exportTrace(),
	directInstructions = machine.dispatcher.directInstructions or 0,
	interpretedInstructions = machine.dispatcher.interpretedInstructions or 0,
}
for i = 0, 7 do
	table.insert(state.regs, CPU.getReg(machine.cpu, i, 16))
end
fs.writeFile(".local-games/oregon-state.json", serde.encode("json", state, true))
local display = table.clone(state)
display.trace = nil
display.discovered = #state.trace.blocks
print(serde.encode("json", display, false))
machine:destroy()
assert(ok, tostring(err))
assert(
	not state.halted and state.waitingForKey and state.mode == 0x13,
	"Expected a running VGA program waiting for input"
)
