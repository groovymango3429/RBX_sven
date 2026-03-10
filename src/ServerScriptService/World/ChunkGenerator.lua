--[[
  ChunkGenerator  [MODULE SCRIPT]
  ==============
  Procedural terrain generation using continental noise + multi-octave Perlin.

  Terrain layout per column  (H = continuous noise-derived surface height)
  -----------------------------------------------------------------------
    Y = 0                        → Bedrock
    Y = 1 … floor(H)-DEPTH       → Air  (not filled — left as 0 for performance)
    Y = floor(H)-DEPTH+1 … floor(H)-2 → Stone
    Y = floor(H)-1               → Sub-surface block (dirt / sand / stone)
    Y = floor(H)                 → Surface block     (grass / sand / stone / snow)
    Y = floor(H)+1 … WATER_LVL   → Water (only when H < WATER_LEVEL)
    Y > max(floor(H), WATER_LVL) → Air

  Height shaping (oversampled)
  ----------------------------
  Terrain heights come from NoiseConfig.GetHeight(), which combines a
  low-frequency continental layer with oversampled multi-octave detail.
  This keeps plains and mountain ranges broad while smoothing out the
  higher-frequency noise that made the previous terrain look blocky.

  Surface block selection
  -----------------------
    High elevations still become snow / rock, but low-elevation shoreline
    blending now also considers continentalness so inland valleys stay grassy
    more often while beaches remain near coasts and low water-adjacent areas.

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
local SHORE_HEIGHT_BAND = T.SHORE_HEIGHT_BAND
local SURFACE_BLEND_BAND = T.SURFACE_BLEND_BAND
local BEACH_CONTINENTALNESS = T.BEACH_CONTINENTALNESS
-- Continentalness carries most of the inland/coastal signal, while the shore
-- blend adds a smaller local push so beaches stay near water instead of
-- appearing as isolated circular patches deeper inland.
local CONTINENTALNESS_GRASS_WEIGHT = 0.85
local SHORE_BLEND_GRASS_WEIGHT = 0.35

local ChunkGenerator = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Private helpers
-- ────────────────────────────────────────────────────────────────────────────

--- _getHeight: Sample the noise heightmap at world position (wx, wz).
-- Returns a continuous surface height clamped to [HEIGHT_MIN, HEIGHT_MAX].
local function _getHeight(wx, wz)
	return math.clamp(NoiseConfig.GetHeight(wx, wz), HEIGHT_MIN, HEIGHT_MAX)
end

local function _getGrassBlend(h, continentalness)
	local heightBlend = math.clamp(
		(h - (GRASS_HEIGHT - SURFACE_BLEND_BAND)) / math.max(SURFACE_BLEND_BAND, 1),
		0,
		1
	)
	local shoreBlend = math.clamp(
		(h - WATER_LEVEL) / math.max(SHORE_HEIGHT_BAND, 1),
		0,
		1
	)

	return math.max(
		heightBlend,
		continentalness * CONTINENTALNESS_GRASS_WEIGHT + shoreBlend * SHORE_BLEND_GRASS_WEIGHT
	)
end

--- _getSurfaceBlock: Top block ID based on terrain height + continentalness.
local function _getSurfaceBlock(h, continentalness)
	if h >= SNOW_HEIGHT  then return ID_SNOW  end  -- mountain peak
	if h >= ROCK_HEIGHT  then return ID_STONE end  -- rocky hillside

	-- Keep sandy beaches concentrated to genuinely coastal / water-adjacent
	-- lowlands while allowing sheltered inland valleys to stay grassy.
	if h <= WATER_LEVEL + SHORE_HEIGHT_BAND and continentalness < BEACH_CONTINENTALNESS then
		return ID_SAND
	end
	if _getGrassBlend(h, continentalness) >= 0.5 then
		return ID_GRASS
	end
	return ID_SAND
end

--- _getSubSurfaceBlock: Block directly beneath the surface.
local function _getSubSurfaceBlock(h, continentalness)
	if h >= ROCK_HEIGHT  then return ID_STONE end  -- rocky
	if _getSurfaceBlock(h, continentalness) == ID_GRASS then
		return ID_DIRT
	end
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
			local cont     = NoiseConfig.GetContinentalness(wx, originZ + z)
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
				blocks[base + subY * S] = _getSubSurfaceBlock(surfH, cont)
			end

			-- ── Top surface block (grass / sand / stone / snow) ───────────
			if surfY >= 0 and surfY < H then
				blocks[base + surfY * S] = _getSurfaceBlock(surfH, cont)
			end

			-- ── Water fill (columns below sea level) ──────────────────────
			-- Fill from the terrain surface upward, clamped to the chunk height
			-- so submerged columns always receive water instead of exposing rock.
			if surfH < WATER_LEVEL then
				local waterStart = math.max(surfY + 1, 1)
				local waterEnd = math.min(WATER_LEVEL, H - 1)
				for y = waterStart, waterEnd do
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
