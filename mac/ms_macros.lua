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


-- Anti-Timeout — prevents Roblox 20-minute inactivity kick
-- Set enabled = true to activate. Toggle from Settings > Developer.
-- Customize: change the action, interval (seconds), etc.
--[[
ms.antiTimeout({
    action = function()
        Press("w")
        ms.wait(50)
        Release("w")
    end,
    interval = 15 * 60,  -- seconds between actions (15 min default)
    enabled  = true,      -- set true to start automatically
})
--]]
