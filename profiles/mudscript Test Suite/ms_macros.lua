-- Creator Credits—CREDIT YOURSELF! --
    ms.macroMeta = {
        name    = "mudscript Test Suite",
        author  = "mudbourn",
        website = "https://mudbourn.info",
    }
-- END Creator Credits --

-- Pack Settings --

    -- Behaviour --
        ms.settings.define({
            type     = "toggle",
            key      = "fastMode",
            label    = "Fast Mode",
            hint     = "Cuts all inter-step delays to 10 ms for quick smoke-testing",
            section  = "settings",
            default  = false,
            save     = true,
        })

        ms.settings.define({
            type    = "slider",
            key     = "repeatCount",
            label   = "Repeat Count",
            hint    = "How many times the Repeat Loop macro iterates",
            section = "settings",
            min     = 1,
            max     = 10,
            step    = 1,
            default = 3,
            save    = true,
        })

        ms.settings.define({
            type    = "seg",
            key     = "triggerMode",
            label   = "Trigger Mode",
            hint    = "Timing profile used by click-based macros",
            section = "settings",
            options = {
                { label = "Quick",    value = "quick"    },
                { label = "Standard", value = "standard" },
                { label = "Precise",  value = "precise"  },
            },
            default = "standard",
            save    = true,
        })
    -- END --

    -- Actions & Slots --
        ms.settings.define({
            type     = "action",
            key      = "resetState",
            label    = "Reset Test State",
            hint     = "Fires the onAction callback — no macro bind required",
            btnLabel = "Reset",
            section  = "settings",
            onAction = function()
                ms.alert("Test state reset.", 2, true)
                ms.playSlot("reset")
            end,
        })

        ms.settings.define({
            type     = "action",
            key      = "showTamperWarning",
            label    = "Tamper Warning",
            hint     = "Shows the integrity warning toast and opens the tamper-protection panel",
            btnLabel = "Show Warning",
            section  = "settings",
            onAction = function()
                ms.alert("\xe2\x9a\xa0 No trusted hash on record.\nSettings \xe2\x86\x92 Developer \xe2\x86\x92 Trust Current Version.", 10)
                ms.playSlot("alert")
                -- Guardian panel preview is opened by the privileged system action
                -- registered in ms_core.lua -- ms.showGuardian is blocked in this sandbox.
            end,
        })

        ms.settings.define({
            type    = "soundSlot",
            key     = "actionSound",
            label   = "Action Feedback",
            section = "settings",
        })
    -- END --

    -- Mouse Offsets (group) --
        ms.settings.define({
            type    = "divider",
            section = "settings",
        })

        ms.settings.define({
            type    = "group",
            label   = "Mouse Offsets",
            section = "settings",
            items   = {
                {
                    type    = "slider",
                    key     = "clickOffsetX",
                    label   = "Click Offset X",
                    hint    = "Horizontal pixel nudge added to all test click coordinates",
                    min     = -50,
                    max     = 50,
                    step    = 1,
                    default = 0,
                    save    = true,
                },
                {
                    type    = "slider",
                    key     = "clickOffsetY",
                    label   = "Click Offset Y",
                    hint    = "Vertical pixel nudge added to all test click coordinates",
                    min     = -50,
                    max     = 50,
                    step    = 1,
                    default = 0,
                    save    = true,
                },
            },
        })
    -- END --

    -- Calibration --
        ms.settings.define({ type = "divider", section = "calibration" })

        ms.settings.define({
            type    = "groupLabel",
            label   = "Click Target",
            section = "calibration",
        })

        ms.settings.define({
            type    = "slider",
            key     = "testTargetX",
            label   = "Target X",
            hint    = "REF-space X for the Mouse Click Test macro",
            section = "calibration",
            min     = 100,
            max     = 1580,
            step    = 1,
            default = 840,
            save    = true,
        })

        ms.settings.define({
            type    = "slider",
            key     = "testTargetY",
            label   = "Target Y",
            hint    = "REF-space Y for the Mouse Click Test macro",
            section = "calibration",
            min     = 100,
            max     = 944,
            step    = 1,
            default = 522,
            save    = true,
        })
    -- END --

-- END Pack Settings --

