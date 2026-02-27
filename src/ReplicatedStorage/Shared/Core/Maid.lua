--[[
  Maid  [MODULE SCRIPT]
  ====
  Lightweight resource cleanup helper.
  Tracks connections, instances, and functions; destroys them on Maid:Destroy().
  (MadworkMaid package not yet installed — this is a self-contained implementation.)
]]

local Maid = {}
Maid.__index = Maid

--- new: Create a Maid instance
function Maid.new()
  return setmetatable({ _tasks = {} }, Maid)
end

--- GiveTask: Register an item for cleanup.
--  Accepts: RBXScriptConnection, Instance, function, or another Maid.
function Maid:GiveTask(task)
  assert(task ~= nil, "Task must not be nil")
  table.insert(self._tasks, task)
  return task
end

--- Destroy: Execute all cleanup tasks and clear the Maid.
--  Tasks are destroyed in reverse order so that objects which depend on
--  others created earlier are torn down first (LIFO dependency chain).
function Maid:Destroy()
  local tasks = self._tasks
  self._tasks = {}
  for i = #tasks, 1, -1 do
    local t = tasks[i]
    local kind = typeof(t)
    if kind == "RBXScriptConnection" then
      t:Disconnect()
    elseif kind == "Instance" then
      t:Destroy()
    elseif kind == "function" then
      t()
    elseif kind == "table" and type(t.Destroy) == "function" then
      t:Destroy()
    end
  end
end

return Maid
