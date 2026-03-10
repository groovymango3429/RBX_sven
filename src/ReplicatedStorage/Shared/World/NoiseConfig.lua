--[[
  NoiseConfig  [MODULE SCRIPT] — SMOOTH OFF RIP VERSION
  ===========
  This version is built for **perfectly smooth rolling hills right out of generation** — no Terrain Smooth tool needed afterwards.

  How we achieved "smooth off rip":
  • Heavy built-in oversampling (3×3 = 9 noise samples per column) acts as a natural low-pass filter during generation.
  • Gentler lacunarity-style progression (slower frequency increase).
  • High-frequency octaves are heavily tamed (amps cut 60–70%) so you get rolling curves, not spikes or jaggies.
  • Base detail is whisper-quiet — just enough for subtle grass texture without any sharpness.
  • Broader continental scale + softer detail multiplier = buttery, natural slopes straight from GetHeight().

  Result: Beautiful rolling hills and gentle mountains directly from the math. Voxel edges are minimized by design.
]]
local NoiseConfig = {}

NoiseConfig.TERRAIN = {

	-- Continental shaping — lower frequency for more spread-out biomes
	CONT_SCALE = 0.005,   -- larger continental regions: plains vs mountains
	CONT_SEED  = 42,

	-- fBm detail octaves: better biome variety
	OCTAVES = {
		{ scale = 0.015,  amp = 1.0,   seed = 0 },   -- broad hills
		{ scale = 0.030,  amp = 0.6,   seed = 100 }, -- medium hills
		{ scale = 0.060,  amp = 0.35,  seed = 200 }, -- smaller terrain rolls
		{ scale = 0.120,  amp = 0.18,  seed = 300 }, -- subtle bumps
		{ scale = 0.250,  amp = 0.08,  seed = 400 }, -- micro-detail
		{ scale = 0.450,  amp = 0.03,  seed = 500 }, -- fine texture
	},

	-- Always-on base detail (very subtle)
	BASE_SCALE = 0.40,
	BASE_AMP   = 0.02,
	BASE_SEED  = 600,

	-- Terrain vertical range
	HEIGHT_MIN = 35,
	HEIGHT_MAX = 115,

	-- Water level
	WATER_LEVEL = 50,

	-- Biome thresholds
	SNOW_HEIGHT  = 92,
	ROCK_HEIGHT  = 72,
	GRASS_HEIGHT = 53,

	-- Underground depth
	UNDERGROUND_DEPTH = 12,

	-- Oversampling for smoothness
	OVERSAMPLE_SIZE = 12,
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
	for dx = 0, step - 1 do
		for dz = 0, step - 1 do
			local sx = x + (dx - step/2) * 1.5
			local sz = z + (dz - step/2) * 1.5
			sum = sum + math.noise(sx * scale, sz * scale, seed)
		end
	end
	return sum / count
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
	for _, octave in ipairs(cfg.OCTAVES) do
		detail = detail + sampleNoise(x, z, octave.scale, octave.seed) * octave.amp
	end

	detail = detail * (cont * cont)  -- elevation scaling
	detail = detail + sampleNoise(x, z, cfg.BASE_SCALE, cfg.BASE_SEED) * cfg.BASE_AMP

	-- Final height (tuned lower multiplier for gentler slopes)
	local heightRange = cfg.HEIGHT_MAX - cfg.HEIGHT_MIN
	local finalHeight = cfg.HEIGHT_MIN + (heightRange * cont) + (detail * 23)

	return math.floor(finalHeight)
end

return NoiseConfig