-- Creator Credits—CREDIT YOURSELF! --
    ms.macroMeta = {
        name    = "Combat Warriors Macros",
        author  = "mudbourn",
        website = "https://mudbourn.info",
    }
-- END Creator Credits --

-- Reference Resolution (used by ms.getScaled, ms.mousePos, coordinate helpers) --
    REF_W    = 1680
    REF_H    = 1044
    REF_SENS = 1.5
-- END Reference Resolution --

-- Pack Settings --
    -- Camera Sensitivity --
        ms.settings.define({
            type    = "slider",
            key     = "cameraSensitivity",
            label   = "Camera Sensitivity",
            min     = 0.1,
            max     = 4,
            step    = 0.1,
            default = 1.5,
            onChange = function(val)
                CUR_CAM_SENS = val
            end,
        })
    -- END Camera Sensitivity --

    -- Click Level --
        ms.settings.define({
            key     = "clickLevel",
            label   = "Click Method",
            hint    = "Switches the method used to perform click sequences",
            section = "calibration",
            type    = "seg",
            options = {
                { label = "1", value = 1 },
                { label = "2", value = 2 },
                { label = "3", value = 3 },
                { label = "4", value = 4 },
            },
            default  = 3,
            save     = true,
        })

        ms.settings.define({
            type = "divider",
            section = "calibration"
        })
    -- END Click Level --

    -- Slide Setup --
        ms.settings.define({
            type = "groupLabel",
            label = "Slide Setup",
            section = "calibration"
        })

        ms.settings.define({
            type = "slider",
            key = "sgMenuX",
            label = "Menu Button X",
            hint = "X coord of the Z-menu button in the top bar",
            min = 350,
            max = 560,
            step = 1,
            default = 445,
            save = true,
            section = "calibration",
        })

        ms.settings.define({
            type = "slider",
            key = "sgMenuY",
            label = "Menu Button Y",
            hint = "Y coord of the Z-menu button in the top bar",
            min = 20,
            max = 80,
            step = 1,
            default = 37,
            save = true,
            section = "calibration",
        })

        ms.settings.define({
            type = "slider",
            key = "sgItemX",
            label = "Item Column X",
            hint = "X coord of the emote / action item column",
            min = 400,
            max = 560,
            step = 1,
            default = 467,
            save = true,
            section = "calibration",
        })
    -- END Slide Setup --

    -- Lag Simulator --
        ms.settings.define({
            type = "divider",
            section = "calibration"
        })

        ms.settings.define({
            type = "groupLabel",
            label = "Lag Simulator",
            section = "calibration"
        })

        ms.settings.define({
            type = "slider",
            key = "spamMoveX",
            label = "Profiler Icon X",
            hint = "X coord of the Micro Profiler icon in the top bar",
            min = 380,
            max = 510,
            step = 1,
            default = 437,
            save = true,
            section = "calibration",
        })

        ms.settings.define({
            type = "slider",
            key = "spamMoveY",
            label = "Profiler Icon Y",
            hint = "Y coord of the Micro Profiler icon in the top bar",
            min = 20,
            max = 70,
            step = 1,
            default = 34,
            save = true,
            section = "calibration",
        })

        ms.settings.define({
            type = "slider",
            key = "spamClickX",
            label = "Profiler Action X",
            hint = "X coord for the profiler action click",
            min = 390,
            max = 530,
            step = 1,
            default = 452,
            save = true,
            section = "calibration",
        })
    -- END Lag Simulator --

    -- Quick Slide --
        ms.settings.define({
            type = "divider",
            section = "calibration"
        })

        ms.settings.define({
            type = "groupLabel",
            label = "Quick Slide",
            section = "calibration"
        })

        ms.settings.define({
            type = "slider",
            key = "qsClickX",
            label = "Click Target X",
            hint = "X coord of the Quick Slide click target",
            min = 600,
            max = 1300,
            step = 1,
            default = 920,
            save = true,
            section = "calibration",
        })

        ms.settings.define({
            type = "slider",
            key = "qsClickY",
            label = "Click Target Y",
            hint = "Y coord of the Quick Slide click target",
            min = 400,
            max = 900,
            step = 1,
            default = 680,
            save = true,
            section = "calibration",
        })
    -- END Quick Slide --
-- END Pack Settings --

