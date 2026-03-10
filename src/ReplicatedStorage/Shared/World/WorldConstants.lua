--[[
  WorldConstants  [MODULE SCRIPT]
  ==============
  World size limits, sea level, max build height, safe spawn region
]]

local WorldConstants = {}

-- World bounds in chunk coordinates (origin at 0,0)
WorldConstants.WORLD_SIZE_CHUNKS = 1068   -- 512×512 chunk grid (16 384 × 16 384 blocks)

-- Vertical limits in block units
WorldConstants.SEA_LEVEL       = 64
WorldConstants.MIN_WORLD_Y     = 0
WorldConstants.MAX_BUILD_HEIGHT = 256   -- hard ceiling for player-placed blocks

-- Surface terrain sits in this range (local block Y)
WorldConstants.SURFACE_Y_DEFAULT = 64   -- flat biome ground level (block Y)
WorldConstants.BEDROCK_Y         = 0

-- Safe spawn radius around world origin (in blocks)
WorldConstants.SPAWN_SAFE_RADIUS = 128

return WorldConstants
