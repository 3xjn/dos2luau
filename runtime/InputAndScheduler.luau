--!strict
local Interpreter = require(script.Parent.Interpreter)
local KeyboardInput = require(script.Parent.KeyboardInput)
-- IPS estimates share an approximate 4.77 MHz / 364130 IPS ratio; these are
-- workload pacing presets, not cycle-accurate CPU models.
local PRESET_IPS = { turbo = 3500000, xt = 364130, ["286"] = 916050, ["386"] = 2519145 }
local Scheduler = {}
Scheduler.__index = Scheduler
local keys: { [string]: { number } } = {
	Escape = { 1, 27 },
	One = { 2, 49, 33 },
	Two = { 3, 50, 64 },
	Three = { 4, 51, 35 },
	Four = { 5, 52, 36 },
	Five = { 6, 53, 37 },
	Six = { 7, 54, 94 },
	Seven = { 8, 55, 38 },
	Eight = { 9, 56, 42 },
	Nine = { 10, 57, 40 },
	Zero = { 11, 48, 41 },
	Minus = { 12, 45, 95 },
	Equals = { 13, 61, 43 },
	Backspace = { 14, 8 },
	Tab = { 15, 9 },
	Q = { 16, 113 },
	W = { 17, 119 },
	E = { 18, 101 },
	R = { 19, 114 },
	T = { 20, 116 },
	Y = { 21, 121 },
	U = { 22, 117 },
	I = { 23, 105 },
	O = { 24, 111 },
	P = { 25, 112 },
	LeftBracket = { 26, 91, 123 },
	RightBracket = { 27, 93, 125 },
	Return = { 28, 13 },
	Enter = { 28, 13 },
	LeftControl = { 29, 0 },
	RightControl = { 29, 0 },
	A = { 30, 97 },
	S = { 31, 115 },
	D = { 32, 100 },
	F = { 33, 102 },
	G = { 34, 103 },
	H = { 35, 104 },
	J = { 36, 106 },
	K = { 37, 107 },
	L = { 38, 108 },
	Semicolon = { 39, 59, 58 },
	Quote = { 40, 39, 34 },
	Backquote = { 41, 96, 126 },
	LeftShift = { 42, 0 },
	BackSlash = { 43, 92, 124 },
	Z = { 44, 122 },
	X = { 45, 120 },
	C = { 46, 99 },
	V = { 47, 118 },
	B = { 48, 98 },
	N = { 49, 110 },
	M = { 50, 109 },
	Comma = { 51, 44, 60 },
	Period = { 52, 46, 62 },
	Slash = { 53, 47, 63 },
	RightShift = { 54, 0 },
	LeftAlt = { 56, 0 },
	RightAlt = { 56, 0 },
	Space = { 57, 32 },
	CapsLock = { 58, 0 },
	F1 = { 59, 0 },
	F2 = { 60, 0 },
	F3 = { 61, 0 },
	F4 = { 62, 0 },
	F5 = { 63, 0 },
	F6 = { 64, 0 },
	F7 = { 65, 0 },
	F8 = { 66, 0 },
	F9 = { 67, 0 },
	F10 = { 68, 0 },
	Home = { 71, 0 },
	Up = { 72, 0 },
	PageUp = { 73, 0 },
	Left = { 75, 0 },
	Right = { 77, 0 },
	End = { 79, 0 },
	Down = { 80, 0 },
	PageDown = { 81, 0 },
	Insert = { 82, 0 },
	Delete = { 83, 0 },
	F11 = { 87, 0 },
	F12 = { 88, 0 },
}
function Scheduler.new(cpu: any, bus: any, dispatcher: any, options: any): any
	options = options or {}
	local self: any = setmetatable({
		cpu = cpu,
		bus = bus,
		dispatcher = dispatcher,
		options = options,
		audio = options.audio,
		video = options.video,
		speedPreset = "turbo",
		speedExplicit = false,
		credit = 0,
		tickCount = 0,
		executedInstructions = 0,
		ticks = 0,
		pendingTimer = 0,
		pendingKeyboard = 0,
		scanQueue = {},
		held = {},
		repeatKey = nil,
		repeatTimer = 0,
		repeatDelay = 0.30,
		repeatInterval = 0.055,
		repeatClock = options.repeatClock or os.clock,
		repeatSampleAt = nil,
		caps = false,
		connections = {},
	}, Scheduler)
	bus:registerPortHandler(0x60, function()
		return table.remove(self.scanQueue, 1) or 0
	end, nil)
	if options.speedPreset ~= nil then
		self:setSpeedPreset(options.speedPreset)
	end
	return self
