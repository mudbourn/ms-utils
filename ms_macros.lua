-- Creator Credits—CREDIT YOURSELF! --
    ms.macroMeta = {
        name    = "Combat Warriors Macros",
        author  = "mudbourn",
        website = "https://mudbourn.info",
    }
-- END Creator Credits --

-- Pack Settings --
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
    -- END --

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
            type = "slider", key = "sgMenuY", label = "Menu Button Y",
            hint = "Y coord of the Z-menu button in the top bar",
            min = 20, max = 80, step = 1, default = 37, save = true,
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
    -- END --

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
    -- END --

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
    -- END --
-- END Pack Settings --

-- Combat Warriors Macros --
    -- Macro Functions --
        -- Helper Variables & Functions --
            local QuickSlideSound    = SoundLib .. "QuickSlide.wav"
            local JumpLowSound       = SoundLib .. "JumpLow.wav"
            local JumpHighSound      = SoundLib .. "JumpHigh.wav"
            local SlideSetupSound    = SoundLib .. "SlideSetup.wav"
            local JumpNormalSound    = SoundLib .. "JumpNormal.wav"
            local ThrowTrickSound    = SoundLib .. "ThrowTrick.wav"
            local SpawnAltSound      = SoundLib .. "SpawnAlt.wav"
            local ThrowTrickEndSound = SoundLib .. "ThrowTrickEnd.wav"


            local getD1 = function()
                local d1  = 52
                local lvl = ms.settings.get("clickLevel")
                if lvl     == 4 then d1 = d1 + 30
                elseif lvl == 3 then d1 = d1 + 20
                elseif lvl == 2 then d1 = d1 + 10
                end
                return d1
            end

            local getD2 = function()
                local d2  = 63
                local lvl = ms.settings.get("clickLevel")
                if lvl     == 4 then d2 = d2 + 20
                elseif lvl == 3 then d2 = d2 + 20
                elseif lvl == 2 then d2 = d2 + 10
                end
                return d2
            end

            local getD3 = function()
                local d3  = 52
                local lvl = ms.settings.get("clickLevel")
                if lvl     == 4 then d3 = d3 + 30
                elseif lvl == 3 then d3 = d3 + 30
                elseif lvl == 2 then d3 = d3 + 10
                end
                return d3
            end
        -- END --

        -- High Leap Assist --
            local HighLeapAssistFunction = ms.fn(function()
                local MovingCheck = ms.keystate("w") or ms.keystate("a") or ms.keystate("s") or ms.keystate("d")
                if not MovingCheck then
                    ms.press("w")
                    ms.wait(10)
                end
                for i = 1, 5 do
                    ms.type("e")
                    ms.wait(1)
                end
                ms.wait(30)
                for i = 1, 2 do
                    ms.type("space")
                end
                ms.wait(10)
                    local JumpHigh = function()
                        if ms.isSub("jumpHigh") then
                            ms.sound(JumpHighSound, true)
                            for i = 1, 60 do
                                ms.cam.move(0, -3145)
                                ms.wait(1)
                                ms.cam.move(0, -3145)
                                ms.wait(.5)
                            end
                            ms.wait(50)
                            ms.cam.move(0, 262)
                            return true
                        end
                        return false
                    end

                    local JumpLow = function()
                        if ms.isSub("jumpLow") then
                            ms.sound(JumpLowSound, true)
                            for i = 1, 14 do
                                ms.cam.move(0, -370)
                                ms.wait(1)
                                ms.cam.move(0, -370)
                                ms.wait(.5)
                            end
                            ms.wait(50)
                            ms.cam.move(0, 308)
                            return true
                        end
                        return false
                    end

                    local JumpDefault = function()
                        ms.sound(JumpNormalSound, true)
                        for i = 1, 14 do
                            ms.cam.move(0, -185)
                            ms.wait(1)
                            ms.cam.move(0, -185)
                            ms.wait(.5)
                        end
                        ms.wait(50)
                        ms.cam.move(0, -69)
                    end

                    if not JumpHigh() then
                        if not JumpLow() then
                            JumpDefault()
                        end
                    end
                    ms.release("space")
                    ms.wait(100)
                    if not MovingCheck then ms.release("w") end
                    ms.wait(20)
                    ms.wait(600)
            end)

            ms.bind.define("superJump", function()
                if ms.modHeld("superThrow") then
                    local fn = ms.bind._wires.superThrow
                    if fn then fn() end
                else HighLeapAssistFunction() end
            end, {
                group    = "main",
                label    = "High Leap Assist",
                cooldown = 3200,
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
        -- END --

        -- Throw Trick --
            local ThrowTrickFunction = ms.fn(function()
                ms.sound(ThrowTrickSound, true)
                ms.press("x")
                for i = 1, 5 do
                    ms.cam.move(-60, 0)
                    ms.wait(1)
                end
                ms.wait(50)
                for i = 1, 4 do
                    ms.cam.move(16, 0)
                    ms.wait(1)
                end
                ms.scroll("up", 2000)
                local MovingCheck = ms.keystate("w") or ms.keystate("a") or ms.keystate("s") or ms.keystate("d")
                if not MovingCheck then
                    ms.press("w")
                    ms.wait(10)
                end
                for i = 1, 5 do
                    ms.type("e")
                    ms.wait(1)
                end
                ms.wait(30)
                for i = 1, 2 do
                    ms.type("space")
                end
                ms.wait(50)
                local ThrowLow = function()
                    if ms.isSub("throwLow") then
                        for i = 1, 15 do
                            ms.cam.move(0, -400)
                            ms.wait(1)
                            ms.cam.move(0, -400)
                            ms.wait(1)
                        end
                        for i2 = 1, 30 do
                            ms.cam.move(0, 8)
                            ms.wait(1)
                            ms.cam.move(0, 8)
                            ms.wait(.5)
                        end
                        for i2 = 1, 180 do
                            ms.release("x")
                            ms.cam.move(0, 8)
                            ms.wait(1)
                            ms.cam.move(0, 8)
                            ms.wait(1)
                        end
                        ms.wait(5)
                        ms.release("space")
                        ms.wait(100)
                        if not MovingCheck then ms.release("w") end
                        ms.wait(20)
                        if not ms.keystate("shift") then ms.release("shift") end
                        ms.scroll("down", 2000)
                        ms.sound(ThrowTrickEndSound, true)
                        ms.wait(3000)

                        return true
                    end
                    return false
                end
                local ThrowDefault = function()
                    for i = 1, 60 do
                        ms.cam.move(0, -3145)
                        ms.wait(2)
                        ms.cam.move(0, -3145)
                        ms.wait(2)
                    end
                    for i2 = 1, 150 do
                        ms.cam.move(0, 8)
                        ms.wait(1)
                        ms.cam.move(0, 8)
                        ms.wait(.5)
                    end
                    for i2 = 1, 180 do
                        ms.release("x")
                        ms.cam.move(0, 10)
                        ms.wait(1)
                        ms.cam.move(0, 9)
                        ms.wait(1)
                    end
                    ms.wait(5)
                    ms.release("space")
                    ms.wait(20)
                    if not MovingCheck then ms.release("w") end
                    ms.wait(20)
                    ms.scroll("down", 2000)
                    ms.sound(ThrowTrickEndSound, true)
                    ms.wait(3000)
                end
                if not ThrowLow() then ThrowDefault() end
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
        -- END --

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
                if string.find(ms.app(), "Roblox") then FakeSwingFunction() end
            end, {
                group    = "main",
                label    = "Swing Cancel",
                cooldown = 780,
                default  = {
                    type   = "mouse",
                    button = 4,
                },
            })
        -- END --

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
                -- ms.press("space")
                -- ms.wait(2000)
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
        -- END --

        -- Quick Slide --
            local QuickSlideFunction = ms.fn(function()
                ms.Mouse(Release, Right, Mouse, 0, 0)
                ms.type("z")
                ms.wait(8)
                ms.press("w")
                ms.wait(8)
                ms.release("w")
                ms.wait(12)
                ms.Mouse(Click, Left, WindowTL,
                    ms.settings.get("qsClickX"),
                    ms.settings.get("qsClickY"))
                ms.sound(QuickSlideSound, true)
                ms.wait(200)
            end)

            ms.bind.define("quickSG", QuickSlideFunction, {
                group   = "optional",
                label   = "Quick Slide",
                default = {
                    type = "key",
                    mods = {"alt"},
                    key  = "z",
                },
            })
        -- END --

        -- Slide Setup --
            local SlideSetupFunction = ms.fn(function()
                ms.sound(SlideSetupSound, true)
                local d1 = getD1()
                local d2 = getD2()
                ms.press("shift")
                ms.press("w")
                ms.press("space")
                ms.wait(15)
                for i = 1, 5 do
                    ms.type("e")
                    ms.wait(3)
                end
                ms.wait(15)
                for i = 2, 15 do
                    ms.cam.move(1, -245)
                    ms.wait(1)
                    ms.cam.move(-1, -245)
                    ms.wait(1)
                end
                ms.wait(30)
                ms.release("w")
                ms.release("shift")
                ms.release("space")
                ms.wait(5)
                ms.press("c")
                ms.Mouse(Move, Left, WindowCenter, 0, 50)
                ms.type("z")
                ms.wait(200)
                local sgMX = ms.settings.get("sgMenuX")
                local sgMY = ms.settings.get("sgMenuY")
                local sgIX = ms.settings.get("sgItemX")
                for i = 1, 2 do
                    ms.Mouse(Click, Left, WindowTL, sgMX, sgMY)
                    ms.wait(10)
                end
                ms.wait(20)
                for i = 1, 3 do
                    ms.Mouse(Click, Left, WindowTL, sgIX, d1)
                    ms.wait(30)
                    ms.release("c")
                end
                for i = 1, 15 do
                    ms.Mouse(Click, Left, WindowTL, sgIX, d2)
                    ms.wait(30)
                end
                ms.wait(400)
                ms.type("z")
                ms.wait(2000)
            end)

            ms.bind.define("sgSetup", SlideSetupFunction, {
                group   = "optional",
                label   = "Slide Setup",
                default = {
                    type = "key",
                    mods = {"alt"},
                    key  = "\\",
                },
            })
        -- END --

        -- Action Spammer --
            local ActionSpammerFunction = ms.fn(function()
                local d3 = getD3()
                ms.type("z")
                ms.wait(10)
                ms.Mouse(Move, Left, WindowTL,
                    ms.settings.get("spamMoveX"),
                    ms.settings.get("spamMoveY"))
                ms.wait(100)
                ms.Mouse(Click, Left, WindowTL,
                    ms.settings.get("spamClickX"), d3)
                ms.wait(50)
                while ms.keystate(998, true) do
                    ms.Mouse(Click, Left, Mouse, 0, 0)
                    ms.wait(15)
                end
                ms.wait(150)
                ms.type("z")
                ms.wait(60)
            end)

            ms.bind.define("frameDump", function()
                if ms.modHeld("spawnAlt") then
                    local fn = ms.bind._wires.spawnAlt
                    if fn then fn() end
                else ActionSpammerFunction() end
            end, {
                group   = "optional",
                label   = "Lag Simulator (Micro Profiler)",
                default = {
                    type   = "mouse",
                    button = 2,
                },
            })
        -- END --

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
        -- END --

        -- Mouse Position Grabber --
            ms.bind.define("mousePos", function()
                local x, y = ms.mousePos()
                ms.alert(string.format("Mouse: %.0f, %.0f", x, y), 3)
                print(string.format("Mouse position: %.0f, %.0f", x, y))
            end, {
                group   = "optional",
                label   = "Get Mouse Position",
                default = {
                    type = "key",
                    mods = {},
                    key  = "f8",
                },
            })
        -- END --
    -- END Macro Functions --
-- END Combat Warriors Macros --
