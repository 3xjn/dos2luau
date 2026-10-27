--!strict
local Router = {}
Router.__index = Router
local scan: { [string]: { number } } = {
	One = { 2, 49 },
	Two = { 3, 50 },
	Three = { 4, 51 },
	Four = { 5, 52 },
	Five = { 6, 53 },
	Six = { 7, 54 },
	Seven = { 8, 55 },
	Eight = { 9, 56 },
	Nine = { 10, 57 },
	Zero = { 11, 48 },
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
	A = { 30, 97 },
	S = { 31, 115 },
	D = { 32, 100 },
	F = { 33, 102 },
	G = { 34, 103 },
	H = { 35, 104 },
	J = { 36, 106 },
	K = { 37, 107 },
	L = { 38, 108 },
	Z = { 44, 122 },
	X = { 45, 120 },
	C = { 46, 99 },
	V = { 47, 118 },
	B = { 48, 98 },
	N = { 49, 110 },
	M = { 50, 109 },
	Space = { 57, 32 },
	Enter = { 28, 13 },
	Return = { 28, 13 },
	Escape = { 1, 27 },
	Backspace = { 14, 8 },
	Tab = { 15, 9 },
	Minus = { 12, 45 },
	Equals = { 13, 61 },
	Comma = { 51, 44 },
	Period = { 52, 46 },
	Slash = { 53, 47 },
	Semicolon = { 39, 59 },
	Quote = { 40, 39 },
	LeftBracket = { 26, 91 },
	RightBracket = { 27, 93 },
	BackSlash = { 43, 92 },
	Backquote = { 41, 96 },
	Up = { 72, 0 },
	Down = { 80, 0 },
	Left = { 75, 0 },
	Right = { 77, 0 },
}
local digits = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
local asciiMap: { [number]: number } = {}
for _, k in pairs(scan) do
	if k[2] ~= 0 then
		asciiMap[k[2]] = k[1]
	end
end
for i = 65, 90 do
	asciiMap[i] = asciiMap[i + 32]
end
local shifted = '!@#$%^&*()_+{}|:"<>?~' -- shifted punctuation uses physical scan codes
local shiftedScans = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 26, 27, 43, 39, 40, 51, 52, 53, 41 }
for i = 1, #shifted do
	asciiMap[string.byte(shifted, i)] = shiftedScans[i]
end
function Router.new(machine: any, options: any): any
	options = options or {}
	local video = machine.video
	local legacy = video ~= nil and getmetatable(video) == nil and video.bus == nil and video.getInputContext ~= nil
	local function flag(name: string): boolean
		if options[name] ~= nil then
			return options[name] == true
		end
		return legacy
	end
	return setmetatable({
		smartMenuClick = flag("smartMenuClick"),
		tapToContinue = flag("tapToContinue"),
		gamepadMenuHighlight = flag("gamepadMenuHighlight"),
		touchQuickBar = flag("touchQuickBar"),
		touchThumbstick = options.touchThumbstick ~= false,
		legacyAssist = legacy,
		machine = machine,
		options = options,
		scheduler = machine.scheduler,
		video = machine.video,
		hle = machine.hle,
		context = { regions = {}, choices = {}, menu = false },
		sources = {},
		held = {},
		queue = {},
		pointers = {},
		connections = {},
		selected = 1,
		mouseX = 0.5,
		mouseY = 0.5,
	}, Router)
end
function Router.attach(self: any, hud: any)
	self.hud = hud
	self.scheduler.inputRouter = self
	self.scheduler.options.externalInput = true
	hud:bind(self)
	if hud.setQuickBarEnabled then
		(hud.setQuickBarEnabled :: any)(hud, self.touchQuickBar)
	end
	if hud.setTouchMode then
		(hud.setTouchMode :: any)(hud, self.touchMode == true)
	end
end
function Router.getContext(self: any): any
	if self.video and self.video.getInputContext then
		self.context = (self.video.getInputContext :: any)(self.video)
	end
	return self.context
end
function Router.pulse(self: any, name: string)
	local k = scan[name]
	if k then
		table.insert(self.queue, { k[1], k[2] })
	end
