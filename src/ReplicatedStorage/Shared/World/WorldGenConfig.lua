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
		{ scale = 0.064, amp = 0.05, seed = 400 },
		{ scale = 0.128, amp = 0.02, seed = 500 },
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
	OVERSAMPLE_SIZE = 2,  -- Reduced from 4 for better performance while maintaining smoothness
	
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

return table.freeze(WorldGenConfig)
