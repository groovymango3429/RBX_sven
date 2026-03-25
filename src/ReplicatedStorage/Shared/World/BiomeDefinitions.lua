--[[
  BiomeDefinitions  [MODULE SCRIPT]
  ================
  Biome configs keyed by numeric ID.

  Each biome describes:
    • its ideal position in (temperature, humidity) climate space [0–1 each]
    • the surface and sub-surface block registry names for terrain layers
    • a tree density multiplier applied on top of the base density noise
      (0 = no trees; 1 = full base density)
    • optional height gates for tree placement

  The BiomeMapper selects the nearest biome by Euclidean distance in
  (temperature, humidity) space.  Altitude-based overrides (snow peaks,
  rocky hillsides) are applied by ChunkGenerator after biome selection.
]]

local BiomeDefinitions = {}

-- ── Numeric ID constants ─────────────────────────────────────────────────────
BiomeDefinitions.PLAINS  = 0
BiomeDefinitions.FOREST  = 1
BiomeDefinitions.DESERT  = 2
BiomeDefinitions.TUNDRA  = 3
BiomeDefinitions.TAIGA   = 4
BiomeDefinitions.SAVANNA = 5

-- ── Biome table ───────────────────────────────────────────────────────────────
-- tempCenter / humidCenter  : ideal climate-space coordinates (Voronoi seed)
-- surfaceBlock              : BlockRegistry name for the top-most surface layer
-- subSurfaceBlock           : BlockRegistry name for the layer directly below surface
-- treeDensityMult           : multiplier on spawn-chance (0 = barren, 1 = full density)
-- treeHeightMin/Max         : world-Y range where trees are allowed in this biome
BiomeDefinitions.Biomes = {

	[BiomeDefinitions.PLAINS] = {
		id               = BiomeDefinitions.PLAINS,
		name             = "Plains",
		-- Moderate temperature, moderate humidity — the default open grassland
		tempCenter       = 0.55,
		humidCenter      = 0.42,
		surfaceBlock     = "grass",
		subSurfaceBlock  = "dirt",
		treeDensityMult  = 0.25,
		treeHeightMin    = 54,
		treeHeightMax    = 78,
	},

	[BiomeDefinitions.FOREST] = {
		id               = BiomeDefinitions.FOREST,
		name             = "Forest",
		-- Moderate temperature, high humidity — dense woodland
		tempCenter       = 0.55,
		humidCenter      = 0.75,
		surfaceBlock     = "grass",
		subSurfaceBlock  = "dirt",
		treeDensityMult  = 1.0,
		treeHeightMin    = 54,
		treeHeightMax    = 80,
	},

	[BiomeDefinitions.DESERT] = {
		id               = BiomeDefinitions.DESERT,
		name             = "Desert",
		-- High temperature, very low humidity — hot sandy wasteland
		tempCenter       = 0.85,
		humidCenter      = 0.15,
		surfaceBlock     = "sand",
		subSurfaceBlock  = "sand",
		treeDensityMult  = 0.0,   -- no trees in the desert
	},

	[BiomeDefinitions.TUNDRA] = {
		id               = BiomeDefinitions.TUNDRA,
		name             = "Tundra",
		-- Very cold, dry — frozen flatlands with a snow surface
		tempCenter       = 0.15,
		humidCenter      = 0.25,
		surfaceBlock     = "snow",
		subSurfaceBlock  = "stone",
		treeDensityMult  = 0.0,   -- treeless frozen plain
	},

	[BiomeDefinitions.TAIGA] = {
		id               = BiomeDefinitions.TAIGA,
		name             = "Taiga",
		-- Cold, moderately wet — boreal forest with scattered conifers
		tempCenter       = 0.25,
		humidCenter      = 0.68,
		surfaceBlock     = "grass",
		subSurfaceBlock  = "dirt",
		treeDensityMult  = 0.60,
		treeHeightMin    = 54,
		treeHeightMax    = 74,
	},

	[BiomeDefinitions.SAVANNA] = {
		id               = BiomeDefinitions.SAVANNA,
		name             = "Savanna",
		-- Hot, moderate humidity — dry grassland with sparse trees
		tempCenter       = 0.80,
		humidCenter      = 0.40,
		surfaceBlock     = "grass",
		subSurfaceBlock  = "dirt",
		treeDensityMult  = 0.12,
		treeHeightMin    = 54,
		treeHeightMax    = 72,
	},

}

--- getById: Return the biome definition table for a numeric ID.
-- Returns nil for unknown IDs.
function BiomeDefinitions.getById(id)
	return BiomeDefinitions.Biomes[id]
end

return BiomeDefinitions
