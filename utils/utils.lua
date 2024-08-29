local utils = {}

function utils.round(number)
  local power = 10 ^ 2
  return math.floor(number * power) / power
end

function utils.loadOptions(modName)
  local file = os.getenv("MODS_OPTIONS_FILE")

  if modName == nil then
    modName = utils.getModName()
  end

  if file == nil then
    file = "options.lua"
  end

  utils.printf("Load options file: %s\\%s", modName, file)
  dofile(string.format("%s\\%s\\%s", utils.getModsDirectory(), modName, file))
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

function utils.getModsDirectory()
  return debug.getinfo(2, "S").source:match("@?(.+\\Mods)\\")
end

function utils.getModName()
  return debug.getinfo(2, "S").source:match("@?.+\\Mods\\([^\\]+)")
end

function utils.getCurrentDirectory()
  return debug.getinfo(2, "S").source:match("@?(.+)\\")
end

function utils.__FILE__()
  return debug.getinfo(2, 'S').source
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
  print("[" .. utils.getModName() .. "] " .. msg .. "\n")
end

function utils.printf(...)
  print("[" .. utils.getModName() .. "] " .. string.format(...) .. "\n")
end

function utils.err(msg)
  print(debug.traceback(msg, 2))
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
