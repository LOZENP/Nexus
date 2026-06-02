-- Nexus Obfuscator - Shadow Name Generator
-- l/I lookalike names, best for Roblox/LuaU targets.
local CHARS = { "l","I","i","O","o","ll","lI","Il","II","li","il" }

local function generateName(id)
    local c = CHARS
    local n = #c
    local d = id % n
    id = (id - d) / n
    local name = c[d + 1]
    while id > 0 do
        local e = id % n
        id = (id - e) / n
        name = name .. c[e + 1]
    end
    return name
end

return { generateName = generateName }
