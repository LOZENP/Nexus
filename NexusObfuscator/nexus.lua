-- Nexus Obfuscator - Entry Point
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end
local base = script_path()
local oldPkgPath = package.path
package.path = base .. "src/?.lua;" .. base .. "src/?/init.lua;" .. package.path

if not pcall(function() return math.random(1, 2^40) end) then
    local _rnd = math.random
    math.random = function(a, b)
        if not a and not b then return _rnd() end
        if not b then return math.random(1, a) end
        if a > b then a, b = b, a end
        local diff = b - a
        if diff > 2^31 - 1 then return math.floor(_rnd() * diff + a)
        else return _rnd(a, b) end
    end
end

_G.newproxy = _G.newproxy or function(arg)
    if arg then return setmetatable({}, {}) end
    return {}
end

local Pipeline = require("nexus.pipeline")
local Presets  = require("nexus.presets")
local Logger   = require("logger")
package.path   = oldPkgPath
return { Pipeline = Pipeline, Presets = Presets, Logger = Logger }
