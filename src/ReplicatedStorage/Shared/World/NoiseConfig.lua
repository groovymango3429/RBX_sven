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
local MIN_DETAIL_SCALE = 0.04          -- baseline detail strength in flatter terrain
local ELEVATION_DETAIL_FACTOR = 0.18   -- extra detail strength added by elevation²

NoiseConfig.TERRAIN = {

	-- Continental shaping — lower frequency for more spread-out biomes
	CONT_SCALE = 0.0028,  -- broader plains and mountain ranges
	CONT_SEED  = 42,

	-- fBm detail octaves: tuned toward broader, smoother landforms
	OCTAVES = {
		{ scale = 0.008,  amp = 1.0,   seed = 0 },   -- broad rolling hills
		{ scale = 0.016,  amp = 0.45,  seed = 100 }, -- wide secondary ridges
		{ scale = 0.032,  amp = 0.20,  seed = 200 }, -- long terrain rolls
		{ scale = 0.064,  amp = 0.09,  seed = 300 }, -- gentle local variation
		{ scale = 0.128,  amp = 0.035, seed = 400 }, -- restrained micro-shaping
		{ scale = 0.240,  amp = 0.012, seed = 500 }, -- tiny surface breakup
	},

	-- Always-on base detail (very subtle)
	BASE_SCALE = 0.14,
	BASE_AMP   = 0.008,
	BASE_SEED  = 600,

	-- Terrain vertical range
	HEIGHT_MIN = 35,
	HEIGHT_MAX = 120,

	-- Water level
	WATER_LEVEL = 50,

	-- Biome thresholds
	SNOW_HEIGHT  = 92,
	ROCK_HEIGHT  = 72,
	GRASS_HEIGHT = 53,

	-- Underground depth
	UNDERGROUND_DEPTH = 12,

	-- Oversampling for smoothness
	OVERSAMPLE_SIZE = 8,
}

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
	return math.clamp(math.floor(height + 0.5), cfg.HEIGHT_MIN, cfg.HEIGHT_MAX)
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
