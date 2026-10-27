--!strict
local CPU = require("../runtime/CPUState")
local Bus = require("../runtime/Bus")
local Audio = require("../runtime/Audio")
local Scheduler = require("../runtime/InputAndScheduler")
local function eq(a: any, b: any, label: string)
	assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a: number, b: number, label: string)
	assert(math.abs(a - b) < 1e-9, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function make(opts: any): (any, any)
	local c: any = CPU.new()
	local b: any = Bus.new()
	local d: any = {}
	function d:run(_cpu: any, _bus: any, budget: number, _deadline: number): number
		return 0
	end
	local s: any = Scheduler.new(c, b, d, opts)
	s.interactive = true
	return s, b
end
local s, b = make({ frameBudgetSeconds = 1 })
s.ticks = 3
for name, expected in pairs({ xt = 3641, ["286"] = 9160, ["386"] = 25191, turbo = 35000 }) do
	s:setSpeedPreset(name)
	s.credit = 0
	s:step(0.01)
	eq(s.executedInstructions, expected, "preset " .. name)
	s.executedInstructions = 0
	eq(b.fastRepEnabled, name == "turbo", "fast REP " .. name)
end
local x = make({ frameBudgetSeconds = 1, instructionsPerSecond = 123456 })
x.ticks = 3
x:step(0.01)
eq(x.executedInstructions, 1234, "explicit rate")
x:setSpeedPreset("286")
x.credit = 0
x.executedInstructions = 0
x:step(0.01)
eq(x.executedInstructions, 9160, "preset overrides explicit rate")
local cal = make({ frameBudgetSeconds = 1 })
cal:setSpeedPreset("386")
cal:step(1)
eq(cal.executedInstructions, 60000, "three calibration ticks")
eq(cal.ticks, 3, "calibration tick count")
assert(not cal.bus.fastRepEnabled)
cal.credit = 0
cal.executedInstructions = 0
cal:step(0.1)
eq(cal.executedInstructions, 250000, "post-calibration frame cap")
eq(cal.ticks, 4, "wall-clock ticks")
local legacy = make({ frameBudgetSeconds = 1, turboVideo = false })
legacy.ticks = 3
legacy:step(0.01)
eq(legacy.executedInstructions, 3641, "legacy disabled turbo")
print("PASS scheduler presets, calibration, wall PIT and explicit rate")
local function fake(): any
	return {
		Volume = 0,
		PlaybackSpeed = 0,
		Play = function(self: any)
			self.playing = true
		end,
		Destroy = function() end,
	}
end
local speaker = fake()
local pcm = fake()
local voices = {}
for i = 1, 9 do
	voices[i] = fake()
end
local bus: any = Bus.new()
local audio: any = Audio.new(bus, {
	headless = true,
	speakerSound = speaker,
	pcmSound = pcm,
	oplSounds = voices,
	pcmAssets = { [0x050c5d1f] = "sample" },
})
audio.pitDivisor = 2712
audio.port61 = 3
audio:updateSpeaker()
near(speaker.Volume, 0.2, "speaker on")
audio.voices[1].level = 0.5
audio:update(0, nil)
near(voices[1].Volume, 0.075, "OPL base")
audio:startDMA(1, false)
assert(pcm.playing, "PCM is playing")
audio:setMasterGain(0.5)
near(speaker.Volume, 0.1, "speaker immediate gain")
near(voices[1].Volume, 0.0375, "OPL immediate gain")
near(pcm.Volume, 0.5, "PCM gain")
audio:setMasterGain(0.25)
audio:setMasterGain(1)
near(speaker.Volume, 0.2, "speaker restored")
near(voices[1].Volume, 0.075, "OPL restored without compounding")
audio:dspWrite(0xd3)
audio:setMasterGain(0.6)
near(pcm.Volume, 0, "muted DSP")
audio:dspWrite(0xd1)
near(pcm.Volume, 0.6, "unmuted DSP")
audio:setMasterGain(3)
eq(audio.masterGain, 1, "gain max clamp")
audio:setMasterGain(-1)
eq(audio.masterGain, 0, "gain min clamp")
eq(speaker.Volume, 0, "speaker muted")
audio:bell()
eq(speaker.Volume, 0, "bell honors gain")
print("PASS speaker, OPL and PCM gain updates and clamping")

local initial, initialBus = make({ frameBudgetSeconds = 1, speedPreset = "286" })
initial.ticks = 3
initial:step(0.01)
eq(initial.executedInstructions, 9160, "constructor speed preset")
eq(initialBus.fastRepEnabled, false, "constructor fixed speed")
local bad = pcall(function()
	make({ speedPreset = "unknown" })
end)
assert(not bad, "constructor rejects unknown preset")
local initialSpeaker = fake()
local initialPCM = fake()
local initialVoice = fake()
local initialAudio: any = Audio.new(Bus.new(), {
	headless = true,
	speakerSound = initialSpeaker,
	pcmSound = initialPCM,
	oplSounds = { initialVoice },
	masterGain = 0.25,
})
eq(initialAudio.masterGain, 0.25, "constructor master gain")
initialAudio:bell()
near(initialSpeaker.Volume, 0.05, "constructor gain affects bell")
near(initialPCM.Volume, 0.25, "constructor PCM gain")
print("PASS constructor speed and master gain settings")

local keyboardScheduler: any = make({ headless = true })
local captured: { string } = {}
keyboardScheduler.keyEvent = function(_self: any, name: string, down: boolean)
	if down then
		table.insert(captured, name)
	end
end
local focused: any = nil
local input: any = {
	GetFocusedTextBox = function()
		return focused
	end,
}
for _, name in ipairs({ "I", "O" }) do
	keyboardScheduler:handleInputBegan(
		{ UserInputType = { Name = "Keyboard" }, KeyCode = { Name = name } },
		true,
		input
	)
end
eq(table.concat(captured, ","), "I,O", "processed keyboard input")
focused = {}
keyboardScheduler:handleInputBegan({ UserInputType = { Name = "Keyboard" }, KeyCode = { Name = "I" } }, false, input)
eq(#captured, 2, "focused text input ignored")
keyboardScheduler:handleInputBegan(
	{ UserInputType = { Name = "MouseButton1" }, KeyCode = { Name = "Unknown" } },
	true,
	input
)
eq(#captured, 2, "processed non-keyboard ignored")
print("PASS legacy keyboard input respects textbox focus")
focused = nil
keyboardScheduler.keyboardInput:ended("I")
keyboardScheduler.keyboardInput:ended("O")
eq(#captured, 2, "normal I/O releases do not duplicate makes")
keyboardScheduler.keyboardInput:ended("I")
keyboardScheduler.keyboardInput:ended("O")
eq(table.concat(captured, ","), "I,O,I,O", "legacy orphan camera keys recovered")
