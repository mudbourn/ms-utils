# mudscript Utility Library — Windows Reference

> **Runtime:** `ms_core.ahk` — AutoHotkey v2 mirror of the `ms.*` API from `ms_core.lua`.  
> **Macro file:** your `.ahk` script — `#Include ms_core.ahk` at the top, then write macros using the same `ms.*` calls.

---

## 1. Overview

The Windows runtime mirrors the full `ms.*` API so that macro logic written for macOS can be ported with minimal changes. The runtime file is `ms_core.ahk`; include it at the top of your macro script.

Every macro file has the same four sections as `ms_macros.lua`:

```ahk
#Requires AutoHotkey v2.0
#Include ms_windows.ahk

; 1. Metadata (required)
ms.macroMeta := {name: "My Pack", author: "me"}

; 2. Pack settings — not supported on Windows (see end of this document)

; 3. Function definitions
MyFunction() {
    ms.press("w")
    ms.wait(50)
    ms.release("w")
}

; 4. Bind declarations
ms.bind.define("myMacro", MyFunction, {
    group:   "main",
    label:   "My Macro",
    default: {type: "key", mods: [], key: "f1"}
})
```

AHKv2 requires the `#Requires AutoHotkey v2.0` directive as the very first line of the file.

---

## 2. Key Differences from macOS

| Topic | macOS (Lua) | Windows (AHKv2) |
|-------|-------------|-----------------|
| `ms.fn()` wrapper | Required — wraps a function in a coroutine so `ms.wait` can yield | Identity wrapper — returns the function unchanged; safe to use but not needed |
| `ms.wait()` | Yields the current coroutine (non-blocking) | Calls `Sleep` — non-blocking per-hotkey because each hotkey runs in its own thread |
| `"cmd"` modifier | macOS ⌘ key | Maps to Ctrl — `ms.type("v", ["cmd"])` sends Ctrl+V |
| `ms.alert()` | Hammerspoon canvas toast in the corner | `ToolTip` in the top-left corner; auto-clears after `duration` seconds |
| `ms.cam` | Synthetic button-5 drag via `CGEventPostToPSN` | `SendInput` with `MOUSEEVENTF_MOVE` relative delta; game must be focused |
| `ms.mousePos()` | Returns two values `x, y` | Returns `[x, y]` array — use `pos[1]`, `pos[2]` |
| Hotkey registration | `ms.bind.define()` installs an `hs.hotkey` | `ms.bind.define()` calls `HotIfWinActive "ahk_exe RobloxPlayerBeta.exe"` then `Hotkey` — fires only when Roblox is the active window |
| `BindValidity` | Global integer; `0` disables all macros | Same — all hotkey handlers check `BindValidity = 1` before firing |

---

## 3. Macro File Structure

The same four sections as macOS, in the same order:

```ahk
#Requires AutoHotkey v2.0
#Include ms_windows.ahk

; ── Section 1: Metadata ──────────────────────────────────────────────────────
; Required. Used internally to identify the pack.
ms.macroMeta := {name: "My Macro Pack", author: "yourname"}

; ── Section 2: Pack settings ─────────────────────────────────────────────────
; ms.settings.define / ms.menu.define / ms.features.hide are macOS-only.
; Leave this section empty or omit it entirely on Windows.

; ── Section 3: Function definitions ──────────────────────────────────────────
; Plain AHKv2 functions — no ms.fn() wrapper required (though it is harmless).
MyFunction() {
    ms.press("space")
    ms.wait(100)
    ms.release("space")
}

QuickResetFn() {
    ms.type("r")
}

; ── Section 4: Bind declarations ─────────────────────────────────────────────
; Identical signature to macOS — hotkeys are registered automatically.
ms.bind.define("myMacro", MyFunction, {
    group:   "main",
    label:   "My Macro",
    default: {type: "mouse", button: 3}
})

ms.bind.define("quickReset", QuickResetFn, {
    group:   "optional",
    label:   "Quick Reset",
    default: {type: "key", mods: ["alt"], key: "r"}
})
```

