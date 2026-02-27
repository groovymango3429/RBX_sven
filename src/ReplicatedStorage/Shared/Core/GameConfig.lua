--[[
  GameConfig  [MODULE SCRIPT]
  ==========
  Global constants: version, tick rate, world seed, max players.
  Replace placeholder values with real ones before shipping.
]]

local GameConfig = {}

local _config = {
  Version        = "0.1.0",
  MaxPlayers     = 50,
  TickRate       = 20,          -- Physics/game-loop ticks per second
  WorldSeed      = 42,          -- Procedural generation seed
  SaveInterval   = 60,          -- Auto-save interval in seconds
  RespawnTime    = 10,          -- Seconds before a player can respawn
  DayLength      = 1200,        -- Real seconds per in-game day
  StartTime      = 14,          -- Default clock time on server start
  ZombieLimit    = 200,         -- Max active zombie entities
  ChunkSize      = 256,         -- Studs per world chunk
  StreamRadius   = 512,         -- Client streaming radius in studs
}

--- get: Return the full config table (frozen — read-only)
function GameConfig.get()
  return table.freeze(_config)
end

--- getValue: Return a single config value by key
function GameConfig.getValue(key)
  assert(_config[key] ~= nil, "GameConfig.getValue: unknown key: " .. tostring(key))
  return _config[key]
end


return GameConfig