end
function Scheduler.setSpeedPreset(self: any, name: string)
	assert(PRESET_IPS[name] ~= nil, "Unknown speed preset: " .. tostring(name))
	self.speedPreset = name
	self.speedExplicit = true
end
local function isModifier(name: string): boolean
	return name == "CapsLock"
		or name == "LeftShift"
		or name == "RightShift"
		or name == "LeftControl"
		or name == "RightControl"
		or name == "LeftAlt"
		or name == "RightAlt"
end
function Scheduler.computeKeyWord(self: any, name: string): (number, number)
	local k = keys[name]
	local ascii = k[2] or 0
	local shift = self.held.LeftShift or self.held.RightShift
	local ctrl = self.held.LeftControl or self.held.RightControl
	local alt = self.held.LeftAlt or self.held.RightAlt
	if ascii >= 97 and ascii <= 122 then
		if ctrl then
			ascii -= 96
		elseif (shift and not self.caps) or (self.caps and not shift) then
			ascii -= 32
		end
	elseif shift and k[3] then
		ascii = k[3]
	end
	if alt then
		ascii = 0
	end
	return k[1], ascii
end
function Scheduler.keyEvent(self: any, name: string, down: boolean)
	local k = keys[name]
	if not k then
		return
	end
	if down and self.held[name] then
		return
	end
	if not down and not self.held[name] then
		return
	end
	self.held[name] = if down then true else nil
	if down and name == "CapsLock" then
		self.caps = not self.caps
	end
	local shift = self.held.LeftShift or self.held.RightShift
	local ctrl = self.held.LeftControl or self.held.RightControl
	local alt = self.held.LeftAlt or self.held.RightAlt
	local flags = (if self.held.RightShift then 1 else 0)
		+ (if self.held.LeftShift then 2 else 0)
		+ (if ctrl then 4 else 0)
		+ (if alt then 8 else 0)
		+ (if self.caps then 64 else 0)
	self.bus:write8(0x417, flags)
	if #self.scanQueue < 256 then
		table.insert(self.scanQueue, if down then k[1] else k[1] + 128)
		self.pendingKeyboard += 1
	end
	if not down then
		if self.repeatKey == name then
			self.repeatKey = nil
			self.repeatTimer = 0
			self.repeatSampleAt = nil
		end
		return
	end
	if isModifier(name) then
		return
	end
	self.repeatKey = name
	self.repeatSampleAt = self.repeatClock()
	self.repeatTimer = if name == "Up"
			or name == "Down"
			or name == "Left"
			or name == "Right"
		then 0.16
		else self.repeatDelay
	local scan, ascii = self:computeKeyWord(name)
	self:enqueueWord(scan, ascii, false)
end
function Scheduler.enqueueWord(self: any, scan: number, ascii: number, injectScan: boolean?): boolean
	if injectScan and #self.scanQueue > 254 then
		return false
	end
	local head = self.bus:read16(0x41a)
	local tail = self.bus:read16(0x41c)
	if head < 0x1e or head >= 0x3e or tail < 0x1e or tail >= 0x3e then
		head = 0x1e
		tail = 0x1e
		self.bus:write16(0x41a, head)
		self.bus:write16(0x41c, tail)
	end
	local nextTail = tail + 2
	if nextTail >= 0x3e then
		nextTail = 0x1e
	end
	if nextTail ~= head then
		self.bus:write16(0x400 + tail, scan * 256 + ascii)
		self.bus:write16(0x41c, nextTail)
		self.cpu.waitingForKey = false
		self.cpu.yieldRequested = false
		self.waitReturn = nil
		if injectScan and #self.scanQueue <= 254 then
			table.insert(self.scanQueue, scan)
			table.insert(self.scanQueue, scan + 128)
			self.pendingKeyboard += 2
		end
		return true
	end
	return false
