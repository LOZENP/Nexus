-- Nexus Obfuscator - Compiler (Prometheus VM engine, nexus paths)
local Ast   = require("nexus.ast")
local Scope = require("nexus.scope")
local util  = require("nexus.util")
local lookupify = util.lookupify
local AstKind   = Ast.AstKind
local unpack    = unpack or table.unpack

local blockModule       = require("nexus.compiler.block")
local registerModule    = require("nexus.compiler.register")
local upvalueModule     = require("nexus.compiler.upvalue")
local emitModule        = require("nexus.compiler.emit")
local compileCoreModule = require("nexus.compiler.compile_core")

local Compiler = {}

function Compiler:new()
    local c = {
        blocks={}, registers={}, activeBlock=nil,
        registersForVar={}, usedRegisters=0, maxUsedRegister=0, registerVars={},
        VAR_REGISTER=newproxy(false), RETURN_ALL=newproxy(false),
        POS_REGISTER=newproxy(false), RETURN_REGISTER=newproxy(false),
        UPVALUE=newproxy(false),
        BIN_OPS=lookupify{
            AstKind.LessThanExpression, AstKind.GreaterThanExpression,
            AstKind.LessThanOrEqualsExpression, AstKind.GreaterThanOrEqualsExpression,
            AstKind.NotEqualsExpression, AstKind.EqualsExpression,
            AstKind.StrCatExpression,  AstKind.AddExpression,
            AstKind.SubExpression,     AstKind.MulExpression,
            AstKind.DivExpression,     AstKind.ModExpression,
            AstKind.PowExpression,
        },
    }
    setmetatable(c,self); self.__index=self; return c
end

blockModule(Compiler)
registerModule(Compiler)
upvalueModule(Compiler)
emitModule(Compiler)
compileCoreModule(Compiler)

function Compiler:pushRegisterUsageInfo()
    table.insert(self.registerUsageStack,{usedRegisters=self.usedRegisters,registers=self.registers})
    self.usedRegisters=0; self.registers={}
end
function Compiler:popRegisterUsageInfo()
    local info=table.remove(self.registerUsageStack)
    self.usedRegisters=info.usedRegisters; self.registers=info.registers
end

