; ms_macros.ahk — Combat Warriors macro pack (Windows / AHKv2)
; Direct port of ms_macros.lua. Included by ms_core.ahk after initialisation.
; Do NOT add #Requires or #Include at the top of this file.

; ── Creator Credits ───────────────────────────────────────────────────────────
ms.macroMeta := {
    name:    "Combat Warriors Macros",
    author:  "mudbourn",
    website: "https://mudbourn.info",
}

; ── Pack Settings ─────────────────────────────────────────────────────────────
ms.settings.define({
    key:     "clickLevel",
    label:   "Click Method",
    hint:    "Switches the method used to perform click sequences",
    type:    "seg",
    options: [
        {label: "1", value: 1},
        {label: "2", value: 2},
        {label: "3", value: 3},
        {label: "4", value: 4},
    ],
    default:  3,
    save:     true,
    onChange: (v) => ms.setClickLevel(v),
})

; ── Helper Variables ──────────────────────────────────────────────────────────
; SoundLib is a super-global set by ms_core.ahk.
global QuickSlideSound := SoundLib . "QuickSlide.wav"
global JumpLowSound    := SoundLib . "JumpLow.wav"
global JumpHighSound   := SoundLib . "JumpHigh.wav"
global SlideSetupSound := SoundLib . "SlideSetup.wav"
global JumpNormalSound := SoundLib . "JumpNormal.wav"
global ThrowTrickSound := SoundLib . "ThrowTrick.wav"
global SpawnAltSound   := SoundLib . "SpawnAlt.wav"

; ── Click-level timing helpers ────────────────────────────────────────────────
; clickLevel is a super-global set by ms_core.ahk (default 3).
getD1() {
    local d1 := 52
    if clickLevel = 4
        d1 += 30
    else if clickLevel = 3
        d1 += 20
    else if clickLevel = 2
        d1 += 10
    return d1
}

getD2() {
    local d2 := 63
    if clickLevel = 4
        d2 += 20
    else if clickLevel = 3
        d2 += 20
    else if clickLevel = 2
        d2 += 10
    return d2
}

getD3() {
    local d3 := 52
    if clickLevel = 4
        d3 += 30
    else if clickLevel = 3
        d3 += 30
    else if clickLevel = 2
        d3 += 10
    return d3
}

; ── High Leap Assist — internal helpers ───────────────────────────────────────
; These are extracted from the Lua nested-function scope; sound constants are
; super-globals declared above.

_HL_JumpHigh() {
    if ms.isSub("jumpHigh") {
        ms.sound(JumpHighSound, true)
        Loop 60 {
            ms.cam.move(0, -3145)
            ms.wait(1)
            ms.cam.move(0, -3145)
            ms.wait(0.5)
        }
        ms.wait(50)
        ms.cam.move(0, 262)
        return true
    }
    return false
}

_HL_JumpLow() {
    if ms.isSub("jumpLow") {
        ms.sound(JumpLowSound, true)
        Loop 14 {
            ms.cam.move(0, -370)
            ms.wait(1)
            ms.cam.move(0, -370)
            ms.wait(0.5)
        }
        ms.wait(50)
        ms.cam.move(0, 308)
        return true
    }
    return false
}

_HL_JumpDefault() {
    ms.sound(JumpNormalSound, true)
    Loop 14 {
        ms.cam.move(0, -185)
        ms.wait(1)
        ms.cam.move(0, -185)
        ms.wait(0.5)
    }
    ms.wait(50)
    ms.cam.move(0, -69)
}

; ── High Leap Assist ──────────────────────────────────────────────────────────
HighLeapAssistFunction() {
    local MovingCheck := ms.keystate("w") || ms.keystate("a") || ms.keystate("s") || ms.keystate("d")
    if !MovingCheck {
        ms.press("w")
        ms.wait(10)
    }
    Loop 3 {
        ms.type("e")
        ms.wait(2)
    }
    ms.wait(30)
    Loop 2
        ms.type("space")
    ms.wait(10)
    if !_HL_JumpHigh() {
        if !_HL_JumpLow()
            _HL_JumpDefault()
    }
    ms.release("space")
    ms.wait(100)
    if !MovingCheck
        ms.release("w")
    ms.wait(20)
    ms.wait(600)
}

_superJump_fn() {
    if ms.modHeld("superThrow")
        ThrowTrickFunction()
    else
        HighLeapAssistFunction()
}

