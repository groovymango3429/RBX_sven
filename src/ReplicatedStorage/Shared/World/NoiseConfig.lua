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

  2. Detail octaves (three-octave Perlin stack)
     Adds local terrain variation on top of the continental base.
     The contribution of detail is *scaled* by elevation² so that:
       • plains stay genuinely flat (small detail contribution)
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

	-- ── Octave 1: regional terrain (large-scale valleys & ridges) ────────
	-- Note: CONT_SCALE handles continent-scale features; SCALE_1 adds
	-- regional variation (ridges, valleys) within those larger zones.
	SCALE_1 = 0.005,
	AMP_1   = 1.0,
	SEED_1  = 0,

	-- ── Octave 2: rolling hills / medium features ────────────────────────
	SCALE_2 = 0.02,
	AMP_2   = 0.35,   -- reduced from 0.9 so hills don't dominate everywhere
	SEED_2  = 100,

	-- ── Octave 3: small terrain detail ───────────────────────────────────
	-- Slightly lower frequency than before (0.09→0.08) to smooth micro-bumps
	-- now that AMP_2 is smaller and less noise is needed for fine variation.
	SCALE_3 = 0.08,
	AMP_3   = 0.08,
	SEED_3  = 200,

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