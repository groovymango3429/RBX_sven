--[[
  CharacterSetup  [LOCAL SCRIPT]
  ==============================
  Runs inside each character model when the player spawns or respawns.
  Sets up humanoid properties, hitbox tags, and proximity prompts.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")

-- Load character modules
local CharMods   = script.Parent:WaitForChild("Character")
local AnimController  = require(CharMods:WaitForChild("AnimationController"))
local MovementCtrl    = require(CharMods:WaitForChild("MovementController"))
local InteractRay     = require(CharMods:WaitForChild("InteractionRaycaster"))
local EquippedHandler = require(CharMods:WaitForChild("EquippedItemHandler"))
local FootstepSys     = require(CharMods:WaitForChild("FootstepSystem"))

-- Configure humanoid
humanoid.BreakJointsOnDeath    = false
humanoid.RequiresNeck           = false
humanoid.AutoRotate             = false
humanoid.WalkSpeed              = 16
humanoid.JumpPower              = 50

print("[CharacterSetup] Character configured for " .. player.Name)
