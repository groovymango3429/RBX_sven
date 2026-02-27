--[[
  Signal  [MODULE SCRIPT]
  ======
  Re-export wrapper over Packages/SignalPlus.
  Use this module everywhere — never require Packages directly.
  See architecture doc §0 for re-export explanation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

-- SignalPlus returns a constructor function directly.
local newSignal = require(Packages:WaitForChild("SignalPlus"))

local Signal = {}

--- new: Create a new Signal instance
function Signal.new()
  return newSignal()
end

return Signal
