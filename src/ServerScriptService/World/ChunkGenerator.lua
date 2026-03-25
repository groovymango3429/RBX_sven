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
  low-frequency continental layer with oversampled multi-octave detail and
  a ridged-noise blend for sharper mountain peaks.

  Surface block selection
  -----------------------
  A two-pass strategy is used:
    1. Pre-compute all column heights, continentalness values, and biome IDs
       into flat cache arrays.  This eliminates redundant noise calls and
       makes the data available to CaveCarver without re-sampling.
    2. For each column, altitude overrides (snow peak, rocky hillside) take
       priority; below those thresholds the biome's palette is used.  The
       original beach/shore blend is preserved for coastal columns.

  Cave generation
  ---------------
  After terrain fill, CaveCarver.carveChunk() hollows out underground stone
  using 3-D spaghetti-tunnel and cheese-cavern noise, depth-gated so caves
  never break the surface.

  Water fill
  ----------
  When H < WATER_LEVEL, the column is filled with water from H+1 up to
  WATER_LEVEL, creating lakes and low-lying water regions naturally.

  Performance notes
  -----------------
  • Per-chunk column cache (heightMap / contMap / biomeMap) computed upfront
    so each noise query happens exactly once per column.
  • Only UNDERGROUND_DEPTH blocks per column are filled as solid.
  • CaveCarver receives the pre-computed heightMap — no double noise eval.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")

local ServerScriptService = game:GetService("ServerScriptService")
local WorldScripts        = ServerScriptService:WaitForChild("World")

local ChunkConstants    = require(WorldFolder:WaitForChild("ChunkConstants"))
local ChunkData         = require(WorldFolder:WaitForChild("ChunkData"))
local BlockRegistry     = require(WorldFolder:WaitForChild("BlockRegistry"))
local NoiseConfig       = require(WorldFolder:WaitForChild("NoiseConfig"))
local WorldConstants    = require(WorldFolder:WaitForChild("WorldConstants"))
local BiomeDefinitions  = require(WorldFolder:WaitForChild("BiomeDefinitions"))

local BiomeMapper  = require(WorldScripts:WaitForChild("BiomeMapper"))
local CaveCarver   = require(WorldScripts:WaitForChild("CaveCarver"))

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

-- Pre-resolve biome surface/sub-surface block IDs for all registered biomes.
-- This avoids string lookups inside the hot generation loop.
local _biomeSurface    = {}  -- [biomeId] = surfaceBlockId
local _biomeSubSurface = {}  -- [biomeId] = subSurfaceBlockId
for id, def in pairs(BiomeDefinitions.Biomes) do
	_biomeSurface[id]    = BlockRegistry.getId(def.surfaceBlock)
	_biomeSubSurface[id] = BlockRegistry.getId(def.subSurfaceBlock)
end

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

-- Desert biome ID shortcut for the beach-override check
local BIOME_DESERT = BiomeDefinitions.DESERT

local ChunkGenerator = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Private helpers
-- ────────────────────────────────────────────────────────────────────────────

--- _getHeight: Sample the noise heightmap at world position (wx, wz).
-- Returns a continuous surface height clamped to [HEIGHT_MIN, HEIGHT_MAX]
-- and the continentalness value so callers don't need to recompute it.
-- Applies river carving and lake lowering where appropriate.
local function _getHeight(wx, wz)
	local cont = NoiseConfig.GetContinentalness(wx, wz)
	local baseHeight = math.clamp(NoiseConfig.GetHeight(wx, wz, cont), HEIGHT_MIN, HEIGHT_MAX)
	
	-- Apply river carving
	local riverInfluence = NoiseConfig.GetRiverInfluence(wx, wz)
	if riverInfluence > 0 then
		-- Rivers carve deeper into terrain, creating downhill flow paths
		baseHeight = baseHeight - (riverInfluence * T.RIVER_DEPTH)
	end
	
	-- Apply lake lowering in appropriate areas (now with smooth transitions)
	local lakeInfluence = NoiseConfig.IsLakePosition(wx, wz, cont)
	if lakeInfluence > 0 and baseHeight > WATER_LEVEL then
		-- Lower terrain in lake basins with smooth blending
		baseHeight = baseHeight - (lakeInfluence * T.LAKE_DEPTH_OFFSET)
	end
	
	return math.clamp(baseHeight, HEIGHT_MIN, HEIGHT_MAX), cont
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

