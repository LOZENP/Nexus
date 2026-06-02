-- Nexus Obfuscator - Vmify Step
local Step     = require("nexus.step")
local Compiler = require("nexus.compiler.compiler")

local Vmify = Step:extend()
Vmify.Name               = "Vmify"
Vmify.Description        = "Compiles script into custom bytecode VM."
Vmify.SettingsDescriptor = {}

function Vmify:init() end

function Vmify:apply(ast)
    return Compiler:new():compile(ast)
end

return Vmify
