--[[
  NoiseConfig  [MODULE SCRIPT] — SMOOTH OFF RIP VERSION
  ===========
  This version is built for **perfectly smooth rolling hills right out of generation** — no Terrain Smooth tool needed afterwards.

  How we achieved "smooth off rip":
  • Heavy built-in oversampling acts as a natural low-pass filter during generation.
  • Gentler lacunarity-style progression (slower frequency increase).
  • High-frequency octaves are heavily tamed (amps cut 60–70%) so you get rolling curves, not spikes or jaggies.
  • Base detail is whisper-quiet — just enough for subtle grass texture without any sharpness.
  • Broader continental scale + softer detail multiplier = buttery, natural slopes straight from GetHeight().

  Result: Beautiful rolling hills and gentle mountains directly from the math. Voxel edges are minimized by design.
]]
local NoiseConfig = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")
local WorldGenConfig = require(WorldFolder:WaitForChild("WorldGenConfig"))
local terrainConfig = WorldGenConfig.Terrain
local MIN_DETAIL_SCALE = terrainConfig.MinDetailScale
local ELEVATION_DETAIL_FACTOR = terrainConfig.ElevationDetailFactor
local MOUNTAIN_DETAIL_BOOST = terrainConfig.MountainDetailBoost
-- Elevation is layered in three parts:
-- 1) a broad continental base shared by all landforms,
-- 2) a rolling-hill lift enabled by the landform mask,
-- 3) an additional mountain lift reserved for the mountain mask.
-- Reduced BASE_ELEVATION_FLOOR to create more flat plains between mountains
local BASE_ELEVATION_FLOOR = 0.12  -- Reduced from 0.16 for flatter terrain
local CONTINENTAL_ELEVATION_WEIGHT = 0.34
local HILL_ELEVATION_BASE = 0.08
local HILL_ELEVATION_WEIGHT = 0.10
local MOUNTAIN_ELEVATION_WEIGHT = 0.32

NoiseConfig.TERRAIN = {

	-- Continental shaping — lower frequency for more spread-out biomes
	CONT_SCALE = terrainConfig.CONT_SCALE,  -- broader plains and mountain ranges
	CONT_SEED  = terrainConfig.CONT_SEED, -- randomized at module load when a new session starts

	-- Low-frequency terrain-type mask to mix plains, rolling hills, and mountains
	LANDFORM_SCALE = terrainConfig.LandformScale,
	LANDFORM_SEED  = terrainConfig.LandformSeed,
	HILL_START     = terrainConfig.HillStart,
	MOUNTAIN_START = terrainConfig.MountainStart,

	-- fBm detail octaves: tuned toward broader, smoother landforms
	OCTAVES = terrainConfig.OCTAVES,

	-- Always-on base detail (very subtle)
	BASE_SCALE = terrainConfig.BASE_SCALE,
	BASE_AMP   = terrainConfig.BASE_AMP,
	BASE_SEED  = terrainConfig.BASE_SEED,

	-- Terrain vertical range
	HEIGHT_MIN = terrainConfig.HEIGHT_MIN,
	HEIGHT_MAX = terrainConfig.HEIGHT_MAX,

	-- Water level
	WATER_LEVEL = terrainConfig.WATER_LEVEL,

	-- Biome thresholds
	SNOW_HEIGHT  = terrainConfig.SNOW_HEIGHT,
	ROCK_HEIGHT  = terrainConfig.ROCK_HEIGHT,
	GRASS_HEIGHT = terrainConfig.GRASS_HEIGHT,

	-- Shore / surface blending thresholds (used by ChunkGenerator)
	SHORE_HEIGHT_BAND = terrainConfig.SHORE_HEIGHT_BAND,
	SURFACE_BLEND_BAND = terrainConfig.SURFACE_BLEND_BAND,
	BEACH_CONTINENTALNESS = terrainConfig.BEACH_CONTINENTALNESS,

	-- Underground depth
	UNDERGROUND_DEPTH = terrainConfig.UNDERGROUND_DEPTH,

	-- Oversampling for smoothness
	OVERSAMPLE_SIZE = terrainConfig.OVERSAMPLE_SIZE,
	
	-- Mountain amplification
	MOUNTAIN_AMP_THRESHOLD = terrainConfig.MOUNTAIN_AMP_THRESHOLD,
	MOUNTAIN_AMP_FACTOR = terrainConfig.MOUNTAIN_AMP_FACTOR,
	
	-- Water features
	LAKE_THRESHOLD = terrainConfig.LAKE_THRESHOLD,
	LAKE_DEPTH_OFFSET = terrainConfig.LAKE_DEPTH_OFFSET,
	RIVER_SCALE = terrainConfig.RIVER_SCALE,
	RIVER_SEED = terrainConfig.RIVER_SEED,
	RIVER_THRESHOLD = terrainConfig.RIVER_THRESHOLD,
	RIVER_DEPTH = terrainConfig.RIVER_DEPTH,
}

