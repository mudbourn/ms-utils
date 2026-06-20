-- Creator Credits—CREDIT YOURSELF! --
    ms.macroMeta = {
        name    = "Combat Warriors Macros",
        author  = "mudbourn",
        website = "https://mudbourn.info",
    }
-- End Creator Credits --

-- Pack Settings --
    ms.settings.define({
        key     = "clickLevel",
        label   = "Click Method",
        hint    = "Switches the method used to perform click sequences",
        type    = "seg",
        options = {
            { label = "1", value = 1 },
            { label = "2", value = 2 },
            { label = "3", value = 3 },
            { label = "4", value = 4 },
        },
        default  = 3,
        save     = true,
        onChange = function(v) ms.setClickLevel(v) end,
    })
-- END --

-- Combat Warriors Macros --
    -- Macro Functions --
        -- Helper Variables & Functions --
            local QuickSlideSound = SoundLib .. "QuickSlide.wav"
            local JumpLowSound    = SoundLib .. "JumpLow.wav"
            local JumpHighSound   = SoundLib .. "JumpHigh.wav"
            local SlideSetupSound = SoundLib .. "SlideSetup.wav"
            local JumpNormalSound = SoundLib .. "JumpNormal.wav"
            local ThrowTrickSound = SoundLib .. "ThrowTrick.wav"
            local SpawnAltSound   = SoundLib .. "SpawnAlt.wav"


            local getD1 = function()
                local d1           = 52
                if clickLevel     == 4 then d1 = d1 + 30
                elseif clickLevel == 3 then d1 = d1 + 20
                elseif clickLevel == 2 then d1 = d1 + 10
                end
                return d1
            end

            local getD2 = function()
                local d2           = 63
                if clickLevel     == 4 then d2 = d2 + 20
                elseif clickLevel == 3 then d2 = d2 + 20
                elseif clickLevel == 2 then d2 = d2 + 10
                end
                return d2
            end

            local getD3 = function()
                local d3           = 52
                if clickLevel     == 4 then d3 = d3 + 30
                elseif clickLevel == 3 then d3 = d3 + 30
                elseif clickLevel == 2 then d3 = d3 + 10
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
                for i = 1, 3 do
                    ms.type("e")
                    ms.wait(2)
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
                if ms.modHeld("superThrow") then ThrowTrickFunction()
                else HighLeapAssistFunction() end
            end, {
                group   = "main",
                label   = "High Leap Assist",
                cooldown = 3200,
                default = {type="mouse", button=3},
            })

            ms.bind.define("jumpHigh",   HighLeapAssistFunction,  { sub="superJump",  label="Jump High",   mod="v"   })
            ms.bind.define("jumpLow",    HighLeapAssistFunction,  { sub="superJump",  label="Jump Low",    mod="x"   })
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
                for i = 1, 4 do
                    ms.type("e")
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
                    ms.wait(3000)
                end
                if not ThrowLow() then ThrowDefault() end
            end)

            ms.bind.define("superThrow", ThrowTrickFunction,      { sub="superJump",  label="Throw Trick", mod="alt" })
            ms.bind.define("throwLow",   ThrowTrickFunction,      { sub="superThrow", label="Throw Low",   mod="v"   })
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
                group   = "main",
                label   = "Swing Cancel",
                cooldown = 780,
                default = {type="mouse", button=4},
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
                default = {type="key", mods={"alt"}, key="escape"},
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
                ms.Mouse(Click, Left, WindowTL, 920, 680)
                ms.sound(QuickSlideSound, true)
                ms.wait(200)
            end)

            ms.bind.define("quickSG", QuickSlideFunction, {
                group   = "optional",
                label   = "Quick Slide",
                default = {type="key", mods={"alt"}, key="z"},
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
                ms.type("e")
                ms.wait(2)
                ms.type("e")
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
                ms.mouse(Move, Left, WindowTL, 0, 0)
                ms.type("z")
                ms.wait(200)
                for i = 1, 2 do
                    ms.mouse(Click, Left, WindowTL, 445, 37)
                    ms.wait(10)
                end
                ms.wait(20)
                for i = 1, 3 do
                    ms.mouse(Click, Left, WindowTL, 467, d1)
                    ms.wait(30)
                    ms.release("c")
                end
                for i = 1, 15 do
                    ms.mouse(Click, Left, WindowTL, 467, d2)
                    ms.wait(30)
                end
                ms.wait(400)
                ms.type("z")
                ms.wait(2000)
            end)

            ms.bind.define("sgSetup", SlideSetupFunction, {
                group   = "optional",
                label   = "Slide Setup",
                default = {type="key", mods={"alt"}, key="\\"},
            })
        -- END --

        -- Action Spammer --
            local ActionSpammerFunction = ms.fn(function()
                local d3 = getD3()
                ms.type("z")
                ms.wait(10)
                for i = 1, 1 do
                    ms.Mouse(Press, Left, WindowTL, 437, 34)
                    ms.wait(10)
                    ms.Mouse(Release, Left, WindowTL, 437, 34)
                    ms.wait(10)
                end
                ms.Mouse(Press, Left, WindowTL, 452, d3)
                ms.wait(10)
                ms.Mouse(Release, Left, WindowTL, 452, d3)
                ms.wait(10)
                while ms.keystate("=") do
                    ms.Mouse(Click, Left, Mouse, nil, nil)
                    ms.wait(15)
                end
                ms.wait(300)
                ms.Mouse(Release, Left, WindowTL, 840, 538)
                ms.type("z")
                ms.wait(60)
            end)


            ms.bind.define("frameDump", ActionSpammerFunction, {
                group   = "optional",
                label   = "Action Spammer",
                default = {type="key", mods={}, key="="},
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
                group   = "optional",
                label   = "Load Second Account",
                default = {type="key", mods={"alt"}, key="="},
                enabled = false,
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
                default = {type="key", mods={}, key="f8"},
            })
        -- END --
    -- END Macro Functions --
-- END Combat Warriors Macros --
