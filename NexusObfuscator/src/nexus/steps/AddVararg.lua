-- Nexus Obfuscator - AddVararg Step
local Step     = require("nexus.step")
local Ast      = require("nexus.ast")
local visitast = require("nexus.visitast")
local AstKind  = Ast.AstKind

local AddVararg = Step:extend()
AddVararg.Name               = "Add Vararg"
AddVararg.Description        = "Adds vararg to all functions."
AddVararg.SettingsDescriptor = {}

function AddVararg:init() end

function AddVararg:apply(ast,_)
    visitast(ast, nil, function(node,_)
        local k = node.kind
        if k==AstKind.FunctionLiteralExpression
        or k==AstKind.FunctionDeclaration
        or k==AstKind.LocalFunctionDeclaration then
            local args = node.args or {}
            local hasV = false
            for _,a in ipairs(args) do if a.kind==AstKind.VarargExpression then hasV=true;break end end
            if not hasV then table.insert(node.args, Ast.VarargExpression()) end
        end
    end)
    return ast
end

return AddVararg
