--!strict
local CPUState = require(script.Parent.CPUState)
local Loader = {}
local function putString(bus: any, address: number, s: string)
	for i = 1, #s do
		bus:write8(address + i - 1, string.byte(s, i))
	end
end
function Loader.load(cpu: any, bus: any, meta: any, options: any?): any
	options = options or {}
	local format = string.lower(meta.format)
	assert(
		format == "com" or format == "mz" or ((format == "coff" or format == "le") and meta.mode32 == true),
		"Loader: unsupported executable format " .. tostring(format)
	)
	assert(type(meta.image) == "string", "Loader: missing image")
	if meta.mode32 then
		local base = meta.imageBase or 0
		assert(
			base >= 0
				and base == math.floor(base)
				and #meta.image <= 0x2000000
				and base + #meta.image <= math.min(buffer.len(bus.ram), 0x2000000),
			"Loader: flat image exceeds bounded RAM"
		)
		assert(
			(meta.entryIP or -1) >= base and (meta.entryIP or -1) < base + #meta.image,
			"Loader: flat entry outside image"
		)
		assert(
			(meta.initialSP or -1) >= 0 and (meta.initialSP or -1) <= buffer.len(bus.ram),
			"Loader: flat stack outside RAM"
		)
		assert(#(meta.relocations or {}) == 0, "Loader: unresolved flat relocations")
		local image = buffer.fromstring(meta.image)
		-- The first kilobyte is the real-mode IVT. Mapped flat images may reserve it
		-- as zero-filled address space, but cannot replace vectors installed by HLE.
		local lowEnd = math.min(base + #meta.image, 0x400)
		if base < 0x400 then
			for a = base, lowEnd - 1 do
				assert(buffer.readu8(image, a - base) == 0, "Loader: flat image overlaps IVT")
			end
		end
		if base < 0x100000 and base + #meta.image > 0xf0000 then
			for a = math.max(base, 0xf0000), math.min(base + #meta.image, 0x100000) - 1 do
				assert(buffer.readu8(image, a - base) == 0, "Loader: flat image overlaps ROM")
			end
		end
		local start = if bus.hle then math.max(base, 0x400) else base
		for a = start, base + #meta.image - 1 do
			if a < 0xf0000 or a >= 0x100000 then
				bus:write8(a, buffer.readu8(image, a - base))
			end
		end
		-- Reserve conventional low memory for a PSP and environment, without
		-- clobbering non-zero mapped program bytes.
		for a = math.max(base, 0x600), math.min(base + #meta.image, 0x900) - 1 do
			assert(buffer.readu8(image, a - base) == 0, "Loader: flat image overlaps PSP")
		end
		local psp, env = 0x80, 0x60
		for i = 0, 255 do
			bus:write8(psp * 16 + i, 0)
		end
		bus:write8(psp * 16, 0xcd)
		bus:write8(psp * 16 + 1, 0x20)
		bus:write16(psp * 16 + 2, 0x100)
		bus:write16(psp * 16 + 0x16, psp)
		bus:write16(psp * 16 + 0x2c, env)
		for i = 0, 19 do
			bus:write8(psp * 16 + 0x18 + i, if i < 5 then i else 0xff)
		end
		bus:write16(psp * 16 + 0x32, 20)
		bus:write16(psp * 16 + 0x34, 0x18)
		bus:write16(psp * 16 + 0x36, psp)
		bus:write8(psp * 16 + 0x50, 0xcd)
		bus:write8(psp * 16 + 0x51, 0x21)
		bus:write8(psp * 16 + 0x52, 0xcb)
		local tail = string.sub(options.commandTail or "", 1, 126)
		bus:write8(psp * 16 + 0x80, #tail)
		putString(bus, psp * 16 + 0x81, tail)
		bus:write8(psp * 16 + 0x81 + #tail, 13)
		local envText = (options.environment or "COMSPEC=C:\\COMMAND.COM\0PATH=C:\\")
			.. "\0\0"
			.. string.char(1, 0)
			.. (options.programPath or "C:\\GAME.EXE")
			.. "\0"
		assert(#envText <= 0x1f0, "Loader: flat environment too large")
		putString(bus, env * 16, envText)
		cpu.pspSegment = psp
		cpu.memoryEndSegment = 0x100
		cpu.imageStart = base
		cpu.imageEnd = base + #meta.image
		cpu.memoryExtendedStart = math.max(
			0x100000,
			math.ceil((base + #meta.image) / 4096) * 4096,
			math.ceil((meta.initialSP or 0) / 4096) * 4096
		)
		cpu.mode32 = true
		cpu.segmentBases = meta.segmentBases or { [0] = 0 }
		cpu.cs = meta.entryCS or 0
		cpu.ss = meta.initialSS or 0
		cpu.ds = meta.initialDS or 0
		cpu.es = meta.initialES or 0
		cpu.ip = meta.entryIP
		cpu.loadSegment = 0
		CPUState.setReg(cpu, 4, 32, meta.initialSP)
		cpu.currentBlockKey = CPUState.key(cpu)
		cpu.halted, cpu.waitingForKey, cpu.yieldRequested = false, false, false
		cpu.flags = 0x202
		cpu.exitCode = nil
		return { loadSegment = 0, imageBase = base, entryIP = cpu.ip }
	end
	local load = options.loadSegment or 0x1000
	local psp = options.pspSegment or (if format == "com" then load else load - 0x10)
	assert(load >= 0 and psp >= 0 and load <= 0xffff and psp <= 0xffff, "Loader: invalid segment")
	local imageAddress = load * 16 + (if format == "com" then 0x100 else 0)
	assert(imageAddress + #meta.image <= buffer.len(bus.ram), "Loader: image exceeds RAM")
	assert(psp * 16 + 256 <= buffer.len(bus.ram), "Loader: PSP exceeds RAM")
	for i = 0, 255 do
		bus:write8(psp * 16 + i, 0)
	end
	bus:write8(psp * 16, 0xcd)
	bus:write8(psp * 16 + 1, 0x20)
	local endSegment = math.min(0x9fff, math.floor(buffer.len(bus.ram) / 16))
	bus:write16(psp * 16 + 2, endSegment)
	bus:write8(psp * 16 + 5, 0x9a)
	bus:write16(psp * 16 + 0x16, psp)
	for i = 0, 19 do
		bus:write8(psp * 16 + 0x18 + i, if i < 5 then i else 0xff)
	end
	bus:write16(psp * 16 + 0x32, 20)
	bus:write16(psp * 16 + 0x34, 0x18)
	bus:write16(psp * 16 + 0x36, psp)
	bus:write8(psp * 16 + 0x50, 0xcd)
	bus:write8(psp * 16 + 0x51, 0x21)
	bus:write8(psp * 16 + 0x52, 0xcb)
	local tail = string.sub(options.commandTail or "", 1, 126)
	bus:write8(psp * 16 + 0x80, #tail)
	putString(bus, psp * 16 + 0x81, tail)
	bus:write8(psp * 16 + 0x81 + #tail, 13)
	-- Environment is allocated below the PSP, including DOS 3+ executable-name trailer.
	local env = options.environmentSegment or math.max(0x60, psp - 0x100)
	local envText = (options.environment or "COMSPEC=C:\\COMMAND.COM\0PATH=C:\\")
		.. "\0\0"
		.. string.char(1, 0)
		.. (options.programPath or "C:\\GAME.EXE")
		.. "\0"
	assert(env * 16 + #envText <= psp * 16, "Loader: environment overlaps PSP")
	putString(bus, env * 16, envText)
	bus:write16(psp * 16 + 0x2c, env)
	putString(bus, imageAddress, meta.image)
	if format == "mz" then
		for _, rel: any in ipairs(meta.relocations or {}) do
			local off = rel.segment * 16 + rel.offset
			assert(off >= 0 and off + 1 < #meta.image, "Loader: relocation outside image")
			local addr = load * 16 + off
			bus:write16(addr, bit32.band(bus:read16(addr) + load, 0xffff))
		end
	end
	cpu.loadSegment = load
	cpu.cs = bit32.band(load + (meta.entryCS or 0), 0xffff)
	cpu.ip = meta.entryIP or (if format == "com" then 0x100 else 0)
	cpu.ss = bit32.band(load + (meta.initialSS or 0), 0xffff)
	local sp = meta.initialSP or (if format == "com" then 0xfffe else 0)
	CPUState.setReg(cpu, 4, 16, sp)
	cpu.ds, cpu.es = psp, psp
	cpu.halted, cpu.waitingForKey, cpu.yieldRequested = false, false, false
	cpu.flags = 0x202
	cpu.exitCode = nil
	cpu.currentBlockKey = CPUState.key(cpu)
	if format == "com" then
		bus:write16(cpu.ss * 16 + sp, 0)
	end
	cpu.pspSegment = psp
	cpu.memoryEndSegment = endSegment
	local available = endSegment - psp
	local initial = available
	if format == "mz" and meta.maxExtraParagraphs ~= nil and meta.maxExtraParagraphs ~= 0xffff then
		local imageParagraphs = (load - psp) + math.ceil(#meta.image / 16)
		local minimum = meta.minExtraParagraphs or 0
		local maximum = meta.maxExtraParagraphs
		assert(
			maximum >= minimum and imageParagraphs + minimum <= available,
			"Loader: insufficient conventional memory for MZ image"
		)
		initial = math.min(available, imageParagraphs + maximum)
	end
	cpu.initialParagraphs = initial
	cpu.allocatedEndSegment = psp + initial
	local freeSize = available - initial - 1
	local mcb = (psp - 1) * 16
	bus:write8(mcb, if freeSize >= 0 then 0x4d else 0x5a)
	bus:write16(mcb + 1, psp)
	bus:write16(mcb + 3, initial)
	if freeSize >= 0 then
		local freeMcb = (psp + initial) * 16
		bus:write8(freeMcb, 0x5a)
		bus:write16(freeMcb + 1, 0)
		bus:write16(freeMcb + 3, freeSize)
	end
	return { loadSegment = load, pspSegment = psp, environmentSegment = env, endSegment = endSegment }
end
return Loader
