--[[
  GameManager  [SERVER SCRIPT]
  ============================
  Master server orchestrator.
  Boots all services in dependency order across 14 phases.
  This is the ONLY top-level Script — all logic lives in Managers/*.
]]

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players            = game:GetService("Players")

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Managers = ServerScriptService:WaitForChild("Managers")

local function load(parent, name)
  local m = parent:FindFirstChild(name)
  assert(m, "[GameManager] Missing module: " .. tostring(name))
  return require(m)
end

local function boot()
  print("[GameManager] === DeadLand Boot Sequence ===")

  local Logger          = load(Shared.Core, "Logger")
  local ServiceLocator  = load(Shared.Core, "ServiceLocator")

  local services = {
    PlayerManager      = load(Managers, "PlayerManager"),
    PersistenceManager = load(Managers, "PersistenceManager"),
    WorldManager       = load(Managers, "WorldManager"),
    EntityManager      = load(Managers, "EntityManager"),
    SpawnManager       = load(Managers, "SpawnManager"),
    CombatManager      = load(Managers, "CombatManager"),
    InventoryManager   = load(Managers, "InventoryManager"),
    CraftingManager    = load(Managers, "CraftingManager"),
    QuestManager       = load(Managers, "QuestManager"),
    EconomyManager     = load(Managers, "EconomyManager"),
    EnvironmentManager = load(Managers, "EnvironmentManager"),
    FarmingManager     = load(Managers, "FarmingManager"),
    VehicleManager     = load(Managers, "VehicleManager"),
    ElectricityManager = load(Managers, "ElectricityManager"),
    HordeManager       = load(Managers, "HordeManager"),
    HeatMapManager     = load(Managers, "HeatMapManager"),
    LootManager        = load(Managers, "LootManager"),
    AntiCheatManager   = load(Managers, "AntiCheatManager"),
  }

  for name, svc in pairs(services) do
    ServiceLocator.register(name, svc)
    Logger.log("INFO", "Registered: " .. name)
  end

  Players.PlayerAdded:Connect(function(p)
    services.PlayerManager.onPlayerAdded(p)
  end)
  Players.PlayerRemoving:Connect(function(p)
    services.PlayerManager.onPlayerRemoving(p)
  end)
  for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(services.PlayerManager.onPlayerAdded, p)
  end

  Logger.log("INFO", "[GameManager] Server READY ✓")
end

local ok, err = pcall(boot)
if not ok then
  warn("[GameManager] BOOT FAILED: " .. tostring(err))
end