ms.bind.define("superJump", _superJump_fn, {
    group:    "main",
    label:    "High Leap Assist",
    cooldown: 3200,
    default:  {type: "mouse", button: 3},
})
ms.bind.define("jumpHigh", HighLeapAssistFunction, {sub: "superJump",  label: "Jump High", mod: "v"})
ms.bind.define("jumpLow",  HighLeapAssistFunction, {sub: "superJump",  label: "Jump Low",  mod: "x"})

; ── Throw Trick — internal helpers ────────────────────────────────────────────
; MovingCheck is passed in because it was an outer-scope local in the Lua version.

_TT_ThrowLow(MovingCheck) {
    if ms.isSub("throwLow") {
        Loop 15 {
            ms.cam.move(0, -400)
            ms.wait(1)
            ms.cam.move(0, -400)
            ms.wait(1)
        }
        Loop 30 {
            ms.cam.move(0, 8)
            ms.wait(1)
            ms.cam.move(0, 8)
            ms.wait(0.5)
        }
        Loop 180 {
            ms.release("x")
            ms.cam.move(0, 8)
            ms.wait(1)
            ms.cam.move(0, 8)
            ms.wait(1)
        }
        ms.wait(5)
        ms.release("space")
        ms.wait(100)
        if !MovingCheck
            ms.release("w")
        ms.wait(20)
        if !ms.keystate("shift")
            ms.release("shift")
        ms.scroll("down", 2000)
        ms.wait(3000)
        return true
    }
    return false
}

_TT_ThrowDefault(MovingCheck) {
    Loop 60 {
        ms.cam.move(0, -3145)
        ms.wait(2)
        ms.cam.move(0, -3145)
        ms.wait(2)
    }
    Loop 150 {
        ms.cam.move(0, 8)
        ms.wait(1)
        ms.cam.move(0, 8)
        ms.wait(0.5)
    }
    Loop 180 {
        ms.release("x")
        ms.cam.move(0, 10)
        ms.wait(1)
        ms.cam.move(0, 9)
        ms.wait(1)
    }
    ms.wait(5)
    ms.release("space")
    ms.wait(20)
    if !MovingCheck
        ms.release("w")
    ms.wait(20)
    ms.scroll("down", 2000)
    ms.wait(3000)
}

; ── Throw Trick ───────────────────────────────────────────────────────────────
ThrowTrickFunction() {
    ms.sound(ThrowTrickSound, true)
    ms.press("x")
    Loop 5 {
        ms.cam.move(-60, 0)
        ms.wait(1)
    }
    ms.wait(50)
    Loop 4 {
        ms.cam.move(16, 0)
        ms.wait(1)
    }
    ms.scroll("up", 2000)
    local MovingCheck := ms.keystate("w") || ms.keystate("a") || ms.keystate("s") || ms.keystate("d")
    if !MovingCheck {
        ms.press("w")
        ms.wait(10)
    }
    Loop 4
        ms.type("e")
    ms.wait(30)
    Loop 2
        ms.type("space")
    ms.wait(50)
    if !_TT_ThrowLow(MovingCheck)
        _TT_ThrowDefault(MovingCheck)
}

ms.bind.define("superThrow", ThrowTrickFunction, {sub: "superJump",  label: "Throw Trick", mod: "alt"})
ms.bind.define("throwLow",   ThrowTrickFunction, {sub: "superThrow", label: "Throw Low",   mod: "v"})

; ── Swing Cancel ──────────────────────────────────────────────────────────────
FakeSwingFunction() {
    ms.Mouse(Click, Left, Mouse, 0, 0)
    ms.wait(99)
    ms.type("5")
    ms.wait(5)
    ms.type("1")
    ms.wait(500)
}

_fakeSwing_fn() {
    if InStr(ms.app(), "Roblox")
        FakeSwingFunction()
}

ms.bind.define("fakeSwing", _fakeSwing_fn, {
    group:    "main",
    label:    "Swing Cancel",
    cooldown: 780,
    default:  {type: "mouse", button: 4},
})

; ── Quick Reset ───────────────────────────────────────────────────────────────
QuickResetFunction() {
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
    Loop 20 {
        ms.press("space")
        ms.wait(100)
    }
    ; ms.press("space")
    ; ms.wait(2000)
    ms.release("space")
}

ms.bind.define("quickReset", QuickResetFunction, {
    group:   "optional",
    label:   "Quick Reset",
    default: {type: "key", key: "escape", mods: ["alt"]},
})

; ── Quick Slide ───────────────────────────────────────────────────────────────
QuickSlideFunction() {
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
}

