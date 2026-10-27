--!strict
-- PC speaker, a lightweight OPL2 approximation, and Sound Blaster DMA playback.
local Audio = {}
Audio.__index = Audio
-- Supply a looped 440 Hz waveform for faithful PC-speaker timbre.
local DEFAULT_SPEAKER_ASSET = "rbxasset://sounds/uuhhh.mp3"
Audio.DEFAULT_SPEAKER_ASSET = DEFAULT_SPEAKER_ASSET
local function sound(asset: any, looped: boolean, provided: any): any
	if provided then
		return provided
	end
	if not asset or not Instance then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = tostring(asset)
	s.Looped = looped
	s.Parent = game:GetService("SoundService")
	return s
end
local function mul32(a: number, b: number): number
	local lo = bit32.band(a, 65535) * b
	local hi = bit32.rshift(a, 16) * b
	return (lo + bit32.lshift(bit32.band(hi, 65535), 16)) % 4294967296
end
local function hash(bus: any, page: number, address: number, count: number): number
	local h = 2166136261
	for i = 0, count - 1 do
		h = mul32(bit32.bxor(h, bus:read8(page * 65536 + (address + i) % 65536)), 16777619)
	end
	return h
end
function Audio.new(bus: any, options: any): any
	options = options or {}
	local self: any = setmetatable({
		bus = bus,
		masterGain = 1,
		speakerBaseVolume = 0,
		speakerHold = 0,
		speakerActive = false,
		speakerFresh = false,
		lastTriggeredFreq = 0,
		options = options,
		pendingIRQ = nil,
		pitDivisor = 0,
		pitLow = nil,
		pitAccess = 3,
		port61 = 0,
		oplIndex = 0,
		opl = {},
		voices = {},
		dmaAddress = 0,
		dmaCount = 0,
		dmaPage = 0,
		dmaFlip = false,
		dmaMasked = true,
		dspQueue = {},
		dspCommand = nil,
		dspArgs = {},
		dspRate = 22050,
		dmaRemaining = 0,
		dmaAuto = false,
		speaker = nil,
		pcm = nil,
	}, Audio)
	if not options.headless or options.speakerSound or options.oplSounds or options.pcmSound then
		local fallback = if options.headless then nil else DEFAULT_SPEAKER_ASSET
		self.speaker = sound(options.speakerAssetId or fallback, true, options.speakerSound)
		if self.speaker and not options.speakerSound then
			self.speaker.Name = "DOSPCSpeaker"
		end
		self.pcm = sound(nil, false, options.pcmSound)
		for i = 1, 9 do
			self.voices[i] = {
				sound = sound(
					options.oplAssetId or fallback,
					true,
					if options.oplSounds then options.oplSounds[i] else nil
				),
				level = 0,
			}
		end
	else
		for i = 1, 9 do
			self.voices[i] = { level = 0 }
		end
	end
	self.dspSpeaker = true
	self.pendingIRQCount = 0
	if self.speaker then
		self.speaker.Looped = true
		self.speaker.Volume = 0
		self.speaker:Play()
	end
	for i, voice in ipairs(self.voices) do
		if voice.sound then
			if not (options.oplSounds and options.oplSounds[i]) then
				voice.sound.Name = "DOSOPL" .. tostring(i)
			end
			voice.sound.Looped = true
			voice.sound.Volume = 0
			voice.sound:Play()
		end
	end
	bus:registerPortHandler(0x43, nil, function(v: number)
		if bit32.rshift(v, 6) == 2 then
			self.pitAccess = bit32.band(bit32.rshift(v, 4), 3)
			self.pitLow = nil
		end
	end)
	bus:registerPortHandler(0x42, nil, function(v: number)
		if self.pitAccess == 1 then
			self.pitDivisor = bit32.bor(bit32.band(self.pitDivisor, 0xff00), v)
		elseif self.pitAccess == 2 then
			self.pitDivisor = bit32.bor(bit32.band(self.pitDivisor, 255), v * 256)
		elseif self.pitLow == nil then
			self.pitLow = v
		else
			self.pitDivisor = self.pitLow + v * 256
			self.pitLow = nil
		end
		self:updateSpeaker()
	end)
	bus:registerPortHandler(0x61, function()
		return self.port61
	end, function(v: number)
		self.port61 = v
		self:updateSpeaker()
	end)
	bus:registerPortHandler(0x388, nil, function(v: number)
		self.oplIndex = v
	end)
	bus:registerPortHandler(0x389, nil, function(v: number)
		self.opl[self.oplIndex] = v
	end)
	bus:registerPortHandler(0x02, nil, function(v: number)
		if not self.dmaFlip then
			self.dmaAddress = bit32.bor(bit32.band(self.dmaAddress, 0xff00), v)
		else
			self.dmaAddress = bit32.bor(bit32.band(self.dmaAddress, 255), v * 256)
		end
		self.dmaFlip = not self.dmaFlip
	end)
	bus:registerPortHandler(0x03, nil, function(v: number)
		if not self.dmaFlip then
			self.dmaCount = bit32.bor(bit32.band(self.dmaCount, 0xff00), v)
		else
			self.dmaCount = bit32.bor(bit32.band(self.dmaCount, 255), v * 256)
		end
		self.dmaFlip = not self.dmaFlip
	end)
	bus:registerPortHandler(0x83, nil, function(v: number)
		self.dmaPage = v
	end)
	bus:registerPortHandler(0x0c, nil, function(_: number)
		self.dmaFlip = false
	end)
	bus:registerPortHandler(0x0a, nil, function(v: number)
		if bit32.band(v, 3) == 1 then
			self.dmaMasked = bit32.band(v, 4) ~= 0
		end
	end)
	bus:registerPortHandler(0x22e, function()
		return if #self.dspQueue > 0 then 0x80 else 0
	end, nil)
	bus:registerPortHandler(0x22a, function()
		return table.remove(self.dspQueue, 1) or 0xff
	end, nil)
	bus:registerPortHandler(0x22c, function()
		return 0
	end, function(v: number)
		self:dspWrite(v)
	end)
	bus:registerPortHandler(0x226, nil, function(v: number)
		if v ~= 0 then
			self.dspReset = true
		elseif self.dspReset then
			self.dspReset = false
			table.insert(self.dspQueue, 0xaa)
		end
	end)
	if options.masterGain ~= nil then
		self:setMasterGain(options.masterGain)
	end
	return self
