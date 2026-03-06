--[[
  StreamingService  [MODULE SCRIPT]
  ================
  Streams chunks to players based on their current position in the world.
  As a player walks, new chunks within RENDER_DISTANCE are generated and sent;
  chunks that fall out of range are unloaded on the client.

  Called from:
    • WorldManager.init()             → StreamingService.init()
    • WorldManager.onPlayerAdded()    → StreamingService.onPlayerAdded(player)
    • WorldManager.onPlayerRemoving() → StreamingService.onPlayerRemoving(player)

  Flow on player join:
    1. GameManager fires Players.PlayerAdded
    2. GameManager calls WorldManager.onPlayerAdded(player)
    3. WorldManager calls StreamingService.onPlayerAdded(player)
    4. StreamingService waits for the character, then starts a polling loop
       that tracks the player's chunk position and dynamically streams new
       chunks (via SendChunk) and unloads old ones (via UnloadChunk).

  The client-side ChunkRenderer listens for SendChunk (render) and
  UnloadChunk (destroy) RemoteEvents.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder  = Shared:WaitForChild("World")
local WorldScripts = ServerScriptService:WaitForChild("World")

local Logger          = require(Shared.Core:WaitForChild("Logger"))
local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))
local ChunkSerializer = require(WorldFolder:WaitForChild("ChunkSerializer"))
local ChunkService    = require(WorldScripts:WaitForChild("ChunkService"))

-- Studs per voxel block and per chunk column (must match ChunkRenderer)
local BLOCK_SIZE      = ChunkConstants.BLOCK_SIZE           -- 4
local STUDS_PER_CHUNK = ChunkConstants.CHUNK_SIZE * BLOCK_SIZE  -- 128
local RENDER_DISTANCE = ChunkConstants.RENDER_DISTANCE      -- 8

-- Number of chunks to send before yielding to prevent frame stalls
local CHUNKS_PER_YIELD = 9

-- Seconds between position polls per player
local POLL_INTERVAL = 0.5

-- Cached remote references
local _sendChunkRemote
local _unloadChunkRemote

-- Per-player streaming state
-- { [player] = { lastCx=number|nil, lastCz=number|nil, sentKeys={[key]=true} } }
local _playerState = {}

local StreamingService = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ────────────────────────────────────────────────────────────────────────────

local function _key(cx, cz)
	return cx .. "," .. cz
end

local function getSendChunkRemote()
	if _sendChunkRemote then return _sendChunkRemote end
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	_sendChunkRemote = WorldRem:WaitForChild("SendChunk", 10)
	assert(_sendChunkRemote, "[StreamingService] SendChunk RemoteEvent not found in Remotes/World")
	return _sendChunkRemote
end

local function getUnloadChunkRemote()
	if _unloadChunkRemote then return _unloadChunkRemote end
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	_unloadChunkRemote = WorldRem:WaitForChild("UnloadChunk", 10)
	assert(_unloadChunkRemote, "[StreamingService] UnloadChunk RemoteEvent not found in Remotes/World")
	return _unloadChunkRemote
end

-- Send newly in-range chunks and unload out-of-range chunks for a player.
local function updateChunksForPlayer(player, cx, cz)
	local state = _playerState[player]
	if not state then return end

	local sendRemote   = getSendChunkRemote()
	local unloadRemote = getUnloadChunkRemote()
	local r            = RENDER_DISTANCE

	-- Build the set of chunk keys that should currently be loaded
	local needed = {}
	for dcx = -r, r do
		for dcz = -r, r do
			local ncx = cx + dcx
			local ncz = cz + dcz
			needed[_key(ncx, ncz)] = { ncx, ncz }
		end
	end

	-- Send any chunks that are newly in range
	local count = 0
	for key, coords in pairs(needed) do
		if not state.sentKeys[key] then
			if not player.Parent then return end
			local chunk   = ChunkService.requestChunk(coords[1], coords[2], player)
			local payload = ChunkSerializer.serialize(chunk)
			sendRemote:FireClient(player, payload)
			state.sentKeys[key] = true
			count = count + 1
			if count % CHUNKS_PER_YIELD == 0 then
				task.wait()
			end
		end
	end

	-- Unload chunks that have gone out of range
	for key in pairs(state.sentKeys) do
		if not needed[key] then
			local kcx, kcz = key:match("^(-?%d+),(-?%d+)$")
			if kcx and kcz then
				kcx = tonumber(kcx)
				kcz = tonumber(kcz)
				if player.Parent then
					unloadRemote:FireClient(player, kcx, kcz)
				end
				ChunkService.releaseChunk(kcx, kcz, player)
			end
			state.sentKeys[key] = nil
		end
	end

	if count > 0 then
		Logger.Debug(string.format(
			"[StreamingService] Sent %d new chunks to %s at chunk (%d,%d)",
			count, player.Name, cx, cz
		))
	end
end

-- Check the player's current chunk position and update streaming if they moved.
local function pollPlayer(player)
	local state = _playerState[player]
	if not state then return end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local pos = root.Position
	local cx  = math.floor(pos.X / STUDS_PER_CHUNK)
	local cz  = math.floor(pos.Z / STUDS_PER_CHUNK)

	if cx == state.lastCx and cz == state.lastCz then return end
	state.lastCx = cx
	state.lastCz = cz

	updateChunksForPlayer(player, cx, cz)
end

-- Background loop that polls one player's position until they leave.
local function runStreamingLoop(player)
	-- Wait for the character (and its root part) to be fully loaded
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then
		Logger.Debug("[StreamingService] HumanoidRootPart not found for " .. player.Name .. " — streaming loop aborted.")
		return
	end

	Logger.Info("[StreamingService] Starting streaming loop for " .. player.Name)

	while player.Parent do
		local ok, err = pcall(pollPlayer, player)
		if not ok then
			Logger.Debug("[StreamingService] pollPlayer error for "
				.. player.Name .. ": " .. tostring(err))
		end
		task.wait(POLL_INTERVAL)
	end

	Logger.Debug("[StreamingService] Streaming loop ended for " .. player.Name)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Called once by WorldManager during server boot
function StreamingService.init()
	getSendChunkRemote()
	getUnloadChunkRemote()
	Logger.Info("[StreamingService] Initialised — SendChunk and UnloadChunk remotes ready.")
end

--- onPlayerAdded: Called by WorldManager when a player joins.
-- Initialises per-player state and spawns the streaming loop.
-- WHERE THIS IS CALLED:
--   GameManager (GameManager.server.lua) fires Players.PlayerAdded
--   → WorldManager.onPlayerAdded(player)
--   → StreamingService.onPlayerAdded(player)   ← here
function StreamingService.onPlayerAdded(player)
	_playerState[player] = {
		lastCx   = nil,
		lastCz   = nil,
		sentKeys = {},
	}
	task.spawn(runStreamingLoop, player)
end

--- onPlayerRemoving: Called by WorldManager when a player leaves.
-- Releases all chunk subscriptions held by this player.
function StreamingService.onPlayerRemoving(player)
	Logger.Debug("[StreamingService] Player leaving: " .. player.Name)
	local state = _playerState[player]
	if state then
		for key in pairs(state.sentKeys) do
			local kcx, kcz = key:match("^(-?%d+),(-?%d+)$")
			if kcx and kcz then
				ChunkService.releaseChunk(tonumber(kcx), tonumber(kcz), player)
			end
		end
		_playerState[player] = nil
	end
end

return StreamingService
