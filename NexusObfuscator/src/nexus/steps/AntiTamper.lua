-- Nexus Obfuscator - AntiTamper Step
-- CUSTOM: Arithmetic hash-chain check, not Prometheus string-equality check.

local Step   = require("nexus.step")
local Parser = require("nexus.parser")
local Enums  = require("nexus.enums")

local AntiTamper = Step:extend()
AntiTamper.Name               = "Anti Tamper"
AntiTamper.Description        = "Breaks script if tampered via arithmetic hash chain."
AntiTamper.SettingsDescriptor = {
    UseDebug = { type="boolean", default=false },
}

function AntiTamper:init() end

local function genChain()
    local n    = math.random(4, 9)
    local vals = {}
    for i=1,n do vals[i]=math.random(1,2^20) end
    local ops  = {}
    for i=2,n do ops[i]=math.random(1,3) end

    local v = vals[1]
    for i=2,n do
        if     ops[i]==1 then v=v+vals[i]
        elseif ops[i]==2 then v=v*vals[i]
        else                   v=v-vals[i] end
    end
    local expected = math.floor(v) % (2^30)

    local parts = { "do", string.format("  local _v = %d", vals[1]) }
    for i=2,n do
        if     ops[i]==1 then parts[#parts+1]=string.format("  _v = _v + %d", vals[i])
        elseif ops[i]==2 then parts[#parts+1]=string.format("  _v = _v * %d", vals[i])
        else                   parts[#parts+1]=string.format("  _v = _v - %d", vals[i]) end
    end
    parts[#parts+1] = string.format("  _v = _v %% %d", 2^30)
    parts[#parts+1] = string.format("  if _v ~= %d then while true do end end", expected)
    parts[#parts+1] = "end"
    return table.concat(parts, "\n")
end

function AntiTamper:apply(ast, _)
    local code   = genChain()
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    local doStat = newAst.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)
    table.insert(ast.body.statements, 1, doStat)
    return ast
end

return AntiTamper
