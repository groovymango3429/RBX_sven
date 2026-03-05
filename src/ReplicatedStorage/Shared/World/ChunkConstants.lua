--[[
  ChunkConstants  [MODULE SCRIPT]
  ==============
  CHUNK_SIZE=32, RENDER_DISTANCE, LOD tier thresholds
]]

local ChunkConstants = {}

-- Voxel dimensions of a single chunk (width × height × depth)
ChunkConstants.CHUNK_SIZE   = 32
ChunkConstants.CHUNK_HEIGHT = 128  -- vertical slices per chunk column

-- How many chunks away from the player are kept loaded
ChunkConstants.RENDER_DISTANCE = 8   -- in chunk units

-- LOD tier thresholds (distance in chunks)
-- Tier 0 = full detail, Tier 1 = simplified mesh, Tier 2 = billboard / impostor
ChunkConstants.LOD_TIER_0 = 3
ChunkConstants.LOD_TIER_1 = 6
ChunkConstants.LOD_TIER_2 = 8

-- Maximum number of chunks held in the server LRU cache before eviction
ChunkConstants.MAX_CACHE_SIZE = 256

-- Maximum dirty (modified) chunks flushed to DataStore per interval
ChunkConstants.DIRTY_FLUSH_BATCH = 16
ChunkConstants.DIRTY_FLUSH_INTERVAL = 30  -- seconds

return ChunkConstants
