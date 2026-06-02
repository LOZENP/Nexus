-- Nexus Obfuscator - Zap Name Generator
-- Shuffled lowercase+digit charset, looks nothing like Prometheus mangled names.
local util = require("nexus.util")

local START = util.chararray("abcdefghijklmnopqrstuvwxyz")
local BODY  = util.chararray("abcdefghijklmnopqrstuvwxyz0123456789_")

local function generateName(id)
    local name = ""
    local d = id % #START
    id = (id - d) / #START
    name = START[d + 1]
    while id > 0 do
        local e = id % #BODY
        id = (id - e) / #BODY
        name = name .. BODY[e + 1]
    end
    return name
end

local function prepare()
    util.shuffle(START)
    util.shuffle(BODY)
end

return { generateName = generateName, prepare = prepare }