function Compiler:compile(ast)
    self.blocks={};self.registers={};self.activeBlock=nil;self.registersForVar={}
    self.scopeFunctionDepths={};self.maxUsedRegister=0;self.usedRegisters=0
    self.registerVars={};self.usedBlockIds={};self.upvalVars={}
    self.registerUsageStack={};self.upvalsProxyLenReturn=math.random(-2^22,2^22)

    local gs  = Scope:newGlobal()
    local psc = Scope:new(gs,nil)
    local _,getfenvVar=gs:resolve("getfenv");  local _,tableVar=gs:resolve("table")
    local _,unpackVar=gs:resolve("unpack");    local _,envVar=gs:resolve("_ENV")
    local _,newproxyVar=gs:resolve("newproxy");local _,setmtVar=gs:resolve("setmetatable")
    local _,getmtVar=gs:resolve("getmetatable");local _,selectVar=gs:resolve("select")

    psc:addReferenceToHigherScope(gs,getfenvVar,2)
    psc:addReferenceToHigherScope(gs,tableVar)
    psc:addReferenceToHigherScope(gs,unpackVar)
    psc:addReferenceToHigherScope(gs,envVar)
    psc:addReferenceToHigherScope(gs,newproxyVar)
    psc:addReferenceToHigherScope(gs,setmtVar)
    psc:addReferenceToHigherScope(gs,getmtVar)

    self.scope=Scope:new(psc)
    self.envVar=self.scope:addVariable()
    self.containerFuncVar=self.scope:addVariable()
    self.unpackVar=self.scope:addVariable()
    self.newproxyVar=self.scope:addVariable()
    self.setmetatableVar=self.scope:addVariable()
    self.getmetatableVar=self.scope:addVariable()
    self.selectVar=self.scope:addVariable()
    local argVar=self.scope:addVariable()

    self.containerFuncScope=Scope:new(self.scope)
    self.whileScope=Scope:new(self.containerFuncScope)
    self.posVar=self.containerFuncScope:addVariable()
    self.argsVar=self.containerFuncScope:addVariable()
    self.currentUpvaluesVar=self.containerFuncScope:addVariable()
    self.detectGcCollectVar=self.containerFuncScope:addVariable()
    self.returnVar=self.containerFuncScope:addVariable()

    self.upvaluesTable=self.scope:addVariable()
    self.upvaluesReferenceCountsTable=self.scope:addVariable()
    self.allocUpvalFunction=self.scope:addVariable()
    self.currentUpvalId=self.scope:addVariable()
    self.upvaluesProxyFunctionVar=self.scope:addVariable()
    self.upvaluesGcFunctionVar=self.scope:addVariable()
    self.freeUpvalueFunc=self.scope:addVariable()
    self.createClosureVars={}
    self.createVarargClosureVar=self.scope:addVariable()

    local csc=Scope:new(self.scope);  local cssc=Scope:new(csc)
    local cPosArg=csc:addVariable(); local cUpvArg=csc:addVariable()
    local cProxy=csc:addVariable();  local cFunc=csc:addVariable()

    local upvalEntries={}; local upvalueIds={}
    self.getUpvalueId=function(self2,scope,id)
        local sfd=self2.scopeFunctionDepths[scope]
        if sfd==0 then
            if upvalueIds[id] then return upvalueIds[id] end
            local expr=Ast.FunctionCallExpression(Ast.VariableExpression(self2.scope,self2.allocUpvalFunction),{})
            table.insert(upvalEntries,Ast.TableEntry(expr))
            local uid=#upvalEntries; upvalueIds[id]=uid; return uid
        else require("logger"):error("Unresolved Upvalue") end
    end

    cssc:addReferenceToHigherScope(self.scope,self.containerFuncVar)
    cssc:addReferenceToHigherScope(csc,cPosArg)
    cssc:addReferenceToHigherScope(csc,cUpvArg,1)
    csc:addReferenceToHigherScope(self.scope,self.upvaluesProxyFunctionVar)
    cssc:addReferenceToHigherScope(csc,cProxy)

    self:compileTopNode(ast)

    local fna={
        {var=Ast.AssignmentVariable(self.scope,self.containerFuncVar),
         val=Ast.FunctionLiteralExpression({
             Ast.VariableExpression(self.containerFuncScope,self.posVar),
             Ast.VariableExpression(self.containerFuncScope,self.argsVar),
             Ast.VariableExpression(self.containerFuncScope,self.currentUpvaluesVar),
             Ast.VariableExpression(self.containerFuncScope,self.detectGcCollectVar),
         },self:emitContainerFuncBody())},
        {var=Ast.AssignmentVariable(self.scope,self.createVarargClosureVar),
         val=Ast.FunctionLiteralExpression({
             Ast.VariableExpression(csc,cPosArg),Ast.VariableExpression(csc,cUpvArg),
         },Ast.Block({
             Ast.LocalVariableDeclaration(csc,{cProxy},{
                 Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.upvaluesProxyFunctionVar),{Ast.VariableExpression(csc,cUpvArg)})
             }),
             Ast.LocalVariableDeclaration(csc,{cFunc},{
                 Ast.FunctionLiteralExpression({Ast.VarargExpression()},Ast.Block({
                     Ast.ReturnStatement{Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.containerFuncVar),{
                         Ast.VariableExpression(csc,cPosArg),
                         Ast.TableConstructorExpression({Ast.TableEntry(Ast.VarargExpression())}),
                         Ast.VariableExpression(csc,cUpvArg),
                         Ast.VariableExpression(csc,cProxy),
                     })}
                 },cssc))
             }),
             Ast.ReturnStatement{Ast.VariableExpression(csc,cFunc)},
         },csc))},
        {var=Ast.AssignmentVariable(self.scope,self.upvaluesTable),                val=Ast.TableConstructorExpression({})},
        {var=Ast.AssignmentVariable(self.scope,self.upvaluesReferenceCountsTable), val=Ast.TableConstructorExpression({})},
        {var=Ast.AssignmentVariable(self.scope,self.allocUpvalFunction),           val=self:createAllocUpvalFunction()},
        {var=Ast.AssignmentVariable(self.scope,self.currentUpvalId),               val=Ast.NumberExpression(0)},
        {var=Ast.AssignmentVariable(self.scope,self.upvaluesProxyFunctionVar),     val=self:createUpvaluesProxyFunc()},
        {var=Ast.AssignmentVariable(self.scope,self.upvaluesGcFunctionVar),        val=self:createUpvaluesGcFunc()},
        {var=Ast.AssignmentVariable(self.scope,self.freeUpvalueFunc),              val=self:createFreeUpvalueFunc()},
    }
    local tbl={
        Ast.VariableExpression(self.scope,self.containerFuncVar),
        Ast.VariableExpression(self.scope,self.createVarargClosureVar),
        Ast.VariableExpression(self.scope,self.upvaluesTable),
        Ast.VariableExpression(self.scope,self.upvaluesReferenceCountsTable),
        Ast.VariableExpression(self.scope,self.allocUpvalFunction),
        Ast.VariableExpression(self.scope,self.currentUpvalId),
        Ast.VariableExpression(self.scope,self.upvaluesProxyFunctionVar),
        Ast.VariableExpression(self.scope,self.upvaluesGcFunctionVar),
        Ast.VariableExpression(self.scope,self.freeUpvalueFunc),
    }
    for _,e in pairs(self.createClosureVars) do
        table.insert(fna,e); table.insert(tbl,Ast.VariableExpression(e.var.scope,e.var.id))
    end
    util.shuffle(fna)
    local lhs,rhs={},{}
    for i,v in ipairs(fna) do lhs[i]=v.var; rhs[i]=v.val end

    local ids=util.shuffle({1,2,3,4,5,6,7})
    local items={
        Ast.VariableExpression(self.scope,self.envVar),
        Ast.VariableExpression(self.scope,self.unpackVar),
        Ast.VariableExpression(self.scope,self.newproxyVar),
        Ast.VariableExpression(self.scope,self.setmetatableVar),
        Ast.VariableExpression(self.scope,self.getmetatableVar),
        Ast.VariableExpression(self.scope,self.selectVar),
        Ast.VariableExpression(self.scope,argVar),
    }
    local astItems={
        Ast.OrExpression(Ast.AndExpression(Ast.VariableExpression(gs,getfenvVar),Ast.FunctionCallExpression(Ast.VariableExpression(gs,getfenvVar),{})),Ast.VariableExpression(gs,envVar)),
        Ast.OrExpression(Ast.VariableExpression(gs,unpackVar),Ast.IndexExpression(Ast.VariableExpression(gs,tableVar),Ast.StringExpression("unpack"))),
        Ast.VariableExpression(gs,newproxyVar),
        Ast.VariableExpression(gs,setmtVar),
        Ast.VariableExpression(gs,getmtVar),
        Ast.VariableExpression(gs,selectVar),
        Ast.TableConstructorExpression({Ast.TableEntry(Ast.VarargExpression())}),
    }

    local fn=Ast.FunctionLiteralExpression({
        items[ids[1]],items[ids[2]],items[ids[3]],items[ids[4]],
        items[ids[5]],items[ids[6]],items[ids[7]],
        unpack(util.shuffle(tbl))
    },Ast.Block({
        Ast.AssignmentStatement(lhs,rhs),
        Ast.ReturnStatement{Ast.FunctionCallExpression(
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.createVarargClosureVar),{
                Ast.NumberExpression(self.startBlockId),
                Ast.TableConstructorExpression(upvalEntries),
            }),
            {Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.unpackVar),{Ast.VariableExpression(self.scope,argVar)})}
        )}
    },self.scope))

    return Ast.TopNode(Ast.Block({
        Ast.ReturnStatement{Ast.FunctionCallExpression(fn,{
            astItems[ids[1]],astItems[ids[2]],astItems[ids[3]],astItems[ids[4]],
            astItems[ids[5]],astItems[ids[6]],astItems[ids[7]],
        })}
    },psc),gs)