end
function Audio.setMasterGain(self: any, gain: number)
	assert(gain == gain, "Master gain must be a number")
	self.masterGain = math.clamp(gain, 0, 1)
	if self.speaker then
		self.speaker.Volume = self.speakerBaseVolume * self.masterGain
	end
	if self.pcm then
		self.pcm.Volume = if self.dspSpeaker then self.masterGain else 0
	end
	for _, voice in ipairs(self.voices) do
		if voice.sound then
			voice.sound.Volume = (voice.baseVolume or 0) * self.masterGain
		end
	end
end
function Audio.startDMA(self: any, length: number, auto: boolean)
	local count = math.min(length, self.dmaCount + 1)
	self.dmaRemaining = count / self.dspRate
	self.dmaAuto = auto
	self.dmaDuration = self.dmaRemaining
	local h = hash(self.bus, self.dmaPage, self.dmaAddress, count)
	self.lastPCMHash = h
	local assets = self.options.pcmAssets or {}
	local id = assets[h] or assets[string.format("%08x", h)] or assets[string.format("0x%08x", h)]
	if id then
		if not self.pcm and not self.options.headless then
			self.pcm = sound(id, false, nil)
		end
		if self.pcm then
			self.pcm.SoundId = tostring(id)
			self.pcm.Looped = auto
			self.pcm.Volume = if self.dspSpeaker then self.masterGain else 0
			self.pcm:Play()
		end
	elseif self.options.onUnknownPCM then
		(self.options.onUnknownPCM :: any)(h, count)
	else
		print("Unknown PCM sample FNV-1a " .. string.format("%08x", h) .. " (" .. count .. " bytes)")
	end
end
function Audio.dspWrite(self: any, v: number)
	if self.dspCommand then
		table.insert(self.dspArgs, v)
		local cmd = self.dspCommand
		local needed = if cmd == 0x40 then 1 else 2
		if #self.dspArgs < needed then
			return
		end
		if cmd == 0x40 then
			self.dspRate = 1000000 / (256 - self.dspArgs[1])
		elseif cmd == 0x41 then
			self.dspRate = math.max(1, self.dspArgs[1] * 256 + self.dspArgs[2])
		elseif cmd == 0x48 then
			self.dspBlock = self.dspArgs[1] + self.dspArgs[2] * 256 + 1
		else
			self:startDMA(self.dspArgs[1] + self.dspArgs[2] * 256 + 1, false)
		end
		self.dspCommand = nil
		self.dspArgs = {}
		return
	end
	if v == 0x40 or v == 0x41 or v == 0x48 or v == 0x14 or v == 0x91 then
		self.dspCommand = v
		self.dspArgs = {}
	elseif v == 0x1c or v == 0x90 then
		self:startDMA(self.dspBlock or (self.dmaCount + 1), true)
	elseif v == 0xd1 then
		self.dspSpeaker = true
		if self.pcm then
			self.pcm.Volume = self.masterGain
		end
	elseif v == 0xd3 then
		self.dspSpeaker = false
		if self.pcm then
			self.pcm.Volume = 0
		end
	elseif v == 0xda then
		self.dmaAuto = false
	elseif v == 0xd0 then
		self.dmaPaused = true
	elseif v == 0xd4 then
		self.dmaPaused = false
	elseif v == 0xe1 then
		table.insert(self.dspQueue, 2)
		table.insert(self.dspQueue, 1)
	end
