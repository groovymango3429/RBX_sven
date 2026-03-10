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
	MinDetailScale = 0.08,
	ElevationDetailFactor = 0.24,

	CONT_SCALE = 0.0021,
	CONT_SEED = nil,

	OCTAVES = {
		{ scale = 0.006, amp = 1.00, seed = 0 },
		{ scale = 0.012, amp = 0.52, seed = 100 },
		{ scale = 0.024, amp = 0.28, seed = 200 },
		{ scale = 0.048, amp = 0.15, seed = 300 },
		{ scale = 0.096, amp = 0.08, seed = 400 },
		{ scale = 0.180, amp = 0.03, seed = 500 },
	},

	BASE_SCALE = 0.009,
	BASE_AMP = 0.014,
	BASE_SEED = 1800,

	HEIGHT_MIN = 30,
	HEIGHT_MAX = 80,
	WATER_LEVEL = 54,
	SNOW_HEIGHT = 75,
	ROCK_HEIGHT = 60,
	GRASS_HEIGHT = 58,
	UNDERGROUND_DEPTH = 18,
	OVERSAMPLE_SIZE = 10,
}

return table.freeze(WorldGenConfig)
