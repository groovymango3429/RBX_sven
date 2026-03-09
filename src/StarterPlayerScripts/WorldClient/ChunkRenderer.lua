--[[
  ChunkRenderer  [MODULE SCRIPT]
  =============
  Receives serialized chunk payloads from the server via the SendChunk
  RemoteEvent and renders terrain using the Roblox Terrain API for smooth,
  continuous geometry instead of discrete cube parts.

  Smooth terrain rendering strategy
  ----------------------------------
  • Each chunk's block data is translated into Roblox Terrain voxels using
    workspace.Terrain:WriteVoxels(), producing smooth and natural-looking
    hills, mountains, and valleys.
  • Block IDs are mapped to Terrain materials (Grass, Rock, Sand, Snow, etc.)
    so biome colouring is preserved.
  • Chunk unloading clears the corresponding terrain region by writing all-air
    voxels with workspace.Terrain:FillBlock().
  • Incoming chunks are queued and processed one at a time so multiple
    arriving chunks don't hammer the Terrain API on the same frame.

  Render-completion tracking
  --------------------------
  Call ChunkRenderer.setExpectedChunks(n) before generation starts so the
  renderer knows how many chunks to expect.  Once all n chunks have been
  rendered, the callback registered via ChunkRenderer.setOnAllRendered(fn)
  is fired once and cleared.  This lets MapLoader hide the loading screen
  only after all terrain has actually appeared on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")

local ChunkSerializer = require(WorldFolder:WaitForChild("ChunkSerializer"))
local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE    -- 9
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT  -- 128
local BLOCK_SIZE   = ChunkConstants.BLOCK_SIZE    -- 4 studs per block

local _renderedChunks = {}  -- chunkKey → true (rendered) | false (unloading/aborted) | nil (not loaded)

-- Queue of deserialized chunk objects waiting to be rendered
local _renderQueue   = {}
local _queueRunning  = false

-- ── Render-completion tracking ───────────────────────────────────────────────
-- Set by MapLoader (via setExpectedChunks / setOnAllRendered) so the loading
-- screen is hidden only after all chunks have actually been drawn on screen.
local _expectedTotal        = 0
local _renderedCount        = 0
local _onAllRenderedCallback = nil

local ChunkRenderer = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

local function chunkKey(cx, cz)
  return cx .. "," .. cz
end

-- Maps block IDs to Roblox Terrain materials for smooth voxel rendering.
-- Block IDs not in this table fall back to Enum.Material.Rock.
local _BLOCK_TO_TERRAIN = {
  [0]  = Enum.Material.Air,     -- air
  [1]  = Enum.Material.Grass,   -- grass
  [2]  = Enum.Material.Ground,  -- dirt
  [3]  = Enum.Material.Rock,    -- stone
  [4]  = Enum.Material.Sand,    -- sand
  [5]  = Enum.Material.Ground,  -- gravel
  [10] = Enum.Material.Rock,    -- bedrock
  [17] = Enum.Material.Ground,  -- clay
  [18] = Enum.Material.Snow,    -- snow
}

local function _getTerrainMaterial(id)
  return _BLOCK_TO_TERRAIN[id] or Enum.Material.Rock
end

--- _renderChunkAsync: Write chunk voxel data to Roblox Terrain via WriteVoxels.
-- Translates block IDs into Terrain materials and occupancy values, then
-- writes the entire chunk in one API call, producing smooth continuous terrain.
local function _renderChunkAsync(chunk)
  local key = chunkKey(chunk.cx, chunk.cz)
  if _renderedChunks[key] then return end  -- already rendered

  local originX = chunk.cx * CHUNK_SIZE * BLOCK_SIZE
  local originZ = chunk.cz * CHUNK_SIZE * BLOCK_SIZE
  local S = CHUNK_SIZE
  local H = CHUNK_HEIGHT

  -- Build materials and occupancy 3D arrays indexed [x][y][z] (1-based).
  -- Each entry covers one BLOCK_SIZE³ voxel in Roblox Terrain.
  local materials = table.create(S)
  local occupancy = table.create(S)

  for xi = 1, S do
    materials[xi] = table.create(H)
    occupancy[xi] = table.create(H)
    for yi = 1, H do
      materials[xi][yi] = table.create(S)
      occupancy[xi][yi] = table.create(S)
      for zi = 1, S do
        -- ChunkData uses 0-based (x,y,z); convert from 1-based loop indices.
        local id = chunk:getBlock(xi - 1, yi - 1, zi - 1)
        if id ~= 0 then
          materials[xi][yi][zi] = _getTerrainMaterial(id)
          occupancy[xi][yi][zi] = 1
        else
          materials[xi][yi][zi] = Enum.Material.Air
          occupancy[xi][yi][zi] = 0
        end
      end
    end
  end

  -- Abort if the chunk was unloaded while we were building the arrays.
  if _renderedChunks[key] == false then return end

  -- Write all voxels to Roblox Terrain in a single call for smooth geometry.
  local region = Region3.new(
    Vector3.new(originX, 0, originZ),
    Vector3.new(originX + S * BLOCK_SIZE, H * BLOCK_SIZE, originZ + S * BLOCK_SIZE)
  )
  workspace.Terrain:WriteVoxels(region, BLOCK_SIZE, materials, occupancy)

  -- Abort check after write: if unloaded mid-write, clear the terrain we placed.
  if _renderedChunks[key] == false then
    workspace.Terrain:FillBlock(
      CFrame.new(
        originX + S * BLOCK_SIZE * 0.5,
        H * BLOCK_SIZE * 0.5,
        originZ + S * BLOCK_SIZE * 0.5
      ),
      Vector3.new(S * BLOCK_SIZE, H * BLOCK_SIZE, S * BLOCK_SIZE),
      Enum.Material.Air
    )
    return
  end

  _renderedChunks[key] = true

  -- Track how many chunks have finished rendering.
  -- When the expected total is reached, fire the completion callback so the
  -- loading screen can be hidden after all terrain is visible.
  _renderedCount = _renderedCount + 1
  if _onAllRenderedCallback
    and _expectedTotal > 0
    and _renderedCount >= _expectedTotal
  then
    local cb = _onAllRenderedCallback
    _onAllRenderedCallback = nil  -- clear before calling to prevent re-entry
    cb()
  end

  print(string.format(
    "[ChunkRenderer] Chunk (%d,%d) rendered as smooth terrain",
    chunk.cx, chunk.cz
  ))
end

-- ────────────────────────────────────────────────────────────────────────────
-- Render queue — processes one chunk at a time so simultaneous arrivals
-- don't all call WriteVoxels on the same frame
-- ────────────────────────────────────────────────────────────────────────────

local function _processQueue()
  if _queueRunning then return end
  _queueRunning = true

  task.spawn(function()
    while #_renderQueue > 0 do
      local chunk = table.remove(_renderQueue, 1)
      _renderChunkAsync(chunk)   -- runs synchronously for this chunk; queue yields between chunks
      task.wait()
    end
    _queueRunning = false
  end)
end

local function _enqueueChunk(chunk)
  local key = chunkKey(chunk.cx, chunk.cz)
  -- Don't queue if already rendered or already queued for unload
  if _renderedChunks[key] then return end
  _renderQueue[#_renderQueue + 1] = chunk
  _processQueue()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

function ChunkRenderer.unloadChunk(cx, cz)
  local key = chunkKey(cx, cz)

  -- Mark as false immediately so any in-progress render pass aborts.
  _renderedChunks[key] = false

  -- Remove from the render queue if it hasn't been built yet.
  for i = #_renderQueue, 1, -1 do
    local c = _renderQueue[i]
    if c.cx == cx and c.cz == cz then
      table.remove(_renderQueue, i)
    end
  end

  -- Clear the Roblox Terrain region for this chunk by filling it with Air.
  local originX = cx * CHUNK_SIZE * BLOCK_SIZE
  local originZ = cz * CHUNK_SIZE * BLOCK_SIZE
  local S = CHUNK_SIZE
  local H = CHUNK_HEIGHT
  workspace.Terrain:FillBlock(
    CFrame.new(
      originX + S * BLOCK_SIZE * 0.5,
      H * BLOCK_SIZE * 0.5,
      originZ + S * BLOCK_SIZE * 0.5
    ),
    Vector3.new(S * BLOCK_SIZE, H * BLOCK_SIZE, S * BLOCK_SIZE),
    Enum.Material.Air
  )

  _renderedChunks[key] = nil
  print(string.format("[ChunkRenderer] Unloaded chunk (%d,%d)", cx, cz))
end

--- setExpectedChunks: Tell the renderer how many chunks to expect for this
-- generation pass.  Resets the rendered counter so progress is tracked from 0.
-- Call this from MapLoader (via connectRenderer) when a new generation starts.
-- @param n  number  Total number of chunks that will be sent
function ChunkRenderer.setExpectedChunks(n)
  _expectedTotal        = n
  _renderedCount        = 0
  _onAllRenderedCallback = nil
end

--- setOnAllRendered: Register a callback that fires once when all expected
-- chunks have finished rendering.  The callback is cleared after it fires.
-- @param fn  function  Called with no arguments when rendering is complete
function ChunkRenderer.setOnAllRendered(fn)
  _onAllRenderedCallback = fn
  -- If all chunks were already rendered before this was set (edge case),
  -- fire immediately so the loading screen is never stuck open.
  if _expectedTotal > 0 and _renderedCount >= _expectedTotal then
    _onAllRenderedCallback = nil
    fn()
  end
end

function ChunkRenderer.init()
  print("[ChunkRenderer] Initialising (smooth Terrain mode)…")

  local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
  local WorldRem = Remotes:WaitForChild("World")
  local remote   = WorldRem:WaitForChild("SendChunk", 10)

  if not remote then
    warn("[ChunkRenderer] SendChunk RemoteEvent not found after 10s — rendering disabled.")
    return
  end

  remote.OnClientEvent:Connect(function(payload)
    local ok, result = pcall(ChunkSerializer.deserialize, payload)
    if not ok then
      warn("[ChunkRenderer] Deserialize error: " .. tostring(result))
      return
    end
    _enqueueChunk(result)
  end)

  local unloadRemote = WorldRem:WaitForChild("UnloadChunk", 10)
  if unloadRemote then
    unloadRemote.OnClientEvent:Connect(function(cx, cz)
      ChunkRenderer.unloadChunk(cx, cz)
    end)
    print("[ChunkRenderer] Listening for UnloadChunk events ✓")
  else
    warn("[ChunkRenderer] UnloadChunk RemoteEvent not found after 10s — unloading disabled.")
  end

  print("[ChunkRenderer] Listening for SendChunk events ✓")
end

return ChunkRenderer