---

## 4. Bind Declarations — `ms.bind.define`

```ahk
ms.bind.define(id, fn, opts)   ; preferred: function first, config last
ms.bind.define(id, opts, fn)   ; legacy order, still accepted
ms.bind.define(id, fn)         ; no opts
ms.bind.define(id, opts)       ; register without wiring a function
```

Both `fn` and `opts` are optional; types are detected automatically — identical to the macOS version.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Unique identifier for this macro. |
| `fn` | function | The function to call when the macro fires. |
| `opts` | object | Configuration object — all fields optional. |

### `opts` fields

| Field | Default | Description |
|-------|---------|-------------|
| `label` | auto | Display name. |
| `group` | `"main"` | `"main"` or `"optional"`. `""` / omitted = hidden. |
| `enabled` | `true` | Initial enabled state. |
| `cooldown` | `1000` | Fire-based lockout in ms. `0` = no cooldown. |
| `default` | — | Default keybind: `{type: "mouse", button: N}` or `{type: "key", mods: [...], key: "..."}` |
| `sub` | — | Parent macro `id`. Makes this a sub-item of that parent. |
| `mod` | — | Default modifier key for this sub-item (e.g. `"alt"`, `"v"`). |

### Examples

```ahk
; Root macro with a mouse bind
ms.bind.define("superJump", MyJumpFn, {
    group:    "main",
    label:    "High Leap Assist",
    default:  {type: "mouse", button: 3},
    cooldown: 1500
})

; Root macro with a key bind
ms.bind.define("quickReset", QuickResetFn, {
    group:   "optional",
    label:   "Quick Reset",
    default: {type: "key", mods: ["alt"], key: "escape"}
})

; Disabled by default
ms.bind.define("spawnAlt", SpawnAltFn, {
    group:   "optional",
    label:   "Load Second Account",
    default: {type: "key", mods: ["alt"], key: "="},
    enabled: false
})
```

`ms.fn()` is still valid — it is a no-op identity wrapper, so ported code that wraps functions in `ms.fn(...)` works without modification.

Sub-items work identically via `ms.isSub()` — see **Section 8**.

### Mouse button → AHKv2 hotkey mapping

| mudscript button | AHKv2 hotkey |
|------------------|--------------|
| `0` (Left) | `LButton` |
| `1` (Right) | `RButton` |
| `2` (Center) | `MButton` |
| `3` (Button4) | `XButton1` |
| `4` (Button5) | `XButton2` |

---

## 5. Keyboard — `ms.press`, `ms.release`, `ms.type`

### `ms.press(key, mods [, hidinject])`

Sends a key-down event. Does not send key-up.

```ahk
ms.press("w")
ms.press("shift")
ms.press("space")
ms.press("v", ["cmd"])    ; Ctrl+V down  (cmd maps to Ctrl)
```

### `ms.release(key, mods [, hidinject])`

Sends a key-up event.

```ahk
ms.release("w")
ms.release("shift")
```

### `ms.type(key, mods [, hidinject])`

Press + release in a single `SendInput` call. Use for single keystrokes.

```ahk
ms.type("e")
ms.type("space")
ms.type("escape")
ms.type("v", ["cmd"])    ; Ctrl+V tap
```

The `hidinject` parameter is accepted for API compatibility but has no effect on Windows — `SendInput` is used for all events.

### Key name translation

mudscript/Hammerspoon key names are translated automatically. Single letters (`"a"`–`"z"`) and digits (`"0"`–`"9"`) pass through unchanged.

