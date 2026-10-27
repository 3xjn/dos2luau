--!strict
local Settings = {}
Settings.__index = Settings
local choices: { [string]: { any } } = {
	aspect = { "stretch", "4:3", "16:10", "integer" },
	filter = { "Pixelated", "Default" },
	scanlines = { "off", "subtle", "classic" },
	speed = { "turbo", "xt", "286", "386" },
	volume = { 0, 0.25, 0.5, 1 },
	touch = { "auto", "on", "off" },
	menuAssist = { "off", "on" },
}
local labels: { [string]: string } = {
	aspect = "Aspect",
	filter = "Filter",
	scanlines = "Scanlines",
	speed = "Speed",
	volume = "Volume",
	touch = "Touch controls",
	menuAssist = "Menu assist",
}
local order = { "aspect", "filter", "scanlines", "speed", "volume", "touch", "menuAssist" }
local captions: { [string]: { [string]: string } } = {
	aspect = {
		stretch = "Full Screen (Stretch)",
		["4:3"] = "CRT 4:3",
		["16:10"] = "Square Pixels (16:10)",
		integer = "Integer Scale",
	},
	filter = { Pixelated = "Sharp (Pixelated)", Default = "Smooth (Bilinear)" },
	speed = {
		turbo = "Turbo Auto (3.5 MIPS)",
		xt = "IBM XT (4.77 MHz)",
		["286"] = "286 (12 MHz)",
		["386"] = "386 (33 MHz)",
	},
	touch = { auto = "Auto (By Input Device)", on = "Force On", off = "Force Off" },
}
local function display(name: string, value: any): string
	if name == "volume" then
		return tostring(math.floor(value * 100 + 0.5)) .. "%"
	end
	local mapping = captions[name]
	if mapping then
		return mapping[tostring(value)] or tostring(value)
	end
	return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
