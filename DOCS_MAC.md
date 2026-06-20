# mudscript Utility Library — Reference

> **Scope:** everything exposed through the `ms` table and related globals in `init.lua`.  
> **Macro file:** `ms_macros.lua` — loaded automatically on every reload; the only file you normally edit.

---

## Table of Contents

1. [Macro File Structure](#1-macro-file-structure)
2. [Declaring Macros — `ms.bind.define`](#2-declaring-macros--msbinddefine)
3. [Sub-item System](#3-sub-item-system)
4. [Wrapping Functions — `ms.fn`](#4-wrapping-functions--msfn)
5. [Keyboard Actions](#5-keyboard-actions)
6. [Mouse Actions](#6-mouse-actions)
7. [Camera Engine — `ms.cam`](#7-camera-engine--mscam)
8. [Timing — `ms.wait`](#8-timing--mswait)
9. [State Queries](#9-state-queries)
10. [Macro Control](#10-macro-control)
11. [Cooldown Helpers](#11-cooldown-helpers)
12. [Audio — `ms.sound`](#12-audio--mssound)
13. [Settings & Defaults](#13-settings--defaults)
14. [SOCD Engine](#14-socd-engine)
15. [Trackpad / Pen Mode](#15-trackpad--pen-mode)
16. [Profiles](#16-profiles)
17. [Utility Functions](#17-utility-functions)
18. [Global Hotkeys](#18-global-hotkeys)
19. [Global Constants](#19-global-constants)
20. [Integrity & Updates](#20-integrity--updates)

---

## 1. Macro File Structure

`ms_macros.lua` has three sections, in order:

```lua
-- 1. Metadata (required for profiles)
ms.macroMeta = {
    name    = "My Macro Pack",   -- used as the profile folder name
    author  = "yourname",
    website = "https://...",
}

-- 2. Preferred defaults (optional)
ms.macroDefaults = {
    sensitivity  = 1.5,
    frameLevel   = 3,
    trackpadMode = false,
    socdEnabled  = false,
    socdMode     = "lastWins",
    macros = {
        myMacro = { enabled = false },
    },
}

-- 3. Function definitions + ms.bind.define calls
local MyFunction = ms.fn(function()
    -- ...
end)

ms.bind.define("myMacro", MyFunction, { group="main", label="My Macro" })
```

`ms.macroDefaults` seeds `ms_settings_default.json` the first time there is no default file.  
Values already saved in `ms_settings.json` always take priority and are never overwritten.

---

## 2. Declaring Macros — `ms.bind.define`

```lua
ms.bind.define(id, fn, opts)   -- preferred: function first, config last
ms.bind.define(id, opts, fn)   -- legacy order, still accepted
ms.bind.define(id, fn)         -- no opts
ms.bind.define(id, opts)       -- register without wiring a function
```

Both `fn` and `opts` are optional; types are detected automatically.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Unique identifier for this macro. Used in all API calls. |
| `fn` | function | The function to run when the macro fires. Wrap with `ms.fn()` if it uses `ms.wait`. |
| `opts` | table | Configuration table — all fields optional. |

### `opts` fields

| Field | Default | Description |
|-------|---------|-------------|
| `label` | auto ("Macro1", "Macro2", …) | Display name in the Settings menu. |
| `group` | `"main"` | `"main"` or `"optional"` appear in the menu. `nil` = hidden. |
| `enabled` | `true` | Initial enabled state. |
| `cooldown` | `1000` | Fire-based lockout in ms. Shared across the entire sub-item family. `0` = no cooldown. |
| `default` | `nil` | Default keybind: `{type="mouse", button=N}` or `{type="key", mods={…}, key="…"}` |
| `sub` | `nil` | Parent macro `id`. Makes this a sub-item of that parent. Parent must be defined first. |
| `mod` | `nil` | Default modifier key for this sub-item (e.g. `"alt"`, `"v"`). |
| `shared` | `nil` | Explicit cooldown group key. Overrides the auto-derived `"G_<rootId>"`. |
| `info` | `nil` | Description string written to `ms_macro_info.txt` (Settings › Macro Info). |

### Examples

```lua
-- Root macro with a mouse bind
ms.bind.define("superJump", myJumpFn, {
    group   = "main",
    label   = "High Leap Assist",
    default = {type="mouse", button=3},
    cooldown = 1500,
})

-- Root macro with a key bind
ms.bind.define("quickReset", QuickResetFunction, {
    group   = "optional",
    label   = "Quick Reset",
    default = {type="key", mods={"alt"}, key="escape"},
})

-- Disabled by default
ms.bind.define("spawnAlt", SpawnAltFunction, {
    group   = "optional",
    label   = "Load Second Account",
    default = {type="key", mods={"alt"}, key="="},
    enabled = false,
})
```

---

## 3. Sub-item System

Sub-items let a single root bind dispatch to different variants depending on which modifier key is held at fire time.

### Defining sub-items

```lua
-- Root bind (must be defined first)
ms.bind.define("superJump", function()
    if ms.modHeld("superThrow") then ThrowTrickFunction()
    else HighLeapAssistFunction() end
end, { group="main", label="High Leap Assist", default={type="mouse", button=3} })

-- Sub-items — fire when parent fires and their mod key is held
ms.bind.define("superThrow", ThrowTrickFunction, { sub="superJump", label="Throw Trick", mod="alt" })
ms.bind.define("jumpHigh",   HighLeapAssistFunction, { sub="superJump", label="Jump High", mod="v" })
ms.bind.define("jumpLow",    HighLeapAssistFunction, { sub="superJump", label="Jump Low",  mod="x" })
```

### Checking which sub-item should run — inside a function

```lua
-- ms.modHeld(id) — true if the sub-item's modifier is currently held
if ms.modHeld("superThrow") then ... end

-- ms.isSub(id) — true if this specific sub-item is the active one
--   Self-clears on match, so only one variant fires per call sequence.
--   Handles both modifier-key routing and independent-bind routing.
local function myFn()
    if ms.isSub("jumpHigh") then
        -- do high jump
        return true
    end
    if ms.isSub("jumpLow") then
        -- do low jump
        return true
    end
    -- default behavior
end
```

### Independent binds

When **Settings › Keybinds › Independent Binds** is enabled, sub-items can also have their own dedicated keybind configured from the menu. They then fire that sub-item directly, bypassing the parent's modifier check.

### `ms.getMod(id)`

Returns the active modifier key for a sub-item — the user-configured value from `ms.modConfig`, or the code default from `opts.mod`, or `nil`.

---

## 4. Wrapping Functions — `ms.fn`

```lua
local MyFunction = ms.fn(fn)
local MyFunction = ms.fn(fn, false)  -- skip wrap (synchronous)
```

Wraps `fn` so it always runs inside a coroutine. Required for any function that calls `ms.wait`. Without it, `ms.wait` falls back to a blocking `usleep`.

```lua
local ThrowTrickFunction = ms.fn(function()
    ms.press("x")
    ms.wait(50)
    ms.release("x")
end)
```

Pass `false` as the second argument to skip wrapping (rarely needed).

**Cancellation:** every `ms.fn` coroutine is tracked. Calling `ms.cancelMacros()` — which happens automatically on every `ms.setMacros(0)` — marks all live coroutines as cancelled and prevents any pending `ms.wait` or `ms.sound` callbacks from resuming them. Keys and mouse buttons held at the time are released automatically.

---

## 5. Keyboard Actions

### `ms.press(key, mods [, hidinject])`

Sends a key-down event. Does not send key-up.

```lua
ms.press("w")
ms.press("shift")
ms.press("space")
ms.press("v", {"cmd"})        -- Cmd+V down
ms.press("w", {}, true)       -- HID-injected directly to Roblox
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `key` | string/number | — | Key name or numeric keycode. |
| `mods` | table | `{}` | Modifier keys, e.g. `{"cmd", "shift"}`. |
| `hidinject` | bool | `false` | Post directly to the Roblox process via `CGEventPostToPSN` instead of the global session event stream. Bypasses all other event taps including the SOCD engine. |

**Key names:** any single character, or named keys: `"space"`, `"escape"`, `"return"`, `"tab"`, `"left"`, `"right"`, `"up"`, `"down"`, `"shift"`, `"ctrl"`, `"alt"`, `"cmd"`, `"f1"`–`"f12"`. Numeric keycodes are also accepted.

---

### `ms.release(key, mods [, hidinject])`

Sends a key-up event.

```lua
ms.release("w")
ms.release("shift")
ms.release("w", {}, true)     -- HID-injected
```

Same parameters as `ms.press`.

---

### `ms.type(key, mods [, hidinject])`

Press + 15 ms wait + release. Use for single keystrokes.

```lua
ms.type("e")
ms.type("space")
ms.type("escape")
ms.type("v", {"cmd"})         -- Cmd+V tap
ms.type("e", {}, true)        -- HID-injected tap
```

---

### `ms.key(mods, key, swallow, pressFn, releaseFn)`

Registers a persistent keybind listener. Returns a handle with a `delete()` method.

| Parameter | Type | Description |
|-----------|------|-------------|
| `mods` | table | Modifier keys, e.g. `{"alt", "shift"}`. |
| `key` | string/number | Key name or keycode. |
| `swallow` | bool | `true` = consume the event (Roblox never sees it). |
| `pressFn` | function | Called on key-down. |
| `releaseFn` | function | Called on key-up. Optional. |

```lua
local handle = ms.key({"alt"}, "z", true, function()
    -- fires on alt+z down
end)

-- later, to unregister:
handle:delete()
```

Macro binds registered through `ms.bind.define` use this internally; you rarely need to call it directly.

---

### `ms.copy(text)`

Sets the system clipboard contents.

```lua
ms.copy("/spawn l")
ms.type("v", {"cmd"})   -- paste
```

---

## 6. Mouse Actions

### `ms.Mouse(operation, button, reference [, Unscaled,] x1, y1 [, x2, y2 [, hidinject]])`

Unified, named-constant mouse API. All arguments are validated at call time — typos error immediately.

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

`Window*` references scale `(x, y)` through the 1680×1044 → actual window size transform by default. Pass the `Unscaled` flag to use raw pixel offsets instead (see below).

#### `Unscaled` flag (optional, between reference and coordinates)

Pass the global constant `Unscaled` between the reference and the first coordinate to treat `(x, y)` as raw pixel offsets from the reference origin rather than REF-space scaled values. Only affects `Window*` references; ignored for `Absolute`, `Mouse`, and `Screen*`.

```lua
ms.Mouse(Click, Left, WindowTL, 900, 660)             -- REF-space (scaled to window)
ms.Mouse(Click, Left, WindowTL, Unscaled, 445, 37)    -- raw pixels from window TL
```

#### `hidinject` (optional, last argument)

Pass `true` as the final argument to inject events directly to the Roblox process via `CGEventPostToPSN` instead of the global session stream.

```lua
ms.Mouse(Click,   Left,  WindowTL, 900, 660)
ms.Mouse(Move,    Left,  Mouse,    0,   0)
ms.Mouse(Drag,    Left,  Absolute, 100, 100, 300, 300)
ms.Mouse(Press,   Left,  WindowTL, Unscaled, 467, 52)
ms.Mouse(Release, Right, WindowCenter, 0, 0)
ms.Mouse(Click,   Left,  WindowTL, 900, 660, nil, nil, true)   -- hidinject
```

---

### `ms.mouse(button, swallow, clickFn [, hidinject])`

Registers a persistent mouse-button listener. When the specified button is clicked, `clickFn` is called inside a coroutine.

| Parameter | Type | Description |
|-----------|------|-------------|
| `button` | number | Button number: `0` = left, `1` = right, `2+` = other. |
| `swallow` | bool | `true` = consume the click (Roblox never sees it). |
| `clickFn` | function | Called when the button fires. |
| `hidinject` | bool | When `swallow = true` and `hidinject = true`, the event is re-injected directly to the Roblox process after being consumed from the global stream. |

```lua
ms.mouse(0, true, function()
    -- fires on left-click
end)

-- Swallow the click but re-deliver it to Roblox via HID path:
ms.mouse(1, true, function()
    -- fires on right-click
end, true)
```

---

### `ms.scroll(direction, clicks)`

Posts a scroll event at the current cursor position.

```lua
ms.scroll("up",    2000)
ms.scroll("down",  2000)
ms.scroll("left",  5)
ms.scroll("right", 5)
```

---

### `ms.resolvePoint(x, y, reference [, unscaled])`

Converts `(x, y)` in the given reference space to absolute screen coordinates. Used internally by `ms.Mouse` and `ms.pixelColor`. Useful when you need the resolved position for other purposes.

```lua
local ax, ay = ms.resolvePoint(900, 660, WindowTL)
local ax, ay = ms.resolvePoint(445, 37,  WindowTL, true)   -- unscaled
```

---

## 7. Camera Engine — `ms.cam`

The camera engine drives Roblox's camera using synthetic button-5 drag events, bypassing the user's mouse entirely. All macros that move the camera use this.

### `ms.cam.move(dy, dx)`

Post a single camera drag delta. Both values are in Roblox sensitivity units; the engine scales them by `cachedMult` to compensate for the user's configured sensitivity.

```lua
ms.cam.move(0,    -3145)   -- pan up sharply
ms.cam.move(-60,  0)       -- pan left
ms.cam.move(0,    8)       -- nudge down
```

Note: parameters are `(dy, dx)` — **vertical first, horizontal second**.

---

### `ms.cam.enable()` / `ms.cam.disable()`

Start or stop the camera engine. Called automatically by the app watcher when Roblox is focused/unfocused. You should not need to call these manually.

---

### `ms.cam.updateAnchor()`

Re-reads the Roblox window frame and recalculates the anchor point (window center) and the sensitivity multiplier. Called automatically on window move/resize. Can be called manually if camera moves are going to the wrong position.

---

### `ms.cam.updateMultiplier()`

Recalculates `ms.cam.cachedMult` from `CUR_CAM_SENS` and `REF_SENS`. Called automatically after sensitivity changes.

---

### `ms.cam.scheduleUpdate()`

Debounced `updateAnchor` — waits 0.5 s before calling it. Used by the UI watcher to avoid rapid recalculation during window resize animations.

---

## 8. Timing — `ms.wait`

```lua
ms.wait(milliseconds)
```

Yields the current coroutine for the given duration, then resumes. Non-blocking — the Hammerspoon event loop continues running while waiting.

```lua
ms.wait(50)    -- 50 ms
ms.wait(1)     -- 1 ms (minimum resolution ~1 ms)
ms.wait(0.5)   -- sub-millisecond durations accepted
ms.wait(2000)  -- 2 seconds
```

Must be called from a coroutine context (i.e. inside an `ms.fn`-wrapped function). Outside a coroutine it falls back to a blocking `usleep`.

---

## 9. State Queries

### `ms.keystate(key [, ...])`

Returns `true` if any of the named keys are currently held, according to the live key-tracking table.

```lua
ms.keystate("shift")
ms.keystate("w")
ms.keystate("w", "a", "s", "d")   -- true if any movement key is held
```

Pass `true` as the second argument to treat the first argument as a raw keycode:

```lua
ms.keystate(56, true)   -- checks shift by keycode
```

---

### `ms.app()`

Returns the name of the frontmost application.

```lua
if string.find(ms.app(), "Roblox") then ... end
```

---

### `ms.mousePos()`

Returns the cursor position in 1680×1044 reference-space coordinates relative to the Roblox window. Returns raw screen coordinates if Roblox is not found.

```lua
local x, y = ms.mousePos()
ms.alert(string.format("Mouse: %.0f, %.0f", x, y), 3)
```

---

### `ms.modHeld(id)`

Returns `true` if the modifier key configured for sub-item `id` is currently held.

```lua
if ms.modHeld("superThrow") then ThrowTrickFunction() end
```

---

### `ms.isSub(id)`

Returns `true` if sub-item `id` is the active variant for this invocation — either because it was fired by an independent bind, or because its modifier key is held. Self-clears on match.

```lua
if ms.isSub("jumpHigh") then
    -- high jump path
    return true
end
```

---

### `ms.getMod(id)`

Returns the active modifier key string for sub-item `id`, or `nil` if none is configured.

```lua
local mod = ms.getMod("superThrow")  -- e.g. "alt"
```

---

### `ms.getRobloxWin()`

Returns the main Roblox `hs.window` object, or `nil` if Roblox is not running.

---

### `ms.winCenter()`

Returns `(x, y)` screen coordinates of the center of the Roblox window (falls back to focused window).

---

### `ms.getScaled(targetX, targetY)`

Converts a 1680×1044 reference-space coordinate to absolute screen pixels, accounting for the actual Roblox window size and position.

```lua
local sx, sy = ms.getScaled(900, 660)
```

---

### `ms.pixelColor(x, y [, reference])`

Returns the colour of a single screen pixel at `(x, y)` in the given reference space. Uses the same coordinate system as `ms.Mouse`. `reference` defaults to `Absolute` if omitted.

Returns a table `{ r, g, b, a }` with integer values in `[0, 255]`, or `nil` if the position is off-screen or the capture fails.

```lua
local c = ms.pixelColor(900, 540, WindowTL)
if c then
    print(c.r, c.g, c.b)   -- e.g. 255  80  0
end

-- At absolute screen coordinates:
local c = ms.pixelColor(1200, 400)
```

---

### `ms.pixelMatch(x, y, reference, r, g, b [, tolerance])`

Returns `true` if the pixel at `(x, y)` is within `tolerance` of the target colour on every channel. `tolerance` defaults to `10`; all values are `[0, 255]`.

```lua
-- Is the pixel at WindowTL (900, 540) roughly orange?
if ms.pixelMatch(900, 540, WindowTL, 255, 80, 0) then
    -- ...
end

-- Tighter match for a specific UI element:
if ms.pixelMatch(445, 37, WindowTL, 12, 200, 64, 5) then
    -- ...
end
```

---

## 10. Macro Control

### `BindValidity`

Global integer. `1` = macros active; `0` = macros disabled. All bind handlers check this before firing.

---

### `ms.setMacros(state [, silent])`

```lua
ms.setMacros(1)          -- enable
ms.setMacros(0)          -- disable + show alert
ms.setMacros(0, true)    -- disable silently
```

Enabling starts the camera engine. Disabling calls `ms.cancelMacros()`, clears `ms.keytrack`, cancels all running cooldown timers, and stops the camera engine.

---

### `ms.cancelMacros()`

Cancels all active `ms.fn` coroutines and releases any keys or mouse buttons currently held by macro presses. Called automatically on every `ms.setMacros(0)`.

Safe to call manually if you need to abort running macros without disabling the system.

```lua
ms.cancelMacros()
```

---

### App watcher behavior

| Event | Action |
|-------|--------|
| Roblox activated | `BindValidity = 1`, camera enabled, enable notification queued |
| Roblox activated (returning from a settings dialog) | `BindValidity = 1`, camera enabled, notification suppressed |
| Any other app activated | `ms.setMacros(0)` — disables and notifies |
| Hammerspoon activated while Roblox was in front | `ms.setMacros(0, true)` — disables silently (settings dialog cycle) |
| Roblox launched | Camera watcher set up |

The in-game keys `/` (disable) and `Enter` (enable) also toggle macros while Roblox is focused.

The **Macros: ENABLED / DISABLED** banner is debounced: only the final settled state after rapid toggling produces a notification. Banners are suppressed during settings-dialog focus-steal cycles and for the first 15 seconds after startup.

---

## 11. Cooldown Helpers

### `ms.bind.group(id)`

Returns the cooldown group key for `id`. All macros in the same group share a single cooldown timer — firing any one of them locks out all others for the cooldown duration.

- If `opts.shared` is set on `id` or its root, that value is used directly.
- Otherwise auto-derives `"G_<rootId>"` by walking the `sub` chain.

```lua
local g = ms.bind.group("superThrow")  -- → "G_superJump"
```

---

### `ms.done(id)`

Manually clears the cooldown for `id`'s group before the timer expires. Useful at the end of a long macro that uses time-based internal logic rather than the cooldown timer.

```lua
ms.done("superJump")
```

---

## 12. Audio — `ms.sound`

### `ms.sound(path [, async [, device]])`

Plays a sound file.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `path` | — | A file path string or a `ms.sounds.*` table entry. Must be the **value**, not a variable name. |
| `async` | `true` | `true` = fire-and-forget. `false` = yield coroutine until playback completes. |
| `device` | `nil` | Output device name. `nil` = system default. |

**Three correct ways to pass a path:**

```lua
-- 1. A local variable holding a path built with SoundLib
local MySound = SoundLib .. "MySound.wav"
ms.sound(MySound)                     -- correct: pass the variable

-- 2. An inline path
ms.sound(SoundLib .. "MySound.wav")   -- correct: pass the concatenated string

-- 3. A discovered sound from ms.sounds
ms.sound(ms.sounds.alert)             -- correct: pass the table value
```

**Common mistake — passing a variable name as a string:**

```lua
local MySound = SoundLib .. "MySound.wav"
ms.sound("MySound")        -- WRONG: this is a string literal, not the variable
ms.sound("MySound.wav")    -- WRONG: filename only, not a full path
ms.sound("MySound", true)  -- WRONG: quoted name, async flag ignored because path fails
```

Passing a quoted name silently fails — `hs.sound` cannot find a file called `"MySound"` and returns nothing. Always pass the variable itself (no quotes) or the full path.

Volume is set automatically from `ms.soundVolume` (0–100).

---

### `ms._discoverSounds()`

Scans `~/.hammerspoon/sounds/` and populates `ms.sounds` — a table keyed by filename without extension. Called once at startup; call again if you add sound files without reloading.

```lua
-- After adding alert.mp3 to the sounds folder:
ms._discoverSounds()
ms.sound(ms.sounds.alert)
```

---

### `ms.playSlot(slotId)`

Plays the sound assigned to a named slot. Falls back to a file named `<slotId>.*` auto-discovered in `SoundLib` if no explicit assignment exists. Returns `true` if a sound was found and played, `false` otherwise.

Calls within 50 ms of the previous call for the same slot are silently suppressed to prevent double-play (e.g. a keyboard shortcut and the action's `fn` both firing simultaneously).

```lua
ms.playSlot("update")   -- plays whatever is assigned to the "update" slot
ms.playSlot("hover")    -- plays the menu hover sound
```

---

### Sound event slots

`ms.soundAssign` maps slot names to sound names from `ms.sounds`. Configured via **Settings › Sound**. Drop a file named after the slot (e.g. `hover.wav`) into `~/.hammerspoon/sounds/` for auto-assignment without any configuration.

| Slot | Fires when |
|------|------------|
| `load` | Hammerspoon finishes reloading |
| `alert` | A dialog is opened asking for input |
| `enabled` | Macros are enabled |
| `disabled` | Macros are disabled |
| `update` | A setting is successfully changed |
| `reset` | A reset button is confirmed |
| `interact` | A menu item is activated (click, Space, Return, or Right arrow into a submenu) |
| `hover` | The cursor or keyboard moves to a new menu item |
| `back` | Left arrow closes a submenu |
| `settingsOpen` | The settings menu appears (first open or reopen after an action) |
| `settingsClose` | The settings menu is dismissed (Escape, click outside, or Alt+P close) |

---

## 13. Settings & Defaults

### `ms.saveSettings()`

Writes all current runtime state to `ms_settings.json`. Called automatically after every settings menu action.

---

### `ms.loadSettings()`

Reads `ms_settings.json` (falls back to `ms_settings_default.json`, then auto-builds from registry). Applies the loaded values to the live runtime state.

---

### `ms.reloadSettings()`

Convenience wrapper that runs the full settings-reload sequence in one call: `loadSettings` → rebind → cam anchor → cam multiplier → SOCD → play update sound → show confirmation alert. Called by both the Settings menu item and the `alt+]` hotkey.

---

### `ms.saveDefault()`

Promotes the current `ms_settings.json` to `ms_settings_default.json`. Archives the previous default to `backups/` with a timestamp.

---

### `ms.resetToDefault()`

Clears all per-macro customisations (`bindConfig`, `subBinds`, `modConfig`, `cooldowns`), applies `ms_settings_default.json` as a full replacement, saves back to `ms_settings.json`, and rebinds everything. Returns `true` on success.

Unlike `ms.loadSettings()`, this is a **replace** — any custom keybind or cooldown not present in the default file is removed, not preserved.

---

### `ms._applySettings(data)`

Internal. Applies a decoded settings table to live runtime state. You do not need to call this directly.

---

### Settings files

| File | Purpose |
|------|---------|
| `ms_settings.json` | Current user settings — written on every change |
| `ms_settings_default.json` | The "reset to default" target |
| `backups/` | Timestamped archives of previous defaults |

---

## 14. SOCD Engine

Simultaneous Opposing Cardinal Directions cleaning. When enabled, prevents both keys in an axis pair (`W`/`S`, `A`/`D`) from being registered as held at the same time.

### `ms.socdMode`

| Value | Behavior |
|-------|----------|
| `"lastWins"` | The most recently pressed key wins; releases the opposite. On release, re-presses the opposite if still physically held. *(default)* |
| `"firstWins"` | The first key pressed wins; the second is swallowed. |
| `"neutral"` | Both keys are released when both are held simultaneously. |

---

### `ms.socdStart()` / `ms.socdStop()`

Start or stop the SOCD eventtap listener. Use `ms.socdApply()` instead to respect the current `ms.socdEnabled` setting.

---

### `ms.socdApply()`

Starts or stops the SOCD listener based on `ms.socdEnabled`. Call this after changing `ms.socdEnabled` or `ms.socdMode`.

---

## 15. Trackpad / Pen Mode

When enabled, re-routes root macro binds through `ms.trackpadBindOverrides` instead of their normal `default` bind. The default overrides move `superJump` from mouse button 3 to a keyboard key.

```lua
-- Defined at the top of init.lua; edit to change trackpad bind overrides:
ms.trackpadBindOverrides = {
    superJump = {type="key", mods={}, key="k"},
}
```

The trackpad hold listeners (`ms._trackpadLeftListener`, `ms._trackpadRightListener`) simulate a held left or right mouse button while their configured key is held. Hold keys are set via Settings › Trackpad Hold Keys; defaults are `n` (left) and `j` (right).

---

## 16. Profiles

A profile is a folder in `~/.hammerspoon/profiles/<name>/` containing `ms_macros.lua` and optionally `ms_settings.json` + `ms_settings_default.json`.

**Switching profiles** (Settings › Profiles):
1. Archives the active `ms_macros.lua` + settings files into `profiles/<currentName>/`.
2. Copies the target profile's files into the active positions.
3. Reloads after 3 seconds.

**Importing a profile** (Settings › Profiles › Import):
- Opens a file picker. The selected `ms_macros.lua` is read for its `ms.macroMeta.name` field and placed in `profiles/<name>/`.

`ms.macroMeta.name` is the canonical profile name. The folder is created using a sanitized version of this name.

**Security:** both import and profile switch run `auditMacros()` on the file before any disk operations. A file that fails the static scan is rejected with an alert and never activated.

---

## 17. Utility Functions

### `ms.alert(msg [, duration [, noDefaultSound]])`

Displays a floating toast notification on screen. Up to 4 alerts stack vertically with animated entry/exit.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `msg` | — | String to display. `\n` for line breaks. |
| `duration` | `2` | Seconds before the toast fades out. |
| `noDefaultSound` | `false` | Pass `true` to suppress the automatic `alert` slot sound for this call. |

```lua
ms.alert("Macros: ENABLED", 3)
ms.alert("Multi-line\nMessage", 5)
ms.alert("Silent confirmation", 2, true)   -- no alert sound
```

---

### `ms.debugRoblox()`

Prints Roblox window info (resolution, position, aspect ratio, sensitivity) to the Hammerspoon console and shows alerts. Also warns if the aspect ratio is too narrow for macros to work correctly. Available via Settings › Developer › Debug Roblox.

---

## 18. Global Hotkeys

These are always active regardless of which app is focused.

| Hotkey | Action |
|--------|--------|
| `alt+[` | Reload Hammerspoon (`hs.reload()`) |
| `alt+]` | Reload settings from disk and rebind |
| `alt+p` | Open the Settings menu at the cursor position |
| `alt+F10` | Emergency reset — disables macros immediately |

---

## 19. Global Constants

### Camera / scaling

| Constant | Value | Description |
|----------|-------|-------------|
| `REF_W` | `1680` | Reference resolution width used for coordinate scaling |
| `REF_H` | `1044` | Reference resolution height |
| `REF_SENS` | `1.5` | Reference camera sensitivity (used to derive `cachedMult`) |
| `CUR_CAM_SENS` | *(user setting)* | Current in-game sensitivity. Set via Settings › Camera Sensitivity |
| `clickLevel` | `3` | Click position offset level (1–4). Set via Settings › Developer › Set Click Level |

---

### `ms.Mouse` named constants

These are plain globals available from `ms_macros.lua`.

**Operations:** `Move`, `Click`, `DoubleClick`, `TripleClick`, `Drag`, `Press`, `Release`

**Buttons:** `Left`, `Right`, `Center`, `Button4`, `Button5`

**References:** `Absolute`, `Mouse`, `WindowTL`, `WindowTR`, `WindowBL`, `WindowBR`, `WindowCenter`, `ScreenTL`, `ScreenTR`, `ScreenBL`, `ScreenBR`, `ScreenCenter`

**Flag:** `Unscaled` (`true`) — pass between the reference and the first coordinate in `ms.Mouse` to use raw pixel window offsets instead of REF-space scaled values.

---

### Sound

| Constant | Description |
|----------|-------------|
| `SoundLib` | Path to `~/.hammerspoon/sounds/` (trailing slash included) |
| `ms.sounds` | Table of discovered sounds, keyed by filename-without-extension |
| `ms.soundEnabled` | Master on/off (bool) |
| `ms.soundVolume` | Volume 0–100 |
| `ms.soundAssign` | Per-slot sound overrides: `{ load=name, update=name, hover=name, … }`. See §12 for all slot names. |
| `ms._updateManifestURL` | Set to a MANIFEST.json URL to enable the Check for Update feature. `nil` by default. |

---

### Internal state (read-only — do not modify directly)

| Variable | Description |
|----------|-------------|
| `BindValidity` | `1` if macros are active, `0` if disabled |
| `ms.keytrack` | Live key-held table: `{[keycode] = true/false}` |
| `ms.running` | Active cooldown timers: `{[groupId] = timerHandle}` |
| `ms.binds` | Enabled state overrides per id |
| `ms.bindConfig` | User keybind overrides per root id |
| `ms.modConfig` | User modifier key overrides per sub-item id |
| `ms.subBinds` | Independent bind configs per sub-item id |
| `ms.cooldowns` | User cooldown overrides per id |
| `ms.registry._defs` | Full definition table by id |
| `ms.registry._defList` | Ordered list of all ids as declared |
| `ms.bind._wires` | Registered functions by id |


## 20. Integrity & Updates

### Overview

The integrity system detects unauthorised modifications to `init.lua` by comparing its SHA-256 hash to a stored baseline. The update system fetches a new `init.lua` from a URL you provide, verifies its hash before installing, backs up the old file, and reloads automatically.

The trusted hash is stored in `~/.hammerspoon/.ms_trusted_hash` — one line, 64 hex characters. It is only written when you explicitly trust a version; normal reloads never change it.

---

### `ms.integrity.check()`

Hashes the live `init.lua` and compares it to the stored baseline.

Returns three values: `status, currentHash, trustedHash`

| `status` | Meaning |
|----------|--------|
| `"trusted"` | File matches the stored baseline |
| `"mismatch"` | File has changed since it was last trusted |
| `"uninitialized"` | No baseline has been stored yet |

```lua
local status, cur, trusted = ms.integrity.check()
if status == "mismatch" then
    ms.alert("init.lua has changed!", 6)
end
```

---

### `ms.integrity.hashFile(path)`

Synchronously SHA-256 hashes a file via `shasum -a 256`. Returns the 64-character lowercase hex string, or `nil` on failure.

---

### `ms.integrity.readTrustedHash()` / `ms.integrity.writeTrustedHash(hash)`

Read or write the baseline hash file at `~/.hammerspoon/.ms_trusted_hash`. `readTrustedHash` returns the hash string or `nil` if the file doesn't exist.

---

### `ms.integrity.trustCurrent()`

Seals the running `init.lua` as the new trusted baseline. Writes its hash to `.ms_trusted_hash` and shows a confirmation alert.

Available via **Settings › Developer › Trust Current Version**. The item is greyed out (disabled) when the file already matches the stored hash — it becomes clickable again as soon as a mismatch or uninitialized state is detected when the menu opens.

Call this once after every intentional edit to `init.lua` so future tamper-detection alerts are meaningful.

---

### `ms.integrity.update()`

Full async update flow. Requires `ms._updateManifestURL` to be set.

1. Fetches `MANIFEST.json` from `ms._updateManifestURL` over HTTPS
2. Downloads `init.lua` from the `url` field in the manifest
3. Verifies the downloaded file's SHA-256 matches the `sha256` field — aborts if not
4. Backs up the current `init.lua` to `backups/init_<timestamp>.lua.bak`
5. Installs the new file, updates `.ms_trusted_hash`, reloads after 3 seconds

Available via **Settings › Help › Check for Update**.

---

### MANIFEST.json format

```json
{
  "version": "1.2.3",
  "sha256": "<64-char lowercase hex of the raw init.lua as served>",
  "url": "https://raw.githubusercontent.com/you/repo/main/init.lua"
}
```

> **Important:** compute `sha256` from the file as GitHub serves it, not your local copy. Use:
> ```sh
> curl -s <raw URL> | shasum -a 256
> ```
> Always push `init.lua` before updating `MANIFEST.json`.

---

### `ms._updateManifestURL`

Global string. Set this in `init.lua` to enable the auto-update feature:

```lua
ms._updateManifestURL = "https://raw.githubusercontent.com/you/repo/main/MANIFEST.json"
```

`nil` by default. When not set, **Check for Update** shows an error instead of attempting a download.