| mudscript name | AHKv2 key |
|----------------|-----------|
| `"space"` | `Space` |
| `"return"` | `Enter` |
| `"escape"` | `Escape` |
| `"backspace"` | `Backspace` |
| `"delete"` | `Delete` |
| `"tab"` | `Tab` |
| `"left"` | `Left` |
| `"right"` | `Right` |
| `"up"` | `Up` |
| `"down"` | `Down` |
| `"home"` | `Home` |
| `"end"` | `End` |
| `"pageup"` | `PgUp` |
| `"pagedown"` | `PgDn` |
| `"insert"` | `Insert` |
| `"f1"`–`"f12"` | `F1`–`F12` |

### Modifier mapping

| mudscript mod | AHKv2 prefix | Note |
|---------------|--------------|------|
| `"shift"` | `+` | |
| `"ctrl"` | `^` | |
| `"alt"` | `!` | |
| `"cmd"` | `^` | macOS ⌘ maps to Ctrl |
| `"win"` | `#` | Windows key — no macOS equivalent |

---

## 6. Mouse — `ms.Mouse`

### `ms.Mouse(operation, button, reference [, Unscaled,] x1, y1 [, x2, y2])`

Unified, named-constant mouse API — identical signature to macOS. All reference constants (`WindowTL`, `Absolute`, `Mouse`, etc.) are declared as global variables and work the same way.

#### Operations (first argument)

| Constant | Description |
|----------|-------------|
| `Move` | Move cursor to the position. No click. |
| `Click` | Move then click (down + wait + up). |
| `DoubleClick` | Two clicks in quick succession. |
| `TripleClick` | Three clicks in quick succession. |
| `Drag` | Click-and-drag from `(x1,y1)` to `(x2,y2)`. |
| `Press` | Move to position then send mouse-down only. |
| `Release` | Send mouse-up at the position without moving. |

#### Buttons (second argument)

`Left`, `Right`, `Center`, `Button4`, `Button5`

#### References (third argument)

| Constant | Coordinate origin |
|----------|-------------------|
| `Absolute` | Raw screen pixels. |
| `Mouse` | Offset from current cursor position. |
| `WindowTL` | From Roblox window top-left. |
| `WindowTR` | From Roblox window top-right. |
| `WindowBL` | From Roblox window bottom-left. |
| `WindowBR` | From Roblox window bottom-right. |
| `WindowCenter` | From Roblox window center. |
| `ScreenTL` | Offset from screen top-left. |
| `ScreenTR` | Offset from screen top-right. |
| `ScreenBL` | Offset from screen bottom-left. |
| `ScreenBR` | Offset from screen bottom-right. |
| `ScreenCenter` | Offset from screen center. |

`Window*` references scale `(x, y)` through the 1680×1044 → actual window size transform by default. Pass the `Unscaled` flag between the reference and the first coordinate to use raw pixel offsets instead.

#### `Unscaled` flag

```ahk
ms.Mouse(Click, Left, WindowTL, 900, 660)             ; REF-space (scaled to window)
ms.Mouse(Click, Left, WindowTL, Unscaled, 445, 37)    ; raw pixels from window TL
```

#### Examples

```ahk
ms.Mouse(Click,       Left,  WindowTL,     900, 660)
ms.Mouse(Move,        Left,  Mouse,        0,   0)
ms.Mouse(Drag,        Left,  Absolute,     100, 100, 300, 300)
ms.Mouse(Press,       Left,  WindowTL,     Unscaled, 467, 52)
ms.Mouse(Release,     Right, WindowCenter, 0, 0)
ms.Mouse(DoubleClick, Left,  WindowTL,     840, 520)
```

### `ms.scroll(direction, clicks)`

```ahk
ms.scroll("up",   3)
ms.scroll("down", 3)
```

### `ms.resolvePoint(x, y, reference [, unscaled])`

Converts `(x, y)` in the given reference space to absolute screen coordinates. Mirrors `ms.resolvePoint()` from `ms_core.lua`.

```ahk
local pos := ms._resolve(900, 660, WindowTL)   ; {x: ..., y: ...}
```

---

## 7. Camera — `ms.cam`

### `ms.cam.move(dy, dx)`

