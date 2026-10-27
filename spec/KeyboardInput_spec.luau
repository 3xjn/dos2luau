--!strict
local Keyboard = require("../runtime/KeyboardInput")
local CPU = require("../runtime/CPUState")
local Bus = require("../runtime/Bus")
local Scheduler = require("../runtime/InputAndScheduler")
local Router = require("../runtime/VirtualInputRouter")
local function signal(): any
	local listeners: { [any]: any } = {}
	return {
		Connect = function(_, callback: any)
			local key = {}
			listeners[key] = callback
			return {
				Disconnect = function()
					listeners[key] = nil
				end,
			}
		end,
		fire = function()
			for _, callback in pairs(listeners) do
				callback()
			end
		end,
	}
end
local focused: any = nil
local pressed: { any } = {}
local input: any = {
	GetFocusedTextBox = function()
		return focused
	end,
	GetKeysPressed = function()
		return pressed
	end,
	TextBoxFocused = signal(),
	TextBoxFocusReleased = signal(),
	WindowFocused = signal(),
	WindowFocusReleased = signal(),
}
local function fixture(): (any, any, any, any)
	local cpu = CPU.new()
	cpu.flags = 0
	local bus = Bus.new()
	local scheduler = Scheduler.new(cpu, bus, {
		run = function(_, _, _, budget)
			return budget
		end,
	}, { headless = true })
	local router = Router.new({ cpu = cpu, bus = bus, scheduler = scheduler }, { headless = true })
	local bridge = Keyboard.new(input, function(name: string, down: boolean)
		router:keyboardEvent(name, down)
	end)
	bridge:start()
	return bridge, router, scheduler, bus
end
local function words(bus: any): string
	local result = ""
	local head, tail = bus:read16(0x41a), bus:read16(0x41c)
	if head == 0 then
		return result
	end
	while head ~= tail do
		result ..= string.char(bus:read16(0x400 + head) % 256)
		head += 2
		if head >= 0x3e then
			head = 0x1e
		end
	end
	return result
end
local bridge, router, scheduler, bus = fixture()
-- Exact physical trace captured in Studio: I/O ended, A began + ended.
bridge:ended("I")
bridge:ended("O")
bridge:began("A")
bridge:ended("A")
assert(words(bus) == "ioa" and #scheduler.scanQueue == 6)
assert(not scheduler.held.I and not scheduler.held.O)
assert((router.held.I or 0) == 0 and (router.held.O or 0) == 0)
bridge:began("I")
bridge:ended("I")
bridge:began("O")
bridge:ended("O")
assert(words(bus) == "ioaio", "normal I/O are not duplicated by recovery")
bridge:ended("B")
assert(words(bus) == "ioaio", "unrelated orphan releases do not synthesize characters")
bridge:began("LeftShift")
bridge:ended("I")
bridge:ended("LeftShift")
assert(words(bus) == "ioaioI", "recovery uses real modifier/scancode mapping")
bridge:destroy()
print("PASS physical orphan I/O trace and normal events produce exactly one character each")

bridge, router, scheduler, bus = fixture()
focused = {}
bridge:ended("I")
bridge:began("O")
focused = nil
bridge:ended("O")
assert(words(bus) == "", "ignored textbox begin stays ignored after focus changes")
focused = {}
pressed = { { KeyCode = { Name = "I" } } }
input.TextBoxFocusReleased.fire()
focused = nil
pressed = {}
bridge:ended("I")
assert(words(bus) == "", "missing begin while leaving textbox does not leak into DOS")
bridge:ended("I")
assert(words(bus) == "i", "next physical press is recoverable")
bridge:destroy()
print("PASS focused textboxes and focus transitions do not leak recovered keys")

bridge, router, scheduler, bus = fixture()
input.WindowFocusReleased.fire()
bridge:ended("I")
assert(words(bus) == "", "inactive window does not recover keys")
pressed = { { KeyCode = { Name = "O" } } }
input.WindowFocused.fire()
pressed = {}
bridge:ended("O")
assert(words(bus) == "", "key held across window focus is ignored until released")
bridge:ended("O")
assert(words(bus) == "o")
router.keyboardInput = bridge
router:setSuspended(true)
bridge:ended("I")
assert(words(bus) == "o", "settings modal suspends recovery")
pressed = { { KeyCode = { Name = "I" } } }
router:setSuspended(false)
pressed = {}
bridge:ended("I")
assert(words(bus) == "o", "key held across modal close stays suppressed")
bridge:ended("I")
assert(words(bus) == "oi")
bridge:destroy()
print("PASS window focus and modal transitions guard missing key-down recovery")

bridge, router, scheduler, bus = fixture()
router.keyboardInput = bridge
pressed = { { KeyCode = { Name = "I" } } }
bridge:poll()
bridge:poll()
assert(words(bus) == "i" and scheduler.repeatKey == "I", "held missing begin is recovered once")
bus:write16(0x41a, bus:read16(0x41c))
scheduler:step(0.31)
assert(words(bus) == "i", "recovered held I uses normal typematic")
pressed = {}
bridge:ended("I")
bus:write16(0x41a, bus:read16(0x41c))
scheduler:step(1)
assert(words(bus) == "" and scheduler.repeatKey == nil, "release stops recovered hold without duplication")
bridge:destroy()
print("PASS suppressed camera key-down supports held-state recovery and typematic")

bridge, router, scheduler, bus = fixture()
bridge:began("A")
pressed = {}
bridge:poll()
assert(scheduler.repeatKey == nil, "actual released state cancels delayed key-up repeat")
bridge:ended("A")
bridge:began("I")
pressed = { { KeyCode = { Name = "I" } } }
bridge:poll()
pressed = {}
bridge:poll()
bridge:ended("I")
assert(words(bus) == "ai", "late I key-up must not repeat a polled release")
bridge:destroy()
print("PASS delayed key-up reconciliation stops repeat without duplicating I/O")
