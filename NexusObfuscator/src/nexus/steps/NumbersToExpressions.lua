-- Nexus Obfuscator - NumbersToExpressions Step
-- CUSTOM: 6 generators including modulo chains and multiply-add.

local Step     = require("nexus.step")
local Ast      = require("nexus.ast")
local visitast = require("nexus.visitast")
local AstKind  = Ast.AstKind

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Name               = "Numbers To Expressions"
NumbersToExpressions.Description        = "Converts number literals to arithmetic expressions."
NumbersToExpressions.SettingsDescriptor = {
    Threshold         = { type="number", default=1,    min=0, max=1   },
    InternalThreshold = { type="number", default=0.15, min=0, max=0.8 },
}

local MAX_DEPTH = 3

function NumbersToExpressions:init() end

function NumbersToExpressions:Leaf(val, depth)
    if depth >= MAX_DEPTH or math.random() > self.InternalThreshold then
        return Ast.NumberExpression(val)
    end
    return self:Gen(val, depth+1)
end

function NumbersToExpressions:Gen(val, depth)
    depth = depth or 0
    if depth >= MAX_DEPTH then return Ast.NumberExpression(val) end
    local pick = math.random(1,6)
    if pick==1 then
        local b=math.random(-2^20,2^20); local a=val-b
        if tonumber(tostring(a))+tonumber(tostring(b))==val then
            return Ast.AddExpression(self:Leaf(a,depth),self:Leaf(b,depth)) end
    elseif pick==2 then
        local b=math.random(-2^20,2^20); local a=val+b
        if tonumber(tostring(a))-tonumber(tostring(b))==val then
            return Ast.SubExpression(self:Leaf(a,depth),self:Leaf(b,depth)) end
    elseif pick==3 then
        if val~=0 and math.abs(val)<2^24 then
            local facs={}
            for n=2,math.min(math.abs(val),50) do if val%n==0 then facs[#facs+1]=n end end
            if #facs>0 then
                local b=facs[math.random(#facs)]; local a=val/b
                return Ast.MulExpression(self:Leaf(a,depth),self:Leaf(b,depth))
            end
        end
    elseif pick==4 then
        local rhs=math.abs(val)+math.random(1,2^14)
        if rhs>0 then
            local k=math.random(1,8); local lhs=val+k*rhs
            if lhs%rhs==val then
                return Ast.ModExpression(self:Leaf(lhs,depth),self:Leaf(rhs,depth)) end
        end
    elseif pick==5 then
        if val~=0 then return Ast.NegateExpression(self:Leaf(-val,depth)) end
    elseif pick==6 then
        local n=math.random(-500,500); local a=val-n
        if tonumber(tostring(a))+tonumber(tostring(n))==val then
            return Ast.AddExpression(self:Leaf(a,depth),self:Leaf(n,depth)) end
    end
    return Ast.NumberExpression(val)
end

function NumbersToExpressions:apply(ast,_)
    visitast(ast, nil, function(node,_)
        if node.kind==AstKind.NumberExpression and math.random()<=self.Threshold then
            local v=node.value
            if type(v)=="number" and v==math.floor(v) and math.abs(v)<2^24 then
                return self:Gen(v,0)
            end
        end
    end)
    return ast
end

return NumbersToExpressions
