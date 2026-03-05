--[[
  ChunkService  [MODULE SCRIPT]
  ============
  Load/unload chunks per player.
  • Maintains a server-side LRU cache of active ChunkData objects.
  • Generates missing chunks via ChunkGenerator (flat terrain).
  • Tracks which players are near which chunks.
  • Marks chunks dirty when modified; dirty chunks are flushed periodically
    by ChunkPersistence (called externally by WorldManager).

  Public API
  ----------
  ChunkService.init()
  ChunkService.onPlayerAdded(player)
  ChunkService.onPlayerRemoving(player)
  ChunkService.requestChunk(cx, cz, player)   → ChunkData
  ChunkService.releaseChunk(cx, cz, player)
  ChunkService.getChunk(cx, cz)               → ChunkData | nil
  ChunkService.getDirtyChunks()               → { chunkKey: ChunkData }
  ChunkService.markAllClean()
]]

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Shared             = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder        = Shared:WaitForChild("World")

local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))
local ChunkData       = require(WorldFolder:WaitForChild("ChunkData"))

local ServerScriptService = game:GetService("ServerScriptService")
local WorldScripts        = ServerScriptService:WaitForChild("World")
local ChunkGenerator      = require(WorldScripts:WaitForChild("ChunkGenerator"))

local MAX_CACHE_SIZE = ChunkConstants.MAX_CACHE_SIZE  -- 256

-- ────────────────────────────────────────────────────────────────────────────
-- Module
-- ────────────────────────────────────────────────────────────────────────────

local ChunkService = {}

-- Cache: chunkKey → ChunkData
-- chunkKey = cx .. "," .. cz  (string key for easy table indexing)
local _cache      = {}     -- { [key] = ChunkData }
local _cacheOrder = {}     -- array of keys in LRU order (oldest first)
local _cachePos   = {}     -- { [key] = index in _cacheOrder } for O(1) lookup
local _cacheSize  = 0

-- Player subscriptions: chunkKey → { [player] = true }
local _subscribers = {}   -- { [key] = { [Player] = true } }

-- Per-player set of subscribed chunk keys: player → { [key] = true }
local _playerChunks = {}  -- { [Player] = { [key] = true } }

-- ────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ────────────────────────────────────────────────────────────────────────────

local function _key(cx, cz)
	return cx .. "," .. cz
end

-- Touch an existing cache entry (move to end of LRU list = most recent)
-- Uses _cachePos for O(1) index lookup instead of a linear scan.
local function _touchLRU(key)
	local pos = _cachePos[key]
	if not pos then return end

	local n = #_cacheOrder
	if pos == n then return end  -- already most-recent

	-- Shift entries left to fill the gap
	for i = pos, n - 1 do
		local k = _cacheOrder[i + 1]
		_cacheOrder[i] = k
		_cachePos[k]   = i
	end
	_cacheOrder[n] = key
	_cachePos[key] = n
end

-- Evict the least-recently-used chunk that has no active subscribers
local function _evictIfNeeded()
	if _cacheSize <= MAX_CACHE_SIZE then return end

	for i, key in ipairs(_cacheOrder) do
		local subs = _subscribers[key]
		local hasSubscribers = subs ~= nil and next(subs) ~= nil
		if not hasSubscribers then
			-- Safe to evict: remove from cache
			_cache[key]   = nil
			_cachePos[key] = nil
			_subscribers[key] = nil

			-- Shift entries left to close the gap
			local n = #_cacheOrder
			for j = i, n - 1 do
				local k = _cacheOrder[j + 1]
				_cacheOrder[j] = k
				_cachePos[k]   = j
			end
			_cacheOrder[n] = nil

			_cacheSize = _cacheSize - 1
			return
		end
	end
	-- All cached chunks are subscribed — nothing to evict right now
end

-- Load or generate a chunk and add it to the cache
local function _loadChunk(cx, cz)
	local key = _key(cx, cz)

	if _cache[key] then
		_touchLRU(key)
		return _cache[key]
	end

	-- TODO: attempt DataStore load via ChunkPersistence here when implemented.
	-- For now, always generate fresh flat terrain.
	local chunk  = ChunkGenerator.generate(cx, cz)
	local newPos = #_cacheOrder + 1

	_cache[key]        = chunk
	_cacheOrder[newPos] = key
	_cachePos[key]     = newPos
	_cacheSize         = _cacheSize + 1

	_evictIfNeeded()

	return chunk
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Set up the service (call once from WorldManager)
function ChunkService.init()
	-- Reset state (safe to call multiple times in tests)
	_cache        = {}
	_cacheOrder   = {}
	_cachePos     = {}
	_cacheSize    = 0
	_subscribers  = {}
	_playerChunks = {}
end

--- onPlayerAdded: Register a player so ChunkService can track their chunks
function ChunkService.onPlayerAdded(player)
	_playerChunks[player] = {}
end

--- onPlayerRemoving: Release all chunks the departing player held
function ChunkService.onPlayerRemoving(player)
	local playerKeys = _playerChunks[player]
	if playerKeys then
		for key in pairs(playerKeys) do
			local subs = _subscribers[key]
			if subs then
				subs[player] = nil
			end
		end
	end
	_playerChunks[player] = nil
end

--- requestChunk: Get (or generate) a chunk and subscribe the player to it.
-- @param cx      number
-- @param cz      number
-- @param player  Player | nil   Pass nil for server-only requests
-- @return ChunkData
function ChunkService.requestChunk(cx, cz, player)
	local key   = _key(cx, cz)
	local chunk = _loadChunk(cx, cz)

	if player then
		-- Subscribe player → chunk
		if not _subscribers[key] then
			_subscribers[key] = {}
		end
		_subscribers[key][player] = true

		-- Track chunk → player
		if _playerChunks[player] then
			_playerChunks[player][key] = true
		end
	end

	return chunk
end

--- releaseChunk: Unsubscribe a player from a chunk.
-- The chunk stays cached; it will be evicted once the LRU fills.
-- @param cx      number
-- @param cz      number
-- @param player  Player
function ChunkService.releaseChunk(cx, cz, player)
	local key = _key(cx, cz)

	local subs = _subscribers[key]
	if subs then
		subs[player] = nil
	end

	if _playerChunks[player] then
		_playerChunks[player][key] = nil
	end
end

--- getChunk: Return the cached ChunkData without generating or subscribing.
-- @return ChunkData | nil
function ChunkService.getChunk(cx, cz)
	local key = _key(cx, cz)
	if _cache[key] then
		_touchLRU(key)
	end
	return _cache[key]
end

--- getDirtyChunks: Return a shallow copy of all dirty cached chunks.
-- Used by ChunkPersistence to find chunks that need saving.
-- @return { [key: string]: ChunkData }
function ChunkService.getDirtyChunks()
	local dirty = {}
	for key, chunk in pairs(_cache) do
		if chunk.dirty then
			dirty[key] = chunk
		end
	end
	return dirty
end

--- markAllClean: Clear the dirty flag on every cached chunk.
-- Call this after a successful persistence flush.
function ChunkService.markAllClean()
	for _, chunk in pairs(_cache) do
		chunk:markClean()
	end
end

--- getSubscriberCount: Number of players subscribed to a chunk (debug helper)
function ChunkService.getSubscriberCount(cx, cz)
	local key  = _key(cx, cz)
	local subs = _subscribers[key]
	if not subs then return 0 end
	local n = 0
	for _ in pairs(subs) do n = n + 1 end
	return n
end

--- getCacheSize: Current number of chunks in the LRU cache (debug helper)
function ChunkService.getCacheSize()
	return _cacheSize
end

return ChunkService
