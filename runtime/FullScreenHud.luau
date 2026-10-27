--!strict
local Hud = {}
Hud.__index = Hud
function Hud.new(options: any): any
	options = options or {}
	local self: any =
		setmetatable({ options = options, waiting = false, keyboardActive = false, connections = {} }, Hud)
	if options.headless then
		return self
	end
	local workspaceService = game:GetService("Workspace")
	self.cameraStates = {}
	local function bindCamera()
		local camera = workspaceService.CurrentCamera
		if camera then
			if not self.cameraStates[camera] then
				self.cameraStates[camera] = { cameraType = camera.CameraType, cameraSubject = camera.CameraSubject }
				self.connections[#self.connections + 1] = camera
					:GetPropertyChangedSignal("CameraType")
					:Connect(function()
						if not self.destroying and camera.CameraType ~= Enum.CameraType.Scriptable then
							camera.CameraType = Enum.CameraType.Scriptable
						end
					end)
			end
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end
	bindCamera()
	self.connections[#self.connections + 1] =
		workspaceService:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	pcall(function()
		game:GetService("ContextActionService"):UnbindAction("RbxCameraKeypress")
	end)
	local players = game:GetService("Players")
	local playerGui = options.playerGui or players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = Instance.new("ScreenGui")
	self.gui.Name = "DOS2LuauDemo"
	self.gui.IgnoreGuiInset = true
	self.gui.ScreenInsets = Enum.ScreenInsets.None
	self.gui.ClipToDeviceSafeArea = false
	self.gui.ResetOnSpawn = false
	self.gui.Parent = playerGui
	self.guiService = game:GetService("GuiService")
	self.oldAutoSelect = self.guiService.AutoSelectGuiEnabled
	self.guiService.AutoSelectGuiEnabled = false
	local backdrop = Instance.new("Frame")
	self.backdrop = backdrop
	backdrop.Name = "BlackBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Position = UDim2.fromScale(0, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BorderSizePixel = 0
	backdrop.Active = false
	backdrop.ZIndex = 0
	backdrop.Parent = self.gui
	local image = Instance.new("ImageLabel")
	self.imageLabel = image
	image.Name = "DOSDisplay"
	image.ZIndex = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Position = UDim2.fromScale(0, 0)
	image.BackgroundColor3 = Color3.new(0, 0, 0)
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Stretch
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image:SetAttribute("DOSFullScreen", true)
	image.Parent = self.gui
	local ring = Instance.new("Frame")
	self.ring = ring
	ring.Name = "ThumbRing"
	ring.Size = UDim2.fromOffset(100, 100)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = Color3.new(1, 1, 1)
	ring.BackgroundTransparency = 0.70
	ring.Visible = false
	ring.Parent = self.gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local thumb = Instance.new("Frame")
	self.thumb = thumb
	thumb.Size = UDim2.fromOffset(34, 34)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.BackgroundColor3 = Color3.new(1, 1, 1)
	thumb.BackgroundTransparency = 0.4
	thumb.Parent = ring
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = thumb
	local bar = Instance.new("ScrollingFrame")
	self.bar = bar
	bar.Name = "QuickBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	local topInset = self.guiService:GetGuiInset()
	bar.Position = UDim2.new(0.5, 0, 0, topInset.Y + 10)
	bar.Size = UDim2.new(1, -20, 0, 52)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BackgroundTransparency = 0.65
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.ScrollingDirection = Enum.ScrollingDirection.X
	bar.ScrollBarThickness = 3
	bar.AutomaticCanvasSize = Enum.AutomaticSize.X
	bar.CanvasSize = UDim2.fromOffset(0, 0)
	bar.Parent = self.gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar
	local labels = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "Y", "N", "Space", "Enter", "Type" }
	self.buttons = {}
	for index, label in ipairs(labels) do
		local button = Instance.new("TextButton")
		button.Name = label
		button.LayoutOrder = index
		button.Text = if label == "Type" then "⌨ Type" else label
		button.Size = UDim2.fromOffset(if #label > 1 then 65 else 42, 42)
		button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		button.BackgroundTransparency = 0.2
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextSize = 18
		button.Parent = bar
		self.buttons[label] = button
	end
	local box = Instance.new("TextBox")
	self.textBox = box
	box.Name = "NativeInput"
	box.Size = UDim2.fromOffset(1, 1)
	box.Position = UDim2.fromScale(0, 1)
	box.BackgroundTransparency = 1
	box.TextTransparency = 1
	box.ClearTextOnFocus = true
	box.MultiLine = false
	box.Text = ""
	box.Parent = self.gui
	return self
end
function Hud.bind(self: any, router: any)
	self.router = router
	if self.options.headless then
		return
	end
	for label, button in pairs(self.buttons) do
		self.connections[#self.connections + 1] = (button :: any).Activated:Connect(function()
			if label == "Type" then
				router:requestKeyboard()
			elseif label == "Space" or label == "Enter" or label == "Y" or label == "N" then
				router:pulse(label)
			else
				local digit = tonumber(label)
				if digit then
					local names = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
					router:pulse(names[digit])
				end
			end
		end)
	end
	self.connections[#self.connections + 1] = self.textBox.Focused:Connect(function()
		self.keyboardActive = true
		router:releaseAll()
		self:setWaiting(self.waiting)
	end)
	self.connections[#self.connections + 1] = self.textBox.FocusLost:Connect(function(_enterPressed: boolean)
		local text = self.textBox.Text
		self.textBox.Text = ""
		self.keyboardActive = false
		if not self.destroying and not self.suspended and self.quickBarEnabled == true then
			router:typeText(text, true)
		end
		self:setWaiting(self.waiting)
	end)
end
function Hud.setWaiting(self: any, waiting: boolean)
	self.waiting = waiting
	if not self.bar then
		return
	end
	local show = waiting and not self.keyboardActive and self.touchMode == true and not self.suspended
	if self.barShown == show then
		return
	end
	self.barShown = show
	local tweenService = game:GetService("TweenService")
	if show then
		self.bar.Visible = true
	end
	local tween =
		tweenService:Create(self.bar, TweenInfo.new(0.15), { BackgroundTransparency = if show then 0.65 else 1 })
	tween:Play()
	for _, button in pairs(self.buttons) do
		tweenService
			:Create(
				button,
				TweenInfo.new(0.15),
				{ TextTransparency = if show then 0 else 1, BackgroundTransparency = if show then 0.2 else 1 }
			)
			:Play()
	end
	if not show then
		tween.Completed:Connect(function()
			if not self.barShown then
				self.bar.Visible = false
			end
		end)
	end
end
function Hud.setQuickBarEnabled(self: any, enabled: boolean)
	self.quickBarEnabled = enabled
	self:setWaiting(self.waiting)
	if not enabled and self.bar then
		self.bar.Visible = false
	end
end
function Hud.setMenuHighlight(self: any, region: any, visible: boolean)
	if not self.imageLabel then
		return
	end
	if not self.menuHighlight then
		local outline = Instance.new("Frame")
		self.menuHighlight = outline
		outline.Name = "MenuHighlight"
		outline.BackgroundTransparency = 1
		outline.BorderSizePixel = 0
		outline.ZIndex = 6
		outline.Visible = false
		outline.Parent = self.imageLabel
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Parent = outline
	end
	self.menuHighlight.Visible = visible and region ~= nil
	if visible and region then
		self.menuHighlight.Position = UDim2.fromScale(region.x, region.y)
		self.menuHighlight.Size = UDim2.fromScale(region.width, region.height)
	end
end
function Hud.setTouchMode(self: any, enabled: boolean)
	self.touchMode = enabled
	self:setWaiting(self.waiting)
	if not enabled then
		if self.bar then
			self.bar.Visible = false
		end
		if self.ring then
			self.ring.Visible = false
		end
	end
end
function Hud.setSuspended(self: any, value: boolean)
	self.suspended = value
	self:setWaiting(self.waiting)
	if value then
		if self.bar then
			self.bar.Visible = false
		end
		if self.ring then
			self.ring.Visible = false
		end
	end
end
function Hud.setThumb(self: any, active: boolean, x: number, y: number, dx: number, dy: number)
	if self.ring then
		self.ring.Visible = active and self.touchMode == true and not self.suspended
		self.ring.Position = UDim2.fromScale(x, y)
		self.thumb.Position = UDim2.new(0.5, math.clamp(dx * 300, -35, 35), 0.5, math.clamp(dy * 300, -35, 35))
	end
end
function Hud.openKeyboard(self: any)
	if self.textBox then
		self.keyboardActive = true
		self:setWaiting(self.waiting)
		self.textBox:CaptureFocus()
	end
end
function Hud.destroy(self: any)
	self.destroying = true
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	if self.guiService then
		self.guiService.AutoSelectGuiEnabled = self.oldAutoSelect
	end
	if self.cameraStates then
		for camera, saved in pairs(self.cameraStates) do
			local c: any = camera
			local state: any = saved
			pcall(function()
				c.CameraType = state.cameraType
				c.CameraSubject = state.cameraSubject
			end)
		end
	end
	if self.gui then
		self.gui:Destroy()
	end
end
return Hud
