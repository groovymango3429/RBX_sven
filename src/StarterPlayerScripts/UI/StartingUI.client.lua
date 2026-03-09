local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("Starting") -- your ScreenGui name
local main = gui:WaitForChild("Main")
local load = gui:WaitForChild("Load")
local MapLoader = require(player:WaitForChild("PlayerScripts")
	:WaitForChild("WorldClient")
	:WaitForChild("MapLoader")
)

MapLoader.setup({
	button       = main:WaitForChild("GenerateButton"),
	loadingFrame = load:WaitForChild("LoadingFrame"),
	loadingBar   = load:WaitForChild("LoadingFrame"):WaitForChild("BarFill"),
})