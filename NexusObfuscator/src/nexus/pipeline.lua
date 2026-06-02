-- Nexus Obfuscator - Pipeline
local Enums          = require("nexus.enums")
local util           = require("nexus.util")
local Parser         = require("nexus.parser")
local Unparser       = require("nexus.unparser")
local Logger         = require("logger")
local NameGenerators = require("nexus.namegenerators")
local Steps          = require("nexus.steps")
local LuaVersion     = Enums.LuaVersion

local isWindows = package and package.config and package.config:sub(1,1) == "\\"
local function gettime() return isWindows and os.clock() or os.time() end

local Pipeline = {
    NameGenerators   = NameGenerators,
    Steps            = Steps,
    DefaultSettings  = {
        LuaVersion    = LuaVersion.LuaU,
        PrettyPrint   = false,
        Seed          = 0,
        VarNamePrefix = "",
    }
}

function Pipeline:new(settings)
    local lv   = settings.LuaVersion or Pipeline.DefaultSettings.LuaVersion
    local conv = Enums.Conventions[lv]
    if not conv then Logger:error("Unknown LuaVersion: "..tostring(lv)) end
    local p = {
        LuaVersion    = lv,
        PrettyPrint   = settings.PrettyPrint  or false,
        VarNamePrefix = settings.VarNamePrefix or "",
        Seed          = settings.Seed          or 0,
        parser        = Parser:new({ LuaVersion = lv }),
        unparser      = Unparser:new({ LuaVersion = lv, PrettyPrint = settings.PrettyPrint or false }),
        namegenerator = NameGenerators.Zap,
        conventions   = conv,
        steps         = {},
    }
    setmetatable(p, self); self.__index = self
    return p
end

function Pipeline:fromConfig(config)
    config = config or {}
    local p = Pipeline:new({
        LuaVersion    = config.LuaVersion    or LuaVersion.Lua51,
        PrettyPrint   = config.PrettyPrint   or false,
        VarNamePrefix = config.VarNamePrefix or "",
        Seed          = config.Seed          or 0,
    })
    p:setNameGenerator(config.NameGenerator or "Zap")
    for _, step in ipairs(config.Steps or {}) do
        if type(step.Name) ~= "string" then Logger:error("Step.Name must be a string") end
        local ctor = p.Steps[step.Name]
        if not ctor then Logger:error("Step not found: "..step.Name) end
        p:addStep(ctor:new(step.Settings or {}))
    end
    return p
end

function Pipeline:addStep(step)   table.insert(self.steps, step) end
function Pipeline:resetSteps()    self.steps = {} end
function Pipeline:getSteps()      return self.steps end

function Pipeline:setNameGenerator(ng)
    if type(ng) == "string" then ng = Pipeline.NameGenerators[ng] end
    if type(ng) == "function" or type(ng) == "table" then
        self.namegenerator = ng
    else
        Logger:error("Invalid NameGenerator")
    end
end

function Pipeline:apply(code, filename)
    local t0 = gettime()
    filename = filename or "script"
    Logger:info("Obfuscating "..filename.." ...")
    if self.Seed and self.Seed > 0 then
        math.randomseed(self.Seed)
    else
        local ok, seed = pcall(function()
            local h = io.popen("openssl rand -hex 8")
            if not h then error("no openssl") end
            local s = h:read("*a"):gsub("\n",""); h:close()
            local n = 0
            for c in s:gmatch(".") do
                c = c:lower()
                local d = c:match("%d") and (c:byte()-48) or (c:byte()-87)
                n = n*16+d
            end
            return n
        end)
        math.randomseed(ok and seed or os.time())
    end
    local srcLen = #code
    Logger:info("Parsing ...")
    local ast = self.parser:parse(code)
    for _, step in ipairs(self.steps) do
        Logger:info("Step: "..(step.Name or "?"))
        local r = step:apply(ast, self)
        if type(r) == "table" then ast = r end
    end
    self:renameVariables(ast)
    local result = self.unparser:unparse(ast)
    Logger:info(string.format("Done %.2fs | size %.1f%%", gettime()-t0, (#result/srcLen)*100))
    return result
end

function Pipeline:renameVariables(ast)
    local gen = self.namegenerator
    if not self.unparser:isValidIdentifier(self.VarNamePrefix) and #self.VarNamePrefix ~= 0 then
        Logger:error("Invalid VarNamePrefix: "..self.VarNamePrefix)
    end
    if type(gen) == "table" then
        if type(gen.prepare) == "function" then gen.prepare(ast) end
        gen = gen.generateName
    end
    ast.globalScope:renameVariables({
        Keywords     = self.conventions.Keywords,
        generateName = gen,
        prefix       = self.VarNamePrefix,
    })
end

function Pipeline:unparse(ast) return self.unparser:unparse(ast) end

return Pipeline
