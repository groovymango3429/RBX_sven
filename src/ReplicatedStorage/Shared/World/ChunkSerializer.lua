--[[
  ChunkSerializer  [MODULE SCRIPT]
  ===============
  Pack/unpack chunk to a compact binary string for network transfer and
  DataStore persistence.

  Binary Format (v1)
  ------------------
  Header  (10 bytes):
    [1]   uint8   format version  (= 1)
    [2-3] int16   chunk cx
    [4-5] int16   chunk cz
    [6-7] uint16  CHUNK_SIZE      (sanity check)
    [8-9] uint16  CHUNK_HEIGHT    (sanity check)
    [10]  uint8   reserved / flags

  Biome section  (CHUNK_SIZE * CHUNK_SIZE bytes, uint8 per column)

  Block section  (CHUNK_SIZE * CHUNK_HEIGHT * CHUNK_SIZE * 2 bytes, uint16 LE per voxel)
    — run-length encoded to save DataStore quota:
      RLE record:  uint16 blockId  |  uint16 runLength
      Sentinel:    both fields = 0xFFFF signals end of block section

  Total uncompressed: 10 + 1024 + (131072 * 2) = ≈ 264 KB worst case.
  With RLE a chunk of mostly air compresses to a few hundred bytes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")
local ChunkConstants    = require(WorldFolder:WaitForChild("ChunkConstants"))
local ChunkData         = require(WorldFolder:WaitForChild("ChunkData"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE    -- 32
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT  -- 128
local VOLUME       = CHUNK_SIZE * CHUNK_HEIGHT * CHUNK_SIZE
local BIOME_COUNT  = CHUNK_SIZE * CHUNK_SIZE

local FORMAT_VERSION = 1
local RLE_SENTINEL   = 0xFFFF

local ChunkSerializer = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Internal helpers: write/read little-endian integers into a byte table
-- ────────────────────────────────────────────────────────────────────────────

local function writeU8(buf, v)
	buf[#buf + 1] = string.char(v % 256)
end

local function writeI16(buf, v)
	-- signed 16-bit little-endian
	if v < 0 then v = v + 0x10000 end
	buf[#buf + 1] = string.char(v % 256)
	buf[#buf + 1] = string.char(math.floor(v / 256) % 256)
end

local function writeU16(buf, v)
	buf[#buf + 1] = string.char(v % 256)
	buf[#buf + 1] = string.char(math.floor(v / 256) % 256)
end

local function readU8(data, pos)
	return string.byte(data, pos), pos + 1
end

local function readI16(data, pos)
	local lo = string.byte(data, pos)
	local hi = string.byte(data, pos + 1)
	local v  = lo + hi * 256
	if v >= 0x8000 then v = v - 0x10000 end
	return v, pos + 2
end

local function readU16(data, pos)
	local lo = string.byte(data, pos)
	local hi = string.byte(data, pos + 1)
	return lo + hi * 256, pos + 2
end

-- ────────────────────────────────────────────────────────────────────────────
-- serialize: Convert a ChunkData object → binary string
-- ────────────────────────────────────────────────────────────────────────────

--- serialize: Pack a ChunkData into a compact binary string.
-- @param  chunk  ChunkData   The chunk to pack
-- @return string             Binary payload
function ChunkSerializer.serialize(chunk)
	assert(chunk and chunk.blocks, "ChunkSerializer.serialize: expected ChunkData")

	local buf = {}

	-- Header
	writeU8(buf,  FORMAT_VERSION)
	writeI16(buf, chunk.cx)
	writeI16(buf, chunk.cz)
	writeU16(buf, CHUNK_SIZE)
	writeU16(buf, CHUNK_HEIGHT)
	writeU8(buf,  0)  -- reserved

	-- Biome section (1 byte per column)
	for i = 1, BIOME_COUNT do
		writeU8(buf, chunk.biomes[i] or 0)
	end

	-- Block section: RLE over the flat voxel array
	local blocks  = chunk.blocks
	local i       = 1
	while i <= VOLUME do
		local id     = blocks[i]
		local run    = 1
		local limit  = math.min(VOLUME, i + 0xFFFE)
		-- count consecutive same-id voxels
		while i + run <= limit and blocks[i + run] == id do
			run = run + 1
		end
		writeU16(buf, id)
		writeU16(buf, run)
		i = i + run
	end
	-- Sentinel end marker
	writeU16(buf, RLE_SENTINEL)
	writeU16(buf, RLE_SENTINEL)

	return table.concat(buf)
end

-- ────────────────────────────────────────────────────────────────────────────
-- deserialize: Convert binary string → ChunkData object
-- ────────────────────────────────────────────────────────────────────────────

--- deserialize: Unpack a binary string into a ChunkData object.
-- @param  data  string   Binary payload (from serialize)
-- @return ChunkData
function ChunkSerializer.deserialize(data)
	assert(type(data) == "string" and #data > 10,
		"ChunkSerializer.deserialize: invalid data")

	local pos = 1

	-- Header
	local version; version, pos = readU8(data, pos)
	assert(version == FORMAT_VERSION,
		"ChunkSerializer.deserialize: unsupported version " .. tostring(version))

	local cx; cx, pos = readI16(data, pos)
	local cz; cz, pos = readI16(data, pos)

	local chunkSize;   chunkSize,   pos = readU16(data, pos)
	local chunkHeight; chunkHeight, pos = readU16(data, pos)

	assert(chunkSize   == CHUNK_SIZE,
		"ChunkSerializer.deserialize: CHUNK_SIZE mismatch " .. tostring(chunkSize))
	assert(chunkHeight == CHUNK_HEIGHT,
		"ChunkSerializer.deserialize: CHUNK_HEIGHT mismatch " .. tostring(chunkHeight))

	local _reserved; _reserved, pos = readU8(data, pos)  -- skip reserved byte

	-- Create empty chunk
	local chunk = ChunkData.new(cx, cz)

	-- Biome section
	for i = 1, BIOME_COUNT do
		local b; b, pos = readU8(data, pos)
		chunk.biomes[i] = b
	end

	-- Block section: decode RLE
	local blocks = chunk.blocks
	local vi     = 1  -- current voxel index (1-based)

	while true do
		local id, run
		id,  pos = readU16(data, pos)
		run, pos = readU16(data, pos)

		if id == RLE_SENTINEL and run == RLE_SENTINEL then
			break
		end

		-- Fill `run` voxels with `id`
		for _ = 1, run do
			if vi > VOLUME then break end
			blocks[vi] = id
			vi = vi + 1
		end
	end

	-- Mark clean (just loaded from storage)
	chunk:markClean()

	return chunk
end

return ChunkSerializer
