--!strict
local CPUState = require(script.CPUState)
local Bus = require(script.Bus)
local Dispatcher = require(script.Dispatcher)
local Loader = require(script.Loader)
local VFS = require(script.VFS)
local HLE = require(script.InterruptsAndHLE)
local Video = require(script.Video)
local Audio = require(script.Audio)
local Scheduler = require(script.InputAndScheduler)

local DOS = {}
function DOS.new(options: any?): any
	local opts: any = options or {}
	local meta: any = opts.meta or require(script.Out.Program_Meta)
	local blocks: any = opts.blocks or require(script.Out.Blocks)
	local assets: any = opts.assets or require(script.Out.VFS_Assets)
	local cpu: any = CPUState.new()
	local bus: any = Bus.new(if meta.mode32 then 32 * 1024 * 1024 else nil)
	local video: any = Video.new(bus, { imageLabel = opts.imageLabel, headless = opts.headless })
	local audio: any = Audio.new(bus, {
		headless = opts.headless,
		speakerAssetId = opts.speakerAssetId,
		oplAssetId = opts.oplAssetId,
		pcmAssets = opts.pcmAssets,
		onUnknownPCM = opts.onUnknownPCM,
		speakerSound = opts.speakerSound,
		oplSounds = opts.oplSounds,
		pcmSound = opts.pcmSound,
	})
	local vfs: any = VFS.new(assets)
	local hle: any = HLE.new(bus, { vfs = vfs, video = video, audio = audio, clock = opts.clock })
	Loader.load(cpu, bus, meta, opts)
	local dispatcher: any = Dispatcher.new(blocks, meta)
	dispatcher:initialize(cpu, bus)
	local scheduler: any = Scheduler.new(cpu, bus, dispatcher, {
		headless = opts.headless,
		audio = audio,
		video = video,
		instructionsPerSecond = opts.instructionsPerSecond,
		maxInstructionsPerFrame = opts.maxInstructionsPerFrame,
		frameBudgetSeconds = opts.frameBudgetSeconds,
	})
	hle.input = scheduler
	local machine: any = {
		cpu = cpu,
		bus = bus,
		video = video,
		audio = audio,
		vfs = vfs,
		hle = hle,
		dispatcher = dispatcher,
		scheduler = scheduler,
	}
	function machine:start()
		scheduler:start()
	end
	function machine:step(dt: number)
		scheduler:step(dt)
	end
	function machine:stop()
		scheduler:stop()
	end
	function machine:destroy()
		scheduler:destroy()
		audio:destroy()
		if video.image then
			video.image:Destroy()
			video.image = nil
		end
	end
	function machine:exportTrace(): any
		local keys: { number } = {}
		for key in pairs(cpu.discoveredBlocks) do
			table.insert(keys, key)
		end
		table.sort(keys)
		local entries: { any } = {}
		for _, key in ipairs(keys) do
			table.insert(
				entries,
				if cpu.mode32 then { eip = key } else { relCS = bit32.rshift(key, 16), ip = bit32.band(key, 0xffff) }
			)
		end
		return { version = 1, blocks = entries }
	end
	return machine
end
return DOS
