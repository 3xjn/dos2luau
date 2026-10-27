--!strict
local Router = require("../runtime/VirtualInputRouter")
local function fixture(): (any, any, any)
	local context: any = {
		menu = true,
		kind = "prompt",
		choices = { 1, 2, 3 },
		regions = {
			{ digit = 1, x = 0, y = 0, width = 1, height = 0.3 },
			{ digit = 2, x = 0, y = 0.3, width = 1, height = 0.3 },
			{ digit = 3, x = 0, y = 0.6, width = 1, height = 0.3 },
		},
	}
	local scheduler: any = {
		options = {},
		events = {},
		keyEvent = function(self: any, name: string, down: boolean)
			table.insert(self.events, { name, down })
		end,
		enqueueWord = function()
			return true
		end,
	}
	local cpu: any = { waitingForKey = true }
	local video: any = {
		bus = {},
		getInputContext = function()
			return context
		end,
	}
	local r: any = Router.new(
		{ cpu = cpu, scheduler = scheduler, video = video, hle = {} },
		{ headless = true, gamepadMenuHighlight = true, smartMenuClick = true, tapToContinue = true }
	)
	return r, scheduler, context
end
local r, s, c = fixture()
r:gamepadButton("DPadDown", true)
assert(r.selected == 2 and #s.events == 0)
r:update(0.31)
assert(r.selected == 2)
r:update(0.02)
assert(r.selected == 3)
r:update(0.22)
assert(r.selected == 2)
r:gamepadButton("DPadDown", false)
r:update(1)
assert(r.selected == 2 and #r.queue == 0 and #s.events == 0)
r:gamepadAxis("Thumbstick1", 0, -0.9)
assert(r.selected == 3)
r:update(0.32)
assert(r.selected == 1)
r:gamepadAxis("Thumbstick1", 0, 0)
r:update(1)
assert(r.selected == 1 and #s.events == 0)
r:keyboardEvent("Down", true)
r:update(0.32)
local before = r.selected
r:keyboardEvent("One", true)
r:update(1)
assert(r.selected == before and r.heldMenuSource == nil)
r:keyboardEvent("One", false)
r:keyboardEvent("Down", false)
r:gamepadButton("DPadDown", true)
r:gamepadButton("DPadUp", false)
assert(r.heldMenuSource == "gamepad:DPadDown")
r:setMenuAssist(false)
assert(r.heldMenuSource == nil)
r:setMenuAssist(true)
r:gamepadButton("DPadDown", true)
c.menu = false
c.textInput = true
c.continuePrompt = true
r:update(1)
assert(r.heldMenuSource == nil)
local queued = #r.queue
r:tap(0.2, 0.2)
assert(#r.queue == queued)
r:releaseAll()
assert(r.heldMenuSource == nil)
print("virtual router repeat tests passed")

r, s, c = fixture()
local menuNow = 0
r.options.headless = false
r.running = true
r.menuClock = function()
	return menuNow
end
r:keyboardEvent("Down", true)
local initial = r.selected
menuNow = 0.01
r:update(1)
assert(r.selected == initial, "time before the menu press does not count toward repeat")
menuNow = 0.34
r:update(0.33)
assert(r.selected ~= initial)
r:keyboardEvent("Down", false)
print("PASS live menu repeat excludes time before the press")

r, s, c = fixture()
c.menu = false
c.textInput = true
c.choices = {}
c.confirmPrompt = { text = "Are these names correct?", x = 0, y = 0.9, width = 0.7, height = 0.04 }
local shown: any = nil
r.hud = {
	setWaiting = function() end,
	setConfirmation = function(_, region: any, visible: boolean)
		shown = if visible then region else nil
	end,
	setMenuHighlight = function() end,
}
r:update(0)
assert(shown == c.confirmPrompt)
r:answerConfirmation("Y")
assert(#r.queue == 2 and r.queue[1][2] == 121 and r.queue[2][2] == 13 and shown == nil)
r.queue = {}
r:answerConfirmation("N")
assert(#r.queue == 2 and r.queue[1][2] == 110 and r.queue[2][2] == 13)
r.queue = {}
r.options.confirmationEnter = false
r:answerConfirmation("Y")
assert(#r.queue == 1 and r.queue[1][2] == 121, "single-key games can opt out of Enter")
r.queue = {}
c.confirmPrompt = nil
r:answerConfirmation("Y")
assert(#r.queue == 0, "stale confirmation button cannot answer another screen")
c.confirmPrompt = { x = 0, y = 0.9, width = 1, height = 0.04 }
r:setMenuAssist(false)
r:answerConfirmation("Y")
assert(#r.queue == 0)
print("PASS explicit confirmation answers and stale/disabled guards")
