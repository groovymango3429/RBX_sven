--[[
  ChunkConstants  [MODULE SCRIPT]
  ==============
  CHUNK_SIZE, CHUNK_HEIGHT, RENDER_DISTANCE, LOD tier thresholds
]]

local ChunkConstants = {}

-- Voxel dimensions of a single chunk (width × height × depth)
-- CHUNK_SIZE=9 → each chunk is 9×9 blocks in XZ (36×36 studs at BLOCK_SIZE=4)
-- CHUNK_HEIGHT=128 → vertical slices per column; surface sits at Y=64 leaving
--   64 blocks of build headroom. Keeping this at 128 (not 400) reduces per-chunk
--   voxel count from 32,400 to 10,368 — a 68% drop that cuts memory, serialization
--   bandwidth, and generation time significantly.
ChunkConstants.CHUNK_SIZE   = 16
ChunkConstants.CHUNK_HEIGHT = 128  -- vertical slices per chunk column

-- Studs per voxel block (visual scale, must match ChunkRenderer)
ChunkConstants.BLOCK_SIZE   = 4

-- How many chunks away from the player are kept loaded
-- RENDER_DISTANCE=8 → (2×8+1)²=289 chunks in view per player
ChunkConstants.RENDER_DISTANCE = 8   -- in chunk units

-- LOD tier thresholds (distance in chunks)
-- Tier 0 = full detail, Tier 1 = simplified mesh, Tier 2 = billboard / impostor
ChunkConstants.LOD_TIER_0 = 3
ChunkConstants.LOD_TIER_1 = 6
ChunkConstants.LOD_TIER_2 = 8

-- Maximum number of chunks held in the server LRU cache before eviction.
-- Must exceed (2×RENDER_DISTANCE+1)² = 289 so a single player's full view fits.
-- 1200 gives comfortable headroom for multiple overlapping player views with
-- RENDER_DISTANCE=8 (289 chunks per player).
ChunkConstants.MAX_CACHE_SIZE = 1200

-- Maximum dirty (modified) chunks flushed to DataStore per interval
ChunkConstants.DIRTY_FLUSH_BATCH = 16
ChunkConstants.DIRTY_FLUSH_INTERVAL = 30  -- seconds

return ChunkConstants
