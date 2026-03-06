--[[
  ChunkData  [MODULE SCRIPT]
  =========
  Chunk data structure — flat voxel array + biome/light metadata.
  Dimensions are driven by ChunkConstants: CHUNK_SIZE × CHUNK_HEIGHT × CHUNK_SIZE.

  Coordinate convention
  ---------------------
  Local coords: x ∈ [0, CHUNK_SIZE-1], y ∈ [0, CHUNK_HEIGHT-1], z ∈ [0, CHUNK_SIZE-1]
  Flat index (1-based Lua): index = x * (CHUNK_HEIGHT * CHUNK_SIZE) + y * CHUNK_SIZE + z + 1

  Each element is a uint16 block ID (0 = air).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")
local ChunkConstants    = require(WorldFolder:WaitForChild("ChunkConstants"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE    -- 9
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT  -- 128
local VOLUME       = CHUNK_SIZE * CHUNK_HEIGHT * CHUNK_SIZE  -- 9*128*9 = 10368

local ChunkData = {}
ChunkData.__index = ChunkData

--- _toIndex: Convert local (x,y,z) to flat 1-based array index
local function _toIndex(x, y, z)
	return x * (CHUNK_HEIGHT * CHUNK_SIZE) + y * CHUNK_SIZE + z + 1
end

--- new: Create an empty chunk for the given chunk-grid coordinate (cx, cz)
-- @param cx  number  Chunk X coordinate in the world grid
-- @param cz  number  Chunk Z coordinate in the world grid
-- @return    ChunkData
function ChunkData.new(cx, cz)
	local self = setmetatable({}, ChunkData)

	-- World-grid position of this chunk
	self.cx = cx or 0
	self.cz = cz or 0

	-- Flat voxel storage: VOLUME entries, all 0 (air) by default
	self.blocks = table.create(VOLUME, 0)

	-- Per-column biome ID (CHUNK_SIZE × CHUNK_SIZE)
	self.biomes = table.create(CHUNK_SIZE * CHUNK_SIZE, 0)

	-- Per-voxel sky-light (nibble, 0-15) — stored as byte array
	self.skyLight = table.create(VOLUME, 0)

	-- Whether this chunk has unsaved changes
	self.dirty = false

	-- Timestamp of last modification
	self.lastModified = os.time()

	return self
end

--- getBlock: Return the block ID at local position (x, y, z)
-- Returns 0 (air) for out-of-bounds queries.
function ChunkData:getBlock(x, y, z)
	if x < 0 or x >= CHUNK_SIZE
		or y < 0 or y >= CHUNK_HEIGHT
		or z < 0 or z >= CHUNK_SIZE then
		return 0
	end
	return self.blocks[_toIndex(x, y, z)]
end

--- setBlock: Write a block ID at local position (x, y, z)
-- Marks the chunk dirty and updates lastModified.
-- Silently ignores out-of-bounds writes.
function ChunkData:setBlock(x, y, z, blockId)
	if x < 0 or x >= CHUNK_SIZE
		or y < 0 or y >= CHUNK_HEIGHT
		or z < 0 or z >= CHUNK_SIZE then
		return
	end
	self.blocks[_toIndex(x, y, z)] = blockId
	self.dirty        = true
	self.lastModified = os.time()
end

--- getBiome: Return the biome ID for column (x, z)
function ChunkData:getBiome(x, z)
	if x < 0 or x >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
		return 0
	end
	return self.biomes[x * CHUNK_SIZE + z + 1]
end

--- setBiome: Set the biome ID for column (x, z)
function ChunkData:setBiome(x, z, biomeId)
	if x < 0 or x >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
		return
	end
	self.biomes[x * CHUNK_SIZE + z + 1] = biomeId
end

--- fill: Fill the entire chunk with a single block ID (useful for generation)
function ChunkData:fill(blockId)
	local blocks = self.blocks
	for i = 1, VOLUME do
		blocks[i] = blockId
	end
	self.dirty        = true
	self.lastModified = os.time()
end

--- markClean: Clear the dirty flag after a successful save
function ChunkData:markClean()
	self.dirty = false
end

return ChunkData
