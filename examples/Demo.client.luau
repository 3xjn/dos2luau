--!strict
-- Install runtime as ReplicatedStorage.DOS2Luau and this as a LocalScript in
-- StarterPlayerScripts, or use default.project.json with Rojo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DOS = require(ReplicatedStorage:WaitForChild("DOS2Luau"))
local gui = Instance.new("ScreenGui")
gui.Name = "DOS2LuauDemo"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
local screen = Instance.new("ImageLabel")
screen.Name = "DOSDisplay"
screen.Size = UDim2.fromScale(0.9, 0.85)
screen.AnchorPoint = Vector2.new(0.5, 0.5)
screen.Position = UDim2.fromScale(0.5, 0.46)
screen.BackgroundColor3 = Color3.new(0, 0, 0)
screen.BorderSizePixel = 0
screen.ResampleMode = Enum.ResamplerMode.Pixelated
screen.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 4 / 3
aspect.Parent = screen
local hint = Instance.new("TextLabel")
hint.Name = "Controls"
hint.Size = UDim2.fromScale(1, 0.08)
hint.Position = UDim2.fromScale(0, 0.9)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.new(1, 1, 1)
hint.Text = "dos2luau • Any key changes color • Esc exits"
hint.TextSize = 18
hint.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local machine = DOS.new({
	imageLabel = screen,
	-- DOS2LUAU_PROGRAM_OPTIONS
	-- Supply an owned seamless 440 Hz square-wave asset here to hear the PC speaker.
	-- speakerAssetId='rbxassetid://YOUR_ASSET_ID',
})
machine:start()
gui.Destroying:Connect(function()
	machine:destroy()
end)
