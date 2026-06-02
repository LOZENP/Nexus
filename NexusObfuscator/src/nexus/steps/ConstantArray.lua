-- Nexus Obfuscator - ConstantArray Step
-- CUSTOM: Uses base32-hex encoding + different rotation logic.

local Step     = require("nexus.step")
local Ast      = require("nexus.ast")
local Scope    = require("nexus.scope")
local visitast = require("nexus.visitast")
local util     = require("nexus.util")
local Parser   = require("nexus.parser")
local enums    = require("nexus.enums")
local AstKind  = Ast.AstKind
local LuaVersion = enums.LuaVersion

local ConstantArray = Step:extend()
ConstantArray.Name        = "Constant Array"
ConstantArray.Description = "Extracts constants into a shuffled rotated array with base32 encoding."

ConstantArray.SettingsDescriptor = {
    Threshold             = { type="number",  default=1,     min=0, max=1 },
    StringsOnly           = { type="boolean", default=false },
    Shuffle               = { type="boolean", default=true  },
    Rotate                = { type="boolean", default=true  },
    LocalWrapperThreshold = { type="number",  default=1,     min=0, max=1 },
    LocalWrapperCount     = { type="number",  default=0,     min=0, max=512 },
    LocalWrapperArgCount  = { type="number",  default=10,    min=1, max=200 },
    MaxWrapperOffset      = { type="number",  default=65535, min=0 },
}

local B32_BASE = "0123456789ABCDEFGHIJKLMNOPQRSTUV"

local function initAlphabet()
    local chars = util.chararray(B32_BASE)
    util.shuffle(chars)
    return table.concat(chars)
end