end
function Scheduler.releaseAll(self: any)
	self.repeatKey = nil
	self.repeatTimer = 0
	self.repeatSampleAt = nil
	local held = {}
	for name in pairs(self.held) do
		table.insert(held, name)
	end
	for _, name in ipairs(held) do
		self:keyEvent(name, false)
	end
end
function Scheduler.step(self: any, dt: number)
	dt = math.max(0, dt)
	if self.keyboardInput then
		self.keyboardInput:poll()
	elseif self.inputRouter and self.inputRouter.keyboardInput then
		self.inputRouter.keyboardInput:poll()
	end
	local repeatKey = self.repeatKey
	if repeatKey and self.held[repeatKey] then
		local repeatDt = dt
		if self.interactive and not self.options.headless and not self.options.deterministic then
			local now = self.repeatClock()
			repeatDt = math.min(dt, math.max(0, now - (self.repeatSampleAt or now)))
			self.repeatSampleAt = now
		end
		self.repeatTimer -= repeatDt
		if self.repeatTimer <= 0 then
			self.repeatTimer = math.max(0.01, self.repeatTimer + self.repeatInterval)
			local head = self.bus:read16(0x41a)
			local tail = self.bus:read16(0x41c)
			if head == tail and #self.scanQueue < 16 then
				local scan, ascii = self:computeKeyWord(repeatKey)
				if self:enqueueWord(scan, ascii, false) then
					table.insert(self.scanQueue, scan)
					self.pendingKeyboard += 1
				end
			end
		end
	end
	local c = self.cpu
	local opts = self.options
	local paced = self.interactive == true
		and not opts.headless
		and not opts.deterministic
		and (opts.turboVideo ~= false or self.speedExplicit)
		and self.ticks >= 3
	local turbo = paced and self.speedPreset == "turbo"
	self.bus.fastRepEnabled = turbo
	self.bus.clockCheckInterval = if paced then 512 else 1
	local maxFrame = opts.maxInstructionsPerFrame or (if paced then 250000 else 100000)
	local speed = if paced and self.speedExplicit
		then PRESET_IPS[self.speedPreset]
		else opts.instructionsPerSecond or (if paced then PRESET_IPS[self.speedPreset] else 364130)
	if turbo and self.audio and self.audio.speakerActive and (self.speedExplicit or not opts.instructionsPerSecond) then
		speed = math.min(speed, PRESET_IPS.xt)
	end
	self.effectiveIPS = speed
	self.credit = math.min(self.credit + dt * speed, maxFrame)
	if paced then
		self.wallTick = (self.wallTick or 0) + dt * 18.2065
		local elapsed = math.floor(self.wallTick)
		self.wallTick -= elapsed
		self.pendingTimer += elapsed
		self.ticks += elapsed
	elseif c.waitingForKey then
		self.waitTick = (self.waitTick or 0) + dt * (364130 / 20000)
		local ticks = math.floor(self.waitTick)
		self.waitTick -= ticks
		self.pendingTimer += ticks
	end
	local budget = math.min(math.floor(self.credit), maxFrame)
	local deadline = os.clock()
		+ (
			opts.frameBudgetSeconds
			or (if self.interactive and not opts.headless and not opts.deterministic then 0.010 else 0.003)
		)
	self.bus.executionDeadline = deadline
	c.yieldRequested = false
	while budget > 0 and os.clock() < deadline do
		if bit32.band(c.flags, 0x200) ~= 0 and (not c.halted or c.exitCode == nil) then
			local vector = nil
			if self.pendingKeyboard > 0 then
				self.pendingKeyboard -= 1
				vector = 9
			elseif self.audio and self.audio.pendingIRQ then
				vector = self.audio.pendingIRQ
				if (self.audio.pendingIRQCount or 0) > 1 then
					self.audio.pendingIRQCount -= 1
				else
					self.audio.pendingIRQCount = 0
					self.audio.pendingIRQ = nil
				end
			elseif self.pendingTimer > 0 then
				self.pendingTimer -= 1
				vector = 8
			end
			if vector then
				if c.waitingForKey then
					self.waitReturn = { cs = c.cs, ip = c.ip, sp = buffer.readu16(c.regs, 8) }
					c.waitingForKey = false
				end
				Interpreter.interrupt(c, self.bus, vector)
			end
		end
		if c.halted or c.waitingForKey or c.yieldRequested then
			break
		end
		local slice =
			math.min(budget, if paced then budget else 20000 - self.tickCount, if self.waitReturn then 1 else budget)
		local remain = self.dispatcher:run(c, self.bus, slice, deadline)
		local used = slice - remain
		if used <= 0 then
			break
		end
		budget -= used
		self.credit -= used
		if not paced then
			self.tickCount += used
		end
		self.executedInstructions += used
		if
			self.waitReturn
			and c.cs == self.waitReturn.cs
			and c.ip == self.waitReturn.ip
			and buffer.readu16(c.regs, 8) == self.waitReturn.sp
		then
			c.waitingForKey = true
			self.waitReturn = nil
		end
		if not paced and self.tickCount >= 20000 then
			self.tickCount -= 20000
			self.pendingTimer += 1
			self.ticks += 1
			if
				self.ticks == 3
				and self.interactive
				and not opts.headless
				and not opts.deterministic
				and (opts.turboVideo ~= false or self.speedExplicit)
			then
				break
			end
		end
	end
	-- Avoid accumulating unbounded catch-up work while the guest is blocked.
	if c.waitingForKey or c.halted then
		self.credit = math.min(self.credit, 1)
	end
	if self.inputRouter then
		self.inputRouter:update(dt)
	end
	if self.audio then
		self.audio:update(dt, c)
	end
	if self.video then
		self.video:present()
	end
