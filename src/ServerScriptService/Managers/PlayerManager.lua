--[[
  PlayerManager  [MODULE SCRIPT]
  =============
  Player join/leave, ProfileStore load, ReplicaService creation
]]

local PlayerManager = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")
local CoreFolder = Shared:WaitForChild("Core")
local BlockRegistry = require(WorldFolder:WaitForChild("BlockRegistry"))
local WorldConstants = require(WorldFolder:WaitForChild("WorldConstants"))
local WorldGenConfig = require(WorldFolder:WaitForChild("WorldGenConfig"))
local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))
local GameConfig = require(CoreFolder:WaitForChild("GameConfig"))

local WorldScripts = ServerScriptService:WaitForChild("World")
local ChunkService = require(WorldScripts:WaitForChild("ChunkService"))

local BLOCK_SIZE = ChunkConstants.BLOCK_SIZE
local mapConfig = WorldGenConfig.Map
local SEA_LEVEL = WorldConstants.SEA_LEVEL
local MAX_SPAWN_ATTEMPTS = 48
local RECENT_SPAWN_LIMIT = 8
local HEIGHT_BUCKET_SIZE = 12
local _spawnUnlocked = {}
local _loadingCharacter = {}
local _recentSpawnBuckets = {}
local _spawnRollCounter = 0

local function ensureWorldReadyRemote()
  local Remotes = ReplicatedStorage:WaitForChild("Remotes")
  local WorldRem = Remotes:WaitForChild("World")
  local readyRemote = WorldRem:WaitForChild("MapReadyForSpawn", 10)
  assert(readyRemote, "[PlayerManager] MapReadyForSpawn RemoteEvent not found in Remotes/World")

  readyRemote.OnServerEvent:Connect(function(player)
    local unlockState = _spawnUnlocked[player]
    if unlockState == nil then
      warn("[PlayerManager] Ignoring MapReadyForSpawn for untracked player: " .. tostring(player and player.Name))
      return
    end
    if unlockState == true then
      return
    end

    _spawnUnlocked[player] = true

    if player.Parent and not player.Character and not _loadingCharacter[player] then
      _loadingCharacter[player] = true
      player:LoadCharacter()
    end
  end)
end

ensureWorldReadyRemote()

local function getChunkCoords(blockX, blockZ)
  local chunkSize = ChunkConstants.CHUNK_SIZE
  local cx = math.floor(blockX / chunkSize)
  local cz = math.floor(blockZ / chunkSize)
  local localX = blockX - cx * chunkSize
  local localZ = blockZ - cz * chunkSize
  return cx, cz, localX, localZ
end

local function findSafeSurface(chunk, localX, localZ)
  for y = ChunkConstants.CHUNK_HEIGHT - 3, 1, -1 do
    local surfaceId = chunk:getBlock(localX, y, localZ)
    local surfaceDef = BlockRegistry.getById(surfaceId)
    if surfaceDef
      and surfaceId ~= 0
      and surfaceDef.solid
      and not surfaceDef.transparent
      and not surfaceDef.liquid
      and y > SEA_LEVEL
    then
      local headId = chunk:getBlock(localX, y + 1, localZ)
      local upperHeadId = chunk:getBlock(localX, y + 2, localZ)
      if headId == 0 and upperHeadId == 0 then
        return y, surfaceId
      end
    end
  end
end

local function pushRecentSpawnBucket(bucketKey)
  if not bucketKey then
    return
  end

  table.insert(_recentSpawnBuckets, bucketKey)
  while #_recentSpawnBuckets > RECENT_SPAWN_LIMIT do
    table.remove(_recentSpawnBuckets, 1)
  end
end

