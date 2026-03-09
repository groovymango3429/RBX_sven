--[[
  ClientMain  [LOCAL SCRIPT]
  ==========================
  Master client orchestrator.
  Boots all client-side services in order.
  Runs once on every player's machine when they join.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core   = script.Parent:WaitForChild("Core")
local UI     = script.Parent:WaitForChild("UI")

local function load(parent, name)
  local m = parent:FindFirstChild(name)
  assert(m, "[ClientMain] Missing module: " .. tostring(name))
  return require(m)
end

local function boot()
  print("[ClientMain] === DeadLand Client Boot ===")

  -- Core
  local ClientServiceLocator = load(Core, "ClientServiceLocator")
  local NetworkClient        = load(Core, "NetworkClient")
  local ReplicaClient        = load(Core, "ReplicaClient")
  local InputHandler         = load(Core, "InputHandler")
  local CameraController     = load(Core, "CameraController")
  local ClientState          = load(Core, "ClientState")

  -- World rendering
  local WorldClient  = script.Parent:WaitForChild("WorldClient")
  local ChunkRenderer    = load(WorldClient, "ChunkRenderer")
  local WeatherRenderer  = load(WorldClient, "WeatherRenderer")
  local DayNightRenderer = load(WorldClient, "DayNightRenderer")
  local MapLoader        = load(WorldClient, "MapLoader")

  -- Initialise ChunkRenderer so it begins listening for SendChunk events.
  -- WHERE: ClientMain.client.lua → ChunkRenderer.init()
  --   This connects OnClientEvent for the SendChunk remote so terrain
  --   appears as soon as the server fires chunks at this client.
  ChunkRenderer.init()

  -- MapLoader wires a ScreenGui button to server-side map generation.
  -- Call MapLoader.setup(config) from a separate LocalScript (or here) and
  -- pass in references to your button, loading frame, and loading bar.
  -- See MapLoader.lua for full documentation and usage examples.
  -- Example:
  --   local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
  --   local myGui     = playerGui:WaitForChild("MapScreenGui")
  --   MapLoader.setup({
  --     button       = myGui:WaitForChild("GenerateButton"),
  --     loadingFrame = myGui:WaitForChild("LoadingFrame"),
  --     loadingBar   = myGui:WaitForChild("LoadingFrame"):WaitForChild("BarFill"),
  --   })

  -- Combat
  local CombatClient = script.Parent:WaitForChild("CombatClient")
  local WeaponClient  = load(CombatClient, "WeaponClient")
  local ScreenEffects = load(CombatClient, "ScreenEffects")
  local BloodVFX      = load(CombatClient, "BloodVFX")
  local ExplosionVFX  = load(CombatClient, "ExplosionVFX")
  local DamageNumbers = load(UI, "DamageNumbers")

  -- Audio
  local Audio = script.Parent:WaitForChild("Audio")
  local AudioClient      = load(Audio, "AudioClient")
  local MusicController  = load(Audio, "MusicController")
  local AmbientSoundscape = load(Audio, "AmbientSoundscape")

  -- UI
  local UIManager         = load(UI, "UIManager")
  local HUDController     = load(UI, "HUDController")
  local NotificationSystem = load(UI, "NotificationSystem")

  -- Register in locator
  ClientServiceLocator.register("NetworkClient",       NetworkClient)
  ClientServiceLocator.register("ReplicaClient",       ReplicaClient)
  ClientServiceLocator.register("InputHandler",        InputHandler)
  ClientServiceLocator.register("CameraController",    CameraController)
  ClientServiceLocator.register("ClientState",         ClientState)
  ClientServiceLocator.register("UIManager",           UIManager)
  ClientServiceLocator.register("HUDController",       HUDController)
  ClientServiceLocator.register("ChunkRenderer",       ChunkRenderer)
  ClientServiceLocator.register("MapLoader",           MapLoader)
  ClientServiceLocator.register("WeaponClient",        WeaponClient)
  ClientServiceLocator.register("AudioClient",         AudioClient)
  ClientServiceLocator.register("MusicController",     MusicController)

  -- Signal server ready
  NetworkClient.sendToServer("ClientReady", {})

  print("[ClientMain] Client boot complete ✓")
end

local ok, err = pcall(boot)
if not ok then
  warn("[ClientMain] BOOT FAILED: " .. tostring(err))
end
