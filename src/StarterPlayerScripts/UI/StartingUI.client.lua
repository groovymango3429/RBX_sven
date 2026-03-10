local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local readyRemote = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild("World")
	:WaitForChild("MapReadyForSpawn")

local gui = playerGui:WaitForChild("Starting") -- your ScreenGui name
local main = gui:WaitForChild("Main")
local load = gui:WaitForChild("Load")
local MapLoader = require(player:WaitForChild("PlayerScripts")
	:WaitForChild("WorldClient")
	:WaitForChild("MapLoader")
)

MapLoader.setup({
	button       = main:WaitForChild("GenerateButton"),
	screenGui    = gui,
	menuFrame    = main,
	loadingScreen = load,
	loadingFrame = load:WaitForChild("LoadingFrame"),
	loadingBar   = load:WaitForChild("LoadingFrame"):WaitForChild("BarFill"),
	autoTrigger  = true,
	onLoaded     = function()
		readyRemote:FireServer()
	end,
})