-- Randomize seeds when module loads so each session gets a different world
do
	-- Seed the Lua RNG with current time for entropy, then pick a large int seed
	if os and os.time then
		math.randomseed(os.time())
	end
	-- Use a 30-bit random integer for the continental noise seed
	NoiseConfig.TERRAIN.CONT_SEED = math.random(0, 2^30 - 1)
end

-- Helpers (these are what make it smooth off rip)
local function smoothstep(x)
	return x * x * (3 - 2 * x)
end

local function inverseLerp(a, b, value)
	if a == b then
		-- A collapsed range means the corresponding mask is effectively disabled,
		-- so fall back to 0 rather than inventing extra hill/mountain influence.
		return 0
	end

	return math.clamp((value - a) / (b - a), 0, 1)
end

local function sampleNoise(x, z, scale, seed)
	local cfg = NoiseConfig.TERRAIN
	local sum = 0
	local step = cfg.OVERSAMPLE_SIZE
	local count = step * step
	local oversampleSpacing = 1.5  -- world-space spacing between oversample taps
	local gridCenterOffset = (step - 1) / 2
	for dx = 0, step - 1 do
		for dz = 0, step - 1 do
			local sx = x + (dx - gridCenterOffset) * oversampleSpacing
			local sz = z + (dz - gridCenterOffset) * oversampleSpacing
			sum = sum + math.noise(sx * scale, sz * scale, seed)
		end
	end
	return sum / count
end

local function clampHeight(cfg, height)
	return math.clamp(height, cfg.HEIGHT_MIN, cfg.HEIGHT_MAX)
end

-- Add position-based micro-dither to break up voxel quantization
-- This creates subtle height variations that smooth out stair-stepping
local function applyHeightDither(x, z, height)
	-- Use high-frequency noise for sub-voxel dithering
	-- Scale is high so dither varies rapidly across positions
	local ditherSeed = 9999
	local ditherScale = 0.25  -- High frequency for fine grain
	local ditherAmount = 0.4  -- Maximum dither in blocks
	
	-- Get a noise value that varies smoothly but rapidly
	-- math.noise returns values in range [-1, 1]
	-- Add seed to x coordinate to create variation from other noise layers
	local ditherNoise = math.noise(x * ditherScale + ditherSeed, z * ditherScale, 0)
	-- ditherNoise is already in [-1, 1], scale to [-ditherAmount, +ditherAmount]
	local dither = ditherNoise * ditherAmount
	
	return height + dither
end

function NoiseConfig.GetContinentalness(x, z)
	local cfg = NoiseConfig.TERRAIN
	local n = sampleNoise(x, z, cfg.CONT_SCALE, cfg.CONT_SEED)
	return smoothstep(math.clamp((n + 1) * 0.5, 0, 1))
end

function NoiseConfig.GetLandformMix(x, z)
	local cfg = NoiseConfig.TERRAIN
	local n = sampleNoise(x, z, cfg.LANDFORM_SCALE, cfg.LANDFORM_SEED)
	return math.clamp((n + 1) * 0.5, 0, 1)
end

