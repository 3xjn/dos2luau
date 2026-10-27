--!strict
local CPU = require("../runtime/CPUState")
local Bus = require("../runtime/Bus")
local Scheduler = require("../runtime/InputAndScheduler")
local function eq(a: any, b: any, label: string)
	assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function new(options: any?): (any, any, any)
	local c: any = CPU.new()
	local b: any = Bus.new()
	b:write16(0x41a, 0x1e)
	b:write16(0x41c, 0x1e)
	local d: any = {
		run = function(_self: any, _c: any, _b: any, _budget: number)
			return 0
		end,
	}
	local s: any = Scheduler.new(c, b, d, options or { headless = true, frameBudgetSeconds = 1 })
	return s, b, c
end
local function readKey(b: any): number?
	local head = b:read16(0x41a)
	local tail = b:read16(0x41c)
	if head == tail then
		return nil
	end
	local word = b:read16(0x400 + head)
	head += 2
	if head >= 0x3e then
		head = 0x1e
	end
	b:write16(0x41a, head)
	return word
end
for _, case in ipairs({ { "Backspace", 0x0e08, 0.30 }, { "Right", 0x4d00, 0.16 }, { "A", 0x1e61, 0.30 } }) do
	local s, b = new()
	local name = case[1] :: string
	local expected = case[2] :: number
	local delay = case[3] :: number
	s:keyEvent(name, true)
	eq(readKey(b), expected, name .. " make")
	s:step(delay - 0.01)
	eq(readKey(b), nil, name .. " before delay")
	s:step(0.011)
	eq(readKey(b), expected, name .. " repeat")
	s:step(0.055)
	eq(readKey(b), expected, name .. " next repeat")
	s:keyEvent(name, false)
	s:step(1)
	eq(readKey(b), nil, name .. " release")
end
print("PASS letter, backspace and arrow typematic delays and release")
local now = 0
local live, liveBus = new({
	frameBudgetSeconds = 1,
	repeatClock = function()
		return now
	end,
})
live.interactive = true
live:keyEvent("A", true)
eq(readKey(liveBus), 0x1e61, "live initial A")
now = 0.01
live:step(1)
eq(readKey(liveBus), nil, "frame time before press does not count toward repeat")
now = 0.31
live:step(0.3)
eq(readKey(liveBus), 0x1e61, "live repeat begins after actual hold delay")
live:keyEvent("A", false)
live:step(1)
eq(readKey(liveBus), nil, "live repeat ends on release")
print("PASS live typematic excludes time before key press")
local s, b = new()
s:keyEvent("A", true)
eq(readKey(b), 0x1e61, "initial A")
s:keyEvent("LeftShift", true)
s:step(0.31)
eq(readKey(b), 0x1e41, "repeat reflects shift")
s:keyEvent("LeftShift", false)
s:keyEvent("A", false)
s:keyEvent("CapsLock", true)
s:step(1)
eq(readKey(b), nil, "modifier no repeat")
s:keyEvent("CapsLock", false)
s:keyEvent("B", true)
eq(readKey(b), 0x3042, "caps letter")
s:releaseAll()
s:step(1)
eq(readKey(b), nil, "focus release stops repeat")
print("PASS modifiers, current ASCII and releaseAll")
s, b = new()
s:keyEvent("A", true)
s:step(10)
eq(readKey(b), 0x1e61, "pending original")
eq(readKey(b), nil, "no BIOS backlog")
local pending = #s.scanQueue
s:step(0.1)
eq(readKey(b), 0x1e61, "one repeat after consumption")
eq(#s.scanQueue, pending + 1, "one queued make")
for _ = 1, 30 do
	s:step(0.06)
end
eq(readKey(b), 0x1e61, "at most one queued BIOS repeat")
eq(readKey(b), nil, "ring does not fill")
s:releaseAll()
s, b = new()
s:keyEvent("A", true)
readKey(b)
for _ = 1, 16 do
	table.insert(s.scanQueue, 1)
end
s:step(0.31)
eq(readKey(b), nil, "scancode backlog cap")
print("PASS repeat avoids keyboard and scan backlogs")
local audio: any = { speakerActive = true, update = function() end }
s, b = new({ audio = audio, frameBudgetSeconds = 1 })
s.interactive = true
s.ticks = 3
s:step(0.01)
eq(s.effectiveIPS, 364130, "active speaker Turbo pacing")
audio.speakerActive = false
s:step(0.01)
eq(s.effectiveIPS, 3500000, "Turbo restored")
s:setSpeedPreset("386")
audio.speakerActive = true
s:step(0.01)
eq(s.effectiveIPS, 2519145, "fixed preset unaffected")
local custom: any = new({ audio = audio, frameBudgetSeconds = 1, instructionsPerSecond = 1000000 })
custom.interactive = true
custom.ticks = 3
custom:step(0.01)
eq(custom.effectiveIPS, 1000000, "custom IPS unaffected")
print("PASS Turbo speaker pacing and preset isolation")
