--[[
  PlayerManager  [MODULE SCRIPT]
  =============
  Player join/leave, ProfileStore load, ReplicaService creation
]]

local PlayerManager = {}


--- onPlayerAdded: Load profile, create Replica, spawn character
function PlayerManager.onPlayerAdded(player)
  -- TODO: implement profile load, Replica creation, character spawn
  print("[PlayerManager] Player added: " .. tostring(player and player.Name))
end

--- onPlayerRemoving: Save profile, clean up Replica and Maid
function PlayerManager.onPlayerRemoving(player)
  -- TODO: implement profile save, Replica/Maid cleanup
  print("[PlayerManager] Player removing: " .. tostring(player and player.Name))
end


return PlayerManager
