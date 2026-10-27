--!strict
-- Install runtime as ReplicatedStorage.DOS2Luau and this as a LocalScript in
-- StarterPlayerScripts, or use default.project.json with Rojo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local runtime = ReplicatedStorage:WaitForChild("DOS2Luau")
local DOS = require(runtime)
local FullScreenHud = require(runtime.FullScreenHud)
local VirtualInputRouter = require(runtime.VirtualInputRouter)
local SettingsUI = require(runtime.SettingsUI)
local PlayerIsolation = require(runtime.PlayerIsolation)
local isolation = PlayerIsolation.new(Players.LocalPlayer)
isolation:start()
local hud = FullScreenHud.new({})
local gui = hud.gui
local machine = DOS.new({
	imageLabel = hud.imageLabel,
	-- DOS2LUAU_PROGRAM_OPTIONS
	-- speakerAssetId='rbxassetid://YOUR_ASSET_ID',
})
local input = VirtualInputRouter.new(machine, {
	-- DOS2LUAU_INPUT_OPTIONS
})
input:attach(hud)
machine.inputRouter = input
local settings = SettingsUI.new(machine, hud, { router = input })
machine:start()
local cleaned = false
local function cleanup()
	if cleaned then
		return
	end
	cleaned = true
	settings:destroy()
	isolation:destroy()
	machine:destroy()
	hud:destroy()
end
gui.Destroying:Connect(cleanup)
script.Destroying:Connect(cleanup)