-- Combat Warriors Macros --
    -- Helper Variables & Functions --
        local QuickSlideSound    = SoundMacroDir .. "QuickSlide.wav"
        local JumpLowSound       = SoundMacroDir .. "JumpLow.wav"
        local JumpHighSound      = SoundMacroDir .. "JumpHigh.wav"
        local SlideSetupSound    = SoundMacroDir .. "SlideSetup.wav"
        local JumpNormalSound    = SoundMacroDir .. "JumpNormal.wav"
        local ThrowTrickSound    = SoundMacroDir .. "ThrowTrick.wav"
        local SpawnAltSound      = SoundMacroDir .. "SpawnAlt.wav"
        local ThrowTrickEndSound = SoundMacroDir .. "ThrowTrickEnd.wav"
        local ActionSpammerSound = SoundMacroDir .. "TimeSlower.wav"
        local Running = 0
        local _movementTimer = nil

        local getD1 = function()
            local d1  = 40
            local lvl = ms.settings.get("clickLevel")
            if lvl     == 4 then d1 = d1 + 30
            elseif lvl == 3 then d1 = d1 + 20
            elseif lvl == 2 then d1 = d1 + 10
            end
            return d1
        end

        local getD2 = function()
            local d2  = 50
            local lvl = ms.settings.get("clickLevel")
            if lvl     == 4 then d2 = d2 + 20
            elseif lvl == 3 then d2 = d2 + 20
            elseif lvl == 2 then d2 = d2 + 10
            end
            return d2
        end

        local getD3 = function()
            local d3  = 50
            local lvl = ms.settings.get("clickLevel")
            if lvl     == 4 then d3 = d3 + 30
            elseif lvl == 3 then d3 = d3 + 20
            elseif lvl == 2 then d3 = d3 + 10
            end
            return d3
        end

        local JumpHigh = ms.sub("JumpHigh", function()
            if ms.isSub("jumpHigh") then
                ms.log("if", "isSub(jumpHigh)", true)
                ms.sound(JumpHighSound, true)
                for i = 1, 60 do
                    ms.cam(-3145, 0)
                    ms.wait(1)
                    ms.cam(-3145, 0)
                    ms.wait(.5)
                end
                ms.cam.rebalance(8)
                ms.log("for", "i=1,60", 60)
                return true
            end
            return false
        end)

        local JumpLow = ms.sub("JumpLow", function()
            if ms.isSub("jumpLow") then
                ms.log("if", "isSub(jumpLow)", true)
                ms.sound(JumpLowSound, true)
                for i = 1, 14 do
                    ms.cam(-370 * 0.6, 0)
                    ms.wait(1)
                    ms.cam(-370 * 0.6, 0)
                    ms.wait(.5)
                end
                ms.cam.rebalance(8)
                ms.log("for", "i=1,14", 14)
                return true
            end
            return false
        end)

        local JumpDefault = ms.sub("JumpDefault", function()
            ms.sound(JumpNormalSound, true)
            for i = 1, 14 do
                ms.cam(-185 * 0.75, 0)
                ms.wait(1)
                ms.cam(-185 * 0.75, 0)
                ms.wait(.5)
            end
            ms.cam.rebalance(4)
            ms.log("for", "i=1,14", 14)
        end)

        local MovementChecker = ms.sub("MovementChecker", function()
            if Running == 0 then
                Running = 1
                local function check()
                    local moving = ms.keystate("w") or ms.keystate("a") or ms.keystate("s") or ms.keystate("d")
                    if Running == 0 then
                        return
                    end
                    if not moving then
                        ms.press("w")
                    end
                    _movementTimer = ms.after(5, check)
                end
                check()
            end
        end)

        local EndMovementChecker = ms.sub("EndMovementChecker", function()
            Running = 0
            if _movementTimer then
                _movementTimer:stop()
                _movementTimer = nil
            end
            local moving = ms.keystate("w") or ms.keystate("a") or ms.keystate("s") or ms.keystate("d")
            if not moving then
                ms.release("w")
            end
        end)

        local ThrowLow = ms.sub("ThrowLow", function()
            if ms.isSub("throwLow") then
                ms.log("if", "isSub(throwLow)", true)
                for i = 1, 15 do
                    ms.cam(-400, 0)
                    ms.wait(1)
                    ms.cam(-400, 0)
                    ms.wait(1)
                end
                ms.log("for", "i=1,15", 15)
                for i2 = 1, 30 do
                    ms.cam(9, 0)
                    ms.wait(1)
                    ms.cam(8, 0)
                    ms.wait(.5)
                end
                ms.log("for", "i2=1,30", 30)
                for i2 = 1, 180 do
                    ms.release("x")
                    ms.cam(9, 0)
                    ms.wait(1)
                    ms.cam(8, 0)
                    ms.wait(1)
                end
                ms.log("for", "i2=1,180", 180)
                ms.wait(5)
                ms.release("space")
                EndMovementChecker()
                ms.wait(20)
                ms.scroll("down", 2000)
                ms.sound(ThrowTrickEndSound, true)
                ms.wait(3000)
                return true
            end
            return false
        end)

        local ThrowDefault = ms.sub("ThrowDefault", function()
            for i = 1, 60 do
                ms.cam(-3145, 0)
                ms.wait(2)
                ms.cam(-3145, 0)
                ms.wait(2)
            end
            ms.log("for", "i=1,60", 60)
            for i2 = 1, 150 do
                ms.cam(9, 0)
                ms.wait(1)
                ms.cam(8, 0)
                ms.wait(.5)
            end
            ms.log("for", "i2=1,150", 150)
            for i2 = 1, 150 do
                ms.release("x")
                ms.cam(9, 0)
                ms.wait(1)
                ms.cam(8, 0)
                ms.wait(1)
            end
            ms.log("for", "i2=1,150", 150)
            ms.wait(5)
            ms.release("space")
            EndMovementChecker()
            ms.wait(20)
            ms.scroll("down", 2000)
            ms.sound(ThrowTrickEndSound, true)
            ms.wait(3000)
        end)

    -- END Helper Variables & Functions --

    -- Macro Functions --
        -- High Leap Assist --
            local HighLeapAssistFunction = ms.fn(function()
                MovementChecker()
                ms.cam.reset()
                for i = 1, 5 do
                    ms.type("e", nil, nil, 7)
                    ms.wait(1)
                end
                ms.log("for", "i=1,5", 5)
                ms.wait(30)
                for i = 1, 2 do
                    ms.type("space", nil, nil, 10)
                end
                ms.log("for", "i=1,2", 2)
                ms.wait(10)

                if not JumpHigh() then
                    if not JumpLow() then
                        ms.log("if", "jumpLow", false)
                        JumpDefault()
                    else
                        ms.log("if", "jumpLow", true)
                    end
                else
                    ms.log("if", "jumpHigh", true)
                end

                ms.release("space")
                ms.wait(100)
                EndMovementChecker()
                ms.wait(3000)
                EndMovementChecker()
            end)

            ms.bind.define("superJump", function()
                if ms.modHeld("superThrow") then
                    ms.log("if", "modHeld(superThrow)", true)
                    local fn = ms.bind._wires.superThrow
                    if fn then fn() end
                else
                    ms.log("if", "modHeld(superThrow)", false)
                    HighLeapAssistFunction()
                end
            end, {
                group    = "main",
                label    = "High Leap Assist",
                default  = {
                    type   = "mouse",
                    button = 3,
                },
            })

            ms.bind.define("jumpHigh", HighLeapAssistFunction, {
                sub   = "superJump",
                label = "Jump High",
                mod   = "v",
            })

            ms.bind.define("jumpLow",  HighLeapAssistFunction, {
                sub   = "superJump",
                label = "Jump Low",
                mod   = "x",
            })
        -- END High Leap Assist --

        -- Throw Trick --
            local ThrowTrickFunction = ms.fn(function()
                ms.sound(ThrowTrickSound, true)
                ms.press("x")
                for i = 1, 5 do
                    ms.cam(0, -100)
                    ms.wait(1)
                end
                ms.log("for", "i=1,5", 5)
                ms.wait(50)
                for i = 1, 4 do
                    ms.cam(0, 13)
                    ms.wait(1)
                end
                ms.log("for", "i=1,4", 4)
                ms.scroll("up", 2000)
                MovementChecker()
                for i = 1, 5 do
                    ms.type("e")
                    ms.wait(1)
                end
                ms.log("for", "i=1,5", 5)
                ms.wait(30)
                for i = 1, 2 do
                    ms.type("space")
                end
                ms.log("for", "i=1,2", 2)
                ms.wait(50)

                if not ThrowLow() then
                    ms.log("if", "throwLow", false)
                    ThrowDefault()
                else
                    ms.log("if", "throwLow", true)
                end
            end)

            ms.bind.define("superThrow", ThrowTrickFunction, {
                sub   = "superJump",
                label = "Throw Trick",
                mod   = "alt",
            })

            ms.bind.define("throwLow",   ThrowTrickFunction, {
                sub   = "superThrow",
                label = "Throw Low",
                mod   = "v",
            })
        -- END Throw Trick --

        -- Swing Cancel --
            local FakeSwingFunction = ms.fn(function()
                ms.Mouse(Click, Left, Mouse, 0, 0)
                ms.wait(99)
                ms.type("5")
                ms.wait(5)
                ms.type("1")
                ms.wait(500)
            end)

            ms.bind.define("fakeSwing", function()
                if string.find(ms.app(), "Roblox") then
                    ms.log("if", "app=Roblox", true)
                    FakeSwingFunction()
                else
                    ms.log("if", "app=Roblox", false)
                end
            end, {
                group    = "main",
                label    = "Swing Cancel",
                cooldown = 780,
                default  = {
                    type   = "mouse",
                    button = 4,
                },
            })
        -- END Swing Cancel --

        -- Quick Reset --
            local QuickResetFunction = ms.fn(function()
                ms.type("escape")
                ms.wait(50)
                ms.type("r")
                ms.wait(50)
                ms.type("return")
                ms.wait(200)
                ms.type("escape")
                ms.wait(100)
                ms.type("return")
                ms.wait(400)
                ms.type("escape")
                ms.type("escape")
                ms.wait(400)
                for i = 1, 20 do
                    ms.press("space")
                    ms.wait(100)
                end
                ms.log("for", "i=1,20", 20)
                ms.release("space")
            end)

            ms.bind.define("quickReset", QuickResetFunction, {
                group   = "optional",
                label   = "Quick Reset",
                default = {
                    type = "key",
                    mods = {"alt"},
                    key  = "escape",
                },
            })
        -- END Quick Reset --

        -- Action Spammer --
            local ActionSpammerFunction = ms.fn(function()
                ms.sound(ActionSpammerSound, true)
                local d3 = getD3()
                ms.type("z")
                ms.wait(10)
                ms.Mouse(Move, Left, WindowTL,
                    ms.settings.get("spamMoveX"),
                    ms.settings.get("spamMoveY")
                )
                ms.wait(45)
                ms.Mouse(Click, Left, WindowTL,
                    ms.settings.get("spamClickX"), d3)
                ms.wait(50)
                local _spamCount = 0
                while ms.keystate(998, true) do
                    _spamCount = _spamCount + 1
                    ms.Mouse(Click, Left, Mouse, 0, 0)
                    ms.wait(15)
                end
                ms.log("while", "keystate(998)", _spamCount)
                ms.wait(150)
                ms.type("z")
                ms.wait(60)
            end)

            ms.bind.define("frameDump", function()
                if ms.modHeld("spawnAlt") then
                    ms.log("if", "modHeld(spawnAlt)", true)
                    local fn = ms.bind._wires.spawnAlt
                    if fn then fn() end
                else
                    ms.log("if", "modHeld(spawnAlt)", false)
                    ActionSpammerFunction()
                end
            end, {
                group   = "optional",
                label   = "Lag Simulator (Micro Profiler)",
                default = {
                    type   = "mouse",
                    button = 2,
                },
            })
        -- END Action Spammer --

        -- Load Second Account (PRIVATE SERVER, MUST HAVE PSCMDS) --
            local SpawnAltFunction = ms.fn(function()
                local t = 100
                    ms.sound(SpawnAltSound, true)
                    ms.type("/")
                    ms.wait(t)
                    ms.copy("/spawn l")
                    ms.wait(t)
                    ms.type("v", { "cmd" })
                    ms.wait(t)
                    ms.type("return")
                    ms.type("/")
                    ms.wait(t)
                    ms.copy("/tp l m")
                    ms.wait(t)
                    ms.type("v", { "cmd" })
                    ms.wait(t)
                    ms.type("return")
                    ms.type("/")
                    ms.wait(t)
                    ms.copy("/health l 64")
                    ms.wait(t)
                    ms.type("v", { "cmd" })
                    ms.wait(t)
                    ms.type("return")
                    ms.type("/")
                    ms.wait(t)
                    ms.copy("/health m 1015")
                    ms.wait(t)
                    ms.type("v", { "cmd" })
                    ms.wait(t)
                    ms.type("return")
            end)

            ms.bind.define("spawnAlt", SpawnAltFunction, {
                sub   = "frameDump",
                label = "Load Second Account",
                mod   = "alt",
            })
        -- END Load Second Account --
    -- END Macro Functions --
-- END Combat Warriors Macros --
