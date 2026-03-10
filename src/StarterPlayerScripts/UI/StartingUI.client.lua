local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local readyRemote = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild("World")
	:WaitForChild("MapReadyForSpawn")

-- When CharacterAutoLoads is false the server does not spawn the character
-- until terrain is ready, which means StarterGui contents are never
-- automatically copied to PlayerGui.  Clone the ScreenGui from StarterGui
-- directly so the loading screen is visible immediately on join.
local guiWasCloned = false
local gui = playerGui:FindFirstChild("Starting")
if not gui then
	local template = StarterGui:WaitForChild("Starting", 10)
	if not template then
		warn("[StartingUI] 'Starting' ScreenGui not found in StarterGui — loading screen unavailable.")
		return
	end
	gui = template:Clone()
	gui.Parent = playerGui
	guiWasCloned = true
end

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
		-- Only destroy the GUI if we cloned it ourselves.  If Roblox already
		-- placed it in PlayerGui (e.g. CharacterAutoLoads was re-enabled),
		-- leave it alone so Roblox's own reset logic can manage it.
		if guiWasCloned then
			gui:Destroy()
		end
	end,
})
