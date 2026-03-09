--[[
  NoiseConfig  [MODULE SCRIPT]
  ===========
  Octave noise parameters for terrain generation.
  All values are tunable for artistic control.

  Terrain height is computed in two stages:

  1. Continental noise  (CONT_SCALE / CONT_SEED)
     A very low-frequency Perlin sample that drives an "elevation zone":
       near 0 → ocean basins / lowland water regions
       mid    → flat plains and rolling hills
       near 1 → highland plateaus and mountain ranges
     The continent value is smoothstepped to sharpen zone transitions.

  2. fBm detail octaves  (OCTAVES table)
     Six layers of Perlin noise stacked with lacunarity = 2.0 and
     persistence = 0.5 — each layer doubles the spatial frequency and
     halves the amplitude.  The full stack (fractional Brownian motion)
     covers feature sizes from ~200 blocks down to ~6 blocks, which
     breaks up the spherical blob / stripe artefacts that arise when only
     a handful of widely-spaced octaves are used.

     The combined detail value is *scaled* by elevation² so that:
       • plains stay genuinely flat  (small detail contribution)
       • mountains receive full roughness (large detail contribution)

  Water fill
  ----------
  Columns whose noise surface height falls below WATER_LEVEL are topped
  with water blocks up to that level, creating natural lakes and lowland
  water regions.  The seafloor is sand (height already below GRASS_HEIGHT).
]]

local NoiseConfig = {}

NoiseConfig.TERRAIN = {

	-- ── Continental shaping ──────────────────────────────────────────────
	-- Very low frequency: creates large plains / highland / mountain zones.
	-- Features are ~1/CONT_SCALE blocks wide (≈333 blocks at 0.003).
	CONT_SCALE = 0.003,
	CONT_SEED  = 42,

	-- ── fBm detail octaves ───────────────────────────────────────────────
	-- Six layers with lacunarity = 2.0 and persistence = 0.5.
	-- Each entry doubles the spatial frequency and halves the amplitude,
	-- giving the classic fBm character that eliminates blobs and stripes.
	--
	--   Octave │ Scale   │ Amplitude │ Feature width
	--   ───────┼─────────┼───────────┼───────────────────────────────────
	--     1    │ 0.005   │ 1.000     │ ~200 blocks  (regional ridges/valleys)
	--     2    │ 0.010   │ 0.500     │ ~100 blocks  (large hills)
	--     3    │ 0.020   │ 0.250     │  ~50 blocks  (rolling hills)
	--     4    │ 0.040   │ 0.125     │  ~25 blocks  (medium bumps)
	--     5    │ 0.080   │ 0.0625    │  ~12 blocks  (small detail)
	--     6    │ 0.160   │ 0.03125   │   ~6 blocks  (micro surface texture)
	OCTAVES = {
		{ scale = 0.005,  amp = 1.000,   seed = 0   },
		{ scale = 0.010,  amp = 0.500,   seed = 100 },
		{ scale = 0.020,  amp = 0.250,   seed = 200 },
		{ scale = 0.040,  amp = 0.125,   seed = 300 },
		{ scale = 0.080,  amp = 0.0625,  seed = 400 },
		{ scale = 0.160,  amp = 0.03125, seed = 500 },
	},

	-- ── Terrain vertical range ───────────────────────────────────────────
	HEIGHT_MIN = 38,   -- lowered to leave room for water below WATER_LEVEL
	HEIGHT_MAX = 110,

	-- ── Water level ──────────────────────────────────────────────────────
	-- Columns with a noise surface height below this value are filled with
	-- water from surfH+1 up to WATER_LEVEL, forming lakes and lowlands.
	WATER_LEVEL = 50,

	-- ── Biome surface thresholds ─────────────────────────────────────────
	SNOW_HEIGHT  = 92,   -- mountain peak → snow
	ROCK_HEIGHT  = 72,   -- rocky hillside → stone surface
	GRASS_HEIGHT = 53,   -- above water+beach band → grass (otherwise sand)

	-- ── Underground depth (performance) ──────────────────────────────────
	UNDERGROUND_DEPTH = 12,
}

return NoiseConfig