end
function Audio.updateSpeaker(self: any)
	local divisor: number = if self.pitDivisor == 0 then 65536 else self.pitDivisor :: number
	local frequency = 1193182 / divisor
	local retrigger = not self.speakerActive or frequency ~= self.lastTriggeredFreq
	self.speakerActive = bit32.band(self.port61, 3) == 3 and frequency >= 20 and frequency <= 8800
	if self.speakerActive then
		self.speakerHold = 0.05
		self.speakerFresh = true
		self.lastTriggeredFreq = frequency
		self.speakerBaseVolume = 0.2
		if self.speaker then
			self.speaker.PlaybackSpeed = math.clamp(frequency / 440, 0.05, 20)
			if retrigger then
				self.speaker.TimePosition = 0
			end
		end
	end
	if self.speaker then
		self.speaker.Volume = self.speakerBaseVolume * self.masterGain
	end
end
local carrierSlots = { 3, 4, 5, 11, 12, 13, 19, 20, 21 }
local function rate(n: number): number
	return if n == 0 then 0 else 0.15 * 2 ^ (n / 2)
end
function Audio.update(self: any, dt: number, _cpu: any)
	-- The guest may turn a note on and off inside this CPU slice. Do not
	-- subtract time from before that note was triggered in this same frame.
	if self.speakerFresh then
		self.speakerFresh = false
	else
		self.speakerHold = math.max(0, self.speakerHold - math.max(0, dt))
	end
	if not self.speakerActive and self.speakerHold <= 0 then
		self.speakerBaseVolume = 0
	end
	if self.speaker then
		self.speaker.Volume = self.speakerBaseVolume * self.masterGain
	end
	for i = 0, 8 do
		local voice = self.voices[i + 1]
		local a = self.opl[0xa0 + i] or 0
		local b = self.opl[0xb0 + i] or 0
		local fnum = a + bit32.band(b, 3) * 256
		local block: number = bit32.band(bit32.rshift(b, 2), 7)
		local frequency = fnum * 49716 * 2 ^ (block - 20)
		local on = bit32.band(b, 0x20) ~= 0
		local slot = carrierSlots[i + 1]
		local ad = self.opl[0x60 + slot] or 0
		local sr = self.opl[0x80 + slot] or 0
		local total = bit32.band(self.opl[0x40 + slot] or 0, 63)
		local sustain = 10 ^ (-3 * (bit32.rshift(sr, 4)) / 20)
		if on and not voice.on then
			voice.phase = "attack"
		elseif not on and voice.on then
			voice.phase = "release"
		end
		voice.on = on
		if voice.phase == "attack" then
			voice.level = math.min(1, voice.level + dt * rate(bit32.rshift(ad, 4)))
			if voice.level >= 1 then
				voice.phase = "decay"
			end
		elseif voice.phase == "decay" then
			voice.level = math.max(sustain, voice.level - dt * rate(bit32.band(ad, 15)))
			if voice.level <= sustain then
				voice.phase = "sustain"
			end
		elseif voice.phase == "release" then
			voice.level = math.max(0, voice.level - dt * rate(bit32.band(sr, 15)))
		end
		if voice.sound then
			voice.sound.PlaybackSpeed = math.clamp(frequency / 440, 0.01, 20)
			voice.baseVolume = voice.level * 10 ^ (-0.75 * total / 20) * 0.15
			voice.sound.Volume = voice.baseVolume * self.masterGain
		end
	end
	if self.dmaRemaining > 0 and not self.dmaPaused and not self.dmaMasked then
		self.dmaRemaining -= dt
		if self.dmaRemaining <= 0 then
			local completions = 1
			if self.dmaAuto and self.dmaDuration > 0 then
				completions += math.floor(-self.dmaRemaining / self.dmaDuration)
				self.dmaRemaining += completions * self.dmaDuration
			else
				self.dmaRemaining = 0
			end
			self.pendingIRQCount += completions
			self.pendingIRQ = 0x0f
		end
	end
end
function Audio.bell(self: any)
	self.speakerHold = 0.08
	self.speakerFresh = true
	self.lastTriggeredFreq = 440
	self.speakerBaseVolume = 0.2
	if self.speaker then
		self.speaker.PlaybackSpeed = 1
		self.speaker.TimePosition = 0
		self.speaker.Volume = self.speakerBaseVolume * self.masterGain
	end
end
function Audio.destroy(self: any)
	if self.speaker then
		self.speaker:Destroy()
	end
	if self.pcm then
		self.pcm:Destroy()
	end
	for _, v in ipairs(self.voices) do
		if v.sound then
			v.sound:Destroy()
		end
	end
end
return Audio