end
function Settings.new(machine: any, hud: any, options: any): any
	options = options or {}
	local self: any = setmetatable({
		machine = machine,
		hud = hud,
		options = options,
		router = options.router or machine.inputRouter or machine.router or machine.scheduler.inputRouter,
		values = {
			aspect = machine.video.aspectMode or "stretch",
			filter = machine.video.resampleMode or "Pixelated",
			scanlines = "off",
			speed = machine.scheduler.speedPreset or "turbo",
			volume = if machine.audio and machine.audio.masterGain ~= nil then machine.audio.masterGain else 1,
			touch = if options.router and options.router.touchControls then options.router.touchControls else "auto",
			menuAssist = "off",
		},
		open = false,
		connections = {},
		buttons = {},
	}, Settings)
	if self.router then
		self.values.touch = self.router.touchControls or "auto"
		self.values.menuAssist = if self.router.smartMenuClick
				and self.router.tapToContinue
				and self.router.gamepadMenuHighlight
				and self.router.touchQuickBar
			then "on"
			else "off"
		self.router:setSettings(self)
	end
	if options.headless then
		return self
	end
	local gui = hud.gui
	local gear = Instance.new("TextButton")
	self.gear = gear
	gear.Name = "Settings"
	gear.Text = "⚙"
	gear.TextSize = 19
	gear.TextColor3 = Color3.new(1, 1, 1)
	gear.TextTransparency = 0.25
	gear.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	gear.BackgroundTransparency = 0.75
	gear.BorderSizePixel = 0
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -12, 0, 12)
	gear.Size = UDim2.fromOffset(32, 32)
	gear.ZIndex = 10
	gear.Parent = gui
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0, 6)
	gc.Parent = gear
	local modal = Instance.new("Frame")
	self.modal = modal
	modal.Name = "SettingsModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.new(1, -24, 1, -24)
	modal.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	modal.BackgroundTransparency = 0.08
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 20
	modal.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(470, 480)
	size.Parent = modal
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = modal
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 90, 100)
	stroke.Transparency = 0.35
	stroke.Parent = modal
	local title = Instance.new("TextLabel")
	title.Text = "Settings"
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -100, 0, 42)
	title.ZIndex = 21
	title.Parent = modal
	local close = Instance.new("TextButton")
	close.Text = "Close"
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(70, 38)
	close.ZIndex = 21
	close.Parent = modal
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 7)
	cc.Parent = close
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, 58)
	scroll.Size = UDim2.new(1, -24, 1, -70)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ZIndex = 21
	scroll.Parent = modal
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 7)
	list.Parent = scroll
	for i, name in ipairs(order) do
		local row = Instance.new("TextButton")
		row.Name = name
		row.Text = ""
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -6, 0, 68)
		row.BackgroundColor3 = Color3.fromRGB(43, 43, 49)
		row.BorderSizePixel = 0
		row.ZIndex = 22
		row.Parent = scroll
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 7)
		rc.Parent = row
		local label = Instance.new("TextLabel")
		label.Text = labels[name]
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(14, 5)
		label.Size = UDim2.new(1, -28, 0, 24)
		label.ZIndex = 23
		label.Parent = row
		local value = Instance.new("TextLabel")
		value.Text = display(name, self.values[name]) .. "  ›"
		value.TextSize = 16
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.TextWrapped = true
		value.TextColor3 = Color3.fromRGB(220, 220, 225)
		value.BackgroundTransparency = 1
		value.Position = UDim2.fromOffset(14, 28)
		value.Size = UDim2.new(1, -28, 0, 36)
		value.ZIndex = 23
		value.Parent = row
		self.buttons[name] = value
		self.connections[#self.connections + 1] = row.Activated:Connect(function()
			self:cycle(name)
		end)
	end
	-- The scanline layer is a child of the game image, so aspect and integer scaling clip it automatically.
	local overlay = Instance.new("Frame")
	self.scanOverlay = overlay
	overlay.Name = "Scanlines"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ClipsDescendants = true
	overlay.Visible = false
	overlay.ZIndex = 3
	overlay.Parent = hud.imageLabel
	self.lines = {}
	for i = 0, 199 do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BorderSizePixel = 0
		line.Position = UDim2.fromScale(0, (i + 0.5) / 200)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.ZIndex = 3
		line.Parent = overlay
		self.lines[#self.lines + 1] = line
	end
	self.connections[#self.connections + 1] = gear.Activated:Connect(function()
		self:toggle()
	end)
	self.connections[#self.connections + 1] = close.Activated:Connect(function()
		self:setOpen(false)
	end)
	local tween = game:GetService("TweenService")
	self.connections[#self.connections + 1] = gear.MouseEnter:Connect(function()
		tween:Create(gear, TweenInfo.new(0.15), { BackgroundTransparency = 0.75, TextTransparency = 0.25 }):Play()
	end)
	self.connections[#self.connections + 1] = gear.MouseLeave:Connect(function()
		tween:Create(gear, TweenInfo.new(0.8), { BackgroundTransparency = 0.92, TextTransparency = 0.65 }):Play()
	end)
	tween:Create(gear, TweenInfo.new(2), { BackgroundTransparency = 0.92, TextTransparency = 0.65 }):Play()
	return self
end
function Settings.setOpen(self: any, value: boolean)
	if self.open == value then
		return
	end
	self.open = value
	if self.router then
		self.router:setSuspended(value)
	end
	if self.modal then
		self.modal.Visible = value
	end
end
function Settings.toggle(self: any)
	self:setOpen(not self.open)
end
function Settings.cycle(self: any, name: string)
	local values = choices[name]
	assert(values, "unknown setting")
	local index = 1
	for i, v in ipairs(values) do
		if v == self.values[name] then
			index = i
			break
		end
	end
	self:applySetting(name, values[index % #values + 1])
end
function Settings.applySetting(self: any, name: string, value: any)
	local valid = false
	for _, v in ipairs(choices[name] or {}) do
		if value == v then
			valid = true
		end
	end
	assert(valid, "invalid setting " .. name)
	if name == "aspect" then
		self.machine.video:setDisplaySettings({ aspectMode = value })
	elseif name == "filter" then
		self.machine.video:setDisplaySettings({ resampleMode = value })
	elseif name == "speed" then
		self.machine.scheduler:setSpeedPreset(value)
	elseif name == "volume" then
		self.machine.audio:setMasterGain(value)
	elseif name == "menuAssist" then
		if self.router then
			self.router:setMenuAssist(value == "on")
		end
	elseif name == "touch" then
		if self.router then
			self.router:setTouchControls(value)
		end
	elseif name == "scanlines" and self.scanOverlay then
		self.scanOverlay.Visible = value ~= "off"
		for _, line in ipairs(self.lines) do
			(line :: any).BackgroundTransparency = if value == "subtle" then 0.85 else 0.65
		end
	end
	self.values[name] = value
	if self.buttons[name] then
		self.buttons[name].Text = display(name, value) .. "  ›"
	end
end
function Settings.destroy(self: any)
	self:setOpen(false)
	if self.router and self.router.settings == self then
		self.router:setSettings(nil)
	end
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	if self.scanOverlay then
		self.scanOverlay:Destroy()
	end
	if self.modal then
		self.modal:Destroy()
	end
	if self.gear then
		self.gear:Destroy()
	end
end
return Settings