local function getRecentSpawnPenalty(bucketKey)
  for i = #_recentSpawnBuckets, 1, -1 do
    if _recentSpawnBuckets[i] == bucketKey then
      return (#_recentSpawnBuckets - i + 1) * 0.35
    end
  end

  return 0
end

local function roundToBlock(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end

  return math.ceil(value - 0.5)
end

local function buildSpawnCandidate(rng, attempt)
  local maxRadius = math.max(mapConfig.SpawnSafeRadius, ChunkConstants.CHUNK_SIZE)
  local minRadius = math.min(math.max(ChunkConstants.CHUNK_SIZE, math.floor(maxRadius * 0.18)), maxRadius)
  local angle = rng:NextNumber(0, math.pi * 2)
  local radialBlend = math.max(rng:NextNumber(), attempt / MAX_SPAWN_ATTEMPTS)
  local radius = minRadius + (maxRadius - minRadius) * radialBlend
  local blockX = mapConfig.SpawnBlockX + roundToBlock(math.cos(angle) * radius)
  local blockZ = mapConfig.SpawnBlockZ + roundToBlock(math.sin(angle) * radius)
  return blockX, blockZ, radius, maxRadius
end

local function selectSpawnColumn(player)
  _spawnRollCounter += 1
  local seed = player.UserId * 131 + os.time() + _spawnRollCounter * 7919
  local rng = Random.new(seed)
  local bestCandidate = nil

  for attempt = 1, MAX_SPAWN_ATTEMPTS do
    local blockX, blockZ, radius, maxRadius = buildSpawnCandidate(rng, attempt)
    local cx, cz, localX, localZ = getChunkCoords(blockX, blockZ)
    local chunk = ChunkService.requestChunk(cx, cz, nil)

    if chunk then
      local surfaceBlockY, surfaceId = findSafeSurface(chunk, localX, localZ)
      if surfaceBlockY then
        local heightBucket = math.floor(surfaceBlockY / HEIGHT_BUCKET_SIZE)
        local bucketKey = tostring(surfaceId) .. ":" .. tostring(heightBucket)
        local score = (radius / maxRadius)
          + math.min((surfaceBlockY - SEA_LEVEL) / 32, 1) * 0.35
          - getRecentSpawnPenalty(bucketKey)

        if surfaceId ~= BlockRegistry.getId("grass") then
          score += 0.1
        end

        local candidate = {
          blockX = blockX,
          blockZ = blockZ,
          surfaceBlockY = surfaceBlockY,
          bucketKey = bucketKey,
          score = score,
        }

        if not bestCandidate or candidate.score > bestCandidate.score then
          bestCandidate = candidate
        end
      end
    end
  end

  if bestCandidate then
    pushRecentSpawnBucket(bestCandidate.bucketKey)
    return bestCandidate
  end

  local fallbackCX, fallbackCZ, fallbackLocalX, fallbackLocalZ = getChunkCoords(mapConfig.SpawnBlockX, mapConfig.SpawnBlockZ)
  local fallbackChunk = ChunkService.requestChunk(fallbackCX, fallbackCZ, nil)
  local surfaceBlockY = WorldConstants.SURFACE_Y_DEFAULT or 64
  if fallbackChunk then
    surfaceBlockY = findSafeSurface(fallbackChunk, fallbackLocalX, fallbackLocalZ) or surfaceBlockY
  end

  return {
    blockX = mapConfig.SpawnBlockX,
    blockZ = mapConfig.SpawnBlockZ,
    surfaceBlockY = surfaceBlockY,
  }
end


--- onPlayerAdded: Load profile, create Replica, spawn character
function PlayerManager.onPlayerAdded(player)
  _spawnUnlocked[player] = false
  _loadingCharacter[player] = false

  print("[PlayerManager] Player added: " .. tostring(player and player.Name))

  player.CharacterAdded:Connect(function(character)
    _loadingCharacter[player] = false

    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not hrp or not humanoid then
      warn("[PlayerManager] Missing HRP or Humanoid for: " .. tostring(player.Name))
      return
    end

    -- Wait one frame for the character to fully initialize before moving it
    task.wait()

    local spawnColumn = selectSpawnColumn(player)
    local spawnBlockX = spawnColumn.blockX
    local spawnBlockZ = spawnColumn.blockZ
    local surfaceBlockY = spawnColumn.surfaceBlockY

    -- Convert block coords to world studs
    -- A block at index y occupies world Y range: [y * BLOCK_SIZE, (y+1) * BLOCK_SIZE]
    -- So the top face of the surface block is at (surfaceBlockY + 1) * BLOCK_SIZE
    local spawnX = spawnBlockX * BLOCK_SIZE + BLOCK_SIZE / 2
    local spawnZ = spawnBlockZ * BLOCK_SIZE + BLOCK_SIZE / 2
    local topSurfaceY = (surfaceBlockY + 1) * BLOCK_SIZE

    -- HipHeight is the distance from the HRP center down to the character's feet,
    -- so placing the HRP at topSurfaceY + HipHeight puts feet exactly on the surface
    local hrpY = topSurfaceY + humanoid.HipHeight

    if not character.PrimaryPart then
      character.PrimaryPart = hrp
    end

    -- Set position once cleanly and zero out any existing velocity
    hrp.CFrame = CFrame.new(spawnX, hrpY, spawnZ)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    humanoid.Died:Connect(function()
      task.delay(GameConfig.getValue("RespawnTime"), function()
        if player.Parent and _spawnUnlocked[player] and not _loadingCharacter[player] then
          _loadingCharacter[player] = true
          player:LoadCharacter()
        end
      end)
    end)

    print(string.format(
      "[PlayerManager] Spawned %s at world (%.1f, %.1f, %.1f) | surfaceBlockY=%d",
      player.Name, spawnX, hrpY, spawnZ, surfaceBlockY
    ))
  end)
end


--- onPlayerRemoving: Save profile, clean up Replica and Maid
function PlayerManager.onPlayerRemoving(player)
  -- TODO: implement profile save, Replica/Maid cleanup
  _spawnUnlocked[player] = nil
  _loadingCharacter[player] = nil
  print("[PlayerManager] Player removing: " .. tostring(player and player.Name))
end


return PlayerManager
