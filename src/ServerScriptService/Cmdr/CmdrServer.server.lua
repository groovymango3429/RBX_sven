--[[
  CmdrServer  [SERVER SCRIPT]
  ===========================
  Bootstraps the Cmdr admin framework on the server.
  Registers all custom commands from the Commands/ folder.
  See: https://github.com/evaera/Cmdr
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cmdr = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Cmdr"))

Cmdr:RegisterDefaultCommands()

-- Register every command module in Commands/
local commandsFolder = ServerScriptService:WaitForChild("Cmdr"):WaitForChild("Commands")
Cmdr:RegisterCommandsIn(commandsFolder)

print("[CmdrServer] Cmdr loaded — " .. #commandsFolder:GetChildren() .. " commands registered")
