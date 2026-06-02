-- Nexus Obfuscator - Logger
local Logger = {}
Logger.silent = false
function Logger:info(msg)
    if not self.silent then print("[Nexus] [INFO] "..tostring(msg)) end
end
function Logger:warn(msg)
    if not self.silent then print("[Nexus] [WARN] "..tostring(msg)) end
end
function Logger:error(msg)
    error("[Nexus] [ERROR] "..tostring(msg), 2)
end
return Logger
