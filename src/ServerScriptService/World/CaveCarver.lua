--[[
  CaveCarver  [MODULE SCRIPT]
  ==========
  Post-processes a generated ChunkData by hollowing out underground voxels
  using two complementary 3-D noise passes:

    1. Spaghetti tunnels
       Two perpendicular noise channels n1, n2 sampled at the same scale but
       with different seeds.  A voxel becomes a tunnel where:
           n1² + n2² < CAVE_THRESHOLD_SQ
       This carves curved, worm-like passages of roughly circular cross-section.

    2. Cheese caverns
       A single noise channel nc.  A voxel becomes a cavern where:
           |nc| < CAVE_CHEESE_THRESHOLD
       This carves large, irregular open chambers that intersect the tunnels.

  Depth constraints
  -----------------
  Neither pass touches voxels within CAVE_MIN_DEPTH / CAVE_CHEESE_MIN_DEPTH
  blocks of the column's surface, so caves never breach the ground.  Bedrock
  (y = 0) is always preserved.

  Usage
  -----
    CaveCarver.carveChunk(chunk, cx, cz, heightMap)

    heightMap  table  Flat array [x*S+z+1] = floor(surfaceHeight), same
                       indexing as ChunkData.blocks.  Pre-computed by
                       ChunkGenerator to avoid double noise evaluation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")

local WorldGenConfig  = require(WorldFolder:WaitForChild("WorldGenConfig"))
local BlockRegistry   = require(WorldFolder:WaitForChild("BlockRegistry"))
local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))

local caveCfg     = WorldGenConfig.Caves
local CHUNK_SIZE  = ChunkConstants.CHUNK_SIZE
local CHUNK_HEIGHT= ChunkConstants.CHUNK_HEIGHT

-- Block IDs
local ID_AIR    = 0
local ID_BEDROCK = BlockRegistry.getId("bedrock")
local ID_WATER  = BlockRegistry.getId("water")

-- ── Cave parameters (read once at load for speed) ─────────────────────────────
local CAVE_SCALE       = caveCfg.CAVE_SCALE
local CAVE_SEED_1      = caveCfg.CAVE_SEED_1
local CAVE_SEED_2      = caveCfg.CAVE_SEED_2
local THRESHOLD_SQ     = caveCfg.CAVE_THRESHOLD_SQ
local CHEESE_SCALE     = caveCfg.CAVE_CHEESE_SCALE
local CHEESE_SEED      = caveCfg.CAVE_CHEESE_SEED
local CHEESE_THRESH    = caveCfg.CAVE_CHEESE_THRESHOLD
local CAVE_MIN_DEPTH   = caveCfg.CAVE_MIN_DEPTH
local CHEESE_MIN_DEPTH = caveCfg.CAVE_CHEESE_MIN_DEPTH

local CaveCarver = {}

--- carveChunk: Apply 3-D noise cave carving to an already-generated chunk.
--
-- Only solid, non-bedrock, non-water blocks that lie at least CAVE_MIN_DEPTH
-- below the column surface are candidates for removal.
--
-- @param chunk      ChunkData   The terrain chunk to modify in-place.
-- @param cx         number      Chunk X coordinate.
-- @param cz         number      Chunk Z coordinate.
-- @param heightMap  table       [x*S+z+1] = floor(surfaceHeight) per column.
function CaveCarver.carveChunk(chunk, cx, cz, heightMap)
	local blocks  = chunk.blocks
	local originX = cx * CHUNK_SIZE
	local originZ = cz * CHUNK_SIZE
	local S       = CHUNK_SIZE
	local H       = CHUNK_HEIGHT

	for x = 0, S - 1 do
		local wx      = originX + x
		local xStride = x * (H * S)
		-- Pre-scale world X for noise sampling (avoids repeated multiply in Y loop)
		local wxC  = wx * CAVE_SCALE
		local wxCh = wx * CHEESE_SCALE

		for z = 0, S - 1 do
			local wz     = originZ + z
			local surfY  = heightMap[x * S + z + 1]

			-- Highest Y that tunnels / caverns may reach for this column
			local maxTunnelY = surfY - CAVE_MIN_DEPTH
			local maxCheeseY = surfY - CHEESE_MIN_DEPTH

			-- Nothing to carve if the ceiling is at or below bedrock
			if maxTunnelY < 1 and maxCheeseY < 1 then
				continue
			end

			local wzC  = wz * CAVE_SCALE
			local wzCh = wz * CHEESE_SCALE

			-- Iterate only the range that either pass can affect
			local yTop = math.max(maxTunnelY, maxCheeseY)
			if yTop < 1 then yTop = 1 end

			for y = 1, yTop do
				local idx     = xStride + y * S + z + 1
				local blockId = blocks[idx]

				-- Skip air, bedrock, and water — only carve solid terrain blocks
				if blockId == ID_AIR or blockId == ID_BEDROCK or blockId == ID_WATER then
					continue
				end

				local wyC  = y * CAVE_SCALE
				local wyCh = y * CHEESE_SCALE
				local carved = false

				-- ── Pass 1: Spaghetti tunnels ─────────────────────────────
				if y <= maxTunnelY then
					local n1 = math.noise(wxC,           wyC, wzC + CAVE_SEED_1)
					local n2 = math.noise(wxC + CAVE_SEED_2, wyC, wzC)
					if (n1 * n1 + n2 * n2) < THRESHOLD_SQ then
						carved = true
					end
				end

				-- ── Pass 2: Cheese caverns ────────────────────────────────
				if not carved and y <= maxCheeseY then
					local nc = math.noise(wxCh, wyCh, wzCh + CHEESE_SEED)
					if math.abs(nc) < CHEESE_THRESH then
						carved = true
					end
				end

				if carved then
					blocks[idx] = ID_AIR
				end
			end
		end
	end
end

return CaveCarver
