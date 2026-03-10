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
	SpawnSafeRadius = 192,
	RenderDistance = 10,
	ChunkHeight = 160,
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
	HEIGHT_MAX = 124,
	WATER_LEVEL = 52,
	SNOW_HEIGHT = 108,
	ROCK_HEIGHT = 84,
	GRASS_HEIGHT = 56,
	SHORE_HEIGHT_BAND = 3,
	SURFACE_BLEND_BAND = 4,
	BEACH_CONTINENTALNESS = 0.34,
	UNDERGROUND_DEPTH = 18,
	OVERSAMPLE_SIZE = 2,
}

return table.freeze(WorldGenConfig)
