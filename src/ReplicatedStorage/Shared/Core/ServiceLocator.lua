--[[
  ServiceLocator  [MODULE SCRIPT]
  ==============
  Central service registry — register and retrieve any manager.
]]

local ServiceLocator = {}

local _services = {}

--- register: Register a service by name
function ServiceLocator.register(name, service)
  assert(type(name) == "string", "ServiceLocator.register: name must be a string")
  assert(service ~= nil, "ServiceLocator.register: service must not be nil")
  _services[name] = service
end

--- get: Retrieve a service by name (errors if not found)
function ServiceLocator.get(name)
  local svc = _services[name]
  assert(svc ~= nil, "ServiceLocator.get: service not found: " .. tostring(name))
  return svc
end


return ServiceLocator
