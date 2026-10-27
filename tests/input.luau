--!strict
local CPU = require("../runtime/CPUState")
local Bus = require("../runtime/Bus")
local Scheduler = require("../runtime/InputAndScheduler")
local Router = require("../runtime/VirtualInputRouter")
local count = 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, name .. ": " .. tostring(err))
	count += 1
	print("PASS", name)
end
local function fixture(): (any, any, any, any, any)
	local cpu: any = CPU.new()
	local bus: any = Bus.new()
	cpu.flags = 0
	local dispatcher: any = {
		run = function(_self: any, _cpu: any, _bus: any, _budget: number, _deadline: number)
			return 0
		end,
	}
	local scheduler: any = Scheduler.new(cpu, bus, dispatcher, { headless = true, frameBudgetSeconds = 1 })
	local hle: any =
		{ mouseX = 0, mouseY = 0, mouseButtons = 0, mouseMinX = 0, mouseMaxX = 639, mouseMinY = 0, mouseMaxY = 199 }
	local context: any = { regions = {}, choices = {}, menu = false, continuePrompt = false }
	local video: any = {
		getInputContext = function()
			return context
		end,
	}
	local router: any = Router.new(
		{ cpu = cpu, bus = bus, scheduler = scheduler, video = video, hle = hle },
		{ headless = true }
	)
	return router, scheduler, bus, hle, context
end
local function flush(router: any)
	router:update(0)
end
local function pop(bus: any): number?
	local head = bus:read16(0x41a)
	local tail = bus:read16(0x41c)
	if head == tail then
		return nil
	end
	local value = bus:read16(0x400 + head)
	head += 2
	if head >= 0x3e then
		head = 0x1e
	end
	bus:write16(0x41a, head)
	return value