Posts a single camera movement delta. Parameters match the macOS signature exactly — **vertical first, horizontal second**.

```ahk
ms.cam.move(0,    -3145)   ; pan up sharply
ms.cam.move(-60,  0)       ; pan left
ms.cam.move(0,    8)       ; nudge down
```

Internally builds a Windows `INPUT` structure and calls `DllCall("SendInput", ...)` with `MOUSEEVENTF_MOVE` (`0x0001`) to inject a relative mouse delta that Roblox reads as camera input. The game must be focused.

Both values are in Roblox sensitivity units; the engine scales them by `ms.cam._mult` to compensate for the user's configured sensitivity.

### Sensitivity

Set `CUR_CAM_SENS` to the user's in-game camera sensitivity, then call `ms.cam.updateMultiplier()`. The multiplier is computed as `REF_SENS / CUR_CAM_SENS`.

```ahk
CUR_CAM_SENS := 2.0
ms.cam.updateMultiplier()
```

`REF_SENS` defaults to `1.5` and should not normally be changed.

### Stub methods

The following methods exist for API compatibility so ported macOS code runs without modification, but they do nothing on Windows:

| Method | macOS behaviour |
|--------|----------------|
| `ms.cam.enable()` | Starts the camera engine |
| `ms.cam.disable()` | Stops the camera engine |
| `ms.cam.updateAnchor()` | Re-reads window frame and recalculates anchor |
| `ms.cam.scheduleUpdate()` | Debounced `updateAnchor` |

---

## 8. Sub-items

Sub-items work identically to macOS. `ms.isSub(id)` checks `GetKeyState` for the sub-item's configured modifier and self-clears on match, so only one variant fires per invocation. The same `if`/`else if` chain used on macOS works without modification.

```ahk
SuperJump() {
    if ms.isSub("jumpHigh") {
        ; high variant
        return
    }
    if ms.isSub("jumpLow") {
        ; low variant
        return
    }
    ; default
}

ms.bind.define("superJump", SuperJump, {
    group:   "main",
    label:   "Super Jump",
    default: {type: "mouse", button: 3}
})
ms.bind.define("jumpHigh", SuperJump, {sub: "superJump", label: "Jump High", mod: "v"})
ms.bind.define("jumpLow",  SuperJump, {sub: "superJump", label: "Jump Low",  mod: "x"})
```

### `ms.isSub(id)`

Returns `true` if sub-item `id` is the active variant — either because it was dispatched directly or because its modifier key is held. Clears the active-sub flag on match.

### `ms.getMod(id)`

Returns the configured modifier key string for sub-item `id`, or `""` if none is set.

### `ms.modHeld(id)`

Returns `true` if the modifier key configured for sub-item `id` is currently physically held.

---

## 9. Timing — `ms.wait`

```ahk
ms.wait(milliseconds)
```

Calls `Sleep ms_time`. AHKv2 runs each hotkey in its own independent thread, so a `Sleep` inside one hotkey does not block any other hotkey from firing — equivalent behaviour to Lua coroutine yielding on macOS.

```ahk
ms.wait(50)     ; 50 ms
ms.wait(1)      ; 1 ms
ms.wait(2000)   ; 2 seconds
```

Unlike macOS, sub-millisecond durations are not supported by `Sleep`; the minimum resolution is 1 ms.

---

## 10. Audio — `ms.sound`, `ms.playSlot`

### `ms.sound(path, async)`

Plays a sound file using `SoundPlay`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `path` | — | Absolute or relative path to the sound file. |
| `async` | `true` | `true` = play asynchronously (non-blocking). `false` = wait until playback finishes. |