function NoiseConfig.GetHeight(x, z)
	local cfg = NoiseConfig.TERRAIN
	local cont = NoiseConfig.GetContinentalness(x, z)
	local landform = NoiseConfig.GetLandformMix(x, z)
	local hillMask = smoothstep(inverseLerp(cfg.HILL_START, cfg.MOUNTAIN_START, landform))
	local mountainMask = smoothstep(inverseLerp(cfg.MOUNTAIN_START, 1, landform))

	-- Oversampled detail for terrain texture without the old spike-heavy extremes.
	local detail = 0
	local ampSum = 0
	for _, octave in ipairs(cfg.OCTAVES) do
		detail = detail + sampleNoise(x, z, octave.scale, octave.seed) * octave.amp
		ampSum = ampSum + octave.amp
	end

	local heightRange = cfg.HEIGHT_MAX - cfg.HEIGHT_MIN
	if ampSum == 0 then
		return clampHeight(cfg, cfg.HEIGHT_MIN + (heightRange * cont))
	end

	-- Safe after the early return above; detail is now normalized to a predictable range.
	detail = detail / ampSum

	-- Plains stay broad and calm, hills get moderate variation, and only the
	-- mountain mask unlocks the larger peaks/valleys.
	-- Adjusted to create more flat plains by reducing base elevation floor
	local baseElevation = BASE_ELEVATION_FLOOR + cont * CONTINENTAL_ELEVATION_WEIGHT
	local rollingLift = hillMask * (HILL_ELEVATION_BASE + cont * HILL_ELEVATION_WEIGHT)
	local mountainLift = mountainMask * cont * cont * MOUNTAIN_ELEVATION_WEIGHT
	local normalizedHeight = math.clamp(baseElevation + rollingLift + mountainLift, 0, 1)
	local detailStrength = MIN_DETAIL_SCALE
		+ hillMask * ELEVATION_DETAIL_FACTOR
		+ mountainMask * MOUNTAIN_DETAIL_BOOST

	detail = detail * detailStrength
	detail = detail + sampleNoise(x, z, cfg.BASE_SCALE, cfg.BASE_SEED) * cfg.BASE_AMP

	-- Final height (detail is normalized so the shaping stays smooth and predictable)
	local finalHeight = cfg.HEIGHT_MIN + (heightRange * normalizedHeight) + (detail * heightRange)
	
	-- Mountain peak amplification: multiply heights above threshold to create steeper peaks.
	-- When terrain is above MOUNTAIN_AMP_THRESHOLD (0.72), we amplify it to create dramatic cliffs.
	-- amplificationMask goes from 0 at threshold to 1 at maximum height (smooth transition).
	-- This creates Minecraft-style steep mountains while keeping plains and hills smooth.
	if normalizedHeight > cfg.MOUNTAIN_AMP_THRESHOLD then
		local amplificationMask = (normalizedHeight - cfg.MOUNTAIN_AMP_THRESHOLD) / (1 - cfg.MOUNTAIN_AMP_THRESHOLD)
		local baseHeight = cfg.HEIGHT_MIN + (heightRange * cfg.MOUNTAIN_AMP_THRESHOLD)
		local heightAboveThreshold = finalHeight - baseHeight
		-- Multiply the excess height by the amplification factor, scaled by how high we are
		finalHeight = baseHeight + (heightAboveThreshold * (1 + amplificationMask * (cfg.MOUNTAIN_AMP_FACTOR - 1)))
	end
	
	-- Apply height dithering to break up voxel quantization and reduce stair-stepping
	-- This allows us to use low oversampling (2) while maintaining smooth terrain
	finalHeight = applyHeightDither(x, z, finalHeight)

	return clampHeight(cfg, finalHeight)
end

-- Get river influence at a position (returns 0-1, higher means river presence)
function NoiseConfig.GetRiverInfluence(x, z)
	local cfg = NoiseConfig.TERRAIN
	local riverNoise = math.abs(sampleNoise(x, z, cfg.RIVER_SCALE, cfg.RIVER_SEED))
	-- Rivers form along low values (near zero after abs)
	if riverNoise < cfg.RIVER_THRESHOLD then
		return 1 - (riverNoise / cfg.RIVER_THRESHOLD)
	end
	return 0
end

-- Check if position should be a lake
function NoiseConfig.IsLakePosition(x, z, continentalness)
	local cfg = NoiseConfig.TERRAIN
	-- Lakes form in low continentalness areas (inland basins/valleys)
	return continentalness < cfg.LAKE_THRESHOLD
end

return NoiseConfig