ms.bind.define("quickSG", QuickSlideFunction, {
    group:   "optional",
    label:   "Quick Slide",
    default: {type: "key", key: "z", mods: ["alt"]},
})

; ── Slide Setup ───────────────────────────────────────────────────────────────
SlideSetupFunction() {
    ms.sound(SlideSetupSound, true)
    local d1 := getD1()
    local d2 := getD2()
    ms.press("shift")
    ms.press("w")
    ms.press("space")
    ms.wait(15)
    ms.type("e")
    ms.wait(2)
    ms.type("e")
    ms.wait(15)
    Loop 14 {       ; Lua: for i = 2, 15 (14 iterations)
        ms.cam.move(1, -245)
        ms.wait(1)
        ms.cam.move(-1, -245)
        ms.wait(1)
    }
    ms.wait(30)
    ms.release("w")
    ms.release("shift")
    ms.release("space")
    ms.wait(5)
    ms.press("c")
    ms.Mouse(Move, Left, WindowTL, 0, 0)
    ms.type("z")
    ms.wait(200)
    Loop 2 {
        ms.Mouse(Click, Left, WindowTL, 445, 37)
        ms.wait(10)
    }
    ms.wait(20)
    Loop 3 {
        ms.Mouse(Click, Left, WindowTL, 467, d1)
        ms.wait(30)
        ms.release("c")
    }
    Loop 15 {
        ms.Mouse(Click, Left, WindowTL, 467, d2)
        ms.wait(30)
    }
    ms.wait(400)
    ms.type("z")
    ms.wait(2000)
}

ms.bind.define("sgSetup", SlideSetupFunction, {
    group:   "optional",
    label:   "Slide Setup",
    default: {type: "key", key: "\\", mods: ["alt"]},
})

; ── Action Spammer (Lag Simulator / Micro Profiler) ───────────────────────────
ActionSpammerFunction() {
    local d3 := getD3()
    ms.type("z")
    ms.wait(10)
    ms.Mouse(Move, Left, WindowTL, 437, 34)
    ms.wait(100)
    ms.Mouse(Click, Left, WindowTL, 452, d3)
    ms.wait(50)
    while ms.keystate("=") {
        ms.Mouse(Click, Left, Mouse, 0, 0)
        ms.wait(15)
    }
    ms.wait(150)
    ms.type("z")
    ms.wait(60)
}

_frameDump_fn() {
    ; ms._currentFlags is set by the bind dispatcher with active modifier state.
    if ms._currentFlags && ms._currentFlags.alt
        SpawnAltFunction()
    else
        ActionSpammerFunction()
}

ms.bind.define("frameDump", _frameDump_fn, {
    group:   "optional",
    label:   "Lag Simulator (Micro Profiler)",
    default: {type: "key", key: "=", mods: []},
})

; ── Load Second Account (Private Server, requires PSCMDS) ────────────────────
SpawnAltFunction() {
    local t := 100
    ms.sound(SpawnAltSound, true)
    ms.type("/")
    ms.wait(t)
    ms.copy("/spawn l")
    ms.wait(t)
    ms.type("v", ["cmd"])
    ms.wait(t)
    ms.type("return")
    ms.type("/")
    ms.wait(t)
    ms.copy("/tp l m")
    ms.wait(t)
    ms.type("v", ["cmd"])
    ms.wait(t)
    ms.type("return")
    ms.type("/")
    ms.wait(t)
    ms.copy("/health l 64")
    ms.wait(t)
    ms.type("v", ["cmd"])
    ms.wait(t)
    ms.type("return")
    ms.type("/")
    ms.wait(t)
    ms.copy("/health m 1015")
    ms.wait(t)
    ms.type("v", ["cmd"])
    ms.wait(t)
    ms.type("return")
}

ms.bind.define("spawnAlt", SpawnAltFunction, {sub: "frameDump", label: "Load Second Account", mod: "alt"})

; ── Mouse Position Grabber ────────────────────────────────────────────────────
_mousePos_fn() {
    local pos := ms.mousePos()     ; returns [relX, relY]
    ms.alert(Format("Mouse: {:.0f}, {:.0f}", pos[1], pos[2]), 3)
    OutputDebug Format("Mouse position: {:.0f}, {:.0f}", pos[1], pos[2])
}

ms.bind.define("mousePos", _mousePos_fn, {
    group:   "optional",
    label:   "Get Mouse Position",
    default: {type: "key", key: "f8", mods: []},
})
