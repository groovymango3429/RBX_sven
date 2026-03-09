--[[
  NoiseConfig  [MODULE SCRIPT]
  ===========
  Octave noise parameters for terrain generation.
  All values are tunable for artistic control.

  Terrain height is computed in two stages:

  1. Continental noise  (CONT_SCALE / CONT_SEED)
     A low-frequency Perlin sample that drives an "elevation zone":
       near 0 → ocean basins / lowland water regions
       mid    → flat plains and rolling hills
       near 1 → highland plateaus and mountain ranges
     The continent value is smoothstepped to sharpen zone transitions.
     CONT_SCALE = 0.012 gives features ~83 blocks wide — large enough for
     distinct biome regions but small enough to avoid the world-sized
     smooth sphere / blob hills produced by very low frequencies (0.003).

  2. fBm detail octaves  (OCTAVES table)
     Six layers of Perlin noise stacked with lacunarity = 2.0 and
     persistence = 0.5 — each layer doubles the spatial frequency and
     halves the amplitude.  Scales start at 0.020 (~50-block features),
     not 0.005 (~200-block blobs), so the dominant octave produces
     recognisable hills rather than giant spherical mounds.

     The combined detail value is *scaled* by elevation² so that:
       • plains stay genuinely flat  (small detail contribution)
       • mountains receive full roughness (large detail contribution)

  3. Always-on base detail  (BASE_SCALE / BASE_AMP / BASE_SEED)
     A small high-frequency layer that is added *without* any elevation
     scaling.  This gives subtle surface texture to flat / low-elevation
     areas and eliminates the horizontal banding / stripe artefact that
     appears on very gentle slopes against Roblox voxel edges.

  Water fill
  ----------
  Columns whose noise surface height falls below WATER_LEVEL are topped
  with water blocks up to that level, creating natural lakes and lowland
  water regions.  The seafloor is sand (height already below GRASS_HEIGHT).
]]

local NoiseConfig = {}

NoiseConfig.TERRAIN = {

	-- ── Continental shaping ──────────────────────────────────────────────
	-- Low frequency: creates large plains / highland / mountain zones.
	-- CONT_SCALE = 0.016 → features ~62 blocks wide.
	-- Raised from 0.012 (≈83-block blobs) to tighten continental features
	-- and reduce the large rounded hill/blob appearance at mid frequencies.
	CONT_SCALE = 0.016,
	CONT_SEED  = 42,

	-- ── fBm detail octaves ───────────────────────────────────────────────
	-- Six layers with lacunarity = 2.0 and persistence = 0.5.
	-- Each entry doubles the spatial frequency and halves the amplitude.
	-- Scales start at 0.020 (not 0.005) so the dominant octave produces
	-- ~50-block hills instead of ~200-block blobs.
	--
	--   Octave │ Scale   │ Amplitude │ Feature width
	--   ───────┼─────────┼───────────┼───────────────────────────────────
	--     1    │ 0.020   │ 1.000     │  ~50 blocks  (regional ridges/valleys)
	--     2    │ 0.040   │ 0.500     │  ~25 blocks  (large hills)
	--     3    │ 0.080   │ 0.250     │  ~12 blocks  (rolling hills)
	--     4    │ 0.160   │ 0.125     │   ~6 blocks  (medium bumps)
	--     5    │ 0.320   │ 0.0625    │   ~3 blocks  (small detail)
	--     6    │ 0.640   │ 0.03125   │  ~1.5 blocks (micro surface texture)
	OCTAVES = {
		{ scale = 0.020,  amp = 1.000,   seed = 0   },
		{ scale = 0.040,  amp = 0.500,   seed = 100 },
		{ scale = 0.080,  amp = 0.250,   seed = 200 },
		{ scale = 0.160,  amp = 0.125,   seed = 300 },
		{ scale = 0.320,  amp = 0.0625,  seed = 400 },
		{ scale = 0.640,  amp = 0.03125, seed = 500 },
	},

	-- ── Always-on base detail ─────────────────────────────────────────────
	-- A small high-frequency layer applied WITHOUT elevation scaling.
	-- This gives subtle texture to flat/low-elevation areas and eliminates
	-- the horizontal banding / stripe artefact on gentle grass slopes.
	BASE_SCALE = 0.8,    -- ~1.25-block features (sub-voxel variation)
	BASE_AMP   = 0.06,   -- small enough to be barely noticeable, big enough
	BASE_SEED  = 600,    --   to break up all remaining perfect-smooth slopes

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