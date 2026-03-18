--[[
    Module to use in the options file.
]]

_G.lldebugger = nil
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    _G.lldebugger = require("lldebugger")
end

---@alias pre_post_function fun(instance: UObject, property: string, value: any, item: Mod_Options_Item): any

local string, table, type, pairs = string, table, type, pairs

local logging = require("lua-mods-libs.logging")
local utils = require("lua-mods-libs.utils")
local UEHelpers = require("UEHelpers")

__CONFIG = utils.loadConfig()

local WARN = "(!) "
local log = __LOGGER
local Items, Loaders, Instances, Filters, Pre, Post = {}, {}, {}, {}, {}, {}

---@class Mod_Options_Module
local M = {
    items = Items,
    loaders = Loaders,
    instances = Instances,
    filters = Filters,
    pre = Pre,
    post = Post,
}

-- expose some libraries and the logger
M.logging = logging
M.log = log
M.utils = utils
M.UEHelpers = UEHelpers

--#region cache
local cache = {
    FindFirstOf = {},
    FindAllOf = {},
    StaticFindObject = {}
}
do
    local function createMetatable(customFunction)
        return {
            __mode = "kv",
            __index = function(t, k)
                local v = customFunction(k)
                rawset(t, k, v) -- cache value
                return v
            end,
            __call = function(t, arg)
                return t[arg]
            end
        }
    end

    setmetatable(cache.FindFirstOf, createMetatable(FindFirstOf))
    setmetatable(cache.FindAllOf, createMetatable(FindAllOf))
    setmetatable(cache.StaticFindObject, createMetatable(StaticFindObject))
end
---@class Mod_Options_Cache
---@field FindFirstOf fun(shortClassName: string): UObject Find the first non-default instance of the supplied class name.
---@field FindAllOf fun(shortClassName: string): UObject[]? Find all non-default instances of the supplied class name.
---@field StaticFindObject fun(objectName: string): UObject

---@cast cache Mod_Options_Cache
--#endregion

---Returns the first valid PlayerController that is currently controlled by a player.
---@return APlayerController?
function M.getPlayerController()
    local playerControllers = cache.FindAllOf("PlayerController") or cache.FindAllOf("Controller")
    if not playerControllers then
        return
    end

    for _, controller in pairs(playerControllers or {}) do
        ---@cast controller APlayerController
        if controller.Pawn:IsValid() and controller.Pawn:IsPlayerControlled() then
            return controller
        end
    end
end

--#region loaders

-- Call the injected function if PlayerController exists or on PlayerController:ClientRestart.
-- The function is called only once.
function Loaders._ifPCExists_or_onPCRestart()
    ---@param injectedFunc function
    return function(injectedFunc)
        if M.getPlayerController() then
            injectedFunc()
            return
        end

        local preId, postId
        preId, postId = RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
            UnregisterHook("/Script/Engine.PlayerController:ClientRestart", preId, postId)
            ExecuteWithDelay(2000, function()
                injectedFunc()
            end)
        end)
    end
end

--#endregion

--#region instances

