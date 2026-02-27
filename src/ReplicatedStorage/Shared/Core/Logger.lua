--[[
  Logger [MODULE SCRIPT]
  =========
  Structured logging with DEBUG / INFO / WARN / ERROR levels.
  Includes timestamps and color-coded output.
]]

local Logger = {}

-- Configuration: current log level threshold
-- Only messages >= current level will be printed
Logger.Levels = {
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
}

Logger.CurrentLevel = Logger.Levels.DEBUG -- change to INFO to filter DEBUG messages

-- Helper: get timestamp
local function timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

-- Generic log function
function Logger.Log(levelName, message)
	local levelValue = Logger.Levels[levelName]
	if not levelValue then
		error("Invalid log level: "..tostring(levelName))
	end

	if levelValue < Logger.CurrentLevel then
		return -- ignore messages below current level
	end

	local output = string.format("[%s] [%s] %s", timestamp(), levelName, message)

	if levelName == "WARN" then
		warn(output) -- yellow in Roblox output
	elseif levelName == "ERROR" then
		error(output, 2) -- red, optionally throws
	else
		print(output) -- DEBUG / INFO
	end
end

-- Convenience methods
function Logger.Debug(msg)
	Logger.Log("DEBUG", msg)
end

function Logger.Info(msg)
	Logger.Log("INFO", msg)
end

function Logger.Warn(msg)
	Logger.Log("WARN", msg)
end

function Logger.Error(msg)
	Logger.Log("ERROR", msg)
end

return Logger