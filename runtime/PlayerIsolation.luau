--!strict
-- Local character controls and sounds only; emulator audio lives outside the character.
local Isolation = {}
Isolation.__index = Isolation
function Isolation.new(player: any, options: any): any
	return setmetatable({
		player = player,
		options = options or {},
		connections = {},
		characterConnections = {},
		sounds = {},
		humanoids = {},
		started = false,
	}, Isolation)
end
function Isolation.disableControls(self: any)
	if self.controls then
		return
	end
	local controls = self.options.controls
	if not controls then
		local scripts = self.player:FindFirstChild("PlayerScripts")
		local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
		if module then
			local ok, result = pcall(function()
				return (require :: any)(module):GetControls()
			end)
			if ok then
				controls = result
			end
		end
	end
	if controls then
		self.controls = controls
		self.controlsWereEnabled = if controls.controlsEnabled == nil then true else controls.controlsEnabled
		if self.controlsWereEnabled then
			controls:Disable()
		end
	end
end
function Isolation.muteSound(self: any, sound: any)
	if not sound:IsA("Sound") or self.sounds[sound] then
		return
	end
	local entry: any = { volume = sound.Volume }
	self.sounds[sound] = entry
	entry.connection = sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if self.started and sound.Volume ~= 0 then
			sound.Volume = 0
		end
	end)
	sound.Volume = 0
end
function Isolation.freezeHumanoid(self: any, humanoid: any)
	if not humanoid:IsA("Humanoid") or self.humanoids[humanoid] then
		return
	end
	local state = self.options.jumpingState or Enum.HumanoidStateType.Jumping
	self.humanoids[humanoid] = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		jumpingEnabled = humanoid:GetStateEnabled(state),
		state = state,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.Jump = false
	humanoid:SetStateEnabled(state, false)
end
function Isolation.clearCharacter(self: any)
	for _, c in ipairs(self.characterConnections) do
		c:Disconnect()
	end
	table.clear(self.characterConnections)
	for sound, entry in pairs(self.sounds) do
		local e: any = entry
		if e.connection then
			e.connection:Disconnect()
		end
		(sound :: any).Volume = e.volume
	end
	table.clear(self.sounds)
	for humanoid, entry in pairs(self.humanoids) do
		local h: any = humanoid
		local saved: any = entry
		h.WalkSpeed = saved.walkSpeed
		h.JumpPower = saved.jumpPower
		h.JumpHeight = saved.jumpHeight
		h.AutoRotate = saved.autoRotate
		h:SetStateEnabled(saved.state, saved.jumpingEnabled)
	end
	table.clear(self.humanoids)
end
function Isolation.attachCharacter(self: any, character: any)
	self:clearCharacter()
	for _, object in ipairs(character:GetDescendants()) do
		self:muteSound(object)
		self:freezeHumanoid(object)
	end
	self.characterConnections[#self.characterConnections + 1] = character.DescendantAdded:Connect(function(object: any)
		self:muteSound(object)
		self:freezeHumanoid(object)
	end)
end
function Isolation.start(self: any)
	if self.started then
		return
	end
	self.started = true
	local guiService = self.options.guiService or (if game then game:GetService("GuiService") else nil)
	if guiService then
		pcall(function()
			guiService:SetEmotesMenuOpen(false)
		end)
		pcall(function()
			if guiService.EmotesMenuOpenChanged then
				self.connections[#self.connections + 1] = guiService.EmotesMenuOpenChanged:Connect(function()
					if self.started then
						pcall(function()
							if guiService:GetEmotesMenuOpen() then
								guiService:SetEmotesMenuOpen(false)
							end
						end)
					end
				end)
			end
		end)
	end
	local starterGui = self.options.starterGui or (if game then game:GetService("StarterGui") else nil)
	local emotesType = self.options.emotesType or (if starterGui then Enum.CoreGuiType.EmotesMenu else nil)
	if starterGui and emotesType then
		local ok, previous = pcall(function()
			return starterGui:GetCoreGuiEnabled(emotesType)
		end)
		if ok then
			self.starterGui = starterGui
			self.emotesType = emotesType
			self.emotesWasEnabled = previous
			pcall(function()
				starterGui:SetCoreGuiEnabled(emotesType, false)
			end)
			pcall(function()
				if starterGui.CoreGuiChangedSignal then
					self.connections[#self.connections + 1] = starterGui.CoreGuiChangedSignal:Connect(
						function(kind: any, enabled: boolean)
							if self.started and kind == emotesType and enabled then
								pcall(function()
									starterGui:SetCoreGuiEnabled(emotesType, false)
								end)
							end
						end
					)
				end
			end)
		end
	end
	self:disableControls()
	local function watchScripts(scripts: any)
		if self.scriptsConnection then
			self.scriptsConnection:Disconnect()
		end
		self.scriptsConnection = scripts.ChildAdded:Connect(function(child: any)
			if child.Name == "PlayerModule" then
				self:disableControls()
			end
		end)
		self:disableControls()
	end
	local scripts = self.player:FindFirstChild("PlayerScripts")
	if scripts then
		watchScripts(scripts)
	end
	self.connections[#self.connections + 1] = self.player.ChildAdded:Connect(function(child: any)
		if child.Name == "PlayerScripts" then
			watchScripts(child)
		end
	end)
	self.connections[#self.connections + 1] = self.player.CharacterAdded:Connect(function(character: any)
		self:attachCharacter(character)
		self:disableControls()
	end)
	if self.player.Character then
		self:attachCharacter(self.player.Character)
	end
end
function Isolation.destroy(self: any)
	if not self.started then
		return
	end
	self.started = false
	for _, c in ipairs(self.connections) do
		(c :: any):Disconnect()
	end
	table.clear(self.connections)
	if self.scriptsConnection then
		self.scriptsConnection:Disconnect()
		self.scriptsConnection = nil
	end
	self:clearCharacter()
	if self.starterGui then
		pcall(function()
			self.starterGui:SetCoreGuiEnabled(self.emotesType, self.emotesWasEnabled)
		end)
		self.starterGui = nil
	end
	if self.controls and self.controlsWereEnabled then
		self.controls:Enable()
	end
	self.controls = nil
end
return Isolation