end
function Scheduler.handleInputBegan(self: any, obj: any, processed: boolean, input: any)
	local keyboard = obj.UserInputType and obj.UserInputType.Name == "Keyboard"
	if keyboard then
		if not self.keyboardInput then
			self.keyboardInput = KeyboardInput.new(input, function(name: string, down: boolean)
				self:keyEvent(name, down)
			end)
		end
		self.keyboardInput:began(obj.KeyCode.Name)
	elseif not processed then
		self:keyEvent(obj.KeyCode.Name, true)
	end
end
function Scheduler.start(self: any)
	if self.running or self.options.headless then
		return
	end
	self.running = true
	local run = game:GetService("RunService")
	self.interactive = run:IsRunning() and not self.options.deterministic and not self.options.headless
	local input = game:GetService("UserInputService")
	local heartbeat: any = run.Heartbeat:Connect(function(dt: number)
		self:step(dt)
	end)
	if self.options.externalInput then
		table.insert(self.connections, heartbeat)
		return
	end
	self.keyboardInput = KeyboardInput.new(input, function(name: string, down: boolean)
		self:keyEvent(name, down)
	end)
	self.keyboardInput:start()
	local began: any = input.InputBegan:Connect(function(obj: any, processed: boolean)
		self:handleInputBegan(obj, processed, input)
	end)
	local ended: any = input.InputEnded:Connect(function(obj: any)
		if obj.UserInputType.Name == "Keyboard" then
			self.keyboardInput:ended(obj.KeyCode.Name)
		else
			self:keyEvent(obj.KeyCode.Name, false)
		end
	end)
	local focus: any = input.WindowFocusReleased:Connect(function()
		self:releaseAll()
	end)
	table.insert(self.connections, heartbeat)
	table.insert(self.connections, began)
	table.insert(self.connections, ended)
	table.insert(self.connections, focus)
end
function Scheduler.stop(self: any)
	if self.keyboardInput then
		self.keyboardInput:destroy()
		self.keyboardInput = nil
	end
	if self.inputRouter then
		self.inputRouter:releaseAll()
	end
	self.running = false
	self.interactive = false
	self.bus.fastRepEnabled = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self:releaseAll()
end
function Scheduler.destroy(self: any)
	self:stop()
end
return Scheduler
