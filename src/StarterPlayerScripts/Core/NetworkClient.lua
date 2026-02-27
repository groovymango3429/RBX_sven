--[[
  NetworkClient  [MODULE SCRIPT]
  =============
  Listen to RemoteEvents and send requests to the server.

  Usage:
    NetworkClient.sendToServer("EventName", payload)
    NetworkClient.onEvent("EventName", function(payload) ... end)

  RemoteEvents are expected to live under ReplicatedStorage/Remotes/<Category>/<Name>
  or directly under ReplicatedStorage/Remotes/<Name>.  sendToServer performs a
  depth-first search so callers don't need to know the folder structure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local NetworkClient = {}

-- Internal map: eventName -> RBXScriptConnection[]
local _handlers = {}

-- Recursive helper: find the first RemoteEvent/RemoteFunction with matching name.
local function findRemote(folder, name)
  for _, child in ipairs(folder:GetChildren()) do
    if child.Name == name and
       (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
      return child
    end
    if child:IsA("Folder") then
      local found = findRemote(child, name)
      if found then return found end
    end
  end
  return nil
end

--- sendToServer: Fire a named RemoteEvent to the server with an optional payload.
function NetworkClient.sendToServer(eventName, payload)
  assert(type(eventName) == "string", "NetworkClient.sendToServer: eventName must be a string")
  local remote = findRemote(Remotes, eventName)
  if remote and remote:IsA("RemoteEvent") then
    remote:FireServer(payload)
  else
    warn("[NetworkClient] sendToServer: RemoteEvent not found: " .. eventName)
  end
end

--- onEvent: Register a handler for an incoming RemoteEvent from the server.
function NetworkClient.onEvent(eventName, callback)
  assert(type(eventName) == "string", "NetworkClient.onEvent: eventName must be a string")
  assert(type(callback) == "function", "NetworkClient.onEvent: callback must be a function")

  local remote = findRemote(Remotes, eventName)
  if not remote then
    warn("[NetworkClient] onEvent: RemoteEvent not found: " .. eventName)
    return
  end
  if not remote:IsA("RemoteEvent") then
    warn("[NetworkClient] onEvent: " .. eventName .. " is not a RemoteEvent")
    return
  end

  if not _handlers[eventName] then
    _handlers[eventName] = {}
  end
  local conn = remote.OnClientEvent:Connect(callback)
  table.insert(_handlers[eventName], conn)
  return conn
end


return NetworkClient
