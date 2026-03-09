--[[
  ChunkRenderer  [MODULE SCRIPT]
  =============
  Receives serialized chunk payloads from the server via the SendChunk
  RemoteEvent and renders surface terrain as BaseParts in the Workspace.

  Phase 1 rendering strategy
  --------------------------
  • Only blocks on the boundary between solid and air are rendered.
    A block is a boundary block when it has at least one solid neighbor
    AND at least one air neighbor (any of the 6 axis-aligned directions).
    This is equivalent to the visible surface of the solid volume and avoids
    spawning parts for fully-buried interior blocks.
  • Parts are created in batches across frames to avoid lag spikes.
  • Incoming chunks are queued and processed one at a time so multiple
    arriving chunks don't all hammer the engine simultaneously.
  • The finished folder is parented in one shot at the end of each render
    so the chunk appears atomically rather than part-by-part.
  • Chunk unloading destroys children in small batches spread across frames
    to prevent single-frame stalls when many parts are removed at once.

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
local BlockRegistry   = require(WorldFolder:WaitForChild("BlockRegistry"))
local ChunkConstants  = require(WorldFolder:WaitForChild("ChunkConstants"))

local CHUNK_SIZE   = ChunkConstants.CHUNK_SIZE    -- 5
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT  -- 128
local BLOCK_SIZE   = ChunkConstants.BLOCK_SIZE    -- 4 studs per block

-- How many parts to create per frame during a render pass.
-- Raise for faster load, lower if you still see frame dips. 128 is a safe start.
local RENDER_BATCH_SIZE = 128

-- How many parts to destroy per frame during a chunk unload.
-- Spreading destruction across frames prevents single-frame lag spikes.
local UNLOAD_BATCH_SIZE = 64

local _activeChunksFolder
local _renderedChunks = {}  -- chunkKey → Folder

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

local function _getMaterial(name)
  local ok, mat = pcall(function() return Enum.Material[name] end)
  return (ok and mat) or Enum.Material.SmoothPlastic
end

-- ────────────────────────────────────────────────────────────────────────────
-- Boundary detection
-- ────────────────────────────────────────────────────────────────────────────

-- The 6 axis-aligned unit-step offsets used for neighbor checks.
-- Stored as plain {dx,dy,dz} tables to avoid Vector3 allocation overhead.
local _NEIGHBOR_OFFSETS = {
  { 1, 0, 0}, {-1, 0, 0},
  { 0, 1, 0}, { 0,-1, 0},
  { 0, 0, 1}, { 0, 0,-1},
}

--- _isOnBoundary: Return true when solid block (x,y,z) touches at least one
-- air block.  Must only be called on known-solid blocks.
-- ChunkData:getBlock() already returns 0 for out-of-bounds coordinates, so
-- chunk edges are treated as air automatically.
local function _isOnBoundary(chunk, x, y, z)
  for _, off in ipairs(_NEIGHBOR_OFFSETS) do
    if chunk:getBlock(x + off[1], y + off[2], z + off[3]) == 0 then
      return true
    end
  end
  return false
end

-- ────────────────────────────────────────────────────────────────────────────
-- Batched rendering
-- ────────────────────────────────────────────────────────────────────────────

--- _buildSurfaceList: Walk the chunk once and collect all boundary block data.
-- A boundary block is any solid block that has at least one air neighbor,
-- i.e. the visible surface of the solid volume.
-- Returns a flat array of {wx, wy, wz, def} so the render loop is just
-- creating parts — no per-part chunk lookups or branching.
local function _buildSurfaceList(chunk)
  local originX = chunk.cx * CHUNK_SIZE * BLOCK_SIZE
  local originZ = chunk.cz * CHUNK_SIZE * BLOCK_SIZE
  local list = {}

  for x = 0, CHUNK_SIZE - 1 do
    for z = 0, CHUNK_SIZE - 1 do
      for y = 0, CHUNK_HEIGHT - 1 do
        local id = chunk:getBlock(x, y, z)
        if id ~= 0 then
          local def = BlockRegistry.getById(id)
          if def and def.solid and _isOnBoundary(chunk, x, y, z) then
            list[#list + 1] = {
              wx  = originX + x * BLOCK_SIZE + BLOCK_SIZE / 2,
              wy  = y * BLOCK_SIZE + BLOCK_SIZE / 2,
              wz  = originZ + z * BLOCK_SIZE + BLOCK_SIZE / 2,
              def = def,
            }
          end
        end
      end
    end
  end

  return list
end

--- _renderChunkAsync: Build parts in RENDER_BATCH_SIZE increments across frames.
-- The folder is kept detached until the very end so the workspace doesn't
-- have to process hundreds of individual parent changes.
local function _renderChunkAsync(chunk)
  local key = chunkKey(chunk.cx, chunk.cz)
  if _renderedChunks[key] then return end  -- already rendered

  local surfaceList = _buildSurfaceList(chunk)

  -- Build into a detached folder — zero workspace cost until we parent it
  local folder = Instance.new("Folder")
  folder.Name = "Chunk_" .. key

  local partCount = 0
  for i, entry in ipairs(surfaceList) do
    local def  = entry.def
    local part = Instance.new("Part")
    part.Name      = def.name
    part.Size      = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
    part.Anchored  = true
    part.CanCollide = true
    part.CastShadow = true
    part.Material  = _getMaterial(def.material)
    part.Color     = def.color
    part.CFrame    = CFrame.new(entry.wx, entry.wy, entry.wz)
    part.Parent    = folder   -- parent to detached folder, not workspace
    partCount      = partCount + 1

    -- Yield every RENDER_BATCH_SIZE parts to spread work across frames
    if i % RENDER_BATCH_SIZE == 0 then
      task.wait()
      -- Abort if the chunk was unloaded while we were building it
      if _renderedChunks[key] == false then
        folder:Destroy()
        return
      end
    end
  end

  -- If unloaded while we were mid-render, throw away the folder
  if _renderedChunks[key] == false then
    folder:Destroy()
    return
  end

  -- Parent the whole folder in one shot — chunk appears atomically
  folder.Parent = _activeChunksFolder
  _renderedChunks[key] = folder

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
    "[ChunkRenderer] Chunk (%d,%d) rendered — %d surface parts",
    chunk.cx, chunk.cz, partCount
  ))
