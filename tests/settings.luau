--!strict
local Settings = require("../runtime/SettingsUI")
local Router = require("../runtime/VirtualInputRouter")
local video: any = {
	calls = {},
	setDisplaySettings = function(self: any, v: any)
		table.insert(self.calls, v)
	end,
}
local scheduler: any = {
	options = {},
	held = {},
	keyEvent = function(self: any, k: string, d: boolean)
		self.held[k] = d
	end,
	setSpeedPreset = function(self: any, v: string)
		self.speed = v
	end,
	enqueueWord = function()
		return true
	end,
}
local audio: any = {
	setMasterGain = function(self: any, v: number)
		self.gain = v
	end,
}
local machine: any = { cpu = { waitingForKey = false }, video = video, scheduler = scheduler, audio = audio, hle = {} }
local r: any = Router.new(machine, { headless = true })
local modes: { boolean } = {}
local hud: any = {
	bind = function() end,
	setTouchMode = function(_, v: boolean)
		table.insert(modes, v)
	end,
	setSuspended = function(self: any, v: boolean)
		self.suspended = v
	end,
	setThumb = function() end,
}
r:attach(hud)
local settings: any = Settings.new(machine, hud, { headless = true, router = r })
local currentMachine: any = {
	video = { aspectMode = "16:10", resampleMode = "Default" },
	scheduler = { speedPreset = "286" },
	audio = {
		masterGain = 0.25,
	},
}
local current: any = Settings.new(currentMachine, {}, { headless = true })
assert(
	current.values.aspect == "16:10"
		and current.values.filter == "Default"
		and current.values.speed == "286"
		and current.values.volume == 0.25
)
settings:applySetting("menuAssist", "on")
assert(r.smartMenuClick and r.tapToContinue and r.gamepadMenuHighlight and r.touchQuickBar)
settings:applySetting("menuAssist", "off")
assert(not r.smartMenuClick and not r.tapToContinue and not r.gamepadMenuHighlight and not r.touchQuickBar)
settings:applySetting("aspect", "4:3")
settings:applySetting("filter", "Default")
settings:applySetting("speed", "386")
settings:applySetting("volume", 0.25)
settings:applySetting("scanlines", "classic")
assert(
	video.calls[1].aspectMode == "4:3"
		and video.calls[2].resampleMode == "Default"
		and scheduler.speed == "386"
		and audio.gain == 0.25
		and settings.values.scanlines == "classic"
)
settings:applySetting("touch", "on")
r:setInputType("Keyboard")
assert(modes[#modes] == true)
settings:applySetting("touch", "off")
r:setInputType("Touch")
assert(modes[#modes] == false)
settings:applySetting("touch", "auto")
assert(modes[#modes] == true)
r:setHeld("physical", "Right", true)
r:keyboardEvent("F10", true)
assert(settings.open and r.suspended and hud.suspended and not scheduler.held.Right)
r:keyboardEvent("A", true)
assert(not scheduler.held.A)
r:keyboardEvent("F10", true)
assert(not settings.open and not r.suspended)
r:keyboardEvent("RightControl", true)
r:keyboardEvent("Comma", true)
r:keyboardEvent("Comma", false)
r:keyboardEvent("RightControl", false)
assert(settings.open and not scheduler.held.RightControl and not scheduler.held.Comma)
settings:destroy()
assert(not r.suspended and r.settings == nil)
print("settings tests passed")
