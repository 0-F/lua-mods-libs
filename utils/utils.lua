---@class Mod
---@field name string
---@field file string
---@field currentDirectory string
---@field modsDirectory string
Mod = {}

local utils = {}

---@return Mod
function utils.init()
  ---@class Mod
  local mod = {
    name = debug.getinfo(2, "S").source:match("@?.+\\Mods\\([^\\]+)"),
    file = debug.getinfo(2, 'S').source:sub(2),
    currentDirectory = debug.getinfo(2, "S").source:match("@?(.+)\\"),
    modsDirectory = debug.getinfo(2, "S").source:match("@?(.+\\Mods)\\")
  }

  return mod
end

function utils.patch(object, options)
  for k, v in pairs(options) do
    if options[k] ~= nil then
      object[k] = v
      if object[k] ~= v then
        utils.error(string.format(
          "Unable to set property: '%s' to '%s'.\nObject full name: %s", k,
          object:GetFName():ToString(), object:GetFullName()))
      end
    end
  end
end

function utils.round(number)
  local power = 10 ^ 2
  return math.floor(number * power) / power
end

function utils.loadOptions()
  local file = os.getenv("MODS_OPTIONS_FILE") or MODS_OPTIONS_FILE

  if file == nil then
    file = "options.lua"
  end

  local path = string.format("%s\\%s\\%s", Mod.modsDirectory, Mod.name, file)
  utils.printf("Load options file: " .. path)
  dofile(path)
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
  print("[" .. Mod.name .. "] " .. msg .. "\n")
end

function utils.printf(...)
  print("[" .. Mod.name .. "] " .. string.format(...) .. "\n")
end

function utils.error(msg, level)
  error("[" .. Mod.name .. "] " .. msg .. "\n", level)
end

function utils.getTraceback(msg)
  return debug.traceback(msg, 2)
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

return utils
