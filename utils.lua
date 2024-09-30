--TODO: utiliser assert() à la place de if then... error()

local utils = {}

local optionsEnv ---@type ___OptionsEnv

---@return ___Mod
function utils.getMod(info)
  if not info then
    info = debug.getinfo(2, "S")
  end

  local source = info.source

  ---@type ___Mod
  return {
    name = source:match("@?.+\\Mods\\([^\\]+)"),
    file = source:sub(2),
    currentDirectory = source:match("@?(.+)\\"),
    modsDirectory = source:match("@?(.+\\Mods)\\")
  }
end

---@param str string
---@param separator string
---@return table
function utils.stringToTable(str, separator)
  local tbl = {}
  local i = 1
  local matches = string.gmatch(str, "[^" .. separator .. "]+")

  for s in matches do
    tbl[s] = i
    i = i + 1
  end

  return tbl
end

---@return table
function utils.getEnabledModsList()
  local enabledMods = {}

  for line in io.lines(utils.mod.modsDirectory .. "\\mods.txt") do
    line = string.gsub(line, ";.*", "")
    line = string.gsub(line, "%s", "")
    if line ~= "" then
      local modName, enabled = string.match(line, "([^:]+):(%d)")
      print(modName, enabled)

      if enabled == "1" then
        enabledMods[modName] = true
      else
        enabledMods[modName] = false
      end
    end
  end

  local fileList = utils.getFileList(utils.mod.modsDirectory, "enabled.txt")

  for _, v in ipairs(fileList) do
    local modName = string.match(v, "Mods\\([^\\]+)\\enabled%.txt")
    if modName ~= nil then
      enabledMods[modName] = true
    end
  end

  return enabledMods
end

---@return ___Mod
function utils.init()
  local info = debug.getinfo(2, "S")
  utils.mod = utils.getMod(info)

  if ___CONFIG == nil then
    ---@type ___CONFIG
    ___CONFIG = {
      verbose = 0,
      mods_options_file = "options.lua"
    }
  end

  -- load script configuration (for dev or advanced users)
  local config = utils.mod.currentDirectory .. "\\config.lua"
  if utils.isFileExists(config) then
    print("Load and merge config file to ___CONFIG global variable. File: " .. utils.getRelPathToModsDir(config))

    utils.mergeConfig(___CONFIG, config)
  end

  return utils.mod
end

---@param path string
function utils.getRelPathToModsDir(path)
  return path:gsub("@?.+\\Mods\\", "")
end

function utils.patch(object, options)
  for k, v in pairs(options) do
    object[k] = v

    local isEqual

    if type(object[k]) == "number" or type(v) == "number" then
      isEqual = utils.isAlmostEqual(object[k], v)
    else
      isEqual = object[k] ~= v
    end

    if not isEqual then
      local msg = string.format("Unable to edit variable value: `%s.%s`.\n", object:GetFName():ToString(), k)
      msg = msg .. string.format("Actual: %s\n", object[k])
      msg = msg .. string.format("Expected: %s\n", v)
      msg = msg .. string.format("Object full name: %s\n", object:GetFullName())
      msg = msg .. utils.getTraceback()

      utils.error(msg)
    end
  end
end

function utils.isAlmostEqual(number1, number2, margin)
  if margin == nil then
    margin = 0.01
  end

  return math.abs(number1 - number2) <= margin
end

function utils.round(number)
  local power = 10 ^ 2
  return math.floor(number * power) / power
end

---@param number number
---@return function
local function mult(number)
  ---@param property number
  ---@return number
  return function(property)
    return property * number
  end
end

---Create metatable
---@param key string
---@return table
local function createMetatable(key)
  return setmetatable({}, {
    __newindex = function(t, subkey, value)
      if type(value) == "function" then
        value = value(optionsEnv.objects[key][subkey])
      end
      rawset(t, subkey, value)
    end
  })
end

---@return ___OptionsEnv
local function createOptionsEnv()
  ---@type ___OptionsEnv
  return {
    options = {},
    createMetatable = createMetatable,
    objects = {},
    mult = mult
  }
end

---Load user options.
---@return function
---@return ___OptionsEnv
function utils.loadOptions()
  local file = os.getenv("mods_options_file")

  if file == nil or type(file) ~= "string" or file == "" then
    file = ModRef:GetSharedVariable("mods_options_file")
  end

  if file == nil or type(file) ~= "string" or file == "" then
    file = ___CONFIG.mods_options_file
  end

  local path = string.format("%s\\%s\\%s", utils.mod.modsDirectory, utils.mod.name, file)
  utils.printf("Load options file: " .. utils.getRelPathToModsDir(path))

  optionsEnv = createOptionsEnv()
  local f, err = loadfile(path, "t", optionsEnv)
  if f == nil or err then
    error(err)
  end

  return f, optionsEnv
end

---@param configTable ___CONFIG
---@param configFile string
---@return ___CONFIG
function utils.mergeConfig(configTable, configFile)
  if type(configTable) ~= "table" then
    error(string.format("The variable 'configTable' is not a table. Type is: %s", type(configTable)))
  end

  local config = dofile(configFile)

  if config == nil or type(config) ~= "table" then
    print(string.format(
      "WARN: The config file will not be loaded. Returned value type: %s. File: %s",
      type(config), configFile))

    return configTable
  end

  for k, v in pairs(config) do
    configTable[k] = v
  end

  return configTable
end

function utils.getFileList(directory, filter)
  local fileList = {}

  for fileName in io.popen(string.format('dir "%s" /B /D /S', directory)):lines() do
    if fileName:match(filter) then
      table.insert(fileList, fileName)
    end
  end

  return fileList
end

function utils.isFileExists(filename)
  local file = io.open(filename, "r")
  if file ~= nil then
    io.close(file)
    return true
  else
    return false
  end
end

function utils.printTable(table)
  local str = "{\n"

  for k, v in pairs(table) do
    str = string.format("%s%s: %s\n", str, k, v)
  end

  str = str .. "}\n"

  print(str)
end

function utils.__LINE__()
  return debug.getinfo(2, 'l').currentline
end

function utils.__NAME__()
  return debug.getinfo(2, "n").name
end

function utils.print(msg)
  print("[" .. utils.mod.name .. "] " .. msg .. "\n")
end

function utils.printf(...)
  print("[" .. utils.mod.name .. "] " .. string.format(...) .. "\n")
end

function utils.getTraceback(msg)
  return debug.traceback(msg, 2)
end

function utils.warn(msg)
  print("[" .. utils.mod.name .. "] WARN: " .. msg .. "\n")
end

function utils.error(msg)
  print("[" .. utils.mod.name .. "] ERROR: " .. msg .. "\n")
end

function utils.dbg(msg)
  local info = debug.getinfo(2, "lnS")
  local file = info.source:gsub(".+\\Mods\\", "")
  local line = string.format("%s %s() %d", file, info.name, info.currentline)

  if msg ~= nil then
    line = line .. ": " .. msg
  end

  print(line)
end

utils.mod = {
  currentDirectory = "",
  file = "",
  modsDirectory = "",
  name = ""
}

return utils
