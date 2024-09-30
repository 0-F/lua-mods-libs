---@meta

---@class ___Mod
---@field name string
---@field file string
---@field currentDirectory string
---@field modsDirectory string

---@class ___CONFIG
---@field verbose number
---@field mods_options_file string
___CONFIG = {}

---@class ___OptionsEnv
---@field objects table
---@field options table
---@field createMetatable function
---@field mult function

objects = {}
options = {}

---Create metatable.
---@param key string
---@return table
function createMetatable(key) end

---Multiply.
---@param number number
---@return number
function mult(number) end
