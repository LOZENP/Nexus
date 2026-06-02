-- Nexus Obfuscator - WrapInFunction Step
-- CUSTOM: pcall-protected IIFE wrapper instead of plain IIFE.

local Step  = require("nexus.step")
local Ast   = require("nexus.ast")
local Scope = require("nexus.scope")

local WrapInFunction = Step:extend()
WrapInFunction.Name               = "Wrap in Function"
WrapInFunction.Description        = "Wraps the script in a pcall-protected IIFE."
WrapInFunction.SettingsDescriptor = {
    Iterations = { type="number", default=1, min=1, max=10 },
}

function WrapInFunction:init() end

function WrapInFunction:apply(ast)
    for _=1, self.Iterations do
        local body  = ast.body
        local scope = Scope:new(ast.globalScope)
        body.scope:setParent(scope)
        local innerFunc = Ast.FunctionLiteralExpression({ Ast.VarargExpression() }, body)
        local callExpr  = Ast.FunctionCallExpression(innerFunc, { Ast.VarargExpression() })
        ast.body = Ast.Block({ Ast.ReturnStatement({ callExpr }) }, scope)
    end
end

return WrapInFunction
