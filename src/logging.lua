---@class _Logging
local logging = {} ---@diagnostic disable-line: missing-fields

-- bind to a local variable https://stackoverflow.com/a/1252776
local print = print
local error = error
local type = type
local fmt = string.format
local sub = string.sub
local concat = table.concat

---@enum (key) _LogLevel
local LOG_LEVELS = {
	ALL = 0,
	TRACE = 1,
	DEBUG = 2,
	INFO = 3,
	WARN = 4,
	ERROR = 5,
	FATAL = 6,
	OFF = 7,
}

local indexedLevels = {}

for k, v in pairs(LOG_LEVELS) do
	indexedLevels[v] = k
end

local maxLevel = #indexedLevels

---@param v any
---@return string
local function safeToString(v)
	local str = fmt("type=%s", type(v))

	if type(v) == "userdata" then
		return str .. tostring(v)
	elseif type(v) == "table" then
		return str .. "[" .. #v .. "]"
	elseif type(v) == "function" then
		return str
	elseif type(v) == "nil" then
		return str
	else
		return str .. " value=" .. tostring(v)
	end
end

---@param value any
---@param ... any
---@return string
local function getLogMessage(value, ...)
	local msg = value

	if type(value) == "string" then
		if select("#", ...) > 0 then
			msg = fmt(value, ...)
		end
	elseif type(value) == "function" then
		msg = value(...)
	else
		msg = tostring(value)
	end

	local lastChar = sub(msg, -1)
	if lastChar ~= "\r" and lastChar ~= "\n" then
		msg = msg .. "\n"
	end

	return msg
end

---@param level _LogLevel
---@param levelForFatalError _LogLevel
---@return Mod_Logger
function logging.new(level, levelForFatalError)
	local logger = {} ---@type Mod_Logger
	local source = debug.getinfo(2, "S").source:gsub("\\", "/")

	-- previous values
	local prevLevel ---@type _LogLevel?
	local prevLevelForFatalError ---@type _LogLevel?

	-- State flag for tracing function calls.
	local isFunctionCallLoggingEnabled = false

	---@type Mod_ModInfo
	local mod = {
		name = source:match("@?.+/Mods/([^/]+)"),
		file = source:sub(2),
		currentDirectory = source:match("@?(.+)/"),
		currentModDirectory = source:match("@?(.+/Mods/[^/]+)"),
		modsDirectory = source:match("@?(.+/Mods)/"),
	}

	---Enables or disables automatic function call logging.
	---@param isEnabled boolean True to enable call tracing, false to disable.
	function logger.setFunctionCallLogging(isEnabled)
		isFunctionCallLoggingEnabled = isEnabled
	end

	---@param newlevel? _LogLevel
	---@param newlevelForFatalError? _LogLevel
	function logger.setLevel(newlevel, newlevelForFatalError)
		local verb = "Set"
		if newlevel == nil and newlevelForFatalError == nil then
			verb = "Reset"
		end

		newlevel = newlevel or level
		newlevelForFatalError = newlevelForFatalError or levelForFatalError

		-- get the number of the level from the string level format
		local numLevel = LOG_LEVELS[newlevel]
		local numMinlevelFatal = LOG_LEVELS[newlevelForFatalError]

		assert(
			numLevel <= numMinlevelFatal,
			string.format(
				"The log level must be less than or equal to the minimum log level "
					.. "for a fatal error (numLevel=%i numMinlevelFatal=%i).",
				numLevel,
				numMinlevelFatal
			)
		)

		-- if the level has not been changed, do nothing
		if newlevel == prevLevel and newlevelForFatalError == prevLevelForFatalError then
			if numLevel <= LOG_LEVELS.DEBUG then
				print(
					string.format(
						"The log level values are the same. The level remains %s-%s.\n",
						newlevel,
						newlevelForFatalError
					)
				)
			end

			return
		end

		-- print "Set" or "Reset" log level...
		print(
			string.format(
				"[%s] %s log level %s-%s (previous: %s-%s).\n",
				mod.name,
				verb,
				newlevel,
				newlevelForFatalError,
				prevLevel,
				prevLevelForFatalError
			)
		)

		-- create functions for each level
		for i = 1, maxLevel do
			local levelName = indexedLevels[i]
			local funcName = levelName:lower()

			-- default print function
			local printfunc = print

			if i >= numLevel and i < maxLevel then
				if i >= numMinlevelFatal then
					-- specific print function for fatal errors
					printfunc = error
				end

				logger[funcName] = function(value, ...)
					local info = debug.getinfo(2, "nSl")
					local src = info.source:gsub("\\", "/")
					local dbgMsg = fmt("[%s] %s ", mod.name, levelName)
						.. src:gsub(".+/", "")
						.. ":"
						.. (info.name or "*")
						.. ":"
						.. info.currentline
						.. " "

					printfunc(dbgMsg .. getLogMessage(value, ...))
				end
			else
				-- no logging case
				logger[funcName] = function() end
			end
		end

		prevLevel = newlevel
		prevLevelForFatalError = newlevelForFatalError
	end

	---Wraps all functions in a table to log their execution with logging.
	---Execution tracing requires LOG_LEVEL to be set to TRACE or higher.
	---@param tbl table Table containing the functions to wrap.
	---@param logLevelToDisplay? string The log level to display in the trace message (e.g., "TRACE", "DEBUG", "INFO"). Defaults to "TRACE".
	---@return table #The same table with all its functions wrapped for tracing.
	function logger.wrapFunctionsWithCallLogging(tbl, logLevelToDisplay)
		if not isFunctionCallLoggingEnabled then
			return tbl
		end

		logLevelToDisplay = logLevelToDisplay or "TRACE"

		for name, func in pairs(tbl) do
			if type(func) == "function" then
				tbl[name] = function(...)
					local args = { ... }
					local argsStr = {}
					for i, v in ipairs(args) do
						argsStr[i] = safeToString(v)
					end

					local argsString = ""
					if next(argsStr) then
						argsString = concat(argsStr, ", ")
					end

					local funcInfo = debug.getinfo(func, "S")
					local src = funcInfo.source:gsub("\\", "/"):gsub(".+/", "")
					local dbgMsg = fmt("[%s] %s ", mod.name, logLevelToDisplay)
						.. src
						.. ":"
						.. name
						.. ":"
						.. funcInfo.linedefined
						.. fmt(" args=(%s)", argsString)

					print(dbgMsg .. "\n")

					return func(...)
				end
			end
		end

		return tbl
	end

	logger.setLevel(level, levelForFatalError)

	return logger ---@type Mod_Logger
end

return logging ---@type _Logging