Sound files should be placed in the `sounds\` folder next to the script, matching the macOS layout.

```ahk
ms.sound(A_ScriptDir "\sounds\alert.wav")
ms.sound(A_ScriptDir "\sounds\alert.wav", false)   ; blocking
```

### `ms.playSlot(slotId)`

Plays `sounds\<slotId>.wav` if the file exists. Mirrors the macOS slot system.

```ahk
ms.playSlot("jump")    ; plays sounds\jump.wav
ms.playSlot("reset")   ; plays sounds\reset.wav
```

---

## 11. State Queries

### `ms.keystate(key)`

Returns `true` if the key is currently physically held.

```ahk
ms.keystate("shift")
ms.keystate("w")
```

Wraps `GetKeyState(key, "P")` with the same key-name translation as `ms.press`.

### `ms.app()`

Returns the title of the currently active window. Wraps `WinGetTitle("A")`.

```ahk
if InStr(ms.app(), "Roblox")
    ; ...
```

### `ms.mousePos()`

Returns the cursor position in 1680×1044 reference-space coordinates relative to the Roblox window. Returns a **two-element array** `[x, y]` — unlike macOS which returns two separate values.

```ahk
local pos := ms.mousePos()
ms.alert(Format("Mouse: {:.0f}, {:.0f}", pos[1], pos[2]), 3)
```

> **Porting note:** `local x, y := ms.mousePos()` (multi-return) is not valid AHKv2. Use `local pos := ms.mousePos()` then `pos[1]`, `pos[2]`.

### `ms.alert(msg [, duration [, noSound]])`

Shows a `ToolTip` in the top-left corner of the screen. Auto-clears after `duration` seconds (default `3`). The `noSound` parameter is accepted for API compatibility but has no effect.

```ahk
ms.alert("Macro enabled")
ms.alert("Cooldown active", 1.5)
```

---

## 12. Macro Control

### `BindValidity`

Global integer. `1` = macros active; `0` = macros disabled. All hotkey handlers inserted by `ms.bind.define` check `BindValidity = 1` before calling the macro function. Set to `0` to globally disable all macros without unregistering the hotkeys.

```ahk
BindValidity := 0   ; disable all macros
BindValidity := 1   ; re-enable
```

---

## 13. Porting Checklist

Use this checklist when converting a Lua macro file to AHKv2:

- [ ] Add `#Requires AutoHotkey v2.0` and `#Include ms_windows.ahk` at the top
- [ ] Change `ms.macroMeta = {...}` (Lua) to `ms.macroMeta := {...}` (AHKv2)
- [ ] Change `local f = ms.fn(function() ... end)` to a plain named function `f() { ... }` — or keep `ms.fn()` as-is; it is a no-op
- [ ] `ms.wait(...)` calls are unchanged
- [ ] All `"cmd"` modifiers are unchanged — they map to Ctrl automatically
- [ ] `ms.type("v", {"cmd"})` (Lua) → `ms.type("v", ["cmd"])` (AHKv2 array literal) — the behaviour is identical (Ctrl+V)
- [ ] `ms.bind.define(...)` is unchanged — hotkeys auto-register for Roblox
- [ ] `ms.isSub(...)` is unchanged
- [ ] Multi-return `local x, y = ms.mousePos()` → `local pos := ms.mousePos()` then `pos[1]`, `pos[2]`
- [ ] `string.format(...)` → `Format(...)` in AHKv2
- [ ] `string.find(str, pat)` → `InStr(str, pat)` in AHKv2
- [ ] Lua `print(...)` → `OutputDebug(...)` or `ToolTip(...)` in AHKv2
- [ ] Lua table constructors `{ key = value }` → AHKv2 object literals `{key: value}`
- [ ] Lua arrays `{ 1, 2, 3 }` → AHKv2 arrays `[1, 2, 3]`

---

> **macOS-only features:** `ms.settings.define`, `ms.menu.define`, `ms.features.hide`, profiles, `.mspkg` packages, the Settings panel, the theme system, integrity checks, and `ms.dev` developer tools are all macOS-only and have no equivalent in this runtime. Remove or comment out any calls to these APIs when porting.

---

*Last updated: 2026-06-21*
