--[[
  ChunkGenerator  [MODULE SCRIPT]
  ==============
  Procedural terrain generation using continental noise + multi-octave Perlin.

  Terrain layout per column  (H = noise-derived surface height)
  -------------------------------------------------------------
    Y = 0               → Bedrock
    Y = 1 … H-DEPTH     → Air  (not filled — left as 0 for performance)
    Y = H-DEPTH+1 … H-2 → Stone
    Y = H-1             → Sub-surface block (dirt / sand / stone)
    Y = H               → Surface block     (grass / sand / stone / snow)
    Y = H+1 … WATER_LVL → Water (only when H < WATER_LEVEL)
    Y > max(H, WATER_LVL) → Air

  Height shaping (oversampled)
  ----------------------------
  Terrain heights come from NoiseConfig.GetHeight(), which combines a
  low-frequency continental layer with oversampled multi-octave detail.
  This keeps plains and mountain ranges broad while smoothing out the
  higher-frequency noise that made the previous terrain look blocky.

  Surface block selection by height  (thresholds from NoiseConfig.TERRAIN)
  ----------------------------------
    H ≥ SNOW_HEIGHT  → Snow   (high mountain)
    H ≥ ROCK_HEIGHT  → Stone  (rocky hillside)
    H ≥ GRASS_HEIGHT → Grass  (plains / hills)
    H < GRASS_HEIGHT → Sand   (beach / lake floor)

  Water fill
  ----------
  When H < WATER_LEVEL, the column is filled with water from H+1 up to
  WATER_LEVEL, creating lakes and low-lying water regions naturally.

  Performance notes
  -----------------
  • Only UNDERGROUND_DEPTH blocks per column are filled as solid — all
    deeper blocks stay as air (table.create initialises to 0).  This cuts
    stone writes by ~75 % compared to the old flat generator.
  • Height sampling avoids Vector3 / object allocation by using plain numbers.
  • markClean() is called once at the end, not inside the loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")

local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))
local ChunkData      = require(WorldFolder:WaitForChild("ChunkData"))
local BlockRegistry  = require(WorldFolder:WaitForChild("BlockRegistry"))
local NoiseConfig    = require(WorldFolder:WaitForChild("NoiseConfig"))
local WorldConstants = require(WorldFolder:WaitForChild("WorldConstants"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT

-- Pre-resolve block IDs once at startup for performance
local ID_BEDROCK = BlockRegistry.getId("bedrock")  -- 10
local ID_STONE   = BlockRegistry.getId("stone")    -- 3
local ID_DIRT    = BlockRegistry.getId("dirt")     -- 2
local ID_GRASS   = BlockRegistry.getId("grass")    -- 1
local ID_SAND    = BlockRegistry.getId("sand")     -- 4
local ID_SNOW    = BlockRegistry.getId("snow")     -- 18
local ID_WATER   = BlockRegistry.getId("water")    -- 11

-- Default biome ID (0 = plains / default)
local DEFAULT_BIOME_ID = 0

-- Noise configuration (read once for speed)
local T           = NoiseConfig.TERRAIN
local HEIGHT_MIN  = T.HEIGHT_MIN
local HEIGHT_MAX  = T.HEIGHT_MAX
local DEPTH       = T.UNDERGROUND_DEPTH
local WATER_LEVEL = T.WATER_LEVEL
local SNOW_HEIGHT  = T.SNOW_HEIGHT
local ROCK_HEIGHT  = T.ROCK_HEIGHT
local GRASS_HEIGHT = T.GRASS_HEIGHT

local ChunkGenerator = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Private helpers
-- ────────────────────────────────────────────────────────────────────────────

--- _getHeight: Sample the noise heightmap at world position (wx, wz).
-- Returns a continuous surface height clamped to [HEIGHT_MIN, HEIGHT_MAX].
local function _getHeight(wx, wz)
	return math.clamp(NoiseConfig.GetHeight(wx, wz), HEIGHT_MIN, HEIGHT_MAX)
end

--- _getSurfaceBlock: Top block ID based on terrain height.
local function _getSurfaceBlock(h)
	if h >= SNOW_HEIGHT  then return ID_SNOW  end  -- mountain peak
	if h >= ROCK_HEIGHT  then return ID_STONE end  -- rocky hillside
	if h >= GRASS_HEIGHT then return ID_GRASS end  -- plains
	return ID_SAND                                 -- lowland / beach
end

--- _getSubSurfaceBlock: Block directly beneath the surface.
local function _getSubSurfaceBlock(h)
	if h >= ROCK_HEIGHT  then return ID_STONE end  -- rocky
	if h >= GRASS_HEIGHT then return ID_DIRT  end  -- grassy biome
	return ID_SAND                                 -- sandy biome
end

-- ────────────────────────────────────────────────────────────────────────────
-- generateNoise: Fill a ChunkData with noise-based terrain
-- ────────────────────────────────────────────────────────────────────────────

--- generateNoise: Generate noise-based terrain for the given chunk.
--
-- Only UNDERGROUND_DEPTH blocks per column are written as solid — everything
-- deeper stays as air (0).  This significantly reduces block writes and
-- speeds up generation without affecting the visible surface.
--
-- @param cx  number  Chunk X in world grid
-- @param cz  number  Chunk Z in world grid
-- @return ChunkData
function ChunkGenerator.generateNoise(cx, cz)
	local chunk  = ChunkData.new(cx, cz)
	local blocks = chunk.blocks
	local biomes = chunk.biomes
	local S      = CHUNK_SIZE
	local H      = CHUNK_HEIGHT

	-- World-space block origin of this chunk
	local originX = cx * S
	local originZ = cz * S

	for x = 0, S - 1 do
		local xStride = x * (H * S)
		local wx      = originX + x
		for z = 0, S - 1 do
			-- Biome (uniform plains for now)
			biomes[x * S + z + 1] = DEFAULT_BIOME_ID

			-- Surface height for this column
			local surfH    = _getHeight(wx, originZ + z)
			local surfY    = math.floor(surfH)
			-- Base flat index for (x, y=0, z) — adding y*S gives (x, y, z)
			local base     = xStride + z + 1

			-- ── Bedrock ───────────────────────────────────────────────────
			blocks[base] = ID_BEDROCK

			-- ── Stone fill ────────────────────────────────────────────────
			-- Only fill from (surfY - DEPTH + 1) down to (surfY - 2).
			-- Y = 1 .. surfY - DEPTH remain air for performance.
			local stoneStart = math.max(1, surfY - DEPTH + 1)
			local stoneEnd   = surfY - 2
			for y = stoneStart, stoneEnd do
				blocks[base + y * S] = ID_STONE
			end

			-- ── Sub-surface block (dirt / sand) ───────────────────────────
			local subY = surfY - 1
			if subY >= 1 and subY < H then
				blocks[base + subY * S] = _getSubSurfaceBlock(surfH)
			end

			-- ── Top surface block (grass / sand / stone / snow) ───────────
			if surfY >= 0 and surfY < H then
				blocks[base + surfY * S] = _getSurfaceBlock(surfH)
			end

			-- ── Water fill (columns below sea level) ──────────────────────
			-- surfH < GRASS_HEIGHT already ensures sand surface/sub-surface,
			-- so we only need to place the water blocks above the floor.
			-- WATER_LEVEL (50) is always well below CHUNK_HEIGHT (128),
			-- so no upper-bound clamp against H is required here.
			if surfH < WATER_LEVEL then
				for y = surfY + 1, WATER_LEVEL do
					blocks[base + y * S] = ID_WATER
				end
			end

			-- Y > max(surfH, WATER_LEVEL) is already 0 (air)
		end
	end

	-- Mark clean — freshly generated, nothing to save yet
	chunk:markClean()

	return chunk
end

-- ────────────────────────────────────────────────────────────────────────────
-- Legacy flat generator — kept for backward compatibility / testing
-- ────────────────────────────────────────────────────────────────────────────

--- generateFlat: Generate the original flat terrain (all columns at SURFACE_Y).
-- @param cx  number
-- @param cz  number
-- @return ChunkData
function ChunkGenerator.generateFlat(cx, cz)
	local chunk  = ChunkData.new(cx, cz)
	local blocks = chunk.blocks
	local biomes = chunk.biomes
	local S      = CHUNK_SIZE
	local H      = CHUNK_HEIGHT

	local surfY  = WorldConstants.SURFACE_Y_DEFAULT
	local surfM1 = surfY - 1
	local surfM2 = surfY - 2

	for x = 0, S - 1 do
		local xStride = x * (H * S)
		for z = 0, S - 1 do
			biomes[x * S + z + 1] = DEFAULT_BIOME_ID
			local base = xStride + z + 1
			blocks[base] = ID_BEDROCK
			for y = 1, surfM2 do
				blocks[base + y * S] = ID_STONE
			end
			blocks[base + surfM1 * S] = ID_DIRT
			blocks[base + surfY  * S] = ID_GRASS
		end
	end

	chunk:markClean()
	return chunk
end

--- generate: Main entry point — uses noise terrain.
-- @param cx  number
-- @param cz  number
-- @return ChunkData
function ChunkGenerator.generate(cx, cz)
	return ChunkGenerator.generateNoise(cx, cz)
end

return ChunkGenerator
