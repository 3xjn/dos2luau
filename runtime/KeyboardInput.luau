--!strict
-- Some Roblox/Studio camera bindings suppress I/O InputBegan entirely while
-- still exposing held state/InputEnded. Recover held I/O, with release fallback.
local Keyboard = {}
Keyboard.__index = Keyboard
local cameraKeys: { [string]: boolean } = { I = true, O = true }
function Keyboard.new(input: any, onKey: (string, boolean) -> ()): any
	return setmetatable(
		{ input = input, onKey = onKey, seen = {}, blocked = {}, released = {}, active = true, connections = {} },
		Keyboard
	)
end
function Keyboard.guardHeld(self: any)
	local getKeys: any = self.input.GetKeysPressed
	if getKeys then
		local pressed: any = (getKeys :: any)(self.input)
		for _, item in ipairs(pressed) do
			local key: any = item
			local name = key.KeyCode.Name
			if cameraKeys[name] then
				self.blocked[name] = true
			end
		end
	end
end
function Keyboard.start(self: any)
	local function connect(name: string, callback: () -> ())
		local signal: any = self.input[name]
		if signal then
			self.connections[#self.connections + 1] = signal:Connect(callback)
		end
	end
	connect("TextBoxFocused", function()
		self:guardHeld()
	end)
	connect("TextBoxFocusReleased", function()
		self:guardHeld()
	end)
	connect("WindowFocusReleased", function()
		self.active = false
		self:guardHeld()
	end)
	connect("WindowFocused", function()
		self.active = true
		self:guardHeld()
	end)
end
function Keyboard.began(self: any, name: string)
	-- Remember ignored begins too: leaving a textbox before key-up must not
	-- turn an ignored key into a recovered DOS character.
	self.seen[name] = true
	self.released[name] = nil
	if self.input:GetFocusedTextBox() == nil then
		self.onKey(name, true)
	end
end
function Keyboard.poll(self: any)
	local getKeys: any = self.input.GetKeysPressed
	if not getKeys or not self.active then
		return
	end
	if self.input:GetFocusedTextBox() ~= nil then
		self:guardHeld()
		return
	end
	-- Recover held camera keys too, enabling immediate input and typematic
	-- when Roblox exposes their pressed state but suppresses InputBegan.
	local pressed: any = (getKeys :: any)(self.input)
	local down: { [string]: boolean } = {}
	for _, item in ipairs(pressed) do
		local key: any = item
		local name = key.KeyCode.Name
		down[name] = true
		if cameraKeys[name] and not self.seen[name] and not self.blocked[name] then
			self:began(name)
		end
	end
	for key in pairs(self.seen) do
		local name = key :: string
		if not down[name] then
			self.onKey(name, false)
			self.seen[name] = nil
			self.released[name] = true
		end
	end
end
function Keyboard.ended(self: any, name: string)
	if
		cameraKeys[name]
		and not self.seen[name]
		and not self.blocked[name]
		and not self.released[name]
		and self.active
		and self.input:GetFocusedTextBox() == nil
	then
		self.onKey(name, true)
	end
	self.onKey(name, false)
	self.seen[name] = nil
	self.blocked[name] = nil
	self.released[name] = nil
end
function Keyboard.destroy(self: any)
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.seen)
	table.clear(self.blocked)
	table.clear(self.released)
	self.active = false
end
return Keyboard
