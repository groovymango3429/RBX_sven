--[[
  WorldGenConfig  [MODULE SCRIPT]
  ===============
  Centralised map-size, spawn, and terrain-shaping settings.
  Tweak values here to make the generated world larger or change its look.
]]

local WorldGenConfig = {}

WorldGenConfig.Map = {
	SpawnBlockX = 0,
	SpawnBlockZ = 0,
	WorldSizeChunks = 1024, -- 1024x1024 chunk world bounds
	SpawnSafeRadius = 5,
	RenderDistance = 15,
	ChunkHeight = 128,
}

WorldGenConfig.Terrain = {
	MinDetailScale = 0.04,
	ElevationDetailFactor = 0.10,
	MountainDetailBoost = 0.08,

	LandformScale = 0.0011,
	LandformSeed = 2400,
	HillStart = 0.35,
	MountainStart = 0.72,

	CONT_SCALE = 0.0016,
	CONT_SEED = nil,

	OCTAVES = {
		{ scale = 0.004, amp = 0.86, seed = 0 },
		{ scale = 0.008, amp = 0.42, seed = 100 },
		{ scale = 0.016, amp = 0.22, seed = 200 },
		{ scale = 0.032, amp = 0.10, seed = 300 },
		-- Removed octaves 5 & 6 (scale 0.064/0.128, combined <5% contribution)
		-- The dithering system already covers micro-variation at those scales.
	},

	BASE_SCALE = 0.007,
	BASE_AMP = 0.010,
	BASE_SEED = 1800,

	HEIGHT_MIN = 36,
	HEIGHT_MAX = 90,
	WATER_LEVEL = 52,
	SNOW_HEIGHT = 87,
	ROCK_HEIGHT = 70,
	GRASS_HEIGHT = 56,
	SHORE_HEIGHT_BAND = 3,
	SURFACE_BLEND_BAND = 4,
	BEACH_CONTINENTALNESS = 0.34,
	UNDERGROUND_DEPTH = 18,
	OVERSAMPLE_SIZE = 1,  -- Single-tap noise; no perceptible quality loss at our scales (period >> 1.5 studs).
	
	-- Height dithering to reduce voxel quantization artifacts
	DITHER_SEED = 9999,
	DITHER_SCALE = 0.25,   -- High frequency for fine-grain variation
	DITHER_AMOUNT = 0.4,   -- Maximum dither in blocks (±0.4)
	
	-- Mountain peak amplification (multiply high elevations to create steeper peaks)
	MOUNTAIN_AMP_THRESHOLD = 0.72,  -- Heights above this get amplified
	MOUNTAIN_AMP_FACTOR = 1.5,       -- Multiplier for steep mountain peaks
	
	-- Water feature generation
	LAKE_THRESHOLD = 0.25,           -- Continentalness below this can form lakes
	LAKE_DEPTH_OFFSET = 4,           -- How much lower lakes sit than surroundings
	RIVER_SCALE = 0.008,             -- Noise scale for river paths
	RIVER_SEED = 3500,
	RIVER_THRESHOLD = 0.15,          -- Narrower means fewer/thinner rivers
	RIVER_DEPTH = 3,                 -- How deep rivers carve into terrain

	-- Flat buildable plateau zones: large, gently level areas suitable for
	-- placing structures.  They appear organically between hills and rivers.
	FLAT_ZONE_SCALE = 0.0028,        -- Low frequency → large zones (~350 block period)
	FLAT_ZONE_SEED = 7777,
	FLAT_ZONE_THRESHOLD = 0.62,      -- Noise fraction above which a flat zone starts
	FLAT_ZONE_BLEND_WIDTH = 0.12,    -- Smoothstep ramp width for natural zone edges
}

WorldGenConfig.Trees = {
	-- Tree density/clustering noise
	TREE_DENSITY_SCALE = 0.02,
	TREE_DENSITY_SEED = 5000,
	TREE_CLUSTER_THRESHOLD = 0.4,  -- Above this value, trees can spawn (0-1)
	
	-- Spawning rules
	MIN_TREE_SPACING = 6,          -- Minimum blocks between trees
	MAX_SLOPE_FOR_TREES = 0.4,     -- Maximum terrain slope (rise/run) for tree spawning
	
	-- Variation
	SCALE_MIN = 0.85,              -- Minimum random scale multiplier
	SCALE_MAX = 1.15,              -- Maximum random scale multiplier
	
	-- Tree models folder path (relative to ReplicatedStorage)
	TREE_MODELS_PATH = "Shared/Environment/Trees",
}

-- ────────────────────────────────────────────────────────────────────────────
-- Biome climate-noise settings
-- Temperature and humidity are each independent large-scale noise layers that
-- determine which biome occupies a given region.  The scales are intentionally
-- very low so that climate zones transition over hundreds of blocks, creating
-- continent-scale biome bands rather than salt-and-pepper noise.
-- ────────────────────────────────────────────────────────────────────────────
WorldGenConfig.Biomes = {
	-- Temperature gradient — controls hot/cold axis
	TEMPERATURE_SCALE = 0.00055,
	TEMPERATURE_SEED  = 4200,
	-- Humidity gradient — controls dry/wet axis, independent of temperature
	HUMIDITY_SCALE    = 0.00070,
	HUMIDITY_SEED     = 6300,
}

-- ────────────────────────────────────────────────────────────────────────────
-- Cave generation settings
-- Two complementary noise passes produce realistic underground systems:
--   • Spaghetti tunnels  — two perpendicular 3-D noise channels; a voxel
--     becomes a tunnel where (n1² + n2²) < CAVE_THRESHOLD_SQ.
--   • Cheese caverns     — a single 3-D noise channel; a voxel becomes a
--     chamber where |noise| < CAVE_CHEESE_THRESHOLD.
-- Both passes are depth-gated so caves never breach the surface.
-- ────────────────────────────────────────────────────────────────────────────
WorldGenConfig.Caves = {
	-- Spaghetti-tunnel noise
	CAVE_SCALE        = 0.052,
	CAVE_SEED_1       = 1111,
	CAVE_SEED_2       = 2222,
	-- Lower threshold → narrower / rarer tunnels (range ~0.02–0.08)
	CAVE_THRESHOLD_SQ = 0.046,
	-- Cheese-cavern noise (distinct scale/seed for independent chambers)
	CAVE_CHEESE_SCALE    = 0.034,
	CAVE_CHEESE_SEED     = 4444,
	CAVE_CHEESE_THRESHOLD = 0.18,
	-- Minimum distance below the terrain surface before caves can start
	CAVE_MIN_DEPTH        = 8,
	CAVE_CHEESE_MIN_DEPTH = 14,
}

return table.freeze(WorldGenConfig)