local function encodeB32(str, alpha)
    local r = {}
    local i = 1
    while i <= #str do
        local b = {str:byte(i, i+4)}
        for k=1,5 do b[k]=b[k] or 0 end
        r[#r+1] = alpha:sub((b[1]>>3)+1,       (b[1]>>3)+1)
        r[#r+1] = alpha:sub(((b[1]&7)<<2|(b[2]>>6))+1, ((b[1]&7)<<2|(b[2]>>6))+1)
        r[#r+1] = alpha:sub(((b[2]>>1)&31)+1,  ((b[2]>>1)&31)+1)
        r[#r+1] = alpha:sub(((b[2]&1)<<4|(b[3]>>4))+1, ((b[2]&1)<<4|(b[3]>>4))+1)
        r[#r+1] = alpha:sub(((b[3]&15)<<1|(b[4]>>7))+1,((b[3]&15)<<1|(b[4]>>7))+1)
        r[#r+1] = alpha:sub(((b[4]>>2)&31)+1,  ((b[4]>>2)&31)+1)
        r[#r+1] = alpha:sub(((b[4]&3)<<3|(b[5]>>5))+1, ((b[4]&3)<<3|(b[5]>>5))+1)
        r[#r+1] = alpha:sub((b[5]&31)+1,       (b[5]&31)+1)
        i = i + 5
    end
    return table.concat(r)
end

local function rev(t,i,j) while i<j do t[i],t[j]=t[j],t[i];i,j=i+1,j-1 end end
local function rotate(t,d,n)
    n=n or #t; d=d%n
    rev(t,1,n); rev(t,1,d); rev(t,d+1,n)
end

function ConstantArray:init() end

function ConstantArray:createArray()
    local e = {}
    for i,v in ipairs(self.constants) do
        if type(v)=="string" then v=encodeB32(v,self.alphabet) end
        e[i] = Ast.TableEntry(Ast.ConstantNode(v))
    end
    return Ast.TableConstructorExpression(e)
end

function ConstantArray:addConstant(v)
    if not self.lookup[v] then
        local idx = #self.constants+1
        self.constants[idx]=v; self.lookup[v]=idx
    end
end

function ConstantArray:getConstant(v, data)
    local idx = self.lookup[v]
    if not idx then self:addConstant(v); idx=self.lookup[v] end
    data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId)
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.rootScope, self.wrapperId),
        { Ast.NumberExpression(idx - self.wrapperOffset) }
    )
end

function ConstantArray:addDecodeBlock(ast)
    local lkEntries = {}
    for i=1,#self.alphabet do
        local ch = self.alphabet:sub(i,i)
        table.insert(lkEntries, Ast.KeyedTableEntry(Ast.StringExpression(ch), Ast.NumberExpression(i-1)))
    end
    util.shuffle(lkEntries)

    local decodeCode = [[
do
    local _lk = LOOKUP
    local _sub = string.sub; local _char = string.char
    local _arr = ARRVAR;     local _type = type
    for _i=1,#_arr do
        local _d=_arr[_i]
        if _type(_d)=="string" then
            local _out={}; local _len=#_d; local _j=1
            while _j<=_len do
                local c0=_lk[_sub(_d,_j,_j)]   or 0
                local c1=_lk[_sub(_d,_j+1,_j+1)] or 0
                local c2=_lk[_sub(_d,_j+2,_j+2)] or 0
                local c3=_lk[_sub(_d,_j+3,_j+3)] or 0
                local c4=_lk[_sub(_d,_j+4,_j+4)] or 0
                local c5=_lk[_sub(_d,_j+5,_j+5)] or 0
                local c6=_lk[_sub(_d,_j+6,_j+6)] or 0
                local c7=_lk[_sub(_d,_j+7,_j+7)] or 0
                local b1=(c0<<3)|(c1>>2)
                local b2=((c1&3)<<6)|(c2<<1)|(c3>>4)
                local b3=((c3&15)<<4)|(c4>>1)
                local b4=((c4&1)<<7)|(c5<<2)|(c6>>3)
                local b5=((c6&7)<<5)|c7
                _out[#_out+1]=_char(b1)
                if _j+2<=_len then _out[#_out+1]=_char(b2) end
                if _j+4<=_len then _out[#_out+1]=_char(b3) end
                if _j+5<=_len then _out[#_out+1]=_char(b4) end
                if _j+7<=_len then _out[#_out+1]=_char(b5) end
                _j=_j+8
            end
            _arr[_i]=table.concat(_out)
        end
    end
end
]]
    local parser = Parser:new({ LuaVersion = LuaVersion.Lua51 })
    local newAst = parser:parse(decodeCode)
    local doStat = newAst.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)

    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.VariableExpression then
            local nm = node.scope:getVariableName(node.id)
            if nm == "ARRVAR" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                data.scope:addReferenceToHigherScope(self.rootScope, self.arrId)
                node.scope = self.rootScope; node.id = self.arrId
            elseif nm == "LOOKUP" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                return Ast.TableConstructorExpression(lkEntries)
            end
        end
    end)
    table.insert(ast.body.statements, 1, doStat)
end

local rotCode = [=[
    for _ri,_rv in ipairs({{1,LEN},{1,SHIFT},{SHIFT+1,LEN}}) do
        while _rv[1]<_rv[2] do
            ARRVAR[_rv[1]],ARRVAR[_rv[2]],_rv[1],_rv[2]=
                ARRVAR[_rv[2]],ARRVAR[_rv[1]],_rv[1]+1,_rv[2]-1
        end
    end
]=]

function ConstantArray:addRotateCode(ast, shift)
    local code = rotCode:gsub("SHIFT",tostring(shift)):gsub("LEN",tostring(#self.constants))
    local newAst = Parser:new({ LuaVersion = LuaVersion.Lua51 }):parse(code)
    local s = newAst.body.statements[1]
    s.body.scope:setParent(ast.body.scope)
    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.VariableExpression then
            if node.scope:getVariableName(node.id) == "ARRVAR" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                data.scope:addReferenceToHigherScope(self.rootScope, self.arrId)
                node.scope = self.rootScope; node.id = self.arrId
            end
        end
    end)
    table.insert(ast.body.statements, 1, s)
end

function ConstantArray:apply(ast, _)
    self.alphabet      = initAlphabet()
    self.rootScope     = ast.body.scope
    self.arrId         = self.rootScope:addVariable()
    self.constants     = {}
    self.lookup        = {}
    self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset)
    self.wrapperId     = self.rootScope:addVariable()

    visitast(ast, nil, function(node, _)
        if math.random() <= self.Threshold then
            node.__nca = true
            if node.kind == AstKind.StringExpression then
                self:addConstant(node.value)
            elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
                self:addConstant(node.value)
            end
        end
    end)

    if self.Shuffle and #self.constants > 0 then
        self.constants = util.shuffle(self.constants)
        self.lookup = {}
        for i,v in ipairs(self.constants) do self.lookup[v]=i end
    end

    visitast(ast, nil, function(node, data)
        if node.__nca then
            node.__nca = nil
            if node.kind == AstKind.StringExpression then
                return self:getConstant(node.value, data)
            elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
                return self:getConstant(node.value, data)
            end
        end
    end)

    self:addDecodeBlock(ast)

    if self.Rotate and #self.constants > 1 then
        local shift = math.random(1, #self.constants-1)
        rotate(self.constants, -shift)
        self:addRotateCode(ast, shift)
    end

    local fs = Scope:new(self.rootScope)
    local a  = fs:addVariable()
    fs:addReferenceToHigherScope(self.rootScope, self.arrId)
    local addSub
    if self.wrapperOffset < 0 then
        addSub = Ast.SubExpression(Ast.VariableExpression(fs,a), Ast.NumberExpression(-self.wrapperOffset))
    else
        addSub = Ast.AddExpression(Ast.VariableExpression(fs,a), Ast.NumberExpression(self.wrapperOffset))
    end
    table.insert(ast.body.statements, 1, Ast.LocalFunctionDeclaration(
        self.rootScope, self.wrapperId,
        { Ast.VariableExpression(fs,a) },
        Ast.Block({ Ast.ReturnStatement({
            Ast.IndexExpression(Ast.VariableExpression(self.rootScope,self.arrId), addSub)
        })}, fs)
    ))
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(self.rootScope, {self.arrId}, {self:createArray()})
    )
    self.rootScope=nil; self.arrId=nil; self.constants=nil; self.lookup=nil
end

return ConstantArray