end

-- ────────────────────────────────────────────────────────────────────────────
-- Render queue — processes one chunk at a time so simultaneous arrivals
-- don't all start hammering Instance.new on the same frame
-- ────────────────────────────────────────────────────────────────────────────

local function _processQueue()
  if _queueRunning then return end
  _queueRunning = true

  task.spawn(function()
    while #_renderQueue > 0 do
      local chunk = table.remove(_renderQueue, 1)
      _renderChunkAsync(chunk)   -- yields internally across frames
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
  local folder = _renderedChunks[key]

  -- Mark as false immediately so any in-progress render pass aborts
  _renderedChunks[key] = false

  -- Remove from the render queue if it hasn't been built yet
  for i = #_renderQueue, 1, -1 do
    local c = _renderQueue[i]
    if c.cx == cx and c.cz == cz then
      table.remove(_renderQueue, i)
    end
  end

  if folder and typeof(folder) == "Instance" then
    -- Unparent instantly — chunk vanishes from view and physics on this frame.
    -- Destroy children in small batches spread across frames to avoid a lag spike.
    folder.Parent = nil
    local logCx, logCz = cx, cz
    task.spawn(function()
      local children = folder:GetChildren()
      for i, child in ipairs(children) do
        child:Destroy()
        if i % UNLOAD_BATCH_SIZE == 0 then
          task.wait()
        end
      end
      folder:Destroy()
      if _renderedChunks[key] == false then
        _renderedChunks[key] = nil
      end
      print(string.format("[ChunkRenderer] Unloaded chunk (%d,%d)", logCx, logCz))
    end)
  else
    _renderedChunks[key] = nil
  end
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
  print("[ChunkRenderer] Initialising…")

  _activeChunksFolder = Workspace
    :WaitForChild("World")
    :WaitForChild("ActiveChunks")

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