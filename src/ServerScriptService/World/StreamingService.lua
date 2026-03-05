--[[
  StreamingService  [MODULE SCRIPT]
  ================
  Streams chunks to players when they join the game.

  Called from:
    • WorldManager.init()          → StreamingService.init()
    • WorldManager.onPlayerAdded() → StreamingService.onPlayerAdded(player)
    • WorldManager.onPlayerRemoving() → StreamingService.onPlayerRemoving(player)

  Flow on player join:
    1. GameManager fires Players.PlayerAdded
    2. GameManager calls WorldManager.onPlayerAdded(player)
    3. WorldManager calls StreamingService.onPlayerAdded(player)
    4. StreamingService spawns a task that generates + serializes chunks
       around the world origin (Phase 1: flat, single biome) and fires
       the SendChunk RemoteEvent to that specific player.

  The client-side ChunkRenderer listens for SendChunk and renders parts.
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

-- Number of chunks to send before yielding to prevent frame stalls.
-- Roblox sends RemoteEvent fires immediately, but generating + serializing
-- many chunks in a tight loop can delay the first heartbeat. Yield every
-- CHUNKS_PER_YIELD chunks so the server stays responsive.
local CHUNKS_PER_YIELD = 9

-- Initial stream radius in chunks (capped at 4 to avoid large payloads on join)
local INITIAL_STREAM_RADIUS = math.min(ChunkConstants.RENDER_DISTANCE, 4)

-- Cached reference to the SendChunk RemoteEvent
local _sendChunkRemote

local StreamingService = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ────────────────────────────────────────────────────────────────────────────

local function getSendChunkRemote()
	if _sendChunkRemote then return _sendChunkRemote end
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	_sendChunkRemote = WorldRem:WaitForChild("SendChunk", 10)
	assert(_sendChunkRemote, "[StreamingService] SendChunk RemoteEvent not found in Remotes/World")
	return _sendChunkRemote
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Called once by WorldManager during server boot
function StreamingService.init()
	-- Ensure the remote is accessible (fail fast during boot if missing)
	getSendChunkRemote()
	Logger.Info("[StreamingService] Initialised — SendChunk remote ready.")
end

--- streamChunksForPlayer: Generate & send all initial chunks to one player.
-- Runs in its own task so it does not block the caller.
-- @param player  Player
local function streamChunksForPlayer(player)
	local remote = getSendChunkRemote()
	local r      = INITIAL_STREAM_RADIUS

	Logger.Info(string.format(
		"[StreamingService] Streaming initial chunks to %s (radius=%d, %d chunks)",
		player.Name, r, (2*r+1)^2
	))

	local count = 0
	for dcx = -r, r do
		for dcz = -r, r do
			-- Abort early if the player left mid-stream
			if not player.Parent then
				Logger.Debug("[StreamingService] Player disconnected mid-stream: " .. player.Name)
				return
			end

			local cx    = dcx
			local cz    = dcz
			local chunk = ChunkService.requestChunk(cx, cz, player)

			Logger.Debug(string.format(
				"[StreamingService] Generated chunk (%d, %d) for %s — dirty=%s",
				cx, cz, player.Name, tostring(chunk.dirty)
			))

			local payload = ChunkSerializer.serialize(chunk)
			remote:FireClient(player, payload)
			count = count + 1

			-- Yield every CHUNKS_PER_YIELD chunks to prevent frame stalls
			if count % CHUNKS_PER_YIELD == 0 then
				task.wait()
			end
		end
	end

	Logger.Info(string.format(
		"[StreamingService] Sent %d chunks to %s ✓", count, player.Name
	))
end

--- onPlayerAdded: Called by WorldManager when a player joins.
-- Spawns a background task to stream the initial chunk set.
-- WHERE THIS IS CALLED:
--   GameManager (GameManager.server.lua) fires Players.PlayerAdded
--   → WorldManager.onPlayerAdded(player)
--   → StreamingService.onPlayerAdded(player)   ← here
function StreamingService.onPlayerAdded(player)
	task.spawn(streamChunksForPlayer, player)
end

--- onPlayerRemoving: Called by WorldManager when a player leaves.
function StreamingService.onPlayerRemoving(player)
	-- ChunkService.onPlayerRemoving already releases subscriptions.
	-- Nothing extra needed here for Phase 1.
	Logger.Debug("[StreamingService] Player leaving: " .. player.Name)
end

return StreamingService
