-- Creator Credits — CREDIT YOURSELF! --
    ms.macroMeta = {
        name    = "Default",
        author  = "User"
    }
-- END Creator Credits --


local NewMacro1Function = ms.fn(function()
    local t = 100
        ms.type("/")
        ms.wait(t)
        ms.copy("Hello world!")
        ms.wait(t)
        ms.type("v", { "cmd" })
        ms.wait(t)
        ms.type("return")
end)

ms.bind.define("NewMacro1", NewMacro1Function, {
    group   = "optional",
    label   = "New Macro 1",
    default = {
        type = "key",
        mods = {"ctrl"},
        key  = "G",
    },
})

-- Camera Sensitivity — Roblox-specific, per-profile
ms.settings.define({
    type    = "slider",
    key     = "cameraSensitivity",
    label   = "Camera Sensitivity",
    min     = 0.1,
    max     = 4,
    step    = 0.1,
    default = 1.5,
    onChange = function(val)
        ms._camSens = val
    end,
})
