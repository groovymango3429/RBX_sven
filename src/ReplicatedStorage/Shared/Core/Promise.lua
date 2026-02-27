--[[
  Promise  [MODULE SCRIPT]
  =======
  Re-export wrapper over Packages/Promise (evaera/roblox-lua-promise).
  Use this module everywhere — never require Packages directly.
  See architecture doc §0 for re-export explanation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Promise = require(Packages:WaitForChild("Promise"))

return Promise
