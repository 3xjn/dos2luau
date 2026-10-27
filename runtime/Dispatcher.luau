--!strict
local CPU = require(script.Parent.CPUState)
local Interpreter = require(script.Parent.Interpreter)
local Dispatcher = {}
Dispatcher.__index = Dispatcher
function Dispatcher.new(blocks: any, meta: any)
	return setmetatable({
		blocks = blocks or {},
		meta = meta or {},
		disabledBlocks = {},
		pagesByBlock = {},
		blocksByPage = {},
		coverageInitialized = false,
	}, Dispatcher)
end
function Dispatcher.initialize(self: any, c: any, b: any)
	local csBase = if c.mode32 then ((c.segmentBases and c.segmentBases[c.cs]) or 0) else 0
	if
		self.coverageInitialized
		and self.boundCPU == c
		and self.boundBus == b
		and self.boundLoadSegment == c.loadSegment
		and self.boundMode32 == c.mode32
		and self.boundCSBase == csBase
	then
		return
	end
	self.disabledBlocks = {}
	self.pagesByBlock = {}
	self.blocksByPage = {}
	self.boundCPU = c
	self.boundBus = b
	self.boundLoadSegment = c.loadSegment
	self.boundMode32 = c.mode32
	self.boundCSBase = csBase
	local image = self.meta.image
	local relocated: any = {}
	if type(image) == "string" and self.meta.format == "mz" then
		for _, rel in ipairs(self.meta.relocations or {}) do
			local at = (rel :: any).segment * 16 + (rel :: any).offset
			local lo = relocated[at] or string.byte(image, at + 1)
			local hi = relocated[at + 1] or string.byte(image, at + 2)
			if lo and hi then
				local value = (lo + hi * 256 + c.loadSegment) % 65536
				relocated[at] = value % 256
				relocated[at + 1] = math.floor(value / 256)
			end
		end
	end
	for key, range in pairs(self.meta.blockRanges or {}) do
		local r: any = range
		local pages: any = {}
		local cs = (c.loadSegment + r.cs) % 65536
		local mismatch = false
		for i = 0, r.length - 1 do
			local off = if c.mode32 then r.ip + i else (r.ip + i) % 65536
			local addr = (if c.mode32 then csBase + off else b.segOffToPhys(cs, off)) % buffer.len(b.ram)
			pages[math.floor(addr / 4096)] = true
			b:markCode(addr, 1)
			if type(image) == "string" then
				local source = if c.mode32
					then off - (self.meta.imageBase or 0)
					else r.cs * 16 + off - (if self.meta.format == "com" then 0x100 else 0)
				local expected = relocated[source] or string.byte(image, source + 1)
				if expected == nil or b:read8(addr) ~= expected then
					mismatch = true
				end
			end
		end
		if mismatch then
			self.disabledBlocks[key] = true
		end
		self.pagesByBlock[key] = pages
		for page in pairs(pages) do
			local keys = self.blocksByPage[page]
			if not keys then
				keys = {}
				self.blocksByPage[page] = keys
			end
			keys[key] = true
		end
	end
	self.coverageInitialized = true
end
function Dispatcher.run(self: any, c: any, b: any, budget: any, deadline: any)
	if (self.meta.mode32 == true) == (c.mode32 == true) then
		self:initialize(c, b)
	end
	while
		budget > 0
		and not c.halted
		and not c.waitingForKey
		and not c.yieldRequested
		and (not deadline or os.clock() < deadline)
	do
		if next(b.invalidatedPages) then
			for page in pairs(b.invalidatedPages) do
				local keys = self.blocksByPage[page]
				if keys then
					for key in pairs(keys) do
						self.disabledBlocks[key] = true
					end
				end
			end
			table.clear(b.invalidatedPages)
		end
		local key = CPU.key(c)
		c.currentBlockKey = key
		-- DPMI real-mode callbacks can share numeric keys with flat EIPs. Their
		-- instruction/address sizes differ, so only use code for the active mode.
		local compatibleMode = (self.meta.mode32 == true) == (c.mode32 == true)
		if compatibleMode then
			self:initialize(c, b)
		end
		local block = if compatibleMode and not self.disabledBlocks[key] then self.blocks[key] else nil
		if block then
			local _, remaining = (block :: any)(c, b, budget)
			if remaining >= budget or remaining < 0 then
				error("Compiled block failed to consume instruction budget at " .. tostring(key))
			end
			local used = budget - remaining
			if self.meta.directBlocks and self.meta.directBlocks[key] then
				self.directInstructions = (self.directInstructions or 0) + used
			else
				self.interpretedInstructions = (self.interpretedInstructions or 0) + used
			end
			budget = remaining
		else
			c.discoveredBlocks[key] = true
			local _, cost = Interpreter.step(c, b)
			if cost <= 0 then
				break
			end
			budget -= cost
			self.interpretedInstructions = (self.interpretedInstructions or 0) + cost
		end
	end
	c.currentBlockKey = CPU.key(c)
	return budget
end
return Dispatcher
