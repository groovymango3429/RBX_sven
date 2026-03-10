--[[
  TreeGenerationService  [MODULE SCRIPT]
  =====================
  Server-side service that spawns trees in generated chunks.
  
  Tree spawning happens after terrain chunk generation but before the chunk
  is sent to clients, so trees are in place when players see the terrain.
  
  Called from:
    • WorldManager.init() → TreeGenerationService.init()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldScripts = ServerScriptService:WaitForChild("World")

local Logger = require(Shared.Core:WaitForChild("Logger"))
local TreeSpawner = require(WorldScripts:WaitForChild("TreeSpawner"))

local TreeGenerationService = {}

-- Track which chunks have had trees spawned (to avoid duplication)
-- Format: { [chunkKey] = true }
local _treesSpawned = {}

-- Reference to workspace Trees folder
local _treesFolder = nil

-- ────────────────────────────────────────────────────────────────────────────
-- Private helpers
-- ────────────────────────────────────────────────────────────────────────────

local function getTreesFolder()
	if _treesFolder then
		return _treesFolder
	end
	
	local world = Workspace:FindFirstChild("World")
	if not world then
		-- Create World folder if it doesn't exist (expected on first run)
		Logger.Info("[TreeGenerationService] World folder not found in Workspace, creating it...")
		world = Instance.new("Folder")
		world.Name = "World"
		world.Parent = Workspace
	end
	
	_treesFolder = world:FindFirstChild("Trees")
	if not _treesFolder then
		-- Create Trees folder if it doesn't exist
		Logger.Info("[TreeGenerationService] Trees folder not found in Workspace.World, creating it...")
		_treesFolder = Instance.new("Folder")
		_treesFolder.Name = "Trees"
		_treesFolder.Parent = world
	end
	
	return _treesFolder
end

local function _key(cx, cz)
	return cx .. "," .. cz
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Initialize the tree generation service
function TreeGenerationService.init()
	Logger.Info("[TreeGenerationService] Initializing...")
	
	-- Reset state
	_treesSpawned = {}
	_treesFolder = nil
	
	-- Ensure Trees folder exists (will be created if missing)
	getTreesFolder()
	
	Logger.Info("[TreeGenerationService] Ready")
end

--- spawnTreesForChunk: Generate trees for a specific chunk if not already done
-- @param chunk ChunkData - The generated terrain chunk
function TreeGenerationService.spawnTreesForChunk(chunk)
	if not chunk then
		return
	end
	
	local key = _key(chunk.cx, chunk.cz)
	
	-- Skip if trees already spawned for this chunk
	if _treesSpawned[key] then
		return
	end
	
	-- Get or create trees folder
	local treesFolder = getTreesFolder()
	
	-- Spawn trees in this chunk
	TreeSpawner.spawnTreesInChunk(chunk, treesFolder)
	
	-- Mark as complete
	_treesSpawned[key] = true
end

--- Clear cached tree positions for a chunk (call when chunk is unloaded)
-- @param cx number - Chunk X coordinate
-- @param cz number - Chunk Z coordinate
function TreeGenerationService.clearChunkTrees(cx, cz)
	local key = _key(cx, cz)
	_treesSpawned[key] = nil
	TreeSpawner.clearChunkCache(cx, cz)
	
	-- NOTE: Tree instances are not automatically removed from workspace when chunks unload.
	-- In a full implementation, you would need to track spawned tree instances per chunk
	-- (e.g., by tagging them with chunk coordinates) and remove them here to prevent
	-- memory leaks. For now, trees persist once spawned.
end

return TreeGenerationService
