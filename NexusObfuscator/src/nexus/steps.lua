-- Nexus Obfuscator - Steps Registry
return {
    WrapInFunction       = require("nexus.steps.WrapInFunction"),
    Vmify                = require("nexus.steps.Vmify"),
    ConstantArray        = require("nexus.steps.ConstantArray"),
    AntiTamper           = require("nexus.steps.AntiTamper"),
    EncryptStrings       = require("nexus.steps.EncryptStrings"),
    NumbersToExpressions = require("nexus.steps.NumbersToExpressions"),
    AddVararg            = require("nexus.steps.AddVararg"),
}
