-- Nexus Obfuscator - Presets
return {
    ["Medium"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "Zap",
        PrettyPrint   = false,
        Seed          = 0,
        Steps = {
            { Name = "EncryptStrings",       Settings = {} },
            { Name = "AntiTamper",           Settings = { UseDebug = false } },
            { Name = "Vmify",                Settings = {} },
            { Name = "ConstantArray",        Settings = {
                Threshold             = 1,
                StringsOnly           = true,
                Shuffle               = true,
                Rotate                = true,
                LocalWrapperThreshold = 0,
            }},
            { Name = "NumbersToExpressions", Settings = {} },
            { Name = "WrapInFunction",       Settings = {} },
        },
    },
}