end
function Router.typeText(self: any, text: string, enter: boolean?)
	local i = 1
	while i <= #text do
		local c = string.byte(text, i)
		if c == 10 or c == 13 then
			table.insert(self.queue, { 28, 13 })
			if c == 13 and string.byte(text, i + 1) == 10 then
				i += 1
			end
		elseif c >= 32 and c <= 126 then
			table.insert(self.queue, { asciiMap[c] or 0, c })
		elseif c >= 128 then
			table.insert(self.queue, { 53, 63 })
			while i < #text and string.byte(text, i + 1) >= 128 and string.byte(text, i + 1) < 192 do
				i += 1
			end
		end
		i += 1
	end
	if enter and string.sub(text, -1) ~= "\n" and string.sub(text, -1) ~= "\r" then
		self:pulse("Enter")
	end
end
function Router.setDirection(self: any, source: string, x: number, y: number)
	local desired: { [string]: boolean } = {}
	if x < -0.35 then
		desired.Left = true
	elseif x > 0.35 then
		desired.Right = true
	end
	if y < -0.35 then
		desired.Up = true
	elseif y > 0.35 then
		desired.Down = true
	end
	local previous = self.sources[source] or {}
	self.sources[source] = desired
	for _, name in ipairs({ "Left", "Right", "Up", "Down" }) do
		local was = previous[name] or false
		local now = desired[name] or false
		if was ~= now then
			local count = self.held[name] or 0
			if now then
				count += 1
				if count == 1 then
					self.scheduler:keyEvent(name, true)
				end
			else
				count = math.max(0, count - 1)
				if count == 0 then
					self.scheduler:keyEvent(name, false)
				end
			end
			self.held[name] = count
		end
	end
end
function Router.setHeld(self: any, source: string, name: string, down: boolean)
	local key = "key:" .. source .. ":" .. name
	local was = self.sources[key] ~= nil
	if was == down then
		return
	end
	self.sources[key] = if down then {} else nil
	local count = self.held[name] or 0
	if down then
		count += 1
		if count == 1 then
			self.scheduler:keyEvent(name, true)
		end
	else
		count = math.max(0, count - 1)
		if count == 0 then
			self.scheduler:keyEvent(name, false)
		end
	end
	self.held[name] = count
end
function Router.mouse(self: any, x: number, y: number, button: number?, down: boolean?)
	self.mouseX = math.clamp(x, 0, 1)
	self.mouseY = math.clamp(y, 0, 1)
	if self.hle then
		self.hle.mouseX =
			math.clamp(math.floor(self.mouseX * 639 + 0.5), self.hle.mouseMinX or 0, self.hle.mouseMaxX or 639)
		self.hle.mouseY =
			math.clamp(math.floor(self.mouseY * 199 + 0.5), self.hle.mouseMinY or 0, self.hle.mouseMaxY or 199)
		if button then
			local mask = if button == 2 then 2 else 1
			local buttons = self.hle.mouseButtons or 0
			self.hle.mouseButtons = if down then bit32.bor(buttons, mask) else bit32.band(buttons, bit32.bnot(mask))
		end
	end
end
function Router.tap(self: any, x: number, y: number, button: number?)
	self:mouse(x, y, button or 1, true)
	self:mouse(x, y, button or 1, false)
	if (button and button ~= 1) or (not self.smartMenuClick and not self.tapToContinue) then
		return
	end
	local context: any = self:getContext()
	for _, item in ipairs(context.regions or {}) do
		local r: any = item
		if
			self.smartMenuClick
			and x >= r.x
			and x <= r.x + r.width
			and y >= r.y
			and y <= r.y + r.height
			and r.digit
			and r.digit >= 1
			and r.digit <= 9
		then
			self:pulse(digits[r.digit])
			self:pulse("Enter")
			return
		end
	end
	if self.tapToContinue and (context.continuePrompt or (self.legacyAssist and not context.menu)) then
		self:pulse("Space")
	end
end
function Router.pointerDown(self: any, id: any, x: number, y: number, isTouch: boolean?)
	self.pointers[id] = { x = x, y = y, lastX = x, lastY = y, touch = isTouch, drag = false }
	self:mouse(x, y, 1, true)
end
function Router.pointerMove(self: any, id: any, x: number, y: number)
	local p = self.pointers[id]
	if not p then
		self:mouse(x, y)
		return
	end
	self:mouse(x, y)
	p.lastX = x
	p.lastY = y
	local dx = x - p.x
	local dy = y - p.y
	if
		self.touchControls ~= "off"
		and self.touchThumbstick
		and p.touch
		and p.x < 0.5
		and (p.drag or dx * dx + dy * dy > 0.0016)
	then
		p.drag = true
		self:setDirection("touch:" .. tostring(id), dx / 0.12, dy / 0.12)
		if self.hud then
			self.hud:setThumb(true, p.x, p.y, dx, dy)
		end
	elseif not p.touch then
		self:mouse(x, y)
	end
