--!strict
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local path = process.args[1] or "dist/dos2luau.rbxmx"
local models = roblox.deserializeModel(fs.readFile(path))
assert(#models == 1 and models[1].Name == "dos2luau", "model root")
local root = models[1]
local runtime = root:FindFirstChild("DOS2Luau")
assert(runtime and runtime.ClassName == "ModuleScript", "runtime ModuleScript")
assert(runtime:FindFirstChild("Interpreter") and runtime:FindFirstChild("Out"), "runtime children")
assert(root:FindFirstChild("DOSDemo"), "client entry")
local client = root:FindFirstChild("DOSDemo")
assert(client and client.ClassName == "LocalScript", "client LocalScript")
if string.find(path, "oregon", 1, true) then
	assert(runtime:FindFirstChild("OutOregon"), "game module folder")
	assert(string.find(client.Source, "OutOregon.Program_Meta", 1, true), "game metadata binding")
	assert(not string.find(client.Source, "DOS2LUAU_PROGRAM_OPTIONS", 1, true), "program insertion applied")
	for _, flag in ipairs({ "smartMenuClick", "tapToContinue", "gamepadMenuHighlight", "touchQuickBar" }) do
		assert(string.find(client.Source, flag .. " = true", 1, true), "Oregon assist flag " .. flag)
	end
	assert(not string.find(client.Source, "DOS2LUAU_INPUT_OPTIONS", 1, true), "input insertion applied")
end
fs.writeDir(".test-runtime")
fs.writeFile(".test-runtime/PackagedClient.luau", client.Source)
print("Verified Studio model structure", #runtime:GetDescendants(), "descendants")
fs.writeFile(path:gsub("%.rbxmx$", ".rbxm"), roblox.serializeModel(models))