---Get all instances of an item in the options file. See: FindAllOf().
---@return fun(item: Mod_Options_Item): UObject[]
function Instances.getAllInstances()
    return function(item)
        assert(item.className ~= "" and item.shortClassName ~= "",
            [[The "className" and "shortClassName" fields are required for getAllInstances. ]] ..
            string.format("Item ID in the options file: %q.", item.id))

        local baseInstances = cache.FindAllOf(item.shortClassName)
        if not baseInstances then
            log.debug(WARN .. "No instances of %q found.", item.shortClassName)
            return {}
        end

        local instances = {}

        for i, instance in ipairs(baseInstances) do
            log.trace("getAllInstances() Instance found (%i/%i): %q.", i, #baseInstances, instance:GetFullName())

            -- check that the the instance inherits from className
            if instance:IsA(item.className) then
                log.trace("Add instance of %q.", item.className)

                table.insert(instances, instance)
            else
                log.trace("The instance will not be added.")
            end
        end

        return instances
    end
end

---Get an instance of an item in the options file. See: StaticFindObject().
---@return fun(item: Mod_Options_Item): UObject[]
function Instances.getStaticObject()
    return function(item)
        assert(item.className ~= "", [[The "className" field is required for getStaticObject. ]] ..
            string.format("Item ID in the options file: %q.", item.id))

        local instance = cache.StaticFindObject(item.className)

        return { instance }
    end
end

--#endregion

--#region filters

---@param chunk string
---@param chunkname? string
---@return fun(instance: UObject, item: Mod_Options_Item): boolean
function Filters.load(chunk, chunkname)
    return function(instance, item)
        local f, err = load("local instance, item = ...; return " .. chunk, chunkname)
        if f then
            return f(instance, item)
        else
            error(err)
        end
    end
end

---Return true whether the instance inherits from the class.
---@param className string
---@return fun(instance: UObject, item: Mod_Options_Item): boolean
function Filters.isA(className, customInstance)
    return function(instance, item) ---@diagnostic disable-line: unused-local
        if type(customInstance) == "function" then
            instance = customInstance(instance)
        end

        if instance:IsA(className) then
            log.trace("Instance inherits from class %q.", className)

            return true
        else
            log.trace("Instance does not inherit from %q.", className)

            return false
        end
    end
end

---Return true whether the instance does not inherit from the class.
---@param className string
---@param customInstance? function
---@return fun(instance: UObject, item: Mod_Options_Item): boolean
function Filters.isNotA(className, customInstance)
    return function(instance, item) ---@diagnostic disable-line: unused-local
        if type(customInstance) == "function" then
            instance = customInstance(instance)
        end
        return not Filters.isA(className)(instance, item)
    end
end

--#endregion

--#region pre

---Check if the property is valid.
---@return pre_post_function
function Pre.checkPropertyValidity()
    return function(instance, property, value, item) ---@diagnostic disable-line: unused-local
        if value == nil then
            log.trace(WARN .. "Property name: %q. The value is nil. Skip value check.", property)

            return nil
        end

        local prop = instance[property]

        log.trace("Property name: %q type: %q.", property, type(prop))

        if type(prop) == "userdata" then
            ---@cast prop UObject
            if not prop:IsValid() then
                log.warn("The property %q is not a valid UObject.", property)

                return false
            end
        end

        return true
    end
end

--#endregion

--#region post

---Check if the property value change was successful.
---@param epsilon number
---@return pre_post_function
function Post.checkPropertyValueChange(epsilon)
    return function(instance, property, value, item) ---@diagnostic disable-line: unused-local
        -- In some cases, the value may be nil.
        -- For example, the IMPORT_TEXT function changes the game value and returns nil.
        if value == nil then
            log.debug(WARN .. "Value is nil. The value will not be checked. Property name: %q. Item ID: %q.",
                property, item.id)
            return nil
        end

        local dataType = type(instance[property])
        local isEqual = false

        if dataType == "number" or dataType == "string" or dataType == "boolean" then
            isEqual = utils.checkEquality(instance[property], value, epsilon)
        end

        if not isEqual then
            local msg = string.format(
                "Unable to modify the property as expected: %s -> %s.\n",
                instance:GetFName():ToString(), property)
            msg = msg .. string.format("Item ID: %s\n", item.id)
            msg = msg .. string.format("Actual: %s. Expected: %s\n", instance[property], value)
            msg = msg .. string.format("UObject full name: %s\n", instance:GetFullName())

            log.warn(msg)

            return false
        end

        return true
    end
end

--#endregion

--#region functions for properties

--Add (+).
---@param number number|function
---@return number
function M.ADD(number)
    ---@param instance UObject
    ---@param property string
    ---@return number
    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        if type(number) == "function" then
            number = number()
        end
        return instance[property] + number
    end
end

--Subtract (-).
---@param number number|function
---@return number
function M.SUB(number)
    ---@param instance UObject
    ---@param property string
    ---@return number
    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        if type(number) == "function" then
            number = number()
        end
        return instance[property] - number
    end
end

---Multiply (*).
---@param number number|function
---@return number
function M.MULT(number)
    ---@param instance UObject
    ---@param property string
    ---@return number
    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        if type(number) == "function" then
            number = number()
        end
        return instance[property] * number
    end
end

---Divide (/).
---@param number number|function
---@return number
function M.DIV(number)
    ---@param instance UObject
    ---@param property string
    ---@return number
    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        if type(number) == "function" then
            number = number()
        end
        return instance[property] / number
    end
end

---Floor divide (//).
---@param number number|function
---@return number
function M.FDIV(number)
    ---@param instance UObject
    ---@param property string
    ---@return number
    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        if type(number) == "function" then
            number = number()
        end
        return instance[property] // number
    end
end

--This function calls [ImportText](lua://Property.ImportText).
--It can be used to modify the property type "MapProperty".
---@param text string
---@return any
function M.IMPORT_TEXT(text)
    ---@param instance UObject
    ---@param property string
    ---@return nil
    return function(instance, property)
        local propertyObj = instance:Reflection():GetProperty(property)
        assert(propertyObj:IsValid())

        log.trace([[-> ImportText "%s" = "%s".]], property, text)

        ---@diagnostic disable-next-line: param-type-mismatch
        propertyObj:ImportText(text, propertyObj:ContainerPtrToValuePtr(instance, 0), 0, instance)

        return nil
    end
end

---Loads a chunk.
---@param chunk string
---@return any
function M.LOAD(chunk, chunkname)
    return function(instance, property)
        local f, err = load("local instance, property = ...;" .. chunk, chunkname)
        if f then
            return f(instance, property)
        else
            error(err)
        end
    end
end

function M.CALL(func, ...)
    local args = table.pack(...)

    return function()
        return func(table.unpack(args))
    end
end

---@param ... any
---@return any
function M.CALL_EACH(...)
    local list = table.pack(...)

    return function(instance, property) ---@diagnostic disable-line: return-type-mismatch
        local value = instance[property]
        local fakeInstance = {}

        fakeInstance[property] = value

        for _, func in ipairs(list) do
            value = func(fakeInstance, property)
            fakeInstance[property] = value
        end

        return value
    end
end

--#endregion

---@param self Mod_Options_Item[]
---@param item Mod_Options_Item
---@param ... table
function Items.insert(self, item, ...)
    local list = table.pack(...)

    -- add item parameters to the list
    for k, v in pairs(item) do
        list[k] = v
    end

    table.insert(self, list)
end

return M
