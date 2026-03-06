--[[
  ChunkGenerator  [MODULE SCRIPT]
  ==============
  Procedural terrain generation.
  Phase 1: flat terrain + single biome only.
  Future phases: caves, ores, structures (see other World/ modules).

  Flat terrain layout (block Y from bottom)
  ------------------------------------------
    Y = 0               → Bedrock
    Y = 1 … SURFACE_Y-2 → Stone
    Y = SURFACE_Y-1     → Dirt
    Y = SURFACE_Y       → Grass (top surface)
    Y > SURFACE_Y       → Air
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")

local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))
local WorldConstants = require(WorldFolder:WaitForChild("WorldConstants"))
local ChunkData      = require(WorldFolder:WaitForChild("ChunkData"))
local BlockRegistry  = require(WorldFolder:WaitForChild("BlockRegistry"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT
local SURFACE_Y    = WorldConstants.SURFACE_Y_DEFAULT  -- e.g. 64

-- Pre-resolve block IDs once at startup for performance
local ID_AIR        = BlockRegistry.getId("air")        -- 0
local ID_BEDROCK    = BlockRegistry.getId("bedrock")    -- 10
local ID_STONE      = BlockRegistry.getId("stone")      -- 3
local ID_DIRT       = BlockRegistry.getId("dirt")       -- 2
local ID_GRASS      = BlockRegistry.getId("grass")      -- 1

-- Default biome ID for the flat single-biome world (0 = plains / default)
local DEFAULT_BIOME_ID = 0

local ChunkGenerator = {}

-- ────────────────────────────────────────────────────────────────────────────
-- generateFlat: Fill a ChunkData with flat terrain
-- ────────────────────────────────────────────────────────────────────────────

--- generateFlat: Generate flat terrain for the given chunk.
-- All columns get the same vertical profile; biome is uniform.
--
-- Optimization notes
-- ------------------
-- • The biome pass and block pass are merged into a single x,z loop to avoid
--   iterating over all CHUNK_SIZE² columns twice.
-- • Blocks are written directly into chunk.blocks and chunk.biomes rather than
--   going through setBlock/setBiome.  This eliminates:
--     – per-call bounds checks (we know x,y,z are in range)
--     – per-call dirty = true assignments (redundant during generation)
--     – per-call os.time() calls (~5,000+ for a 9×9 chunk at SURFACE_Y=64)
-- • The column base index (for fixed x,z varying y) is pre-computed outside
--   the y-loop so the inner loop only does one addition and one multiplication.
-- • markClean() is still called at the end to clear the dirty flag that
--   ChunkData.new sets (lastModified is set once at construction time).
--
-- @param cx  number  Chunk X in world grid
-- @param cz  number  Chunk Z in world grid
-- @return ChunkData
function ChunkGenerator.generateFlat(cx, cz)
	local chunk  = ChunkData.new(cx, cz)
	local blocks = chunk.blocks
	local biomes = chunk.biomes
	local S      = CHUNK_SIZE
	local H      = CHUNK_HEIGHT

	-- Pre-compute reused values to keep the inner loop tight
	local surfY   = SURFACE_Y          -- grass Y
	local surfM1  = SURFACE_Y - 1      -- dirt Y
	local surfM2  = SURFACE_Y - 2      -- top stone Y

	-- Index formula (mirrors ChunkData._toIndex, 1-based):
	--   index(x,y,z) = x*(H*S) + y*S + z + 1
	-- For a fixed (x,z) column the y=0 base is  x*(H*S) + z + 1
	-- and each successive y adds S to the index.
	for x = 0, S - 1 do
		local xStride = x * (H * S)
		for z = 0, S - 1 do
			-- Biome: write directly, no bounds check needed
			biomes[x * S + z + 1] = DEFAULT_BIOME_ID

			-- Column base index (y = 0)
			local base = xStride + z + 1

			-- Bedrock at Y = 0
			blocks[base] = ID_BEDROCK

			-- Stone: Y = 1 … SURFACE_Y - 2
			for y = 1, surfM2 do
				blocks[base + y * S] = ID_STONE
			end

			-- Dirt at Y = SURFACE_Y - 1
			blocks[base + surfM1 * S] = ID_DIRT

			-- Grass at Y = SURFACE_Y
			blocks[base + surfY * S] = ID_GRASS

			-- Y > SURFACE_Y: already 0 (air) — table.create(VOLUME, 0) in ChunkData.new
		end
	end

	-- Mark clean — freshly generated, nothing to save yet
	chunk:markClean()

	return chunk
end

--- generate: Main entry point.
-- In Phase 1 this delegates directly to generateFlat.
-- Swap in richer generators later without changing call sites.
-- @param cx  number
-- @param cz  number
-- @return ChunkData
function ChunkGenerator.generate(cx, cz)
	return ChunkGenerator.generateFlat(cx, cz)
end

return ChunkGenerator
