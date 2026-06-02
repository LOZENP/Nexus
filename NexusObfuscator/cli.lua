-- Nexus Obfuscator - CLI
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end
local base = script_path()
package.path = base .. "src/?.lua;" .. base .. "src/?/init.lua;" .. package.path

_G.newproxy = _G.newproxy or function(a) if a then return setmetatable({},{}) end return {} end
if not pcall(function() return math.random(1,2^40) end) then
    local r = math.random
    math.random = function(a,b)
        if not a and not b then return r() end
        if not b then return math.random(1,a) end
        if a>b then a,b=b,a end
        local d=b-a
        if d>2^31-1 then return math.floor(r()*d+a) else return r(a,b) end
    end
end

local Pipeline = require("nexus.pipeline")
local Presets  = require("nexus.presets")
local Logger   = require("logger")

local inputFile, outputFile, preset = nil, nil, "Medium"
local i = 1
while i <= #arg do
    local a = arg[i]
    if     a=="--in"  or a=="-i" then i=i+1; inputFile=arg[i]
    elseif a=="--out" or a=="-o" then i=i+1; outputFile=arg[i]
    elseif a=="--preset" or a=="-p" then i=i+1; preset=arg[i]
    elseif a=="--help" or a=="-h" then
        print("Usage: lua cli.lua --in <file> --out <file> --preset Medium")
        os.exit(0)
    end
    i = i + 1
end

if not inputFile then Logger:error("No input file. Use --in <file>") end
outputFile = outputFile or "out.lua"

local cfg = Presets[preset]
if not cfg then Logger:error("Unknown preset: "..tostring(preset)) end

local f = assert(io.open(inputFile,"r"), "Cannot open: "..inputFile)
local source = f:read("*a"); f:close()

local pipeline = Pipeline:fromConfig(cfg)
local result   = pipeline:apply(source, inputFile)

local out = assert(io.open(outputFile,"w"), "Cannot write: "..outputFile)
out:write(result); out:close()
print("[Nexus] Done -> " .. outputFile)
