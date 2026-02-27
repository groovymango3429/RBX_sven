--[[
  ClientServiceLocator  [MODULE SCRIPT]
  ====================
  Client-side service registry (mirrors server ServiceLocator).
]]

local ClientServiceLocator = {}

local _services = {}

--- register: Register a client service by name
function ClientServiceLocator.register(name, service)
  assert(type(name) == "string", "ClientServiceLocator.register: name must be a string")
  assert(service ~= nil, "ClientServiceLocator.register: service must not be nil")
  _services[name] = service
end

--- get: Retrieve a client service by name (errors if not found)
function ClientServiceLocator.get(name)
  local svc = _services[name]
  assert(svc ~= nil, "ClientServiceLocator.get: service not found: " .. tostring(name))
  return svc
end


return ClientServiceLocator
