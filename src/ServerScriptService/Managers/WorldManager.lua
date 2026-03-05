--[[
  WorldManager  [MODULE SCRIPT]
  ============
  World init, chunk service boot, first-run POI placement.
  Called by GameManager as part of the main boot sequence.
]]

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local WorldScripts = ServerScriptService:WaitForChild("World")

local Logger      = require(Shared.Core:WaitForChild("Logger"))
local ChunkService = require(WorldScripts:WaitForChild("ChunkService"))

local WorldManager = {}

--- init: Boot the world subsystem
function WorldManager.init()
	Logger.Info("[WorldManager] Initialising world systems…")
	ChunkService.init()
	Logger.Info("[WorldManager] ChunkService ready.")
end

--- onPlayerAdded: Called by GameManager (via PlayerManager) when a player joins
function WorldManager.onPlayerAdded(player)
	ChunkService.onPlayerAdded(player)
	Logger.Debug("[WorldManager] Registered chunks for player: " .. player.Name)
end

--- onPlayerRemoving: Called when a player leaves; releases their chunk subscriptions
function WorldManager.onPlayerRemoving(player)
	ChunkService.onPlayerRemoving(player)
	Logger.Debug("[WorldManager] Released chunks for player: " .. player.Name)
end

return WorldManager