-- Advanced Section --
    ms.menu.define({
        id    = "advanced",
        title = "Advanced",
        icon  = "⚙",
        items = {
            {
                type    = "toggle",
                key     = "verboseAlerts",
                label   = "Verbose Alerts",
                hint    = "Print extra info in macro alerts and the Hammerspoon console",
                default = false,
                save    = true,
            },
            {
                type = "divider",
            },
            {
                type  = "groupLabel",
                label = "Timing (ms)",
            },
            {
                type    = "slider",
                key     = "baseDelay",
                label   = "Base Delay",
                hint    = "Minimum wait time between macro steps when Fast Mode is off",
                min     = 5,
                max     = 200,
                step    = 5,
                default = 50,
                save    = true,
            },
            {
                type    = "slider",
                key     = "holdDuration",
                label   = "Hold Duration",
                hint    = "How long the key-hold macros hold the target key",
                min     = 50,
                max     = 1000,
                step    = 50,
                default = 300,
                save    = true,
            },
        },
    })
-- END Advanced Section --

-- Feature Visibility --
    -- SOCD is not relevant to this test pack.
    ms.features.hide("socd")
-- END Feature Visibility --

-- Test Macros --
    -- Helpers --
        local stepDelay = ms.sub("stepDelay", function()
            if ms.settings.get("fastMode") then
                ms.log("if", "fastMode", true)
                return 10
            end
            ms.log("if", "fastMode", false)
            return ms.settings.get("baseDelay") or 50
        end)

        local verbose = ms.sub("verbose", function(msg)
            if ms.settings.get("verboseAlerts") then
                ms.log("if", "verboseAlerts", true)
                ms.alert(msg, 2, true)
                print("[mudscript Test Suite] " .. tostring(msg))
            end
        end)
    -- END --

    -- Hello World --
        -- Simplest possible macro: alert + sound + settings read.
        -- Verifies: ms.fn, ms.alert, ms.playSlot, ms.settings.get
        ms.bind.define("helloWorld", ms.fn(function()
            local mode = ms.settings.get("triggerMode") or "standard"
            ms.alert("Hello from mudscript!\nTrigger mode: " .. mode, 3, true)
            ms.playSlot("actionSound")
            ms.sound(SoundLib .. "Alert.wav", true)
        end), {
            group   = "test",
            label   = "Hello World",
            default = {
                type = "key",
                mods = {},
                key  = "f9",
            },
        })
    -- END --

    -- Wait and Press --
        -- Tests timing primitives and key injection.
        -- Verifies: ms.fn, ms.wait, ms.press, ms.type, ms.release
        ms.bind.define("waitAndPress", ms.fn(function()
            local d = stepDelay()
            ms.press("shift")
            ms.wait(d)
            ms.type("e")
            ms.wait(d)
            ms.release("shift")
            ms.wait(d)
            verbose("Wait & Press done. Delay: " .. tostring(d) .. " ms")
        end), {
            group    = "test",
            label    = "Wait and Press",
            cooldown = 500,
            default  = {
                type = "key",
                mods = {},
                key  = "f10",
            },
        })
    -- END --

    -- Repeat Loop --
        -- Tests looping, scroll, and repeat-count setting.
        -- Verifies: ms.fn, ms.wait, ms.type, ms.scroll, ms.settings.get
        ms.bind.define("repeatLoop", ms.fn(function()
            local count = ms.settings.get("repeatCount") or 3
            local d     = stepDelay()

            for i = 1, count do
                ms.type("e")
                ms.wait(d)
            end
            ms.log("for", "i=1," .. count, count)

            ms.scroll("up", 1)
            ms.wait(d)
            ms.scroll("down", 1)

            ms.alert("Loop done: " .. tostring(count) .. " reps", 2, true)
        end), {
            group    = "test",
            label    = "Repeat Loop",
            cooldown = 1000,
            default  = {
                type = "key",
                mods = {},
                key  = "f11",
            },
        })
    -- END --

    -- Mouse Click Test --
        -- Tests calibration settings, coordinate offsets, and Mouse API.
        -- Verifies: ms.Mouse, ms.settings.get (calibration values)
        ms.bind.define("mouseClickTest", ms.fn(function()
            local tx = ms.settings.get("testTargetX") or 840
            local ty = ms.settings.get("testTargetY") or 522
            local ox = ms.settings.get("clickOffsetX") or 0
            local oy = ms.settings.get("clickOffsetY") or 0

            ms.Mouse(Click, Left, WindowTL, tx + ox, ty + oy)
            ms.wait(stepDelay())

            verbose(string.format("Click at %d, %d (offset %d, %d)", tx, ty, ox, oy))
        end), {
            group    = "test",
            label    = "Mouse Click Test",
            cooldown = 500,
            default  = {
                type   = "mouse",
                button = 3,
            },
        })
    -- END --

    -- Camera Sweep --
        -- Tests camera movement and sub-bind dispatch.
        -- Verifies: ms.cam.move, ms.isSub, sub-bind setup
        local CameraSweepFn = ms.fn(function()
            local d = stepDelay()

            local sweepFull = ms.sub("sweepFull", function()
                ms.cam.move(0,    -600)
                ms.wait(d)
                ms.cam.move(0,     600)
                ms.wait(d)
                ms.cam.move(-600,  0)
                ms.wait(d)
                ms.cam.move( 600,  0)
            end)

            local sweepUp = ms.sub("sweepUp", function()
                ms.cam.move(0, -600)
                ms.wait(d)
                ms.cam.move(0,  600)
            end)

            if ms.isSub("sweepUpOnly") then
                ms.log("if", "isSub(sweepUpOnly)", true)
                sweepUp()
            else
                ms.log("if", "isSub(sweepUpOnly)", false)
                sweepFull()
            end
        end)

        ms.bind.define("cameraSweep", CameraSweepFn, {
            group    = "test",
            label    = "Camera Sweep",
            cooldown = 800,
            default  = {
                type   = "mouse",
                button = 4,
            },
        })

        ms.bind.define("sweepUpOnly", CameraSweepFn, {
            sub   = "cameraSweep",
            label = "Up Only",
            mod   = "v",
        })
    -- END --

    -- State Dump --
        -- Reads every user setting and prints them.
        -- Verifies: ms.settings.get across all defined keys, ms.mousePos
        ms.bind.define("stateDump", function()
            local x, y = ms.mousePos()
            local lines = {
                "== mudscript Test Suite ==",
                "Fast Mode:     " .. tostring(ms.settings.get("fastMode")),
                "Repeat Count:  " .. tostring(ms.settings.get("repeatCount")),
                "Trigger Mode:  " .. tostring(ms.settings.get("triggerMode")),
                "Verbose:       " .. tostring(ms.settings.get("verboseAlerts")),
                "Base Delay:    " .. tostring(ms.settings.get("baseDelay")),
                "Hold Duration: " .. tostring(ms.settings.get("holdDuration")),
                "Click Offset:  " .. tostring(ms.settings.get("clickOffsetX"))
                    .. ", " .. tostring(ms.settings.get("clickOffsetY")),
                "Target:        " .. tostring(ms.settings.get("testTargetX"))
                    .. ", " .. tostring(ms.settings.get("testTargetY")),
                string.format("Mouse Pos:     %.0f, %.0f", x, y),
            }
            ms.alert(table.concat(lines, "\n"), 8, true)
            print(table.concat(lines, "\n"))
        end, {
            group   = "optional",
            label   = "Dump Settings State",
            default = {
                type = "key",
                mods = {},
                key  = "f12",
            },
        })
    -- END --

    -- Key Hold --
        -- Tests key hold duration setting and conditional key state.
        -- Verifies: ms.fn, ms.press, ms.wait, ms.release, ms.keystate
        ms.bind.define("keyHoldTest", ms.fn(function()
            local dur = ms.settings.get("holdDuration") or 300
            ms.press("c")
            ms.wait(dur)
            ms.release("c")

            if ms.keystate("shift") then
                ms.log("if", "keystate(shift)", true)
                verbose("Shift was held during key hold test.")
            else
                ms.log("if", "keystate(shift)", false)
            end
        end), {
            group    = "optional",
            label    = "Key Hold Test",
            cooldown = 1500,
            default  = {
                type   = "mouse",
                button = 5,
            },
        })
    -- END --

-- END Test Macros --
