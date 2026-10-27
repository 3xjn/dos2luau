--!strict
local Isolation = require("../runtime/PlayerIsolation")
local function signal(): any
	local callbacks: { [any]: any } = {}
	return {
		Connect = function(_self: any, fn: any)
			local token = {}
			callbacks[token] = fn
			return {
				Disconnect = function()
					callbacks[token] = nil
				end,
			}
		end,
		fire = function(_self: any, ...: any)
			for _, fn in pairs(callbacks) do
				fn(...)
			end
		end,
	}
end
local function sound(volume: number): any
	local changed = signal()
	return {
		Volume = volume,
		IsA = function(_self: any, name: string)
			return name == "Sound"
		end,
		GetPropertyChangedSignal = function()
			return changed
		end,
		changed = changed,
	}
end
local function character(initial: { any }): any
	return {
		objects = initial,
		DescendantAdded = signal(),
		GetDescendants = function(self: any)
			return self.objects
		end,
	}
end
local controls: any = {
	controlsEnabled = true,
	Disable = function(self: any)
		self.disabled = true
	end,
	Enable = function(self: any)
		self.enabled = true
	end,
}
local a = sound(0.7)
local char = character({ a })
local player: any = {
	Character = char,
	ChildAdded = signal(),
	CharacterAdded = signal(),
	FindFirstChild = function()
		return nil
	end,
}
local isolation: any = Isolation.new(player, { controls = controls })
isolation:start()
assert(controls.disabled and a.Volume == 0)
a.Volume = 0.3
a.changed:fire()
assert(a.Volume == 0)
local b = sound(0.4)
char.DescendantAdded:fire(b)
assert(b.Volume == 0)
local c = sound(0.2)
local nextChar = character({ c })
player.CharacterAdded:fire(nextChar)
assert(a.Volume == 0.7 and b.Volume == 0.4 and c.Volume == 0)
isolation:destroy()
assert(c.Volume == 0.2 and controls.enabled)
c.Volume = 0.8
c.changed:fire()
assert(c.Volume == 0.8)
local disabled: any = {
	controlsEnabled = false,
	Disable = function()
		error("already disabled")
	end,
	Enable = function()
		error("must stay disabled")
	end,
}
local isolation2: any = Isolation.new(player, { controls = disabled })
isolation2:start()
isolation2:destroy()
local function humanoid(): any
	return {
		WalkSpeed = 16,
		JumpPower = 50,
		JumpHeight = 7,
		AutoRotate = true,
		Jump = true,
		enabled = true,
		IsA = function(_self: any, n: string)
			return n == "Humanoid"
		end,
		GetStateEnabled = function(self: any, _s: any)
			return self.enabled
		end,
		SetStateEnabled = function(self: any, _s: any, v: boolean)
			self.enabled = v
		end,
	}
end
local hum = humanoid()
local withHumanoid = character({ hum })
player.Character = withHumanoid
local iso: any = Isolation.new(player, { jumpingState = "jump" })
iso:start()
assert(
	hum.WalkSpeed == 0
		and hum.JumpPower == 0
		and hum.JumpHeight == 0
		and not hum.AutoRotate
		and not hum.Jump
		and not hum.enabled
)
local hum2 = humanoid()
local nextCharacter = character({ hum2 })
player.CharacterAdded:fire(nextCharacter)
assert(
	hum.WalkSpeed == 16
		and hum.JumpPower == 50
		and hum.JumpHeight == 7
		and hum.AutoRotate
		and hum.enabled
		and hum2.WalkSpeed == 0
)
iso:destroy()
assert(hum2.WalkSpeed == 16 and hum2.JumpPower == 50 and hum2.JumpHeight == 7 and hum2.AutoRotate and hum2.enabled)
local gui: any = {
	enabled = true,
	GetCoreGuiEnabled = function(self: any, _kind: any)
		return self.enabled
	end,
	SetCoreGuiEnabled = function(self: any, _kind: any, value: boolean)
		self.enabled = value
	end,
}
local iso3: any = Isolation.new(player, { jumpingState = "jump", starterGui = gui, emotesType = "emotes" })
iso3:start()
assert(not gui.enabled)
iso3:destroy()
assert(gui.enabled)
local event = signal()
local coreEvent = signal()
local emoteGui: any = {
	open = false,
	EmotesMenuOpenChanged = event,
	SetEmotesMenuOpen = function(self: any, value: boolean)
		self.open = value
		event:fire()
	end,
	GetEmotesMenuOpen = function(self: any)
		return self.open
	end,
}
local core: any = {
	enabled = true,
	CoreGuiChangedSignal = coreEvent,
	GetCoreGuiEnabled = function(self: any, _kind: any)
		return self.enabled
	end,
	SetCoreGuiEnabled = function(self: any, kind: any, value: boolean)
		self.enabled = value
		coreEvent:fire(kind, value)
	end,
}
local iso4: any =
	Isolation.new(player, { jumpingState = "jump", starterGui = core, emotesType = "emotes", guiService = emoteGui })
iso4:start()
emoteGui:SetEmotesMenuOpen(true)
assert(not emoteGui.open)
core:SetCoreGuiEnabled("emotes", true)
assert(not core.enabled)
iso4:destroy()
assert(core.enabled)
emoteGui:SetEmotesMenuOpen(true)
assert(emoteGui.open)
local denied = {
	Connect = function()
		error("RobloxScript capability required")
	end,
}
local deniedGui: any = { EmotesMenuOpenChanged = denied, SetEmotesMenuOpen = function() end }
local deniedCore: any = {
	enabled = true,
	CoreGuiChangedSignal = denied,
	GetCoreGuiEnabled = function(self: any)
		return self.enabled
	end,
	SetCoreGuiEnabled = function(self: any, _kind: any, value: boolean)
		self.enabled = value
	end,
}
local hum3 = humanoid()
local sound3 = sound(0.6)
player.Character = character({ hum3, sound3 })
local iso5: any = Isolation.new(
	player,
	{ jumpingState = "jump", guiService = deniedGui, starterGui = deniedCore, emotesType = "emotes" }
)
iso5:start()
assert(not deniedCore.enabled and hum3.WalkSpeed == 0 and sound3.Volume == 0)
iso5:destroy()
assert(deniedCore.enabled and hum3.WalkSpeed == 16 and sound3.Volume == 0.6)
print("player isolation tests passed")
