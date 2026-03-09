--[[
  NoiseConfig  [MODULE SCRIPT]
  ===========
  Octave noise parameters for terrain generation.
  All values are tunable for artistic control.

  Terrain height is computed as a weighted sum of three Perlin octaves,
  each sampled with math.noise(wx * SCALE, wz * SCALE, SEED).
  math.noise returns values approximately in [-0.5, 0.5], so the combined
  range is ±(AMP_1 + AMP_2 + AMP_3) * 0.5 which is then normalised to [0,1]
  before being mapped to [HEIGHT_MIN, HEIGHT_MAX].
]]

local NoiseConfig = {}

NoiseConfig.TERRAIN = {

	-- Octave 1: continent / biome scale (decides plains vs mountains)
	SCALE_1 = 0.004,
	AMP_1   = 1.0,
	SEED_1  = 0,

	-- Octave 2: rolling hills
	SCALE_2 = 0.02,
	AMP_2   = 0.9,
	SEED_2  = 100,

	-- Octave 3: small terrain detail
	SCALE_3 = 0.09,
	AMP_3   = 0.08,
	SEED_3  = 200,

	-- Terrain vertical range
	HEIGHT_MIN = 42,
	HEIGHT_MAX = 105,

	-- Biome thresholds
	SNOW_HEIGHT  = 92,
	ROCK_HEIGHT  = 72,
	GRASS_HEIGHT = 48,

	-- Underground depth (performance)
	UNDERGROUND_DEPTH = 12,
}

return NoiseConfig