end

function Compiler:getCreateClosureVar(argCount)
    if not self.createClosureVars[argCount] then
        local var=Ast.AssignmentVariable(self.scope,self.scope:addVariable())
        local csc=Scope:new(self.scope); local cssc=Scope:new(csc)
        local pa=csc:addVariable(); local ua=csc:addVariable()
        local po=csc:addVariable(); local fv=csc:addVariable()
        cssc:addReferenceToHigherScope(self.scope,self.containerFuncVar)
        cssc:addReferenceToHigherScope(csc,pa)
        cssc:addReferenceToHigherScope(csc,ua,1)
        csc:addReferenceToHigherScope(self.scope,self.upvaluesProxyFunctionVar)
        cssc:addReferenceToHigherScope(csc,po)
        local at,at2={},{}
        for i=1,argCount do
            local a=cssc:addVariable()
            at[i]=Ast.VariableExpression(cssc,a); at2[i]=Ast.TableEntry(Ast.VariableExpression(cssc,a))
        end
        local val=Ast.FunctionLiteralExpression({Ast.VariableExpression(csc,pa),Ast.VariableExpression(csc,ua)},
            Ast.Block({
                Ast.LocalVariableDeclaration(csc,{po},{Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.upvaluesProxyFunctionVar),{Ast.VariableExpression(csc,ua)})}),
                Ast.LocalVariableDeclaration(csc,{fv},{Ast.FunctionLiteralExpression(at,Ast.Block({
                    Ast.ReturnStatement{Ast.FunctionCallExpression(Ast.VariableExpression(self.scope,self.containerFuncVar),{
                        Ast.VariableExpression(csc,pa),Ast.TableConstructorExpression(at2),
                        Ast.VariableExpression(csc,ua),Ast.VariableExpression(csc,po),
                    })}
                },cssc))}),
                Ast.ReturnStatement{Ast.VariableExpression(csc,fv)},
            },csc)
        )
        self.createClosureVars[argCount]={var=var,val=val}
    end
    local v=self.createClosureVars[argCount].var
    return v.scope,v.id
end

return Compiler
