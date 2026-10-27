--!strict
local Bus = require("../runtime/Bus")
local Tracker = require("../runtime/TextRegions")
local Font = require("../runtime/CP437Font")
local CPU = require("../runtime/CPUState")
local Scheduler = require("../runtime/InputAndScheduler")
local Router = require("../runtime/VirtualInputRouter")

local lines = {
	"1. First option",
	"2. Second option",
	"3. Third option",
	"4. Find out the differences",
	"   between these choices",
	"",
	"What is your choice?",
}
local function textContext(source: { string }, shifts: { [number]: number }?): (any, any)
	local bus = Bus.new()
	for row, text in ipairs(source) do
		for col = 1, #text do
			bus:write8(
				0xb8000 + ((row + 3) * 80 + 8 + (if shifts then shifts[row] or 0 else 0) + col - 1) * 2,
				string.byte(text, col)
			)
		end
	end
	local video = { mode = 3, width = 640, height = 200, frameGeneration = 1 }
	return Tracker.new(bus):refresh(video), bus
end
local function graphicsContext(source: { string }, shifts: { [number]: number }?): (any, any)
	local bus = Bus.new()
	local pixels = buffer.create(320 * 200 * 4)
	for i = 0, 320 * 200 - 1 do
		buffer.writeu32(pixels, i * 4, 0xff000000)
	end
	for row, text in ipairs(source) do
		for col = 1, #text do
			local ch = string.byte(text, col)
			for y = 0, 7 do
				local bits = buffer.readu8(Font, ch * 8 + y)
				for x = 0, 7 do
					if bit32.band(bits, bit32.rshift(128, x)) ~= 0 then
						buffer.writeu32(
							pixels,
							(
								(40 + (row - 1) * 9 + y) * 320
								+ 24
								+ (if shifts then shifts[row] or 0 else 0)
								+ (col - 1) * 8
								+ x
							) * 4,
							0xffffffff
						)
					end
				end
			end
		end
	end
	local video = { mode = 0x13, width = 320, height = 200, pixels = pixels, frameGeneration = 1 }
	return Tracker.new(bus):refresh(video), bus
end
local function choiceFour(context: any): any
	assert(#context.choices == 4, "four distinct menu choices")
	local result: any = nil
	for _, region in ipairs(context.regions) do
		if region.digit == 4 then
			assert(result == nil, "only one region for option 4")
			result = region
		end
	end
	assert(result ~= nil, "option 4 recognized")
	return result
end
local function verifyInteraction(context: any, bus: any, x: number, y: number)
	local cpu = CPU.new()
	cpu.waitingForKey = true
	local scheduler = Scheduler.new(cpu, bus, {}, { headless = true })
	local shown: any = nil
	local video = {
		bus = bus,
		getInputContext = function()
			return context
		end,
	}
	local router = Router.new(
		{ cpu = cpu, scheduler = scheduler, bus = bus, video = video, hle = {} },
		{ headless = true, smartMenuClick = true, gamepadMenuHighlight = true }
	)
	router.hud = {
		setMenuHighlight = function(_, region: any, visible: boolean)
			shown = if visible then region else nil
		end,
		setWaiting = function() end,
	}
	router:setInputType("MouseMovement")
	router:pointerMove("mouse", x, y)
	assert(shown and shown.digit == 4, "hover on continuation highlights option 4")
	router:tap(x, y)
	router:update(0)
	local head = bus:read16(0x41a)
	assert(bus:read16(0x400 + head) == 0x0534, "click enqueues digit 4")
	assert(bus:read16(0x400 + head + 2) == 0x1c0d, "click enqueues Enter")
end
local text, textBus = textContext(lines)
local tr = choiceFour(text)
assert(tr.y <= 7 / 25 and tr.y + tr.height >= 9 / 25, "text choice covers both rows")
assert(tr.text == "4. Find out the differences between these choices", "text retains complete choice")
assert(not tr.text:find("What", 1, true), "prompt excluded")
verifyInteraction(text, textBus, 14 / 80, 8.5 / 25)
print("PASS wrapped text-mode choice hover and click")

local graphics, graphicsBus = graphicsContext(lines)
local gr = choiceFour(graphics)
assert(gr.y <= 68 / 200 and gr.y + gr.height >= 82 / 200, "graphics choice covers both rows")
assert(gr.text:find("between these choices", 1, true) ~= nil, "graphics continuation text appended")
verifyInteraction(graphics, graphicsBus, 60 / 320, 79 / 200)
print("PASS wrapped graphics choice hover and click")

for _, make in ipairs({ textContext, graphicsContext }) do
	for _, tail in ipairs({
		{ "", "   Unrelated line" },
		{ "   What is your choice?" },
		{ "   Press SPACE to continue" },
		{ "   Name:" },
	}) do
		local source = table.clone(lines)
		while #source > 4 do
			table.remove(source)
		end
		for _, line in ipairs(tail) do
			table.insert(source, line)
		end
		local context = make(source)
		local r = choiceFour(context)
		assert(r.height < (if make == textContext then 2 / 25 else 15 / 200), "prompt/gap terminates continuation")
	end
	local source = { lines[1], lines[2], lines[3], lines[4], "Unindented text" }
	local context = make(source, { [5] = -8 })
	local r = choiceFour(context)
	assert(r.height < (if make == textContext then 2 / 25 else 15 / 200), "outdent terminates continuation")
	local multiple = make({ lines[1], lines[2], lines[3], lines[4], lines[5], "   further details" })
	assert(
		choiceFour(multiple).height >= (if make == textContext then 3 / 25 else 22 / 200),
		"multiple continuation rows merge"
	)
end
print("PASS prompts, blank lines and outdents stop continuation merging; multiple rows merge")
