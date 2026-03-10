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
local WorldConstants = require(WorldFolder:WaitForChild("WorldConstants"))
local WorldGenConfig = require(WorldFolder:WaitForChild("WorldGenConfig"))
local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))
local GameConfig = require(CoreFolder:WaitForChild("GameConfig"))

local WorldScripts = ServerScriptService:WaitForChild("World")
local ChunkService = require(WorldScripts:WaitForChild("ChunkService"))

local BLOCK_SIZE = ChunkConstants.BLOCK_SIZE
local MAP_CONFIG = WorldGenConfig.Map
local _spawnUnlocked = {}
local _readyRemoteConnected = false

local function ensureWorldReadyRemote()
  if _readyRemoteConnected then
    return
  end

  local Remotes = ReplicatedStorage:WaitForChild("Remotes")
  local WorldRem = Remotes:WaitForChild("World")
  local readyRemote = WorldRem:WaitForChild("MapReadyForSpawn", 10)
  assert(readyRemote, "[PlayerManager] MapReadyForSpawn RemoteEvent not found in Remotes/World")

  readyRemote.OnServerEvent:Connect(function(player)
    if _spawnUnlocked[player] ~= false then
      return
    end

    _spawnUnlocked[player] = true

    if player.Parent and not player.Character then
      player:LoadCharacter()
    end
  end)

  _readyRemoteConnected = true
end


--- onPlayerAdded: Load profile, create Replica, spawn character
function PlayerManager.onPlayerAdded(player)
  ensureWorldReadyRemote()
  _spawnUnlocked[player] = false

  print("[PlayerManager] Player added: " .. tostring(player and player.Name))

  player.CharacterAdded:Connect(function(character)
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not hrp or not humanoid then
      warn("[PlayerManager] Missing HRP or Humanoid for: " .. tostring(player.Name))
      return
    end

    -- Wait one frame for the character to fully initialize before moving it
    task.wait()

    -- Spawn at block origin (0, 0) — change these to set a different spawn column
    local spawnBlockX = MAP_CONFIG.SpawnBlockX
    local spawnBlockZ = MAP_CONFIG.SpawnBlockZ
    local cx = math.floor(spawnBlockX / ChunkConstants.CHUNK_SIZE)
    local cz = math.floor(spawnBlockZ / ChunkConstants.CHUNK_SIZE)
    local localX = spawnBlockX - cx * ChunkConstants.CHUNK_SIZE
    local localZ = spawnBlockZ - cz * ChunkConstants.CHUNK_SIZE

    -- Request the chunk server-side (generates if missing)
    local chunk = ChunkService.requestChunk(cx, cz, nil)

    local surfaceBlockY = WorldConstants.SURFACE_Y_DEFAULT or 64

    -- Find the highest non-air block in the spawn column
    if chunk then
      for y = ChunkConstants.CHUNK_HEIGHT - 1, 0, -1 do
        local id = chunk:getBlock(localX, y, localZ)
        if id ~= 0 then
          surfaceBlockY = y
          break
        end
      end
    else
      warn("[PlayerManager] Chunk not available at cx=" .. cx .. " cz=" .. cz .. ", using default surface Y.")
    end

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
        if player.Parent and _spawnUnlocked[player] then
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
  print("[PlayerManager] Player removing: " .. tostring(player and player.Name))
end


return PlayerManager
