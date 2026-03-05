--[[
  WorldManager  [MODULE SCRIPT]
  ============
  World init, chunk service boot, streaming service boot, first-run POI placement.
  Called by GameManager as part of the main boot sequence.

  Call chain for player join:
    GameManager (Players.PlayerAdded) → WorldManager.onPlayerAdded(player)
      → ChunkService.onPlayerAdded(player)        (register chunk subscriptions)
      → StreamingService.onPlayerAdded(player)    (stream initial chunks to client)
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local WorldScripts = ServerScriptService:WaitForChild("World")

local Logger          = require(Shared.Core:WaitForChild("Logger"))
local ChunkService    = require(WorldScripts:WaitForChild("ChunkService"))
local StreamingService = require(WorldScripts:WaitForChild("StreamingService"))

local WorldManager = {}

--- init: Boot the world subsystem (called once from GameManager)
function WorldManager.init()
	Logger.Info("[WorldManager] Initialising world systems…")
	ChunkService.init()
	Logger.Info("[WorldManager] ChunkService ready.")
	StreamingService.init()
	Logger.Info("[WorldManager] StreamingService ready.")
	Logger.Info("[WorldManager] All world systems online ✓")
end

--- onPlayerAdded: Called by GameManager when a player joins.
-- WHERE THIS IS CALLED:
--   GameManager.server.lua → Players.PlayerAdded → WorldManager.onPlayerAdded(player)
function WorldManager.onPlayerAdded(player)
	Logger.Info("[WorldManager] Player joined: " .. player.Name .. " — registering chunks & streaming…")
	ChunkService.onPlayerAdded(player)
	StreamingService.onPlayerAdded(player)
end

--- onPlayerRemoving: Called by GameManager when a player leaves.
function WorldManager.onPlayerRemoving(player)
	StreamingService.onPlayerRemoving(player)
	ChunkService.onPlayerRemoving(player)
	Logger.Debug("[WorldManager] Released chunks for player: " .. player.Name)
end

return WorldManager
