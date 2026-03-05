--[[
  BlockRegistry  [MODULE SCRIPT]
  =============
  Central registry of all block type definitions.
  Each block has a numeric ID, a unique name, and a property table.

  Properties
  ----------
  name        string   Human-readable identifier
  hardness    number   Ticks to break with bare hands (0 = instant)
  solid       bool     Whether the block is physically solid (collides)
  transparent bool     Whether light passes through
  liquid      bool     Whether the block behaves as a fluid
  luminance   number   Light emission level 0-15
  material    string   Roblox BasePart.Material enum name
  color       Color3   Default surface color
  tool        string   Required tool category ("any"|"pickaxe"|"axe"|"shovel")
  drops       table    { blockId, count } list — nil = drops self
]]

local BlockRegistry = {}

-- Numeric ID → definition table
BlockRegistry.Blocks = {}

-- Name → numeric ID (reverse lookup)
BlockRegistry.NameToId = {}

--- _define: internal helper to register one block type
local function _define(id, props)
	assert(type(id) == "number",  "BlockRegistry: id must be a number")
	assert(type(props.name) == "string", "BlockRegistry: name must be a string")
	assert(BlockRegistry.Blocks[id] == nil, "BlockRegistry: duplicate id " .. id)
	assert(BlockRegistry.NameToId[props.name] == nil, "BlockRegistry: duplicate name " .. props.name)

	BlockRegistry.Blocks[id]            = props
	BlockRegistry.NameToId[props.name]  = id
end

-- ────────────────────────────────────────────────────────────────────────────
-- 20 Starter Block Types
-- ────────────────────────────────────────────────────────────────────────────

-- 0 = Air (always registered first — represents empty space)
_define(0, {
	name        = "air",
	hardness    = 0,
	solid       = false,
	transparent = true,
	liquid      = false,
	luminance   = 0,
	material    = "Air",
	color       = Color3.fromRGB(0, 0, 0),
	tool        = "any",
})

-- 1 = Grass
_define(1, {
	name        = "grass",
	hardness    = 2,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Grass",
	color       = Color3.fromRGB(106, 127, 68),
	tool        = "shovel",
})

-- 2 = Dirt
_define(2, {
	name        = "dirt",
	hardness    = 2,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Ground",
	color       = Color3.fromRGB(106, 76, 54),
	tool        = "shovel",
})

-- 3 = Stone
_define(3, {
	name        = "stone",
	hardness    = 10,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Rock",
	color       = Color3.fromRGB(128, 128, 128),
	tool        = "pickaxe",
})

-- 4 = Sand
_define(4, {
	name        = "sand",
	hardness    = 2,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Sand",
	color       = Color3.fromRGB(219, 196, 148),
	tool        = "shovel",
})

-- 5 = Gravel
_define(5, {
	name        = "gravel",
	hardness    = 3,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Ground",
	color       = Color3.fromRGB(130, 130, 130),
	tool        = "shovel",
})

-- 6 = Wood (log)
_define(6, {
	name        = "wood",
	hardness    = 6,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Wood",
	color       = Color3.fromRGB(127, 102, 63),
	tool        = "axe",
})

-- 7 = Leaves
_define(7, {
	name        = "leaves",
	hardness    = 1,
	solid       = true,
	transparent = true,
	liquid      = false,
	luminance   = 0,
	material    = "Grass",
	color       = Color3.fromRGB(78, 128, 56),
	tool        = "any",
})

-- 8 = Planks
_define(8, {
	name        = "planks",
	hardness    = 5,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "WoodPlanks",
	color       = Color3.fromRGB(198, 160, 110),
	tool        = "axe",
})

-- 9 = Cobblestone
_define(9, {
	name        = "cobblestone",
	hardness    = 12,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Cobblestone",
	color       = Color3.fromRGB(108, 108, 108),
	tool        = "pickaxe",
})

-- 10 = Bedrock
_define(10, {
	name        = "bedrock",
	hardness    = math.huge,   -- indestructible
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Rock",
	color       = Color3.fromRGB(50, 50, 50),
	tool        = "pickaxe",
})

-- 11 = Water
_define(11, {
	name        = "water",
	hardness    = 0,
	solid       = false,
	transparent = true,
	liquid      = true,
	luminance   = 0,
	material    = "Water",
	color       = Color3.fromRGB(60, 120, 200),
	tool        = "any",
})

-- 12 = Coal Ore
_define(12, {
	name        = "coal_ore",
	hardness    = 12,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Rock",
	color       = Color3.fromRGB(90, 90, 90),
	tool        = "pickaxe",
})

-- 13 = Iron Ore
_define(13, {
	name        = "iron_ore",
	hardness    = 15,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Rock",
	color       = Color3.fromRGB(200, 160, 130),
	tool        = "pickaxe",
})

-- 14 = Gold Ore
_define(14, {
	name        = "gold_ore",
	hardness    = 18,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Rock",
	color       = Color3.fromRGB(220, 190, 60),
	tool        = "pickaxe",
})

-- 15 = Torch (light source, non-solid)
_define(15, {
	name        = "torch",
	hardness    = 0,
	solid       = false,
	transparent = true,
	liquid      = false,
	luminance   = 14,
	material    = "Wood",
	color       = Color3.fromRGB(255, 200, 80),
	tool        = "any",
})

-- 16 = Glass
_define(16, {
	name        = "glass",
	hardness    = 1,
	solid       = true,
	transparent = true,
	liquid      = false,
	luminance   = 0,
	material    = "Glass",
	color       = Color3.fromRGB(200, 230, 255),
	tool        = "any",
})

-- 17 = Clay
_define(17, {
	name        = "clay",
	hardness    = 3,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Ground",
	color       = Color3.fromRGB(162, 166, 182),
	tool        = "shovel",
})

-- 18 = Snow
_define(18, {
	name        = "snow",
	hardness    = 1,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Snow",
	color       = Color3.fromRGB(235, 245, 255),
	tool        = "shovel",
})

-- 19 = Brick
_define(19, {
	name        = "brick",
	hardness    = 14,
	solid       = true,
	transparent = false,
	liquid      = false,
	luminance   = 0,
	material    = "Brick",
	color       = Color3.fromRGB(178, 100, 77),
	tool        = "pickaxe",
})

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- getById: Return the block definition for a numeric ID (nil if unknown)
function BlockRegistry.getById(id)
	return BlockRegistry.Blocks[id]
end

--- getByName: Return the block definition for a name string (nil if unknown)
function BlockRegistry.getByName(name)
	local id = BlockRegistry.NameToId[name]
	if id == nil then return nil end
	return BlockRegistry.Blocks[id]
end

--- getId: Return the numeric ID for a name (nil if unknown)
function BlockRegistry.getId(name)
	return BlockRegistry.NameToId[name]
end

--- isSolid: Quick solid check by ID
function BlockRegistry.isSolid(id)
	local def = BlockRegistry.Blocks[id]
	return def ~= nil and def.solid
end

--- isTransparent: Quick transparency check by ID
function BlockRegistry.isTransparent(id)
	local def = BlockRegistry.Blocks[id]
	return def ~= nil and def.transparent
end

--- isLiquid: Quick liquid check by ID
function BlockRegistry.isLiquid(id)
	local def = BlockRegistry.Blocks[id]
	return def ~= nil and def.liquid
end

return BlockRegistry