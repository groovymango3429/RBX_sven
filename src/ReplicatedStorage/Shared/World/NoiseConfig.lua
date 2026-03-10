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

NoiseConfig.TERRAIN = {

	-- Continental shaping — lower frequency for more spread-out biomes
	CONT_SCALE = terrainConfig.CONT_SCALE,  -- broader plains and mountain ranges
	CONT_SEED  = terrainConfig.CONT_SEED, -- randomized at module load when a new session starts

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

	-- Underground depth
	UNDERGROUND_DEPTH = terrainConfig.UNDERGROUND_DEPTH,

	-- Oversampling for smoothness
	OVERSAMPLE_SIZE = terrainConfig.OVERSAMPLE_SIZE,
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

function NoiseConfig.GetContinentalness(x, z)
	local cfg = NoiseConfig.TERRAIN
	local n = sampleNoise(x, z, cfg.CONT_SCALE, cfg.CONT_SEED)
	return smoothstep(math.clamp((n + 1) * 0.5, 0, 1))
end

function NoiseConfig.GetHeight(x, z)
	local cfg = NoiseConfig.TERRAIN
	local cont = NoiseConfig.GetContinentalness(x, z)

	-- Oversampled detail (this is what removes sharpness)
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

	-- Flat areas keep a little shape, while higher continental terrain gets more variation.
	detail = detail * (MIN_DETAIL_SCALE + cont * cont * ELEVATION_DETAIL_FACTOR)
	detail = detail + sampleNoise(x, z, cfg.BASE_SCALE, cfg.BASE_SEED) * cfg.BASE_AMP

	-- Final height (detail is normalized so the shaping stays smooth and predictable)
	local finalHeight = cfg.HEIGHT_MIN + (heightRange * cont) + (detail * heightRange)

	return clampHeight(cfg, finalHeight)
end

return NoiseConfig
