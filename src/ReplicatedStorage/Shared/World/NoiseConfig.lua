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

-- ── Terrain height noise ─────────────────────────────────────────────────────
NoiseConfig.TERRAIN = {
	-- Octave 1: broad continental shapes (mountains vs plains)
	SCALE_1    = 0.015,
	AMP_1      = 1.0,
	SEED_1     = 0,

	-- Octave 2: regional hills
	SCALE_2    = 0.04,
	AMP_2      = 0.5,
	SEED_2     = 100,

	-- Octave 3: surface micro-variation
	SCALE_3    = 0.09,
	AMP_3      = 0.25,
	SEED_3     = 200,

	-- Surface height output range (block Y units, must be < CHUNK_HEIGHT)
	HEIGHT_MIN = 50,  -- valley / lowland floor
	HEIGHT_MAX = 82,  -- mountain peak

	-- Biome height thresholds — used for surface and sub-surface block selection.
	-- Columns at or above SNOW_HEIGHT get snow caps (mountain peaks).
	-- Columns at or above ROCK_HEIGHT get bare stone (rocky hillsides).
	-- Columns at or above GRASS_HEIGHT get grass (plains); below that → sand.
	SNOW_HEIGHT  = 77,
	ROCK_HEIGHT  = 68,
	GRASS_HEIGHT = 53,

	-- How many solid blocks to generate below the surface (for performance).
	-- Blocks deeper than this are left as air.  Keeps generation fast while
	-- the terrain surface still looks fully solid from every angle.
	UNDERGROUND_DEPTH = 16,
}

return NoiseConfig
