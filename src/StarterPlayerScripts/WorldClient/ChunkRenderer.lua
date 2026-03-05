--[[
  ChunkRenderer  [MODULE SCRIPT]
  =============
  Receives serialized chunk payloads from the server via the SendChunk
  RemoteEvent and renders surface terrain as BaseParts in the Workspace.

  Phase 1 rendering strategy
  --------------------------
  • Only the highest non-air, solid block per XZ column is rendered.
    This avoids spawning hundreds of thousands of parts for a full chunk.
  • Each surface block becomes a BLOCK_SIZE-stud Part coloured and
    material-matched to the BlockRegistry definition.
  • All parts for a chunk live inside a Folder named "Chunk_cx,cz" under
    Workspace.World.ActiveChunks, making them easy to destroy later.

  WHERE init() IS CALLED:
    ClientMain.client.lua (StarterPlayerScripts) calls ChunkRenderer.init()
    during the client boot sequence right after the module is loaded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")

local ChunkSerializer = require(WorldFolder:WaitForChild("ChunkSerializer"))
local BlockRegistry   = require(WorldFolder:WaitForChild("BlockRegistry"))
local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))

local CHUNK_SIZE  = ChunkConstants.CHUNK_SIZE    -- 32
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT -- 128
local BLOCK_SIZE  = 4  -- studs per block (visual scale)

-- Parent folder for all rendered chunk geometry
local _activeChunksFolder

local ChunkRenderer = {}

-- Track rendered chunk folders: chunkKey → Folder
local _renderedChunks = {}

local function chunkKey(cx, cz)
	return cx .. "," .. cz
end

-- ────────────────────────────────────────────────────────────────────────────
-- Rendering helpers
-- ────────────────────────────────────────────────────────────────────────────

--- _getMaterial: Safely resolve a Roblox Material enum from a name string.
local function _getMaterial(name)
	local ok, mat = pcall(function()
		return Enum.Material[name]
	end)
	return (ok and mat) or Enum.Material.SmoothPlastic
end

--- _renderChunk: Build surface Parts for a deserialized ChunkData.
local function _renderChunk(chunk)
	local key = chunkKey(chunk.cx, chunk.cz)
	if _renderedChunks[key] then
		-- Already rendered — skip duplicate sends
		return
	end

	-- World-space origin (studs) of this chunk
	local originX = chunk.cx * CHUNK_SIZE * BLOCK_SIZE
	local originZ = chunk.cz * CHUNK_SIZE * BLOCK_SIZE

	-- Folder to hold this chunk's parts
	local folder = Instance.new("Folder")
	folder.Name   = "Chunk_" .. key
	folder.Parent = _activeChunksFolder

	local partCount = 0
	for x = 0, CHUNK_SIZE - 1 do
		for z = 0, CHUNK_SIZE - 1 do
			-- Find the highest non-air block in this column
			local surfaceY  = -1
			local surfaceId = 0
			for y = CHUNK_HEIGHT - 1, 0, -1 do
				local id = chunk:getBlock(x, y, z)
				if id ~= 0 then
					surfaceY  = y
					surfaceId = id
					break
				end
			end

			if surfaceY >= 0 then
				local def = BlockRegistry.getById(surfaceId)
				if def and def.solid then
					local part          = Instance.new("Part")
					part.Name           = def.name
					part.Size           = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					part.Anchored       = true
					part.CanCollide     = true
					part.CastShadow     = true
					part.Material       = _getMaterial(def.material)
					part.Color          = def.color
					part.CFrame         = CFrame.new(
						originX + x * BLOCK_SIZE + BLOCK_SIZE / 2,
						surfaceY * BLOCK_SIZE + BLOCK_SIZE / 2,
						originZ + z * BLOCK_SIZE + BLOCK_SIZE / 2
					)
					part.Parent  = folder
					partCount    = partCount + 1
				end
			end
		end
	end

	_renderedChunks[key] = folder

	print(string.format(
		"[ChunkRenderer] Chunk (%d,%d) rendered — %d surface parts",
		chunk.cx, chunk.cz, partCount
	))
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

--- init: Connect to the SendChunk RemoteEvent and begin listening for chunks.
-- Called by ClientMain during client boot (StarterPlayerScripts/ClientMain.client.lua).
function ChunkRenderer.init()
	print("[ChunkRenderer] Initialising…")

	-- Resolve the ActiveChunks folder
	_activeChunksFolder = Workspace
		:WaitForChild("World")
		:WaitForChild("ActiveChunks")

	-- Wait for the server to expose the SendChunk RemoteEvent
	local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
	local WorldRem = Remotes:WaitForChild("World")
	local remote   = WorldRem:WaitForChild("SendChunk", 10)

	if not remote then
		warn("[ChunkRenderer] SendChunk RemoteEvent not found after 10s timeout — rendering disabled.")
		return
	end

	remote.OnClientEvent:Connect(function(payload)
		local ok, result = pcall(ChunkSerializer.deserialize, payload)
		if not ok then
			warn("[ChunkRenderer] Deserialize error: " .. tostring(result))
			return
		end
		-- Render on next frame to keep the connection handler responsive
		task.spawn(_renderChunk, result)
	end)

	print("[ChunkRenderer] Listening for SendChunk events ✓")
end

--- unloadChunk: Remove a rendered chunk from the workspace.
-- @param cx  number
-- @param cz  number
function ChunkRenderer.unloadChunk(cx, cz)
	local key = chunkKey(cx, cz)
	local folder = _renderedChunks[key]
	if folder then
		folder:Destroy()
		_renderedChunks[key] = nil
		print(string.format("[ChunkRenderer] Unloaded chunk (%d,%d)", cx, cz))
	end
end

return ChunkRenderer
