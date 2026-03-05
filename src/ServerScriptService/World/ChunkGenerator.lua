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
-- @param cx  number  Chunk X in world grid
-- @param cz  number  Chunk Z in world grid
-- @return ChunkData
function ChunkGenerator.generateFlat(cx, cz)
	local chunk = ChunkData.new(cx, cz)

	-- Set all columns to the same biome
	for x = 0, CHUNK_SIZE - 1 do
		for z = 0, CHUNK_SIZE - 1 do
			chunk:setBiome(x, z, DEFAULT_BIOME_ID)
		end
	end

	-- Fill every XZ column with the flat profile
	for x = 0, CHUNK_SIZE - 1 do
		for z = 0, CHUNK_SIZE - 1 do
			-- Bedrock layer
			chunk:setBlock(x, 0, z, ID_BEDROCK)

			-- Stone layers (Y = 1 … SURFACE_Y - 2)
			for y = 1, SURFACE_Y - 2 do
				chunk:setBlock(x, y, z, ID_STONE)
			end

			-- Dirt layer
			chunk:setBlock(x, SURFACE_Y - 1, z, ID_DIRT)

			-- Grass surface
			chunk:setBlock(x, SURFACE_Y, z, ID_GRASS)

			-- Everything above is air (already 0 from ChunkData.new)
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