--- _getSurfaceBlock: Top block ID based on terrain height, continentalness,
-- and biome.  Altitude overrides (snow peaks, rocky hillsides) take priority.
-- Coastal sand blending is suppressed for desert biomes (already sandy).
local function _getSurfaceBlock(h, continentalness, biomeId)
	-- ── Altitude overrides (independent of biome) ─────────────────────────
	if h >= SNOW_HEIGHT then return ID_SNOW  end
	if h >= ROCK_HEIGHT  then return ID_STONE end

	-- ── Coastal sand strip (skip for desert — it's sand anyway) ───────────
	if biomeId ~= BIOME_DESERT
		and h <= WATER_LEVEL + SHORE_HEIGHT_BAND
		and continentalness < BEACH_CONTINENTALNESS then
		return ID_SAND
	end

	-- ── Biome-determined surface block ────────────────────────────────────
	local biomeBlockId = _biomeSurface[biomeId]
	if biomeBlockId then
		return biomeBlockId
	end

	-- ── Fallback: original grass-blend logic ──────────────────────────────
	if _getGrassBlend(h, continentalness) >= 0.5 then
		return ID_GRASS
	end
	return ID_SAND
end

--- _getSubSurfaceBlock: Block directly beneath the surface, biome-aware.
local function _getSubSurfaceBlock(h, continentalness, biomeId)
	if h >= ROCK_HEIGHT then return ID_STONE end

	local biomeBlockId = _biomeSubSurface[biomeId]
	if biomeBlockId then
		return biomeBlockId
	end

	-- Fallback
	if _getSurfaceBlock(h, continentalness, biomeId) == ID_GRASS then
		return ID_DIRT
	end
	return ID_SAND
end

-- ────────────────────────────────────────────────────────────────────────────
-- generateNoise: Fill a ChunkData with noise-based terrain
-- ────────────────────────────────────────────────────────────────────────────

--- generateNoise: Generate noise-based terrain for the given chunk.
--
-- Two-phase approach:
--   Phase 1 — Pre-compute height / continentalness / biome for every column.
--             Stores results in flat cache arrays so Phase 2 and CaveCarver
--             can share the data without re-evaluating noise.
--   Phase 2 — Fill voxel data using the cached column values.
--   Phase 3 — Post-process with CaveCarver (3-D cave hollowing).
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

	-- ── Phase 1: Pre-compute per-column data ────────────────────────────────
	-- colIdx = x * S + z + 1  (same convention as ChunkData biomes array)
	local heightMap  = table.create(S * S, 0)  -- continuous surface heights
	local surfYMap   = table.create(S * S, 0)  -- floor(surfaceHeight)
	local contMap    = table.create(S * S, 0)  -- continentalness [0,1]
	local biomeMap   = table.create(S * S, 0)  -- biome ID

	for x = 0, S - 1 do
		local wx = originX + x
		for z = 0, S - 1 do
			local wz  = originZ + z
			local idx = x * S + z + 1

			local surfH, cont = _getHeight(wx, wz)
			local biomeId     = BiomeMapper.getBiomeAt(wx, wz)

			heightMap[idx] = surfH
			surfYMap[idx]  = math.floor(surfH)
			contMap[idx]   = cont
			biomeMap[idx]  = biomeId
		end
	end

	-- ── Phase 2: Voxel fill using cached column data ─────────────────────────
	for x = 0, S - 1 do
		local xStride = x * (H * S)
		for z = 0, S - 1 do
			local colIdx  = x * S + z + 1
			local surfH   = heightMap[colIdx]
			local surfY   = surfYMap[colIdx]
			local cont    = contMap[colIdx]
			local biomeId = biomeMap[colIdx]

			-- Write biome ID into the chunk for downstream consumers (TreeSpawner, etc.)
			biomes[colIdx] = biomeId

			-- Base flat index for (x, y=0, z) — adding y*S gives (x, y, z)
			local base = xStride + z + 1

			-- ── Bedrock ─────────────────────────────────────────────────
			blocks[base] = ID_BEDROCK

			-- ── Stone fill ──────────────────────────────────────────────
			-- Only fill from (surfY - DEPTH + 1) down to (surfY - 2).
			local stoneStart = math.max(1, surfY - DEPTH + 1)
			local stoneEnd   = surfY - 2
			for y = stoneStart, stoneEnd do
				blocks[base + y * S] = ID_STONE
			end

			-- ── Sub-surface block (dirt / sand / stone) ─────────────────
			local subY = surfY - 1
			if subY >= 1 and subY < H then
				blocks[base + subY * S] = _getSubSurfaceBlock(surfH, cont, biomeId)
			end

			-- ── Top surface block ────────────────────────────────────────
			if surfY >= 0 and surfY < H then
				blocks[base + surfY * S] = _getSurfaceBlock(surfH, cont, biomeId)
			end

			-- ── Water fill (columns below sea level) ────────────────────
			if surfH < WATER_LEVEL then
				local waterStart = math.max(surfY + 1, 1)
				local waterEnd   = math.min(WATER_LEVEL, H - 1)
				for y = waterStart, waterEnd do
					blocks[base + y * S] = ID_WATER
				end
			end
		end
	end

	-- ── Phase 3: Cave carving ────────────────────────────────────────────────
	-- CaveCarver uses the pre-computed surfYMap so it never resamples noise.
	CaveCarver.carveChunk(chunk, cx, cz, surfYMap)

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
			biomes[x * S + z + 1] = BiomeDefinitions.PLAINS  -- flat world = plains
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

