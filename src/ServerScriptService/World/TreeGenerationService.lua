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
		warn("[TreeGenerationService] World folder not found in Workspace")
		return nil
	end
	
	_treesFolder = world:FindFirstChild("Trees")
	if not _treesFolder then
		warn("[TreeGenerationService] Trees folder not found in Workspace.World")
		return nil
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
	
	-- Verify Trees folder exists
	local folder = getTreesFolder()
	if not folder then
		warn("[TreeGenerationService] Trees folder missing. Trees will not spawn.")
	end
	
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
	
	local treesFolder = getTreesFolder()
	if not treesFolder then
		return
	end
	
	-- Spawn trees in this chunk
	TreeSpawner.spawnTreesInChunk(chunk, treesFolder)
	
	-- Mark as complete
	_treesSpawned[key] = true
end

--- clearChunkTrees: Remove spawned trees for a chunk when it's unloaded
-- @param cx number - Chunk X coordinate
-- @param cz number - Chunk Z coordinate
function TreeGenerationService.clearChunkTrees(cx, cz)
	local key = _key(cx, cz)
	_treesSpawned[key] = nil
	TreeSpawner.clearChunkCache(cx, cz)
	
	-- Also remove tree instances from workspace
	local treesFolder = getTreesFolder()
	if not treesFolder then
		return
	end
	
	-- Trees are tagged with chunk coordinates in their name or we'd need
	-- to track them separately. For now, we'll rely on the cache clearing.
	-- In a production system, you might want to tag tree instances with
	-- their chunk coordinates and clean them up here.
end

return TreeGenerationService
