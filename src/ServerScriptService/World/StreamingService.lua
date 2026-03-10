--[[
  StreamingService  [MODULE SCRIPT]
  ================
  Generates the entire map for a player on demand (button-triggered).

  When the client fires the RequestMapGeneration RemoteEvent this service:
    1. Generates every chunk in the world grid (RENDER_DISTANCE radius from
       the world origin).
    2. Fires a MapGenProgress event after each chunk so the client loading bar
       can update.
    3. Sends each serialized chunk to the client via SendChunk.

  Dynamic per-player streaming (position polling / chunk eviction) has been
  removed.  All chunks are generated once during the loading screen and then
  remain in the world for the duration of the session.

  Called from:
    • WorldManager.init()             → StreamingService.init()
    • WorldManager.onPlayerAdded()    → StreamingService.onPlayerAdded(player)
    • WorldManager.onPlayerRemoving() → StreamingService.onPlayerRemoving(player)

  The client-side MapLoader listens for MapGenProgress events and hides the
  loading screen once all chunks have been received.  ChunkRenderer continues
  to listen for SendChunk to render terrain.
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
local TreeGenerationService = require(WorldScripts:WaitForChild("TreeGenerationService"))

-- Radius of the world grid that is generated when the button is clicked.
-- Changing RENDER_DISTANCE in ChunkConstants automatically adjusts this.
-- Default value is 4, producing (2×4+1)² = 81 chunks total.
local RENDER_DISTANCE = ChunkConstants.RENDER_DISTANCE

-- Number of chunks to send before yielding to keep the server responsive.
local CHUNKS_PER_YIELD = 9

-- Cached remote references
local _sendChunkRemote
local _progressRemote

-- Guard against duplicate generation requests per player.
-- { [player] = true } while a generation is in progress.
local _generating = {}

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

local function getProgressRemote()
	if _progressRemote then return _progressRemote end
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	_progressRemote = WorldRem:WaitForChild("MapGenProgress", 10)
	assert(_progressRemote, "[StreamingService] MapGenProgress RemoteEvent not found in Remotes/World")
	return _progressRemote
end

-- Generate (or retrieve from the LRU cache) every chunk in the world grid
-- and stream them all to the requesting player in one pass.
-- Progress events are fired after each chunk so the client loading bar updates.
local function generateMapForPlayer(player)
	if _generating[player] then
		Logger.Debug("[StreamingService] Generation already in progress for " .. player.Name)
		return
	end
	_generating[player] = true

	local sendRemote     = getSendChunkRemote()
	local progressRemote = getProgressRemote()
	local r              = RENDER_DISTANCE

	-- Build the complete chunk list up front so we know the total count.
	local chunkList = {}
	for dcx = -r, r do
		for dcz = -r, r do
			chunkList[#chunkList + 1] = { dcx, dcz }
		end
	end
	local total = #chunkList

	Logger.Info(string.format(
		"[StreamingService] Generating %d chunks for %s…", total, player.Name
	))

	for i, coords in ipairs(chunkList) do
		if not player.Parent then
			Logger.Debug("[StreamingService] Player left during generation — aborting.")
			_generating[player] = nil
			return
		end

		local cx, cz  = coords[1], coords[2]
		local chunk   = ChunkService.requestChunk(cx, cz, player)
		
		-- Spawn trees in this chunk after terrain generation
		TreeGenerationService.spawnTreesForChunk(chunk)
		
		local payload = ChunkSerializer.serialize(chunk)
		sendRemote:FireClient(player, payload)

		-- Report progress after each chunk (done, total).
		progressRemote:FireClient(player, i, total)

		if i % CHUNKS_PER_YIELD == 0 then
			task.wait()
		end
	end

	Logger.Info("[StreamingService] Map generation complete for " .. player.Name)
	
	-- Print tree spawning statistics after all chunks are generated
	TreeGenerationService.printDebugStats()
	
	_generating[player] = nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Called once by WorldManager during server boot.
-- Caches remotes and connects the RequestMapGeneration handler so it is
-- ready before any player can join and click the button.
function StreamingService.init()
	getSendChunkRemote()
	getProgressRemote()

	-- Listen for client-triggered generation requests (button click).
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	local requestRemote = WorldRem:WaitForChild("RequestMapGeneration", 10)
	assert(requestRemote, "[StreamingService] RequestMapGeneration RemoteEvent not found in Remotes/World")

	requestRemote.OnServerEvent:Connect(function(player)
		task.spawn(generateMapForPlayer, player)
	end)

	Logger.Info("[StreamingService] Initialised — awaiting RequestMapGeneration events.")
end

--- onPlayerAdded: Register the player with the service.
-- Map generation is now deferred until the client fires RequestMapGeneration.
-- WHERE THIS IS CALLED:
--   GameManager (GameManager.server.lua) fires Players.PlayerAdded
--   → WorldManager.onPlayerAdded(player)
--   → StreamingService.onPlayerAdded(player)   ← here
function StreamingService.onPlayerAdded(player)
	-- ChunkService registration is handled by WorldManager.
	-- Generation starts only when the client fires RequestMapGeneration.
end

--- onPlayerRemoving: Clean up any in-progress generation for this player.
-- Chunk subscription cleanup is handled by ChunkService.onPlayerRemoving
-- (called by WorldManager).
function StreamingService.onPlayerRemoving(player)
	Logger.Debug("[StreamingService] Player leaving: " .. player.Name)
	_generating[player] = nil
end

return StreamingService
