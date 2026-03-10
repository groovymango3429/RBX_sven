--[[
  WorldConstants  [MODULE SCRIPT]
  ==============
  World size limits, sea level, max build height, safe spawn region
]]

local WorldConstants = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")
local WorldGenConfig = require(WorldFolder:WaitForChild("WorldGenConfig"))
local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))

local mapConfig = WorldGenConfig.Map
local terrainConfig = WorldGenConfig.Terrain

-- World bounds in chunk coordinates (origin at 0,0)
WorldConstants.WORLD_SIZE_CHUNKS = mapConfig.WorldSizeChunks

-- Vertical limits in block units
WorldConstants.SEA_LEVEL       = terrainConfig.WATER_LEVEL
WorldConstants.MIN_WORLD_Y     = 0
WorldConstants.MAX_BUILD_HEIGHT = ChunkConstants.CHUNK_HEIGHT

-- Surface terrain sits in this range (local block Y)
WorldConstants.SURFACE_Y_DEFAULT = math.floor(
	(terrainConfig.HEIGHT_MIN + terrainConfig.HEIGHT_MAX) * 0.5
)
WorldConstants.BEDROCK_Y         = 0

-- Safe spawn radius around world origin (in blocks)
WorldConstants.SPAWN_SAFE_RADIUS = mapConfig.SpawnSafeRadius

return WorldConstants