end
check("menu hit test sends digit and enter; non-menu tap sends space", function()
	local r, _, b, _, ctx = fixture()
	ctx.menu = true
	ctx.regions = { { x = 0.2, y = 0.2, width = 0.3, height = 0.1, digit = 3 } }
	r:update(0)
	r:tap(0.25, 0.25)
	flush(r)
	assert(pop(b) == 0x0433)
	assert(pop(b) == 0x1c0d)
	r:tap(0.9, 0.9)
	flush(r)
	assert(pop(b) == nil)
	ctx.menu = false
	r:update(0)
	r:tap(0.9, 0.9)
	flush(r)
	assert(pop(b) == 0x3920)
	ctx.menu = true
	ctx.continuePrompt = true
	r:update(0)
	r:tap(0.9, 0.9)
	flush(r)
	assert(pop(b) == 0x3920)
end)
check("independent diagonal sources release without stealing holds", function()
	local r, s = fixture()
	r:setDirection("touch", 1, -1)
	r:setDirection("stick", 1, 1)
	assert(s.held.Right and s.held.Up and s.held.Down)
	r:setDirection("touch", 0, 0)
	assert(s.held.Right and not s.held.Up and s.held.Down)
	r:setDirection("stick", 0, 0)
	assert(not s.held.Right and not s.held.Down)
end)
check("native text survives BIOS buffer backpressure and normalizes CRLF", function()
	local r, _, b = fixture()
	local text = "abcdefghijklmnopqrstuvwxyz0123456789"
	r:typeText(text .. "\r\n", true)
	flush(r)
	assert(#r.queue > 0)
	local result = ""
	for _ = 1, #text + 1 do
		local word = pop(b)
		assert(word ~= nil)
		result ..= string.char((word :: number) % 256)
		flush(r)
	end
	assert(result == text .. "\r" and #r.queue == 0)
end)
check("pointer updates clamped coordinates and releases touch button", function()
	local r, _, _, h = fixture()
	r:pointerDown("a", -0.2, 1.3, true)
	assert(h.mouseX == 0 and h.mouseY == 199 and h.mouseButtons == 1)
	r:pointerMove("a", 2, -1)
	assert(h.mouseX == 639 and h.mouseY == 0)
	r:pointerUp("a", 2, -1)
	assert(h.mouseButtons == 0)
	h.mouseMinX = 10
	h.mouseMaxX = 30
	h.mouseMinY = 20
	h.mouseMaxY = 40
	r:mouse(1, 0)
	assert(h.mouseX == 30 and h.mouseY == 20)
end)
check("gamepad shoulders wrap and buttons emit mapped keys", function()
	local r, _, b, _, ctx = fixture()
	r.machine.cpu.waitingForKey = true
	ctx.menu = true
	ctx.choices = { 2, 4 }
	ctx.regions = { { digit = 2 }, { digit = 4 } }
	r:update(0)
	r:gamepadButton("ButtonL1", true)
	r:gamepadButton("ButtonR1", true)
	r:gamepadButton("ButtonA", true)
	r:gamepadButton("ButtonB", true)
	flush(r)
	assert(
		pop(b) == 0x0534
			and pop(b) == 0x1c0d
			and pop(b) == 0x0332
			and pop(b) == 0x1c0d
			and pop(b) == 0x0332
			and pop(b) == 0x1c0d
			and pop(b) == 0x1c0d
	)
	r.machine.cpu.waitingForKey = false
	r:gamepadAxis("Thumbstick1", 0.5, 0.5)
	assert(r.held.Right == 1 and r.held.Up == 1)
	r:releaseAll()
	assert(r.held.Right == nil)
end)
check("interactive calibration then wall clock turbo", function()
	local _, s, b = fixture()
	s.options.headless = false
	s.interactive = true
	s:step(1)
	assert(s.ticks == 3 and s.executedInstructions == 60000 and not b.fastRepEnabled)
	s:step(1)
	assert(b.fastRepEnabled and b.clockCheckInterval == 512 and s.executedInstructions == 310000 and s.ticks == 21)
	s:step(0.5)
	assert(s.ticks == 30 and s.pendingTimer == 30)
end)
check("headless and deterministic execution never enable turbo", function()
	for _, opts in ipairs({
		{ headless = true, frameBudgetSeconds = 1 },
		{ deterministic = true, frameBudgetSeconds = 1 },
	}) do
		local cpu: any = CPU.new()
		cpu.flags = 0
		local bus: any = Bus.new()
		local d: any = {
			run = function(_s: any, _c: any, _b: any, _n: number)
				return 0
			end,
		}
		local s: any = Scheduler.new(cpu, bus, d, opts)
		s.interactive = true
		s:step(1)
		assert(s.ticks == 5 and s.executedInstructions == 100000 and not bus.fastRepEnabled)
	end
end)
check("context recognition only on demand and refreshed after screen changes", function()
	local r, _, b, _, ctx = fixture()
	local reads = 0
	r.video.getInputContext = function()
		reads += 1
		return ctx
	end
	for _ = 1, 20 do
		r:update(0.016)
	end
	assert(reads == 0)
	r.machine.cpu.waitingForKey = true
	r:update(0)
	assert(reads == 1)
	r.machine.cpu.waitingForKey = false
	ctx.menu = true
	ctx.regions = { { x = 0, y = 0, width = 1, height = 1, digit = 2 } }
	r:tap(0.5, 0.5)
	assert(reads == 2)
	flush(r)
	assert(pop(b) == 0x0332 and pop(b) == 0x1c0d)
	ctx.regions = {}
	ctx.menu = false
	r:tap(0.5, 0.5)
	assert(reads == 3)
	flush(r)
	assert(pop(b) == 0x3920)
	ctx.menu = true
	ctx.choices = { 4 }
	ctx.regions = { { digit = 4 } }
	r.machine.cpu.waitingForKey = true
	r:gamepadButton("ButtonR1", true)
	assert(reads == 4)
	flush(r)
	assert(pop(b) == 0x0534 and pop(b) == 0x1c0d)
	assert(r:getContext() == ctx and reads == 6)
end)
check("screen pointer coordinates account for GUI inset", function()
	local r, _, b, _, ctx = fixture()
	r.hud = { imageLabel = { AbsolutePosition = { X = 0, Y = -58 }, AbsoluteSize = { X = 1178, Y = 630 } } }
	local service = {
		GetGuiInset = function()
			return { X = 0, Y = 58 }
		end,
	}
	local x, y = r:normalizePosition({ X = 400, Y = 207 }, service)
	assert(math.abs(x - 400 / 1178) < 0.000001 and math.abs(y - 265 / 630) < 0.000001)
	ctx.menu = true
	ctx.regions = {
		{ x = 0.3, y = 0.4, width = 0.2, height = 0.05, digit = 1 },
		{
			x = 0.3,
			y = 0.5,
			width = 0.2,
			height = 0.05,
			digit = 3,
		},
	}
	r.hud = nil
	r:tap(x, y)
	flush(r)
	assert(pop(b) == 0x0231 and pop(b) == 0x1c0d)
end)
check("last input type gates touch overlays and releases touch holds", function()
	local r, s, _, h = fixture()
	local mode = false
	local ring = false
	local hud = {
		bind = function() end,
		setTouchMode = function(_, v)
			mode = v
		end,
		setThumb = function(_, v)
			ring = v
		end,
	}
	r:attach(hud)
	r:setInputType("MouseMovement")
	assert(not mode)
	r:setInputType("Touch")
	assert(mode)
	r:pointerDown("finger", 0.2, 0.2, true)
	r:pointerMove("finger", 0.4, 0.2)
	assert(s.held.Right and ring and h.mouseButtons == 1)
	r:setHeld("physical", "Right", true)
	r:setInputType("Keyboard")
	assert(not mode and not ring and s.held.Right and h.mouseButtons == 0)
	r:setHeld("physical", "Right", false)
	assert(not s.held.Right)
	r:setInputType("Gamepad1")
	assert(not mode)
	r:setInputType("Touch")
	assert(mode)
end)
check("processed keyboard still reaches DOS unless a textbox is focused", function()
	local function signal(): any
		local listeners: { any } = {}
		return {
			Connect = function(_self: any, callback: any)
				table.insert(listeners, callback)
				return { Disconnect = function() end }
			end,
			fire = function(_self: any, ...: any)
				for _, fn in ipairs(listeners) do
					fn(...)
				end
			end,
		}
	end
	local r, s, b = fixture()
	local focused: any = nil
	local input: any = {
		InputBegan = signal(),
		InputEnded = signal(),
		InputChanged = signal(),
		WindowFocusReleased = signal(),
		GamepadDisconnected = signal(),
		LastInputTypeChanged = signal(),
		GetLastInputType = function()
			return { Name = "Keyboard" }
		end,
		GetFocusedTextBox = function()
			return focused
		end,
	}
	r.options.headless = false
	r.options.inputService = input
	r.options.guiService = {}
	r:start()
	local period = { UserInputType = { Name = "Keyboard" }, KeyCode = { Name = "Period" } }
	input.InputBegan:fire(period, true)
	assert(s.held.Period and pop(b) == 0x342e)
	focused = {}
	input.InputEnded:fire(period)
	assert(not s.held.Period)
	input.InputBegan:fire(period, true)
	assert(pop(b) == nil and not s.held.Period)
	local button = { UserInputType = { Name = "Gamepad1" }, KeyCode = { Name = "ButtonA" } }
	input.InputBegan:fire(button, true)
	assert(#r.queue == 0)
	focused = nil
	input.InputBegan:fire(button, true)
	assert(#r.queue == 1 and r.queue[1][2] == 32)
	r:stop()
end)
check("real video defaults are passthrough and avoid OCR", function()
	local r, s, b, h, ctx = fixture()
	local reads = 0
	local video: any = setmetatable({
		bus = b,
		getInputContext = function()
			reads += 1
			return ctx
		end,
	}, {})
	local real: any = Router.new(
		{ cpu = r.machine.cpu, bus = b, scheduler = s, video = video, hle = h },
		{ headless = true }
	)
	ctx.menu = true
	ctx.choices = { 1, 2 }
	ctx.regions = {
		{ x = 0, y = 0, width = 0.5, height = 0.5, digit = 1 },
		{ x = 0.5, y = 0, width = 0.5, height = 0.5, digit = 2 },
	}
	for _ = 1, 10 do
		real:update(0.016)
	end
	real:tap(0.2, 0.2)
	real:gamepadButton("ButtonA", true)
	real:gamepadButton("DPadDown", true)
	assert(reads == 0 and #real.queue == 1 and real.queue[1][2] == 32 and h.mouseButtons == 0 and s.held.Down)
	real:gamepadButton("DPadDown", false)
	real.queue = {}
	real:setMenuAssist(true)
	real.machine.cpu.waitingForKey = true
	real:setInputType("Gamepad1")
	local shown: any = nil
	real.hud = {
		setMenuHighlight = function(_, region: any, visible: boolean)
			shown = if visible then region else nil
		end,
		setQuickBarEnabled = function() end,
		setWaiting = function() end,
	}
	real:gamepadButton("DPadDown", true)
	assert(not s.held.Down and shown.digit == 2)
	real:gamepadButton("ButtonA", true)
	assert(real.queue[1][2] == 50 and real.queue[2][2] == 13)
	ctx.regions = {}
	ctx.choices = {}
	ctx.menu = false
	real.machine.cpu.waitingForKey = true
	real:update(0)
	assert(shown == nil)
	real:setMenuAssist(false)
	assert(shown == nil)
end)
check("explicit false overrides legacy mocks and touch thumbstick may be disabled", function()
	local r, s, b, h, ctx = fixture()
	local legacy: any = r.video
	local rr: any = Router.new(
		{ cpu = r.machine.cpu, scheduler = s, bus = b, video = legacy, hle = h },
		{ headless = true, smartMenuClick = false, tapToContinue = false, touchThumbstick = false }
	)
	ctx.menu = true
	ctx.regions = { { x = 0, y = 0, width = 1, height = 1, digit = 1 } }
	rr:tap(0.5, 0.5)
	assert(#rr.queue == 0)
	rr:pointerDown("finger", 0.2, 0.2, true)
	rr:pointerMove("finger", 0.5, 0.2)
	assert(not s.held.Right and h.mouseX > 0)
	rr:pointerUp("finger", 0.5, 0.2)
end)
check("force off suppresses touch thumbstick while preserving mouse", function()
	local r, s, _, h = fixture()
	local shown: any = nil
	local hud: any = {
		bind = function() end,
		setTouchMode = function(_, v: boolean)
			shown = v
		end,
		setThumb = function() end,
		setQuickBarEnabled = function() end,
	}
	r:attach(hud)
	r:setTouchControls("off")
	r:setInputType("Touch")
	assert(shown == false)
	r:pointerDown("finger", 0.2, 0.2, true)
	r:pointerMove("finger", 0.45, 0.2)
	assert(not s.held.Right and h.mouseButtons == 1 and h.mouseX > 0)
	r:pointerUp("finger", 0.45, 0.2)
	r:setTouchControls("on")
	r:pointerDown("other", 0.2, 0.2, true)
	r:pointerMove("other", 0.45, 0.2)
	assert(s.held.Right)
	r:pointerUp("other", 0.45, 0.2)
	assert(not s.held.Right)
end)
local function menuFixture(): (any, any, any, any, any)
	local r, s, b, _, ctx = fixture()
	r.machine.cpu.waitingForKey = true
	ctx.menu = true
	ctx.kind = "prompt"
	ctx.choices = { 1, 3, 5, 7 }
	ctx.regions = {
		{ digit = 1, x = 0.2, y = 0.2, width = 0.5, height = 0.08 },
		{ digit = 3, x = 0.2, y = 0.3, width = 0.5, height = 0.08 },
		{ digit = 7, x = 0.2, y = 0.4, width = 0.5, height = 0.08 },
	}
	local shown: any = { region = nil }
	r.hud = {
		setMenuHighlight = function(_, region: any, visible: boolean)
			shown.region = if visible then region else nil
		end,
		setThumb = function() end,
		setWaiting = function() end,
	}
	r:setInputType("Keyboard")
	return r, s, b, ctx, shown
end
check("mouse hover shares filtered choices and clears stale regions", function()
	local r, _, _, ctx, shown = menuFixture()
	assert(table.concat(r:getAvailableChoices(ctx), ",") == "1,3,7")
	r:pointerMove("mouse", 0.4, 0.33)
	assert(r.hoveredDigit == 3 and r.selected == 2 and shown.region.digit == 3)
	r:pointerMove("mouse", 0.9, 0.9)
	assert(r.hoveredDigit == nil and shown.region == nil)
	r:pointerMove("mouse", 0.4, 0.33)
	ctx.choices = { 1, 7 }
	r:updateMenuHighlight(ctx)
	assert(r.hoveredDigit == nil and shown.region == nil)
	ctx.choices = { 1, 3, 5, 7 }
	r:pointerMove("mouse", 0.4, 0.33)
	ctx.regions[2].y = 0.6
	r:updateMenuHighlight(ctx)
	assert(r.hoveredDigit == nil and shown.region == nil)
	r.machine.cpu.waitingForKey = false
	r:pointerMove("mouse", 0.4, 0.22)
	assert(shown.region == nil)
end)
check("keyboard selector wraps, confirms once, and manual keypad input takes over", function()
	local r, s, b, _, shown = menuFixture()
	r:keyboardEvent("Down", true)
	r:keyboardEvent("Down", false)
	assert(r.menuNavActive and r.selected == 1 and shown.region.digit == 1)
	assert(not s.held.Down and pop(b) == nil)
	r:keyboardEvent("Up", true)
	r:keyboardEvent("Up", false)
	assert(r.selected == 3 and shown.region.digit == 7)
	r:keyboardEvent("Right", true)
	r:keyboardEvent("Right", false)
	assert(r.selected == 1)
	r:keyboardEvent("KeypadEnter", true)
	r:keyboardEvent("KeypadEnter", false)
	assert(not r.menuNavActive and shown.region == nil and #r.queue == 2)
	flush(r)
	assert(pop(b) == 0x0231 and pop(b) == 0x1c0d and pop(b) == nil)
	r.machine.cpu.waitingForKey = true
	r:keyboardEvent("Down", true)
	r:keyboardEvent("Down", false)
	r:keyboardEvent("KeypadSeven", true)
	r:keyboardEvent("KeypadSeven", false)
	r:keyboardEvent("Return", true)
	r:keyboardEvent("Return", false)
	assert(not r.menuNavActive and #r.queue == 0)
	assert(pop(b) == 0x0837 and pop(b) == 0x1c0d and pop(b) == nil)
end)
check("hover and keyboard hand off, navigation resets on gameplay and assist disable", function()
	local r, s, b, ctx, shown = menuFixture()
	r:pointerMove("mouse", 0.4, 0.33)
	r:keyboardEvent("Down", true)
	r:keyboardEvent("Down", false)
	assert(r.selected == 3 and r.menuNavActive and r.hoveredDigit == nil and shown.region.digit == 7)
	r:pointerMove("mouse", 0.4, 0.22)
	assert(not r.menuNavActive and r.selected == 1 and shown.region.digit == 1)
	r:keyboardEvent("Left", true)
	r:keyboardEvent("Left", false)
	ctx.kind = "gameplay"
	r:update(0)
	assert(not r.menuNavActive and r.hoveredDigit == nil and shown.region == nil)
	r:keyboardEvent("Left", true)
	assert(s.held.Left and pop(b) == 0x4b00)
	r:keyboardEvent("Left", false)
	ctx.kind = "prompt"
	r.machine.cpu.waitingForKey = true
	r:keyboardEvent("Down", true)
	r:keyboardEvent("Down", false)
	r:setMenuAssist(false)
	assert(not r.menuNavActive and shown.region == nil)
	r:keyboardEvent("Up", true)
	assert(s.held.Up and pop(b) == 0x4800)
	r:keyboardEvent("Up", false)
end)
check("left stick menu navigation is edge triggered with neutral hysteresis", function()
	local r, s, b, ctx, shown = menuFixture()
	r:setInputType("Gamepad1")
	r:gamepadAxis("Thumbstick1", 0, -0.8)
	assert(r.selected == 2 and shown.region.digit == 3)
	for _ = 1, 20 do
		r:gamepadAxis("Thumbstick1", 0.8, -0.9)
	end
	assert(r.selected == 2 and not s.held.Down and not s.held.Right and pop(b) == nil)
	r:gamepadAxis("Thumbstick1", 0, -0.4)
	r:gamepadAxis("Thumbstick1", 0, -0.8)
	assert(r.selected == 2)
	r:gamepadAxis("Thumbstick1", 0, 0.2)
	r:gamepadAxis("Thumbstick1", 0, -0.8)
	assert(r.selected == 3)
	r:gamepadAxis("Thumbstick1", 0, 0.8)
	assert(r.selected == 2)
	r:gamepadButton("ButtonA", true)
	assert(r.queue[1][2] == 51 and r.queue[2][2] == 13)
	r.queue = {}
	ctx.menu = false
	r.machine.cpu.waitingForKey = false
	r:gamepadAxis("Thumbstick1", 0.8, -0.8)
	assert(r.stickMenuDir == 0 and s.held.Down and s.held.Right)
	r:gamepadAxis("Thumbstick1", 0, 0)
	assert(not s.held.Down and not s.held.Right)
	r.machine.cpu.waitingForKey = true
	ctx.menu = true
	ctx.regions = {}
	r:update(0)
	assert(not r.menuNavActive and shown.region == nil)
end)
print("input tests passed:", count)
