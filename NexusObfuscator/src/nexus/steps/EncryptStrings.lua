-- Nexus Obfuscator - EncryptStrings Step
-- CUSTOM: Rolling XOR cipher with two keys. Completely different from Prometheus LCG.

local Step     = require("nexus.step")
local Ast      = require("nexus.ast")
local Parser   = require("nexus.parser")
local Enums    = require("nexus.enums")
local visitast = require("nexus.visitast")
local util     = require("nexus.util")
local AstKind  = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Name               = "Encrypt Strings"
EncryptStrings.Description        = "Encrypts strings with a rolling XOR cipher."
EncryptStrings.SettingsDescriptor = {}

function EncryptStrings:init() end

function EncryptStrings:CreateService()
    local keyA    = math.random(1, 255)
    local keyB    = math.random(2, 254)
    local usedSeeds = {}

    local function genSeed()
        local s
        repeat s = math.random(1, 0x7FFFFFFF) until not usedSeeds[s]
        usedSeeds[s] = true
        return s
    end

    local function encrypt(str)
        local seed = genSeed()
        local out  = {}
        local roll = seed % 256
        for i = 1, #str do
            local b   = str:byte(i)
            local enc = ((b ~ keyA) ~ roll) % 256
            out[i]    = string.char(enc)
            roll      = (roll * keyB + i) % 256
        end
        return table.concat(out), seed
    end

    local function genRuntime()
        local locals = util.shuffle({
            "local _xk = " .. keyA,
            "local _rb = " .. keyB,
            "local _sc = string.char",
            "local _sb = string.byte",
            "local _sl = string.len",
            "local _tc = table.concat",
            "local _ch = {}",
        })
        local code = "do\n\t" .. table.concat(locals, "\n\t") .. "\n"
        code = code .. [[
    NX_DECRYPT = function(s, seed)
        if _ch[seed] then return _ch[seed] end
        local roll = seed % 256
        local out  = {}
        for i = 1, _sl(s) do
            local b   = _sb(s, i)
            local dec = ((b ~ roll) ~ _xk) % 256
            out[i]    = _sc(dec)
            roll      = (roll * _rb + i) % 256
        end
        local r   = _tc(out)
        _ch[seed] = r
        return r
    end
end]]
        return code
    end

    return { encrypt = encrypt, genRuntime = genRuntime }
end

function EncryptStrings:apply(ast, _)
    local svc  = self:CreateService()
    local code = svc.genRuntime()

    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    local doStat = newAst.body.statements[1]

    local scope      = ast.body.scope
    local decryptVar = scope:addVariable()
    local cacheVar   = scope:addVariable()

    doStat.body.scope:setParent(ast.body.scope)

    visitast(newAst, nil, function(node, data)
        local kind = node.kind
        if kind == AstKind.FunctionDeclaration or kind == AstKind.AssignmentVariable then
            if node.scope:getVariableName(node.id) == "NX_DECRYPT" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                data.scope:addReferenceToHigherScope(scope, decryptVar)
                node.scope = scope
                node.id    = decryptVar
            end
        end
    end)

    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.StringExpression then
            local enc, seed = svc.encrypt(node.value)
            data.scope:addReferenceToHigherScope(scope, decryptVar)
            return Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decryptVar),
                { Ast.StringExpression(enc), Ast.NumberExpression(seed) }
            )
        end
    end)

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(scope, { decryptVar, cacheVar }, {})
    )
    return ast
end

return EncryptStrings
