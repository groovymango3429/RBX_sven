--[[
  Logger [MODULE SCRIPT]
  =========
  Structured logging with DEBUG / INFO / WARN / ERROR levels.
  Includes timestamps and color-coded output.
  Matches GameManager style (log(), warn(), error()).
]]

local Logger = {}

-- Configuration: current log level threshold
-- Only messages >= current level will be printed
Logger.Levels = {
	debug = 1,
	info  = 2,
	warn  = 3,
	error = 4,
}

Logger.CurrentLevel = Logger.Levels.debug -- change to info to filter debug messages

-- Helper: get timestamp
local function timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

-- Generic log function
function Logger.log(levelName, message)
	levelName = string.lower(levelName)
	local levelValue = Logger.Levels[levelName]
	if not levelValue then
		error("[Logger] Invalid log level: "..tostring(levelName))
	end

	if levelValue < Logger.CurrentLevel then
		return -- ignore messages below current level
	end

	local output = string.format("[%s] [%s] %s", timestamp(), string.upper(levelName), message)

	if levelName == "warn" then
		warn(output) -- yellow
	elseif levelName == "error" then
		error(output, 2) -- red, throws
	else
		print(output) -- debug/info
	end
end

-- Convenience shortcuts
function Logger.Debug(msg) return Logger.log("debug", msg) end
function Logger.Info(msg)  return Logger.log("info", msg) end
function Logger.Warn(msg)  return Logger.log("warn", msg) end
function Logger.Error(msg) return Logger.log("error", msg) end

return Logger