end
function Router.pointerUp(self: any, id: any, x: number, y: number)
	local p = self.pointers[id]
	if not p then
		return
	end
	self.pointers[id] = nil
	local otherPointer = next(self.pointers) ~= nil
	self:mouse(x, y, 1, otherPointer)
	if p.drag then
		self:setDirection("touch:" .. tostring(id), 0, 0)
		if self.hud then
			self.hud:setThumb(false, 0, 0, 0, 0)
		end
	else
		if not p.touch then
			self:mouse(x, y, 1, false)
		end
		self:tap(x, y)
		if otherPointer then
			self:mouse(x, y, 1, true)
		end
	end
end
function Router.updateMenuHighlight(self: any, context: any?)
	local c = context or self:getContext()
	local choices = c.choices or {}
	local active = self.gamepadMenuHighlight
		and not self.suspended
		and self.lastInputType
		and string.sub(self.lastInputType, 1, 7) == "Gamepad"
		and c.menu
		and #choices > 0
	if active then
		self.selected = math.clamp(self.selected, 1, #choices)
		local digit = choices[self.selected]
		for _, item in ipairs(c.regions or {}) do
			local region: any = item
			if region.digit == digit then
				if self.hud and self.hud.setMenuHighlight then
					(self.hud.setMenuHighlight :: any)(self.hud, region, true)
				end
				return
			end
		end
	end
	if self.hud and self.hud.setMenuHighlight then
		(self.hud.setMenuHighlight :: any)(self.hud, nil, false)
	end
end
function Router.setMenuAssist(self: any, enabled: boolean)
	self.smartMenuClick = enabled
	self.tapToContinue = enabled
	self.gamepadMenuHighlight = enabled
	self.touchQuickBar = enabled
	if self.hud and self.hud.setQuickBarEnabled then
		(self.hud.setQuickBarEnabled :: any)(self.hud, enabled)
	end
	if enabled then
		self:updateMenuHighlight()
	elseif self.hud and self.hud.setMenuHighlight then
		(self.hud.setMenuHighlight :: any)(self.hud, nil, false)
	end
end
function Router.gamepadButton(self: any, name: string, down: boolean)
	local directions = { DPadLeft = "Left", DPadRight = "Right", DPadUp = "Up", DPadDown = "Down" }
	local menu: any = nil
	if
		self.gamepadMenuHighlight
		and (directions[name] or name == "ButtonA" or name == "ButtonL1" or name == "ButtonR1")
	then
		menu = self:getContext()
	end
	local list: { number } = if menu and menu.menu then menu.choices or {} else {}
	if not self.legacyAssist and #list > 0 then
		local available: { [number]: boolean } = {}
		for _, item in ipairs(menu.regions or {}) do
			local region: any = item
			if region.digit then
				available[region.digit] = true
			end
		end
		local filtered: { number } = {}
		for _, digit in ipairs(list) do
			if available[digit] then
				table.insert(filtered, digit)
			end
		end
		list = filtered
	end
	if directions[name] and #list > 0 then
		if not down then
			self:setHeld("gamepad", directions[name], false)
		end
		if down then
			self.selected = (self.selected - 1 + (if name == "DPadUp" or name == "DPadLeft" then -1 else 1)) % #list + 1
			self:updateMenuHighlight(menu)
		end
		return
	end
	if directions[name] then
		self:setHeld("gamepad", directions[name], down)
		return
	end
	if not down then
		return
	end
	if name == "ButtonA" and #list > 0 then
		local digit = list[math.clamp(self.selected, 1, #list)]
		if digits[digit] then
			self:pulse(digits[digit])
			self:pulse("Enter")
		end
	elseif name == "ButtonA" or name == "ButtonR2" then
		self:pulse("Space")
	elseif name == "ButtonB" then
		self:pulse("Enter")
	elseif name == "ButtonX" then
		self:pulse("Y")
	elseif name == "ButtonSelect" then
		self:pulse("Escape")
	elseif name == "ButtonY" then
		self:requestKeyboard()
	elseif (name == "ButtonL1" or name == "ButtonR1") and #list > 0 then
		self.selected = (self.selected - 1 + (if name == "ButtonL1" then -1 else 1)) % #list + 1
		local digit = list[self.selected]
		if digits[digit] then
			self:pulse(digits[digit])
			self:pulse("Enter")
		end
		self:updateMenuHighlight(menu)
	end
end
function Router.gamepadAxis(self: any, name: string, x: number, y: number)
	if name == "Thumbstick1" then
		self:setDirection("gamepad:stick", x, -y)
	elseif name == "Thumbstick2" then
		self.mouseDX = if math.abs(x) > 0.35 then x else 0
		self.mouseDY = if math.abs(y) > 0.35 then -y else 0
	end
end
function Router.requestKeyboard(self: any)
	self:releaseAll()
	if self.hud then
		self.hud:openKeyboard()
	end
end
function Router.releaseAll(self: any)
	for name, count in pairs(self.held) do
		if count > 0 then
			self.scheduler:keyEvent(name, false)
		end
	end
	self.held = {}
	self.sources = {}
	self.pointers = {}
	self.mouseDX = 0
	self.mouseDY = 0
	if self.hle then
		self.hle.mouseButtons = 0
	end
	if self.hud then
		self.hud:setThumb(false, 0, 0, 0, 0)
	end
end
function Router.update(self: any, dt: number)
	if self.machine.cpu.waitingForKey and (self.smartMenuClick or self.tapToContinue or self.gamepadMenuHighlight) then
		local context = self:getContext()
		if self.gamepadMenuHighlight then
			self:updateMenuHighlight(context)
		end
	end
	if not self.machine.cpu.waitingForKey and self.hud and self.hud.setMenuHighlight then
		(self.hud.setMenuHighlight :: any)(self.hud, nil, false)
	end
	if self.mouseDX or self.mouseDY then
		self:mouse(self.mouseX + (self.mouseDX or 0) * dt * 0.7, self.mouseY + (self.mouseDY or 0) * dt * 0.7)
	end
	while not self.suspended and #self.queue > 0 do
		local k = self.queue[1]
		if not self.scheduler:enqueueWord(k[1], k[2], true) then
			break
		end
		table.remove(self.queue, 1)
		if self.hud then
			self.hud:setWaiting(false)
		end
	end
	if self.hud then
		self.hud:setWaiting(self.machine.cpu.waitingForKey)
	end
end
function Router.normalizePosition(self: any, position: any, _guiService: any): (number, number)
	local gui = self.hud.imageLabel
	return math.clamp((position.X - gui.AbsolutePosition.X) / math.max(1, gui.AbsoluteSize.X), 0, 1),
		math.clamp((position.Y - gui.AbsolutePosition.Y) / math.max(1, gui.AbsoluteSize.Y), 0, 1)
end
function Router.setInputType(self: any, name: string)
	self.lastInputType = name
	if self.gamepadMenuHighlight then
		self:updateMenuHighlight()
	end
	local touch = self.touchControls == "on" or (self.touchControls ~= "off" and name == "Touch")
	if self.touchMode and not touch then
		for id, pointer in pairs(self.pointers) do
			local p: any = pointer
			if p.touch then
				self:setDirection("touch:" .. tostring(id), 0, 0)
				self.pointers[id] = nil
			end
		end
		if self.hle and next(self.pointers) == nil then
			self.hle.mouseButtons = bit32.band(self.hle.mouseButtons or 0, bit32.bnot(1))
		end
		if self.hud then
			self.hud:setThumb(false, 0, 0, 0, 0)
		end
	end
	self.touchMode = touch
	if self.hud and self.hud.setTouchMode then
		(self.hud.setTouchMode :: any)(self.hud, touch)
	end
end
function Router.setTouchControls(self: any, mode: string)
	assert(mode == "auto" or mode == "on" or mode == "off", "invalid touch controls")
	self.touchControls = mode
	self:setInputType(self.lastInputType or "None")
end
function Router.setSettings(self: any, settings: any)
	self.settings = settings
end
function Router.setSuspended(self: any, suspended: boolean)
	self.suspended = suspended
	if suspended and self.hud and self.hud.setMenuHighlight then
		(self.hud.setMenuHighlight :: any)(self.hud, nil, false)
	end
	if suspended then
		self:releaseAll()
		self.pendingRightControl = false
		self.forwardedRightControl = false
	end
	if self.hud and self.hud.setSuspended then
		(self.hud.setSuspended :: any)(self.hud, suspended)
	end
end
function Router.keyboardEvent(self: any, name: string, down: boolean)
	if self.settings and name == "F10" then
		if down then
			self.settings:toggle()
		end
		return
	end
	if name == "RightControl" and self.settings then
		if down then
			self.pendingRightControl = true
		else
			if self.forwardedRightControl then
				self:setHeld("physical", name, false)
			elseif self.pendingRightControl and not self.suspended then
				self:setHeld("physical", name, true)
				self:setHeld("physical", name, false)
			end
			self.pendingRightControl = false
			self.forwardedRightControl = false
		end
		return
	end
	if name == "Comma" and down and self.pendingRightControl and self.settings then
		if self.forwardedRightControl then
			self:setHeld("physical", "RightControl", false)
		end
		self.pendingRightControl = false
		self.forwardedRightControl = false
		self.suppressComma = true
		self.settings:toggle()
		return
	end
	if name == "Comma" and not down and self.suppressComma then
		self.suppressComma = false
		return
	end
	if self.suspended then
		return
	end
	if down and self.pendingRightControl and not self.forwardedRightControl then
		self:setHeld("physical", "RightControl", true)
		self.forwardedRightControl = true
	end
	self:setHeld("physical", name, down)
end
function Router.start(self: any)
	if self.running or self.options.headless then
		return
	end
	self.running = true
	local input = self.options.inputService or game:GetService("UserInputService")
	self:setInputType(input:GetLastInputType().Name)
	self.connections[#self.connections + 1] = input.LastInputTypeChanged:Connect(function(kind: any)
		self:setInputType(kind.Name)
	end)
	local guiService = self.options.guiService or game:GetService("GuiService")
	local function position(obj: any): (number, number)
		return self:normalizePosition(obj.Position, guiService)
	end
	self.connections[#self.connections + 1] = input.InputBegan:Connect(function(obj: any, processed: boolean)
		local kind = obj.UserInputType.Name
		local name = obj.KeyCode.Name
		if kind == "Keyboard" then
			if input:GetFocusedTextBox() == nil then
				self:keyboardEvent(name, true)
			end
			return
		end
		if string.sub(kind, 1, 7) == "Gamepad" then
			if not self.suspended and input:GetFocusedTextBox() == nil then
				self:gamepadButton(name, true)
			end
			return
		end
		if processed or self.suspended then
			return
		end
		if kind == "Keyboard" then
			self:keyboardEvent(name, true)
		elseif kind == "Touch" then
			local x, y = position(obj)
			self:pointerDown(obj, x, y, true)
		elseif kind == "MouseButton1" then
			local x, y = position(obj)
			self:pointerDown("mouse", x, y, false)
		elseif kind == "MouseButton2" then
			local x, y = position(obj)
			self:mouse(x, y, 2, true)
		elseif string.sub(kind, 1, 7) == "Gamepad" then
			self:gamepadButton(name, true)
		end
	end)
	self.connections[#self.connections + 1] = input.InputEnded:Connect(function(obj: any)
		local kind = obj.UserInputType.Name
		local name = obj.KeyCode.Name
		if kind == "Keyboard" then
			if input:GetFocusedTextBox() ~= nil and name == "RightControl" and not self.forwardedRightControl then
				self.pendingRightControl = false
			else
				self:keyboardEvent(name, false)
			end
		elseif self.suspended then
			return
		elseif kind == "Touch" then
			local x, y = position(obj)
			self:pointerUp(obj, x, y)
		elseif kind == "MouseButton1" then
			local x, y = position(obj)
			self:pointerUp("mouse", x, y)
		elseif kind == "MouseButton2" then
			local x, y = position(obj)
			self:mouse(x, y, 2, false)
		elseif string.sub(kind, 1, 7) == "Gamepad" then
			self:gamepadButton(name, false)
		end
	end)
	self.connections[#self.connections + 1] = input.InputChanged:Connect(function(obj: any)
		local kind = obj.UserInputType.Name
		if self.suspended then
			return
		end
		if kind == "Touch" then
			local x, y = position(obj)
			self:pointerMove(obj, x, y)
		elseif kind == "MouseMovement" then
			local x, y = position(obj)
			self:pointerMove("mouse", x, y)
		elseif string.sub(kind, 1, 7) == "Gamepad" then
			self:gamepadAxis(obj.KeyCode.Name, obj.Position.X, obj.Position.Y)
		end
	end)
	self.connections[#self.connections + 1] = input.WindowFocusReleased:Connect(function()
		self:releaseAll()
	end)
	self.connections[#self.connections + 1] = input.GamepadDisconnected:Connect(function()
		self:releaseAll()
	end)
end
function Router.stop(self: any)
	self.running = false
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	self:releaseAll()
end
function Router.destroy(self: any)
	self:stop()
	if self.scheduler.inputRouter == self then
		self.scheduler.inputRouter = nil
	end
end
return Router
