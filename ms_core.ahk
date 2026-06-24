; ═══════════════════════════════════════════════════════════════════════════
; mudscript Windows Runtime — AutoHotkey v2
; ═══════════════════════════════════════════════════════════════════════════
; Mirrors the ms.* API from ms_core.lua so macro logic written for the macOS
; version can be ported to Windows with minimal changes.
;
; Usage:
;   #Include ms_core.ahk
;   ; then write macro functions using the same ms.* calls
;
; Key differences from macOS:
;   ms.fn()    — identity wrapper; AHKv2 is synchronous, no coroutines needed
;   ms.wait()  — calls Sleep with cancellation check
;   "cmd"      — maps to Ctrl (macOS ⌘ → Windows Ctrl for app shortcuts)
;   ms.cam     — uses SendInput relative delta; game must be focused
;   ms.alert() — uses ToolTip; clears after duration seconds
; ═══════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0
; Dependencies (WebView2.ahk, Jxon.ahk) must be loaded before this file —
; init.ahk includes them. If including ms_core.ahk directly from your own
; script, add these #Include directives above:
;   #Include lib\WebView2.ahk
;   #Include lib\Jxon.ahk

; ── Global constants (mirror ms_core.lua) ────────────────────────────────────
global REF_W     := 1680
global REF_H     := 1044
global REF_SENS  := 1.5
global SoundLib  := A_ScriptDir "\sounds\"
global BindValidity := 0
global loadfinish   := 0
global _ms_loadDone := false  ; set to true by _ms_loadAnnounce; gates automatic macro activation
global clickLevel   := 3
global CUR_CAM_SENS := 1.5

; ── ms.Mouse operation constants ─────────────────────────────────────────────
global Move        := "Move"
global Click       := "Click"
global DoubleClick := "DoubleClick"
global TripleClick := "TripleClick"
global Drag        := "Drag"
global Press       := "Press"
global Release     := "Release"

; ── ms.Mouse button constants ─────────────────────────────────────────────────
global Left    := "Left"
global Right   := "Right"
global Center  := "Middle"
global Button4 := "X1"
global Button5 := "X2"

; ── ms.Mouse reference constants ──────────────────────────────────────────────
global Unscaled     := true
global Absolute     := "Absolute"
global Mouse        := "Mouse"
global WindowTL     := "WindowTL"
global WindowTR     := "WindowTR"
global WindowBL     := "WindowBL"
global WindowBR     := "WindowBR"
global WindowCenter := "WindowCenter"
global ScreenTL     := "ScreenTL"
global ScreenTR     := "ScreenTR"
global ScreenBL     := "ScreenBL"
global ScreenBR     := "ScreenBR"
global ScreenCenter := "ScreenCenter"

; ── Internal registry / sub-item state ───────────────────────────────────────
global _ms_registry   := Map()   ; id → {func, opts}

global _ms_active_sub := ""      ; currently dispatched sub-item id

; ── Cancellation ─────────────────────────────────────────────────────────────
global _ms_cancel_gen := 0       ; incremented by ms.cancelMacros()

; ── Cooldown / bind state (mirrors ms.running / ms.binds / etc.) ─────────────
global _ms_running    := Map()   ; groupId → true (cooldown active)
global _ms_binds      := Map()   ; id → enabled override
global _ms_bindConfig := Map()   ; id → bind override
global _ms_subBinds   := Map()   ; sub-id → bind override
global _ms_modConfig  := Map()   ; id → mod key override
global _ms_cooldowns  := Map()   ; id → cooldown ms override

; ── Sound state ──────────────────────────────────────────────────────────────
global _ms_sounds          := Map()  ; name → path
global _ms_importedSounds  := Map()  ; name → filename (persisted in settings)
global _ms_soundAssign     := Map()  ; slotId → soundName override
global _ms_soundEnabled    := true
global _ms_soundVolume     := 100
global _ms_playSlotTimes   := Map()  ; slotId → last-play tick (dedup)

; ── Target application ────────────────────────────────────────────────────────
global _ms_target_exe     := "ahk_exe RobloxPlayerBeta.exe"   ; target window criteria; change via ms.setTargetApp()
global _ms_roblox_active  := false
global _ms_ui_open        := false   ; true while settings panel is visible

; ── Settings / profile paths (mirror macOS data/ layout) ─────────────────────
global _ms_json_path     := A_ScriptDir "\data\ms_settings.json"
global _ms_default_path  := A_ScriptDir "\data\ms_settings_default.json"
global _ms_archive_path  := A_ScriptDir "\backups\"
global _ms_profiles_path := A_ScriptDir "\profiles\"
; When compiled (A_IsCompiled = 1), integrity hashes the exe itself — not ms_core.ahk.
global _ms_core_path     := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\ms_core.ahk"
global _ms_hash_path     := A_ScriptDir "\data\.ms_trusted_hash"
global _ms_theme_path    := A_ScriptDir "\data\ms_theme.json"
global _ms_dev_log_path  := A_ScriptDir "\data\ms_dev.log"
global _ms_dev_arch_dir  := A_ScriptDir "\data\ms_dev_logs\"

; ── Dev log archive on every reload (mirrors Lua archive+prune) ────────────
do {
    if FileExist(_ms_dev_log_path) {
        DirCreate _ms_dev_arch_dir
        local ts := FormatTime(, "yyyy-MM-dd_HHmmss")
        FileMove _ms_dev_log_path, _ms_dev_arch_dir "ms_dev_" ts ".log", 0
        ; Prune: keep only the 20 most recent archives.
        local archives := []
        Loop Files _ms_dev_arch_dir "ms_dev_*.log"
            archives.Push(A_LoopFileName)
        archives.Sort()
        while archives.Length > 20 {
            FileDelete _ms_dev_arch_dir archives[1]
            archives.RemoveAt(1)
        }

    }
}


; ── URLs ─────────────────────────────────────────────────────────────────────
global _ms_docs_url     := "https://docs-ms.mudbourn.info"
global _ms_manifest_url := "https://raw.githubusercontent.com/mudbourn/ms-utils/main/MANIFEST.json"

; ── RSA-2048 public key for update verification ───────────────────────────────
global _ms_update_pubkey := "
(
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
)"

; ── Theme state ───────────────────────────────────────────────────────────────
global _ms_theme := Map(
    "bg",       "#060402",
    "surface",  "#100806",
    "surface2", "#1c100c",
    "hover",    "#301610",
    "accent",   "#c41a1a",
    "accentHi", "#e52424",
    "success",  "#4a7820",
    "dangerBg", "#1e0608",
    "danger",   "#d42020",
    "warning",  "#c47820",
    "text",     "#f0ddb0",
    "radius",   3,
    "font",     "Almendra"
)
global _ms_theme_loaded := false

; ── User Settings / Menu API state ────────────────────────────────────────────
global _ms_user_defs    := []       ; ordered array of setting defs
global _ms_user_index   := Map()    ; key → def
global _ms_user_vals    := Map()    ; key → current value
global _ms_menu_defs    := []       ; ordered array of ms.menu.define entries
global _ms_hidden_feats := Map()    ; feature name → true

; ── SOCD state (managed by socdStart/socdStop) ───────────────────────────────
global _ms_socd_held    := Map("a", false, "d", false, "w", false, "s", false)
global _ms_socd_active  := false    ; true when SOCD hotkeys are registered

; ── Trackpad mode state ───────────────────────────────────────────────────────
global _ms_trackpad_mode      := false
global _ms_trackpad_hold_keys := {left: "n", right: "j"}

global _ms_trackpad_bind_ovr  := Map("superJump", {type: "key", mods: [], key: "k"})
global _ms_independent_binds  := false

; ── Dev tools state ───────────────────────────────────────────────────────────
global _ms_dev_console_wv := 0
global _ms_dev_watcher_wv := 0
global _ms_dev_keys_wv    := 0
global _ms_dev_console_gui := 0
global _ms_dev_watcher_gui := 0
global _ms_dev_keys_gui    := 0
global _ms_dev_active_keys := Map()
global _ms_dev_busy         := false
global _ms_dev_key_notice   := false
global _ms_dev_console_open := false
global _ms_dev_watcher_open := false
global _ms_dev_keys_open    := false
global _ms_dev_window_open  := false
global _ms_dev_console_pos  := Map()
global _ms_dev_watcher_pos  := Map()
global _ms_dev_keys_pos     := Map()
global _ms_dev_window_pos   := Map()
global _ms_dev_window_gui   := 0
global _ms_dev_window_wv    := 0
global _ms_dev_window_history := []
global _ms_dev_window_last_id := 0
global _ms_dev_window_poller := 0

; ── UI panel state ────────────────────────────────────────────────────────────
global _ms_ui_panel_gui := 0
global _ms_ui_panel_wv  := 0
global _ms_ui_open_flag := false
global _ms_ui_modal_cb  := 0        ; pending modal callback
global _ms_ui_pos       := {x: 0, y: 0, w: 360, h: 640}


; ── Notify debounce ───────────────────────────────────────────────────────────
global _ms_notify_timer := 0

; ═══════════════════════════════════════════════════════════════════════════════
class ms {

    ; metadata set by the macro file
    static macroMeta     := {}

    static macroDefaults := {}


    ; ── Keyboard ──────────────────────────────────────────────────────────────

    static press(key, mods := [], hidinject := false) {
        local m := ""
        for mod in mods
            m .= ms._mod(mod)
        SendInput m "{" ms._key(key) " down}"
    }


    static release(key, mods := [], hidinject := false) {
        SendInput "{" ms._key(key) " up}"
    }


    static type(key, mods := [], hidinject := false) {
        local m := ""
        for mod in mods
            m .= ms._mod(mod)
        SendInput m "{" ms._key(key) "}"
    }


    ; ── Timing ────────────────────────────────────────────────────────────────

    ; Pause execution for ms_time milliseconds.
    ; Checks the cancellation generation — throws if cancelled.
    ; AHKv2 hotkeys each run in their own thread so Sleep does not block
    ; other hotkeys — equivalent to Lua coroutine yield behaviour.
    static wait(ms_time) {
        global _ms_cancel_gen
        local gen := _ms_cancel_gen
        Sleep ms_time
        if _ms_cancel_gen != gen
            throw Error("ms.cancelled")
    }


    ; ── fn() wrapper ──────────────────────────────────────────────────────────

    ; Identity wrapper — AHKv2 hotkey threads are already independent.
    static fn(func, async := true) {
        return func
    }


    ; ── Clipboard ─────────────────────────────────────────────────────────────

    static copy(text) {
        A_Clipboard := text
    }


    ; ── Scroll ────────────────────────────────────────────────────────────────

    static scroll(direction, amount := 1) {
        if direction = "up" {
            Send "{WheelUp " amount "}"
        } else {
            Send "{WheelDown " amount "}"
        }

    }

    ; ── Audio ─────────────────────────────────────────────────────────────────

    ; Play a sound by path. Respects master soundEnabled and volume.
    static sound(path, async := true) {
        global _ms_soundEnabled
        if !_ms_soundEnabled {
            return
        }
        if !path {
            return
        }
        if async {
            SoundPlay path, true
        } else {
            SoundPlay path
        }

    }

    ; Play the sound assigned to a named slot (e.g. "update", "enabled", "load").
    ; Suppresses duplicate plays within 50 ms.
    static playSlot(slotId) {
        global _ms_soundEnabled, _ms_sounds, _ms_soundAssign, _ms_playSlotTimes
        if !_ms_soundEnabled {
            return false
        }
        local now := A_TickCount
        if _ms_playSlotTimes.Has(slotId) && (now - _ms_playSlotTimes[slotId]) < 50
            return false
        _ms_playSlotTimes[slotId] := now
        local assigned := _ms_soundAssign.Has(slotId) ? _ms_soundAssign[slotId] : ""
        local path := ""
        if assigned != "" && _ms_sounds.Has(assigned)
            path := _ms_sounds[assigned]
        else if _ms_sounds.Has(slotId)
            path := _ms_sounds[slotId]
        if path = "" {
            return false
        }
        ms.sound(path, true)
        return true
    }


    ; ── Alert / Notification ──────────────────────────────────────────────────

    ; Shows a ToolTip in the top-left corner; auto-clears after duration seconds.
    ; noSound parameter accepted for API compatibility (sound handled by caller).
    static alert(msg, duration := 3, noSound := false) {
        ToolTip msg
        SetTimer () => ToolTip(), -(duration * 1000)
    }


    ; ── Target app API (mirrors Lua ms.setTargetApp / ms.getTargetWin) ──────

    ; Change the target application at runtime.
    ; Pass the executable name (e.g. "RobloxPlayerBeta.exe") or a full window
    ; criteria string (e.g. "ahk_exe notepad.exe").
    ; Pass empty string to clear the target (macros won't auto-enable).
    static setTargetApp(name) {
        global _ms_target_exe
        if name = "" {
            _ms_target_exe := ""
            return
        }

        ; If it already contains "ahk_" prefix, use as-is; otherwise build "ahk_exe "
        if InStr(name, "ahk_") = 1 {
            _ms_target_exe := name
        } else {
            _ms_target_exe := "ahk_exe " name
        }

    }

    ; Returns the window criteria for the target app, or "" if unset.
    static getTargetWin() {
        global _ms_target_exe
        return _ms_target_exe
    }


    ; ── State queries ─────────────────────────────────────────────────────────

    static keystate(key, rawCode := false) {
        return GetKeyState(ms._key(key), "P")
    }


    static app() {
        try return WinGetTitle("A")
        return ""
    }


    static mousePos() {
        MouseGetPos &mx, &my
        local wX := 0, wY := 0, wW := REF_W, wH := REF_H
        global _ms_target_exe
        try WinGetPos &wX, &wY, &wW, &wH, _ms_target_exe
        local relX := (mx - wX) * (REF_W / wW)
        local relY := (my - wY) * (REF_H / wH)
        return [relX, relY]
    }


    ; ── Sub-item dispatch ─────────────────────────────────────────────────────

    static getMod(id) {
        global _ms_modConfig, _ms_registry
        if _ms_modConfig.Has(id)
            return _ms_modConfig[id]
        if _ms_registry.Has(id) && _ms_registry[id].opts.HasProp("mod")
            return _ms_registry[id].opts.mod
        return ""
    }


    static modHeld(id) {
        local mod := ms.getMod(id)
        if mod = "" {
            return false
        }
        return GetKeyState(ms._key(mod), "P")
    }


    static isSub(id) {
        global _ms_active_sub
        if (_ms_active_sub = id) || (_ms_active_sub = "" && ms.modHeld(id)) {
            _ms_active_sub := ""
            return true
        }

        return false
    }


    ; ── Mouse ─────────────────────────────────────────────────────────────────

    static Mouse(operation, button, reference, params*) {
        local unscaled := false
        local x1 := 0, y1 := 0, x2 := 0, y2 := 0
        local offset := 1

        if params.Length >= 1 && params[1] == true {
            unscaled := true
            offset   := 2
        }

        if params.Length >= offset {
            x1 := params[offset]
        }

        if params.Length >= offset + 1 {
            y1 := params[offset + 1]
        }

        if params.Length >= offset + 2 {
            x2 := params[offset + 2]
        }

        if params.Length >= offset + 3 {
            y2 := params[offset + 3]
        }


        local btn  := ms._mouseBtn(button)
        local pos1 := ms._resolve(x1, y1, reference, unscaled)
        local pos2 := ms._resolve(x2, y2, reference, unscaled)

        if operation = "Move" {
            MouseMove pos1.x, pos1.y
        } else if operation = "Click" {
            MouseMove pos1.x, pos1.y
            Sleep 50
            Click btn " " pos1.x " " pos1.y
        } else if operation = "DoubleClick" {
            MouseMove pos1.x, pos1.y
            Sleep 50
            Click "2 " btn " " pos1.x " " pos1.y
        } else if operation = "TripleClick" {
            MouseMove pos1.x, pos1.y
            Sleep 50
            loop 3
                Click btn " " pos1.x " " pos1.y
        } else if operation = "Drag" {
            Click btn " Down " pos1.x " " pos1.y
            Sleep 50
            MouseMove pos2.x, pos2.y
            Sleep 50
            Click btn " Up " pos2.x " " pos2.y
        } else if operation = "Press" {
            MouseMove pos1.x, pos1.y
            Click btn " Down " pos1.x " " pos1.y
        } else if operation = "Release" {
            Click btn " Up " pos1.x " " pos1.y
        }

    }

    ; ── Coordinate resolution ─────────────────────────────────────────────────

    static resolvePoint(x, y, reference, unscaled := false) {
        local p := ms._resolve(x, y, reference, unscaled)
        return [p.x, p.y]
    }


    static _resolve(x, y, reference, unscaled := false) {
        if reference = "Absolute"
            return {x: x, y: y}


        if reference = "Mouse" {
            MouseGetPos &mx, &my
            return {x: mx + x, y: my + y}

        }

        local wX := 0, wY := 0, wW := REF_W, wH := REF_H
        global _ms_target_exe
        try WinGetPos &wX, &wY, &wW, &wH, _ms_target_exe

        local sX := unscaled ? 1 : wW / REF_W
        local sY := unscaled ? 1 : wH / REF_H

        if reference = "WindowTL"     return {x: wX + x * sX,          y: wY + y * sY}

        if reference = "WindowTR"     return {x: wX + wW + x * sX,     y: wY + y * sY}

        if reference = "WindowBL"     return {x: wX + x * sX,          y: wY + wH + y * sY}

        if reference = "WindowBR"     return {x: wX + wW + x * sX,     y: wY + wH + y * sY}

        if reference = "WindowCenter" return {x: wX + wW // 2 + x * sX, y: wY + wH // 2 + y * sY}


        MonitorGetWorkArea , &sL, &sT, &sR, &sB
        if reference = "ScreenTL"     return {x: sL + x,               y: sT + y}

        if reference = "ScreenTR"     return {x: sR + x,               y: sT + y}

        if reference = "ScreenBL"     return {x: sL + x,               y: sB + y}

        if reference = "ScreenBR"     return {x: sR + x,               y: sB + y}

        if reference = "ScreenCenter" return {x: (sL + sR) // 2 + x,  y: (sT + sB) // 2 + y}


        return {x: x, y: y}

    }

    ; ── Pixel color ───────────────────────────────────────────────────────────

    static pixelColor(x, y, reference := "Absolute") {
        local pos := ms._resolve(x, y, reference)
        local color := PixelGetColor(pos.x, pos.y, "RGB")
        return {
            r: (color >> 16) & 0xFF,
            g: (color >> 8)  & 0xFF,
            b:  color        & 0xFF,
            a: 255
        }

    }

    static pixelMatch(x, y, reference, r, g, b, tolerance := 10) {
        local c := ms.pixelColor(x, y, reference)
        return Abs(c.r - r) <= tolerance
            && Abs(c.g - g) <= tolerance
            && Abs(c.b - b) <= tolerance
    }


    ; ── Camera ────────────────────────────────────────────────────────────────

    class cam {
        static _mult := 1.0

        static updateMultiplier() {
            ms.cam._mult := REF_SENS / (CUR_CAM_SENS > 0 ? CUR_CAM_SENS : 1.5)
        }


        static move(dy, dx) {
            local sdx := Round(dx * ms.cam._mult)
            local sdy := Round(dy * ms.cam._mult)
            if sdx = 0 && sdy = 0
                return

            ; Windows INPUT structure (x64, 40 bytes) — MOUSEEVENTF_MOVE
            local input := Buffer(40, 0)
            NumPut "UInt", 0,      input,  0
            NumPut "Int",  sdx,    input,  8
            NumPut "Int",  sdy,    input, 12
            NumPut "UInt", 0x0001, input, 20
            DllCall "SendInput", "UInt", 1, "Ptr", input, "Int", 40
        }


        ; Stubs for API compatibility — not required on Windows.
        static enable() {
            return
        }

        static disable() {
            return
        }

        static updateAnchor() {
            return
        }

        static scheduleUpdate() {
            return
        }

    }

    ; ── Bind / registry system ────────────────────────────────────────────────

    class bind {
        static _autoCount := 0
        static _defs      := Map()   ; id → opts (mirroring ms.registry._defs in Lua)
        static _defList   := []      ; ordered id list
        static _hotkeys   := Map()   ; registered hotkey strings → id (for teardown)

        ; Store the bind definition and function. Hotkeys are NOT registered here —
        ; call ms.bind.rebind() after all defines are done (happens in startup sequence).
        static define(id, fnOrOpts, optsOrFn := "") {
            global _ms_registry

            local func := ""
            local opts := {}


            if fnOrOpts is Func || fnOrOpts is BoundFunc || fnOrOpts is Closure {
                func := fnOrOpts,  opts := (optsOrFn != "" ? optsOrFn : {})
            } else {
                opts := fnOrOpts,  func := (optsOrFn != "" ? optsOrFn : "")
            }


            ; Build the canonical opts table (mirror Lua ms.registry._defs shape)
            local label, group
            if !opts.HasProp("sub") || opts.sub = "" {
                if opts.HasProp("label") && opts.label != ""
                    label := opts.label
                else {
                    ms.bind._autoCount++
                    label := "Macro" ms.bind._autoCount
                }

                group := opts.HasProp("group") ? opts.group : "main"
            } else {
                label := opts.HasProp("label") ? opts.label : id
                group := opts.HasProp("group") ? opts.group : ""
            }


            local def := {
                label:    label,
                group:    group,
                enabled:  (!opts.HasProp("enabled") || opts.enabled != false),
                cooldown: opts.HasProp("cooldown") ? opts.cooldown : 1000,
                shared:   opts.HasProp("shared")   ? opts.shared   : "",
                sub:      opts.HasProp("sub")       ? opts.sub      : "",
                mod:      opts.HasProp("mod")       ? opts.mod      : "",
                info:     opts.HasProp("info")      ? opts.info     : "",
                default:  opts.HasProp("default")   ? opts.default  : "",
            }


            _ms_registry[id] := {func: func, opts: def}

            ms.bind._defs[id] := def
            ms.bind._defList.Push(id)
        }


        ; Returns the cooldown group key for a macro id.
        ; If opts.shared is set on id or its root, uses that; else "G_<rootId>".
        static group(id) {
            global _ms_registry
            if !_ms_registry.Has(id) {
                return "G_" id
            }
            local def := _ms_registry[id].opts
            if def.shared != "" {
                return def.shared
            }
            local current := id, seen := Map()
            loop {
                local d := _ms_registry.Has(current) ? _ms_registry[current].opts : ""
                if d = "" || d.sub = "" || seen.Has(current) {
                    break
                }
                seen[current] := true
                current := d.sub
            }

            local rootDef := _ms_registry.Has(current) ? _ms_registry[current].opts : ""
            if rootDef != "" && rootDef.shared != "" {
                return rootDef.shared
            }
            return "G_" current
        }


        ; Tears down all registered hotkeys without touching SOCD/trackpad listeners.
        static teardown() {
            for hk, _ in ms.bind._hotkeys {
                try Hotkey hk, "Off"
            }

            ms.bind._hotkeys := Map()
        }


        ; Rebuilds all hotkeys from the current registry + settings overrides.
        ; Mirrors Lua ms.bind.rebind() with conflict detection.
        static rebind() {
            global _ms_registry, _ms_binds, _ms_bindConfig, _ms_subBinds
            global _ms_modConfig, _ms_cooldowns, _ms_independent_binds, _ms_trackpad_mode
            global _ms_trackpad_bind_ovr, _ms_active_sub, _ms_running, BindValidity

            ms.bind.teardown()

            ; ── Conflict detection ───────────────────────────────────────────
            local conflicted := Map()

            ; Root bind conflicts
            local rootUsed := Map()
            for _, id in ms.bind._defList {
                local def := ms.bind._defs[id]
                if !def || def.sub != "" {
                    continue
                }
                local enabled := _ms_binds.Has(id) ? _ms_binds[id] : def.enabled
                if !enabled {
                    continue
                }
                local c := ms._effectiveBind(id)
                local k := ms._bindKey(c)
                if k = "" {
                    continue
                }
                if rootUsed.Has(k) {
                    conflicted[id] := true
                    conflicted[rootUsed[k]] := true
                    local l1 := def.label, l2 := ms.bind._defs[rootUsed[k]].label
                    SetTimer () => ms.alert('Bind conflict: "' l1 '" and "' l2 '" share the same input.`nBoth disabled — resolve via Settings › Keybinds.', 10), -50
                } else
                    rootUsed[k] := id
            }


            ; ── Hotkey callback factories ──────────────────────────────────────────

                    ; Shared callback for sub-item binds (captures _fn, _id, group, cooldown)
                    static _fireSubBind(fn, id, group, cooldown, *) {
                        if _ms_running.Has(group) {
                            return
                        }
                        _ms_running[group] := true
                        SetTimer () => _ms_running.Delete(group), -cooldown
                        _ms_active_sub := id
                        fn()
                    }


                    ; Shared callback for root binds (captures _fn, _id, group, cooldown)
                    static _fireRootBind(fn, id, group, cooldown, *) {
                        if BindValidity != 1 {
                            return
                        }
                        if _ms_running.Has(group) {
                            return
                        }
                        _ms_running[group] := true
                        SetTimer () => _ms_running.Delete(group), -cooldown
                        _ms_active_sub := ""
                        try fn()
                        catch as e {
                            if e.Message != "ms.cancelled"
                                ms.alert("Macro error — check OutputDebug.", 4)
                        }

                    }

            ; ── Modifier conflicts among siblings
                    local modUsed := Map()
            for _, id in ms.bind._defList {
                local def := ms.bind._defs[id]
                if !def || def.sub = "" {
                    continue
                }
                local mod := ms.getMod(id)
                if mod = "" {
                    continue
                }
                local parent := def.sub
                if !modUsed.Has(parent) {
                    modUsed[parent] := Map()
                }
                if modUsed[parent].Has(mod) {
                    conflicted[id] := true
                    conflicted[modUsed[parent][mod]] := true
                } else
                    modUsed[parent][mod] := id
            }


            ; ── Registration ─────────────────────────────────────────────────
            for _, id in ms.bind._defList {
                if conflicted.Has(id) {
                    continue
                }
                local entry := _ms_registry.Has(id) ? _ms_registry[id] : ""
                if entry = "" || entry.func = "" {
                    continue
                }

                local def      := ms.bind._defs[id]
                local group    := ms.bind.group(id)
                local cooldown := _ms_cooldowns.Has(id) ? _ms_cooldowns[id] : def.cooldown

                if def.sub != "" {
                    ; Sub-item: register only when independent binds is on and a bind is set
                    if !_ms_independent_binds || !_ms_subBinds.Has(id) {
                        continue
                    }
                    local c := _ms_subBinds[id]
                    local _fn := entry.func, _id := id
                    local hk := ms.bind._buildHotkey(c)
                    if hk = "" {
                        continue
                    }
                    HotIfWinActive _ms_target_exe
                    Hotkey "$" hk, ms.bind._fireSubBind.Bind(_fn, _id, group, cooldown)
                    HotIfWinActive
                    ms.bind._hotkeys["$" hk] := id
                } else {
                    ; Root bind: check enabled + resolve effective bind
                    local enabled := _ms_binds.Has(id) ? _ms_binds[id] : def.enabled
                    if !enabled {
                        continue
                    }
                    local c := ms._effectiveBind(id)
                    if c = "" {
                        continue
                    }
                    local _fn := entry.func, _id := id
                    local hk := ms.bind._buildHotkey(c)
                    if hk = "" {
                        continue
                    }
                    HotIfWinActive _ms_target_exe
                    Hotkey "$" hk, ms.bind._fireRootBind.Bind(_fn, _id, group, cooldown)
                    HotIfWinActive
                    ms.bind._hotkeys["$" hk] := id
                }

            }

            ; Trackpad listeners: start/stop based on current mode
            if _ms_trackpad_mode {
                _ms_trackpadStart()
            } else {
                _ms_trackpadStop()
            }

        }

        ; Returns the canonical conflict-detection key for a bind config object.
        static _bindKey(c) {
            if c = "" {
                return ""
            }
            if c.HasProp("type") && c.type = "mouse"
                return "mouse:" c.button
            if c.HasProp("type") && c.type = "key" {
                local mods := []
                if c.HasProp("mods")
                    for m in c.mods
                        mods.Push(m)
                mods.Sort()
                local modsStr := ""
                for m in mods {
                    modsStr .= m ","
                }
                return "key:" modsStr ":" (c.HasProp("key") ? c.key : "")
            }

            return ""
        }


        ; Converts a bind config object to an AHKv2 hotkey string (no $ prefix).
        static _buildHotkey(c) {
            if c = "" {
                return ""
            }
            if c.HasProp("type") && c.type = "mouse"
                return ms.bind._mouseHotkey(c.button)
            if c.HasProp("type") && c.type = "key"
                return ms.bind._keyHotkey(c.HasProp("mods") ? c.mods : [], c.HasProp("key") ? c.key : "")
            return ""
        }


        static _mouseHotkey(button) {
            static m := Map(0,"LButton", 1,"RButton", 2,"MButton", 3,"XButton1", 4,"XButton2")
            return m.Has(button) ? m[button] : ""
        }


        static _keyHotkey(mods, key) {
            local prefix := ""
            for mod in mods
                prefix .= ms._mod(mod)
            return prefix ms._key(key)
        }

    }

    ; ── Effective bind (respects trackpad mode overrides) ────────────────────

    static _effectiveBind(id) {
        global _ms_bindConfig, _ms_trackpad_mode, _ms_trackpad_bind_ovr
        if _ms_trackpad_mode && _ms_trackpad_bind_ovr.Has(id)
            return _ms_trackpad_bind_ovr[id]
        local def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
        if _ms_bindConfig.Has(id) {
            return _ms_bindConfig[id]
        }
        if def != "" && def.default != "" {
            return def.default
        }
        return ""
    }


    ; ── parseBind ─────────────────────────────────────────────────────────────

    static parseBind(str) {
        local btn := RegExMatch(str, "^mouse:(\d+)$", &m) ? m[1] : ""
        if btn != ""  return {type: "mouse", button: Integer(btn)}

        local mods := [], parts := StrSplit(StrLower(str), "+")
        local modkeys := Map("cmd",true,"alt",true,"ctrl",true,"shift",true)
        local key := ""
        for p in parts {
            if modkeys.Has(p) {
                mods.Push(p)
            } else {
                key := p
            }

        }
        if key != ""  return {type: "key", mods: mods, key: key}

        return ""
    }


    ; ── done() — optional cooldown early-clear ────────────────────────────────

    static done(id) {
        global _ms_running
        local group := ms.bind.group(id)
        if _ms_running.Has(group) {
            _ms_running.Delete(group)
            SetTimer () => 0, 0   ; no-op; the timer already cleared above
        }

    }

    ; ── setMacros / cancelMacros ──────────────────────────────────────────────

    static setMacros(state, silent := false) {
        global BindValidity, _ms_cancel_gen, _ms_running
        if state = 1 && BindValidity != 1 {
            BindValidity := 1
            ms.cam.enable()
            if !silent {
                ms._notify(1)
            }

        } else if state = 0 && BindValidity != 0 {
            BindValidity := 0
            ms.cancelMacros()
            _ms_running := Map()
            ms.cam.disable()
            if !silent {
                ms._notify(0)
            }

        }
    }


    static cancelMacros() {
        global _ms_cancel_gen
        _ms_cancel_gen++   ; all pending ms.wait() calls will see the change
    }


    ; Callback for _notify timer (avoid anonymous block-body function)
    static _notifyTimer(state, *) {
        global loadfinish
        if loadfinish != 1 {
            return
        }
        if state = 1 {
            ms.playSlot("enabled")
            ms.alert("Macros enabled!", 3, true)
        } else {
            ms.playSlot("disabled")
            ms.alert("Macros disabled.", 3, true)
        }

    }

    ; Debounced 50ms state-change toast + sound.
    static _notify(state) {
        global _ms_notify_timer
        if _ms_notify_timer
            SetTimer _ms_notify_timer, 0
        _ms_notify_timer := ms._notifyTimer.Bind(state)
        SetTimer _ms_notify_timer, -50
    }


    ; ── reloadSettings ────────────────────────────────────────────────────────

    static reloadSettings() {
        ms.loadSettings()
        ms.bind.rebind()
        ms.cam.updateMultiplier()
        ms.socdApply()
        ms.playSlot("update")
        ms.alert("Settings reloaded.", 5, true)
    }


    ; ── Settings persistence ──────────────────────────────────────────────────

    static saveSettings() {
        global _ms_json_path, _ms_binds, _ms_bindConfig, _ms_subBinds
        global _ms_modConfig, _ms_cooldowns, _ms_user_vals
        global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign, _ms_importedSounds
        global _ms_trackpad_mode, _ms_trackpad_hold_keys, _ms_independent_binds
        global CUR_CAM_SENS, clickLevel

        local macros := Map()

        ; Enabled state per macro
        for id, enabled in _ms_binds {
            if !macros.Has(id) {
                macros[id] := Map()
            }
            macros[id]["enabled"] := enabled
        }

        ; Root bind overrides (only when different from code default)
        for id, cfg in _ms_bindConfig {
            local def := ms.bind._defs.Has(id) ? ms.bind._defs[id].default : ""
            if def = "" {
                continue
            }
            local isDiff := false
            if cfg.type != def.type {
                isDiff := true
            } else if cfg.type = "mouse" && cfg.button != def.button {
                isDiff := true
            } else if cfg.type = "key" {
                local cfgMods := cfg.HasProp("mods") ? cfg.mods : []
                local defMods := def.HasProp("mods")  ? def.mods  : []
                cfgMods.Sort(), defMods.Sort()
                local cm := "", dm := ""
                for m in cfgMods {
                    cm .= m "+"
                }
                for m in defMods {
                    dm .= m "+"
                }
                if cfg.key != def.key || cm != dm {
                    isDiff := true
                }

            }
            if isDiff {
                if !macros.Has(id) {
                    macros[id] := Map()
                }
                macros[id]["bind"] := cfg
            }

        }
        ; Modifier overrides
        for id, key in _ms_modConfig {
            if !macros.Has(id) {
                macros[id] := Map()
            }
            macros[id]["mod"] := key
        }

        ; Sub-item independent binds
        for id, cfg in _ms_subBinds {
            if !macros.Has(id) {
                macros[id] := Map()
            }
            macros[id]["bind"] := cfg
        }

        ; Cooldown overrides
        for id, cd in _ms_cooldowns {
            if !macros.Has(id) {
                macros[id] := Map()
            }
            macros[id]["cooldown"] := cd
        }


        local data := Map(
            "sensitivity",      CUR_CAM_SENS,
            "frameLevel",       clickLevel,
            "trackpadMode",     _ms_trackpad_mode,
            "socdEnabled",      ms.socdEnabled,
            "socdMode",         ms.socdMode,
            "independentBinds", _ms_independent_binds,
            "trackpadHoldKeys", Map("left", _ms_trackpad_hold_keys.left, "right", _ms_trackpad_hold_keys.right),
            "soundEnabled",     _ms_soundEnabled,
            "soundVolume",      _ms_soundVolume,
            "soundAssign",      _ms_soundAssign,
            "importedSounds",   _ms_importedSounds,
            "user",             _ms_user_vals,
            "macros",           macros
        )
        DirCreate A_ScriptDir "\data"
        try FileOpen(_ms_json_path, "w").Write(Jxon_Dump(data, 4))
    }


    static loadSettings() {
        global _ms_json_path, _ms_default_path
        if FileExist(_ms_json_path) {
            local raw := ""
            FileRead &raw, _ms_json_path
            local data := Jxon_Load(&raw)
            if data {
                ms._applySettings(data)
                return
            }

        }
        if FileExist(_ms_default_path) {
            local raw2 := ""
            FileRead &raw2, _ms_default_path
            local data2 := Jxon_Load(&raw2)
            if data2 {
                ms._applySettings(data2)
                return
            }

        }
        ms._buildDefaultSettings()
        if FileExist(_ms_default_path) {
            local raw3 := ""
            FileRead &raw3, _ms_default_path
            local data3 := Jxon_Load(&raw3)
            if data3 {
                ms._applySettings(data3)
            }

        }
    }


    static _applySettings(data) {
        global _ms_binds, _ms_bindConfig, _ms_subBinds, _ms_modConfig, _ms_cooldowns
        global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign, _ms_importedSounds
        global _ms_trackpad_mode, _ms_trackpad_hold_keys, _ms_independent_binds
        global _ms_user_index, _ms_user_vals, CUR_CAM_SENS, clickLevel

        if !data {
            return
        }
        if data.Has("sensitivity") {
            local n := Number(data["sensitivity"])
            if n >= 0.1 && n <= 4 {
                CUR_CAM_SENS := n
            }

        }
        if data.Has("frameLevel") {
            local n := Number(data["frameLevel"])
            if n >= 1 && n <= 4 {
                clickLevel := Integer(n)
            }

        }
        if data.Has("trackpadMode") {
            _ms_trackpad_mode        := (data["trackpadMode"]     = true)
        }
        if data.Has("socdEnabled") {
            ms.socdEnabled           := (data["socdEnabled"]      = true)
        }
        if data.Has("independentBinds") {
            _ms_independent_binds := (data["independentBinds"] = true)
        }
        if data.Has("socdMode") {
            local m := data["socdMode"]
            if m = "lastWins" || m = "neutral" || m = "firstWins"
                ms.socdMode := m
        }

        if data.Has("trackpadHoldKeys") {
            local thk := data["trackpadHoldKeys"]
            if thk.Has("left") {
                _ms_trackpad_hold_keys.left  := thk["left"]
            }
            if thk.Has("right") {
                _ms_trackpad_hold_keys.right := thk["right"]
            }

        }
        if data.Has("soundEnabled") {
            _ms_soundEnabled := (data["soundEnabled"] = true)
        }
        if data.Has("soundVolume") {
            local v := Number(data["soundVolume"])
            if v >= 0 && v <= 100 {
                _ms_soundVolume := Integer(v)
            }

        }
        if data.Has("soundAssign") {
            _ms_soundAssign    := data["soundAssign"]
        }
        if data.Has("importedSounds") {
            _ms_importedSounds := data["importedSounds"]
        }
        if data.Has("macros") {
            for id, entry in data["macros"] {
                if entry.Has("enabled") {
                    _ms_binds[id] := (entry["enabled"] = true)
                }

                if entry.Has("bind") {
                    local def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
                    if def != "" && def.sub != "" {
                        _ms_subBinds[id] := entry["bind"]
                    } else {
                        _ms_bindConfig[id] := entry["bind"]
                    }

                }
                if entry.Has("mod") {
                    _ms_modConfig[id] := entry["mod"]
                }
                if entry.Has("cooldown") {
                    local n := Number(entry["cooldown"])
                    if n >= 0 {
                        _ms_cooldowns[id] := Integer(n)
                    }

                }
            }

        }
        if data.Has("user") {
            for key, val in data["user"] {
                if _ms_user_index.Has(key) {
                    local uDef := _ms_user_index[key]
                    local validated := ms._validateUserValue(uDef, val)
                    if validated != "" {
                        _ms_user_vals[key] := validated
                        if uDef.HasProp("onChange") && uDef.onChange is Func
                            try uDef.onChange.Call(validated)
                    }

                }
            }

        }
    }


    static _buildDefaultSettings() {
        global _ms_default_path, _ms_archive_path
        DirCreate A_ScriptDir "\data"
        local data := Map(
            "sensitivity",      1.5,
            "frameLevel",       3,
            "trackpadMode",     false,
            "socdEnabled",      false,
            "socdMode",         "lastWins",
            "independentBinds", false,
            "trackpadHoldKeys", Map("left", "n", "right", "j"),
            "soundEnabled",     true,
            "soundVolume",      100,
            "soundAssign",      Map(),
            "macros",           Map()
        )
        if ms.macroDefaults.HasProp("sensitivity") {
            data["sensitivity"]      := ms.macroDefaults.sensitivity
        }
        if ms.macroDefaults.HasProp("frameLevel") {
            data["frameLevel"]       := ms.macroDefaults.frameLevel
        }
        if ms.macroDefaults.HasProp("trackpadMode") {
            data["trackpadMode"]     := ms.macroDefaults.trackpadMode
        }
        if ms.macroDefaults.HasProp("socdEnabled") {
            data["socdEnabled"]      := ms.macroDefaults.socdEnabled
        }
        if ms.macroDefaults.HasProp("socdMode") {
            data["socdMode"]         := ms.macroDefaults.socdMode
        }
        for _, id in ms.bind._defList {
            local def := ms.bind._defs[id]
            if !def || def.sub != "" {
                continue
            }
            if !data["macros"].Has(id) {
                data["macros"][id] := Map()
            }
            if !data["macros"][id].Has("enabled") {
                data["macros"][id]["enabled"] := def.enabled
            }

    }
        if ms.macroDefaults.HasProp("macros") {
            for id, entry in ms.macroDefaults.macros {
                if !data["macros"].Has(id) {
                    data["macros"][id] := Map()
                }

                for k, v in entry {
                    data["macros"][id][k] := v
                }

            }
        }

        try FileOpen(_ms_default_path, "w").Write(Jxon_Dump(data, 4))
    }


    static saveDefault() {
        ms.saveSettings()
        if !FileExist(_ms_json_path) {
            return
        }
        DirCreate _ms_archive_path
        local ts := FormatTime(, "yyyy-MM-dd_HHmm")
        try FileCopy _ms_default_path, _ms_archive_path "ms_settings_default_" ts ".json"
        FileCopy _ms_json_path, _ms_default_path, 1
        ms.alert("Default settings saved.", 3)
    }


    static resetToDefault() {
        global _ms_bindConfig, _ms_subBinds, _ms_modConfig, _ms_cooldowns
        if !FileExist(_ms_default_path) {
            ms.alert("No default settings file found.", 3)
            return false
        }

        local raw := ""
        FileRead &raw, _ms_default_path
        local data := Jxon_Load(&raw)
        if !data {
            ms.alert("Default settings file could not be decoded.", 3)
            return false
        }

        _ms_bindConfig := Map(), _ms_subBinds := Map()
        _ms_modConfig  := Map(), _ms_cooldowns := Map()
        ms._applySettings(data)
        for key, def in _ms_user_index {
            if def.type != "action" && def.HasProp("default") && def.default != "" {
                _ms_user_vals[key] := def.default
                if def.HasProp("onChange") && def.onChange is Func
                    try def.onChange.Call(def.default)
            }

        }
        ms.saveSettings()
        ms.bind.rebind()
        ms.cam.updateMultiplier()
        ms.socdApply()
        return true
    }


    ; ── Sound discovery ───────────────────────────────────────────────────────

    static _discoverSounds() {
        global _ms_sounds, _ms_importedSounds
        _ms_sounds := Map()
        if DirExist(SoundLib) {
            Loop Files SoundLib "*.*" {
                local name := RegExReplace(A_LoopFileName, "\.[^.]+$")
                if name != "" {
                    _ms_sounds[name] := A_LoopFileFullPath
                }

            }
        }

        for name, filename in _ms_importedSounds {
            local path := SoundLib filename
            if FileExist(path) && !_ms_sounds.Has(name)
                _ms_sounds[name] := path
        }

    }

    ; ── SOCD ──────────────────────────────────────────────────────────────────
    ; State lives in _ms_socd_* globals; socdMode/socdEnabled are static here.

    static socdEnabled := false
    static socdMode    := "lastWins"

    static socdStart() {
        global _ms_socd_active
        if _ms_socd_active {
            return
        }
        _ms_socd_active := true
        global _ms_socd_held
        _ms_socd_held := Map("a", false, "d", false, "w", false, "s", false)
        HotIfWinActive _ms_target_exe
        Hotkey "$a",    _ms_socdKeyDown.Bind("a"), "On"
        Hotkey "$a Up", _ms_socdKeyUp.Bind("a"),   "On"
        Hotkey "$d",    _ms_socdKeyDown.Bind("d"), "On"
        Hotkey "$d Up", _ms_socdKeyUp.Bind("d"),   "On"
        Hotkey "$w",    _ms_socdKeyDown.Bind("w"), "On"
        Hotkey "$w Up", _ms_socdKeyUp.Bind("w"),   "On"
        Hotkey "$s",    _ms_socdKeyDown.Bind("s"), "On"
        Hotkey "$s Up", _ms_socdKeyUp.Bind("s"),   "On"
        HotIfWinActive
    }


    static socdStop() {
        global _ms_socd_active
        if !_ms_socd_active {
            return
        }
        _ms_socd_active := false
        HotIfWinActive _ms_target_exe
        try Hotkey "$a",    "Off"
        try Hotkey "$a Up", "Off"
        try Hotkey "$d",    "Off"
        try Hotkey "$d Up", "Off"
        try Hotkey "$w",    "Off"
        try Hotkey "$w Up", "Off"
        try Hotkey "$s",    "Off"
        try Hotkey "$s Up", "Off"

        HotIfWinActive
        global _ms_socd_held
        _ms_socd_held := Map("a", false, "d", false, "w", false, "s", false)
    }


    static socdApply() {
        if ms.socdEnabled {
            ms.socdStart()
        } else {
            ms.socdStop()
        }

    }

    ; ── User Settings API ─────────────────────────────────────────────────────

    class settings {
        static define(def) {
            global _ms_user_defs, _ms_user_index, _ms_user_vals
            local validTypes := Map("toggle",true,"slider",true,"seg",true,"action",true,"divider",true,"groupLabel",true,"soundSlot",true)
            local t := def.HasProp("type") ? def.type : ""
            if !validTypes.Has(t) {
                throw Error("ms.settings.define: unknown type '" t "'")
            }
            if t = "divider" || t = "groupLabel" {
                _ms_user_defs.Push(def)
                return
            }

            local key := def.HasProp("key") ? def.key : ""
            if key = "" {
                throw Error("ms.settings.define: 'key' is required for type '" t "'")
            }
            if _ms_user_index.Has(key) {
                throw Error("ms.settings.define: duplicate key '" key "'")
            }
            _ms_user_index[key] := def
            _ms_user_defs.Push(def)
            if t = "action" || t = "soundSlot" {
                return
            }
            local default := def.HasProp("default") ? def.default : ""
            _ms_user_vals[key] := default
            if default != "" && def.HasProp("onChange") && def.onChange is Func
                try def.onChange.Call(default)
        }


        static get(key) {
            global _ms_user_index, _ms_user_vals
            if !_ms_user_index.Has(key) {
                return ""
            }
            local def := _ms_user_index[key]
            local v := _ms_user_vals.Has(key) ? _ms_user_vals[key] : ""
            return v != "" ? v : (def.HasProp("default") ? def.default : "")
        }


        static set(key, value) {
            global _ms_user_index, _ms_user_vals
            if !_ms_user_index.Has(key) {
                return
            }
            local def := _ms_user_index[key]
            if def.type = "action" {
                return
            }
            local validated := ms._validateUserValue(def, value)
            if validated = "" {
                return
            }
            _ms_user_vals[key] := validated
            if def.save != false {
                ms.saveSettings()
            }
            if def.HasProp("onChange") && def.onChange is Func
                try def.onChange.Call(validated)
        }

    }

    class menu {
        static define(def) {
            global _ms_menu_defs, _ms_user_index, _ms_user_vals
            for item in (def.HasProp("items") ? def.items : []) {
                if item.HasProp("key") && item.key != "" && !_ms_user_index.Has(item.key) {
                    _ms_user_index[item.key] := item
                    if item.type != "action" {
                        local dv := item.HasProp("default") ? item.default : ""
                        _ms_user_vals[item.key] := dv
                        if dv != "" && item.HasProp("onChange") && item.onChange is Func
                            try item.onChange.Call(dv)
                    }

                }
            }

            _ms_menu_defs.Push(def)
        }

    }

    class features {
        static hide(name) {
            global _ms_hidden_feats
            static allowed := Map("socd",true,"trackpad",true,"independentBinds",true,"sensitivity",true)
            if !allowed.Has(name) {
                OutputDebug "ms.features.hide: '" name "' is not a hideable feature."
            } else {
                _ms_hidden_feats[name] := true
            }

        }
    }


    static _validateUserValue(def, value) {
        if def.type = "toggle" {
            if value = true || value = false {
                return value
            }

        } else if def.type = "slider" {
            local n := Number(value)
            if n != "" {
                return Max(def.HasProp("min") ? def.min : 0, Min(def.HasProp("max") ? def.max : 100, n))
            }

        } else if def.type = "seg" {
            if def.HasProp("options")
                for opt in def.options
                    if opt.HasProp("value") && opt.value = value {
                        return value
                    }

        }
        return ""
    }


    static setClickLevel(n) {
        global clickLevel
        n := Integer(n)
        if n = 1 || n = 2 || n = 3 || n = 4 {
            clickLevel := n
        }

    }

    ; ── has(feature) ─────────────────────────────────────────────────────────

    static has(feature) {
        global _ms_sounds, _ms_soundEnabled, _ms_theme_loaded, _ms_profiles_path
        if feature = "theme" {
            return _ms_theme_loaded = true
        }
        if feature = "sound" {
            return _ms_soundEnabled = true && _ms_sounds.Count > 0
        }
        if feature = "socd" {
            return ms.socdEnabled = true
        }
        if feature = "trackpad" {
            return _ms_trackpad_mode = true
        }
        if feature = "profiles" {
            return _ms_getProfiles().Length > 0
        }
        if feature = "userSettings" {
            return true
        }
        if feature = "userMenu" {
            return true
        }
        if feature = "integrity" {
            return ms.integrity.check() = "trusted"
        }
        if feature = "hidinject" {
            return FileExist(A_ScriptDir "\bin\hidinject") != ""
        }
        return false
    }


    ; ── Theme system ──────────────────────────────────────────────────────────

    static loadTheme() {
        global _ms_theme_path, _ms_theme, _ms_theme_loaded
        for k, v in Map("bg","#060402","surface","#100806","surface2","#1c100c","hover","#301610","accent","#c41a1a","accentHi","#e52424","success","#4a7820","dangerBg","#1e0608","danger","#d42020","warning","#c47820","text","#f0ddb0","radius",3,"font","Almendra")
            _ms_theme[k] := v
        if !FileExist(_ms_theme_path) {
            return
        }
        local raw := ""
        FileRead &raw, _ms_theme_path
        local data := Jxon_Load(&raw)
        if !data {
            return
        }
        _ms_theme_loaded := true
        for _, k in ["bg","surface","surface2","hover","accent","accentHi","success","dangerBg","danger","warning","text"] {
            if data.Has(k) && RegExMatch(data[k], "^#[0-9a-fA-F]+$")
                _ms_theme[k] := data[k]
        }

        if data.Has("radius") && data["radius"] is Number
            _ms_theme["radius"] := Max(0, Min(40, Integer(data["radius"])))
        if data.Has("font") && data["font"] != "" {
            local clean := RegExReplace(data["font"], "[;{}()<>""]", "")
            if clean != "" {
                _ms_theme["font"] := clean
            }

        }
    }


    ; ── System Integrity ──────────────────────────────────────────────────────

    class integrity {
        static hashFile(path) {
            local out := ""
            RunWait 'powershell -NoProfile -Command "(Get-FileHash \"' path '\" -Algorithm SHA256).Hash.ToLower()" > "' A_Temp '\ms_hash.txt"',, "Hide"
            try {
                FileRead &out, A_Temp "\ms_hash.txt"
                FileDelete A_Temp "\ms_hash.txt"
            }

            local h := Trim(out)
            return (StrLen(h) = 64) ? h : ""
        }


        static readTrustedHash() {
            global _ms_hash_path
            if !FileExist(_ms_hash_path) {
                return ""
            }
            local h := ""
            FileRead &h, _ms_hash_path
            h := Trim(h)
            return (StrLen(h) = 64) ? h : ""
        }


        static writeTrustedHash(hash) {
            global _ms_hash_path
            DirCreate A_ScriptDir "\data"
            try {
                FileOpen(_ms_hash_path, "w").Write(hash "`n")
                return true
            }

            return false
        }


        static deleteTrustedHash() {
            global _ms_hash_path
            try FileDelete _ms_hash_path
            return !FileExist(_ms_hash_path)
        }


        static check() {
            global _ms_core_path
            local cur     := ms.integrity.hashFile(_ms_core_path)
            local trusted := ms.integrity.readTrustedHash()
            if trusted = "" {
                return "uninitialized"
            }
            return (cur = trusted) ? "trusted" : "mismatch"
        }


        static trustCurrent() {
            global _ms_core_path
            local hash := ms.integrity.hashFile(_ms_core_path)
            if hash = "" {
                ms.alert("System integrity: could not hash ms_core.ahk.", 4)
                return false
            }

            if ms.integrity.writeTrustedHash(hash) {
                ms.alert("Trusted hash saved.`n" SubStr(hash, 1, 16) "…", 4, true)
                return true
            }

            ms.alert("System integrity: could not write trusted hash file.", 4)
            return false
        }


        static update() {
            global _ms_manifest_url, _ms_archive_path, _ms_core_path, _ms_update_pubkey
            if !RegExMatch(_ms_manifest_url, "^https://") {
                ms.alert("Update URL must use HTTPS.", 6)
                return
            }

            ms.alert("Fetching update manifest…", 4, true)
            ; Download manifest to temp file
            local tmpManifest := A_Temp "\ms_manifest.json"
            try FileDelete tmpManifest
            local ret := 0
            RunWait 'powershell -NoProfile -Command "Invoke-WebRequest -Uri \"' _ms_manifest_url '\" -OutFile \"' tmpManifest '\" -UseBasicParsing"',, "Hide", &ret
            if !FileExist(tmpManifest) {
                ms.alert("Update failed: could not download manifest.", 5)
                return
            }

            local raw := ""
            FileRead &raw, tmpManifest
            try FileDelete tmpManifest
            local manifest := Jxon_Load(&raw)
            if !manifest || !manifest.Has("windows_sha256") || !manifest.Has("windows_url") {
                ms.alert("Update failed: manifest missing Windows fields.", 5)
                return
            }

            local newVer       := manifest.Has("version")      ? manifest["version"]      : "?"
            local expectedHash := manifest["windows_sha256"]
            local dlURL        := manifest["windows_url"]
            ms.alert("Downloading v" newVer "…", 4, true)
            local tmpFile := A_Temp "\ms_core_update.ahk"
            try FileDelete tmpFile
            RunWait 'powershell -NoProfile -Command "Invoke-WebRequest -Uri \"' dlURL '\" -OutFile \"' tmpFile '\" -UseBasicParsing"',, "Hide"
            if !FileExist(tmpFile) {
                ms.alert("Update failed: could not download file.", 5)
                return
            }

            local actualHash := ms.integrity.hashFile(tmpFile)
            if actualHash != StrLower(expectedHash)
                OutputDebug "ms update: MANIFEST hash mismatch (expected " SubStr(expectedHash,1,16) "… got " SubStr(actualHash,1,16) "…) — installing anyway."
            ; Backup current file
            DirCreate _ms_archive_path
            local ts := FormatTime(, "yyyy-MM-dd_HHmm")
            local backupFile := _ms_archive_path "ms_core_" ts ".ahk.bak"
            FileCopy _ms_core_path, backupFile, 1
            ; Replace
            try {
                FileDelete _ms_core_path
                FileCopy tmpFile, _ms_core_path
                FileDelete tmpFile
            }

            ms.integrity.writeTrustedHash(actualHash)
            ms.alert("Updated to v" newVer ".`nReloading in 3 seconds…", 5, true)
            SetTimer () => Reload(), -3000
        }

    }

    ; ── Profile system ────────────────────────────────────────────────────────

    ; auditMacros — static scanner for dangerous AHKv2 patterns (mirrors Lua auditMacros)
    static auditMacros(src) {
        local errs := []
        static patterns := [
            "DllCall\s*\(",
            "FileAppend\s*[^,]*,\s*[^,]*[A-Z]:\\",
            "RunWait?\s+[^`n]*(?:cmd|powershell|reg|wscript)",
            "RegWrite\b", "RegDelete\b",
            "EnvSet\b",
            "A_AppData\b", "A_WinDir\b", "A_ProgramFiles\b"
        ]
        for p in patterns
            if RegExMatch(src, "i)" p)
                errs.Push("Blocked pattern: " p)
        return errs
    }


    static switchProfile(targetName) {
        global _ms_profiles_path, _ms_json_path
        local targetFile := _ms_profiles_path targetName "\ms_macros.ahk"
        if !FileExist(targetFile) {
            ms.alert("Profile switch failed: cannot read target profile.", 5)
            return
        }

        local raw := ""
        FileRead &raw, targetFile
        local errs := ms.auditMacros(raw)
        if errs.Length > 0 {
            ms.alert("Profile blocked: " errs[1], 6)
            return
        }

        ; Archive current macros + settings
        DirCreate _ms_profiles_path
        local curName := ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "default"
        local safeN := RegExReplace(curName, '[/\\:*?"<>|]', "_")
        DirCreate _ms_profiles_path safeN
        FileCopy A_ScriptDir "\ms_macros.ahk", _ms_profiles_path safeN "\ms_macros.ahk", 1
        FileCopy _ms_json_path, _ms_profiles_path safeN "\ms_settings.json", 1
        ; Activate target
        FileCopy targetFile, A_ScriptDir "\ms_macros.ahk", 1
        local tSettingsFile := _ms_profiles_path targetName "\ms_settings_default.json"
        if FileExist(tSettingsFile)
            FileCopy tSettingsFile, _ms_json_path, 1
        ms.playSlot("update")
        ms.alert("Switched to '" targetName "'.`nReloading in 3 s…", 5, true)
        SetTimer () => Reload(), -3000
    }


    static exportProfilePkg() {
        global _ms_archive_path
        local name := ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "profile"
        local safe := RegExReplace(name, '[/\\:*?"<>|]', "_")
        local outFile := A_MyDocuments "\Downloads\" safe ".mspkg"
        local tmpDir := A_Temp "\ms_export_" A_TickCount
        DirCreate tmpDir
        FileCopy A_ScriptDir "\ms_macros.ahk",                tmpDir "\ms_macros.ahk",         1
        FileCopy A_ScriptDir "\data\ms_settings_default.json", tmpDir "\ms_settings_default.json", 0
        FileCopy A_ScriptDir "\data\ms_theme.json",            tmpDir "\ms_theme.json",          0
        DirCreate tmpDir "\sounds"
        Loop Files SoundLib "*.*" {
            FileCopy A_LoopFileFullPath, tmpDir "\sounds\" A_LoopFileName, 0
        }

        RunWait 'powershell -NoProfile -Command "Compress-Archive -Path \"' tmpDir '\*\" -DestinationPath \"' outFile '\" -Force"',, "Hide"
        DirDelete tmpDir, true
        ms.playSlot("update")
        ms.alert("Profile exported to:`n" outFile, 6)
    }


    static importProfilePkg() {
        local file := FileSelect(3, A_ScriptDir, "Select a .mspkg file", "Macro Pack (*.mspkg)")
        if file = "" {
            return
        }
        local tmpDir := A_Temp "\ms_import_" A_TickCount
        DirCreate tmpDir
        RunWait 'powershell -NoProfile -Command "Expand-Archive -Path \"' file '\" -DestinationPath \"' tmpDir '\" -Force"',, "Hide"
        local macrosFile := tmpDir "\ms_macros.ahk"
        if !FileExist(macrosFile) {
            DirDelete tmpDir, true
            ms.alert("Import failed: ms_macros.ahk not found in package.", 5)
            return
        }

        local raw := ""
        FileRead &raw, macrosFile
        local errs := ms.auditMacros(raw)
        if errs.Length > 0 {
            DirDelete tmpDir, true
            ms.alert("Import blocked: " errs[1], 6)
            return
        }

        ; Read meta to get profile name
        local profileName := "imported"
        ; Copy macros + sounds
        global _ms_profiles_path
        DirCreate _ms_profiles_path profileName
        FileCopy macrosFile, _ms_profiles_path profileName "\ms_macros.ahk", 1
        if FileExist(tmpDir "\ms_settings_default.json")
            FileCopy tmpDir "\ms_settings_default.json", _ms_profiles_path profileName "\ms_settings_default.json", 1
        if FileExist(tmpDir "\sounds") {
            Loop Files tmpDir "\sounds\*.*" {
                if !FileExist(SoundLib A_LoopFileName)
                    FileCopy A_LoopFileFullPath, SoundLib A_LoopFileName
            }

        }
        DirDelete tmpDir, true
        ms.playSlot("update")
        ms.alert('"' profileName '" imported.`nSwitch to it from Settings → Profiles.', 6, true)
        ms.ui.refresh()
    }


    static importSounds() {
        local files := FileSelect("M3", SoundLib, "Select sound files to import")
        if !files {
            return
        }
        local added := 0
        for file in files {
            if !FileExist(file) {
                continue
            }
            local fname := RegExReplace(file, ".*[/\\]")
            local dst := SoundLib fname
            if !FileExist(dst) {
                FileCopy file, dst
                global _ms_importedSounds
                local name := RegExReplace(fname, "\.[^.]+$")
                _ms_importedSounds[name] := fname
                added++
            }

        }
        if added > 0 {
            ms.saveSettings()
            ms._discoverSounds()
        }

        ms.playSlot("update")
        ms.ui.refresh()
    }


    ; ── UI panel (WebView2) ───────────────────────────────────────────────────

    class ui {
        static _panel_gui := 0
        static _panel_wv  := 0
        static _open      := false
        static _modal_cb  := 0
        static _pos       := {x: 0, y: 0, w: 360, h: 640}


        static show() {
            if ms.ui._open && ms.ui._panel_gui {
                WinActivate "ahk_id " ms.ui._panel_gui.Hwnd
                return
            }

            local panelW := 360, panelH := 640
            local gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
            gui.OnEvent("Close", (*) => ms.ui._onClose())
            gui.Show("w" panelW " h" panelH " NoActivate")
            ms.ui._pos := {x: 0, y: 0, w: panelW, h: panelH}

            ; Position: left-centre of screen
            MonitorGetWorkArea , &sL, &sT, &sR, &sB
            local x := sL + Floor((sR - sL) / 4 - panelW / 2)
            local y := sT + Floor(((sB - sT) - panelH) / 2)
            gui.Move(x, y)
            ms.ui._pos.x := x, ms.ui._pos.y := y
            local wv := WebView2.create(gui.Hwnd)
            wv.Navigate("file:///" A_ScriptDir "\ui\ms_settings_ui.html")
            wv.OnEvent("WebMessageReceived", ms.ui._onMessage.Bind(ms.ui))
            ms.ui._panel_gui := gui
            ms.ui._panel_wv  := wv
            ms.ui._open      := true
            global _ms_ui_open_flag := true
            ms.playSlot("settingsOpen")
            ; Push state once page is ready (ready action triggers refresh)
        }


        static hide() {
            if ms.ui._panel_gui {
                ms.playSlot("settingsClose")
                ms.ui._panel_gui.Destroy()
                ms.ui._panel_gui := 0
                ms.ui._panel_wv  := 0
            }

            ms.ui._open := false
            global _ms_ui_open_flag := false
        }


        static toggle() {
            if ms.ui._open {
                ms.ui.hide()
            } else {
                ms.ui.show()
            }

        }

        static refresh() {
            if !ms.ui._panel_wv {
                return
            }
            local json := Jxon_Dump(ms._buildUIState(), 0)
            try ms.ui._panel_wv.ExecuteScript("receiveState(" json ")")
        }


        static _onClose() {
            ms.ui._open := false
            global _ms_ui_open_flag := false
            ms.ui._panel_gui := 0
            ms.ui._panel_wv  := 0
            ms.playSlot("settingsClose")
            ; Restore target window focus
            global _ms_target_exe
            if _ms_target_exe != ""
                try WinActivate _ms_target_exe
        }


        static _onMessage(self, wv, event) {
            local raw := event.TryGetWebMessageAsString()
            local data := Jxon_Load(&raw)
            if !data || !data.Has("action") {
                return
            }
            local action := data["action"]
            if ms.ui._actions.Has(action) {
                try ms.ui._actions[action].Call(data)
            } else {
                OutputDebug "ms.ui: unknown action: " action
            }

        }

        static _actions := Map(
            "ready",        (data) => ms.ui.refresh(),
            "setMacros",    (data) => (ms.setMacros(data.Has("value") && data["value"] = 1 ? 1 : 0), ms.ui.refresh()),
            "playSlot",     (data) => (data.Has("slot") ? ms.playSlot(data["slot"]) : 0),
            "alert",        (data) => (data.Has("msg") ? ms.alert(data["msg"], data.Has("duration") ? data["duration"] : 3) : 0),
            "close",        (data) => ms.ui.hide(),
            "moveWindow",   (data) {
                if !ms.ui._panel_gui {
                    return
                }
                local dx := data.Has("dx") ? data["dx"] : 0
                local dy := data.Has("dy") ? data["dy"] : 0
                ms.ui._pos.x += dx, ms.ui._pos.y += dy
                ms.ui._panel_gui.Move(ms.ui._pos.x, ms.ui._pos.y)
            },
            "reloadMacros", (data) => Reload(),
            "reloadSettings", (data) => (ms.reloadSettings(), ms.ui.refresh()),
            "setMacroEnabled", (data) {
                if !data.Has("id") {
                    return
                }
                global _ms_binds
                _ms_binds[data["id"]] := (data.Has("value") && data["value"] = true)
                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
            },
            "setSensitivity", (data) {
                local n := data.Has("value") ? Number(data["value"]) : 0
                if n >= 0.1 && n <= 4 {
                    global CUR_CAM_SENS := n
                    ms.saveSettings(), ms.cam.updateMultiplier(), ms.playSlot("update")
                }

                ms.ui.refresh()
            },
            "setTrackpadMode", (data) {
                global _ms_trackpad_mode := (data.Has("value") && data["value"] = true)
                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
            },
            "setSocdEnabled", (data) {
                ms.socdEnabled := (data.Has("value") && data["value"] = true)
                ms.saveSettings(), ms.socdApply(), ms.playSlot("update"), ms.ui.refresh()
            },
            "setSocdMode", (data) {
                local m := data.Has("value") ? data["value"] : ""
                if m = "lastWins" || m = "neutral" || m = "firstWins" {
                    ms.socdMode := m, ms.saveSettings(), ms.playSlot("update")
                }

                ms.ui.refresh()
            },
            "setIndependentBinds", (data) {
                global _ms_independent_binds := (data.Has("value") && data["value"] = true)
                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
            },
            "setSoundEnabled", (data) {
                global _ms_soundEnabled := (data.Has("value") && data["value"] = true)
                ms.saveSettings(), ms.playSlot("update"), ms.ui.refresh()
            },
            "setSoundVolume", (data) {
                local n := data.Has("value") ? Number(data["value"]) : -1
                if n >= 0 && n <= 100 {
                    global _ms_soundVolume := Integer(n)
                    ms.saveSettings(), ms.playSlot("update")
                }

                ms.ui.refresh()
            },
            "setSoundAssign", (data) {
                if !data.Has("slot") {
                    return
                }
                global _ms_soundAssign
                local name := data.Has("name") ? data["name"] : ""
                if name = "" {
                    _ms_soundAssign.Delete(data["slot"])
                } else {
                    _ms_soundAssign[data["slot"]] := name
                }

                ms.saveSettings(), ms.playSlot("update"), ms.ui.refresh()
            },
            "importSounds",      (data) => ms.importSounds(),
            "switchProfile",     (data) => (data.Has("name") ? ms.switchProfile(data["name"]) : 0),
            "importProfilePkg",  (data) => ms.importProfilePkg(),
            "exportProfilePkg",  (data) => ms.exportProfilePkg(),
            "saveDefault",       (data) => (ms.saveDefault(), ms.ui.refresh()),
            "resetToDefault",    (data) => (ms.resetToDefault() ? ms.playSlot("reset") : 0, ms.ui.refresh()),
            "trustCurrentVersion",(data) => (ms.integrity.trustCurrent(), ms.ui.refresh()),
            "deleteTrustedHash", (data) => (ms.integrity.deleteTrustedHash(), ms.ui.refresh()),
            "checkIntegrity",    (data) => ms.ui.refresh(),
            "checkForUpdate",    (data) => ms.integrity.update(),
            "openConsole",       (data) => ms.dev.console.toggle(),
            "openWatcher",       (data) => ms.dev.watcher.toggle(),
            "openKeys",          (data) => ms.dev.keys.toggle(),
            "openWindow",        (data) => ms.dev.window.toggle(),
            "startRebind",       (data) {
                if !data.Has("id") {
                    return
                }
                ms.ui.hide()
                _ms_captureRebind(data["id"])
            },
            "setModifier", (data) {
                if !data.Has("id") {
                    return
                }
                global _ms_modConfig
                local key := data.Has("key") ? Trim(data["key"]) : ""
                if key = "" {
                    _ms_modConfig.Delete(data["id"])
                } else {
                    _ms_modConfig[data["id"]] := key
                }

                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
            },
            "startModRebind", (data) {
                if !data.Has("id") {
                    return
                }
                ms.ui.hide()
                _ms_captureModRebind(data["id"])
            },
            "resetBind", (data) {
                if !data.Has("id") {
                    return
                }
                local def := ms.bind._defs.Has(data["id"]) ? ms.bind._defs[data["id"]] : ""
                if def = "" {
                    return
                }
                if def.sub != "" {
                    _ms_subBinds.Delete(data["id"])
                } else {
                    _ms_bindConfig.Delete(data["id"])
                }

                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset"), ms.ui.refresh()
            },
            "clearModifier", (data) {
                if !data.Has("id") {
                    return
                }
                _ms_modConfig.Delete(data["id"])
                ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset"), ms.ui.refresh()
            },
            "reloadTheme", (data) => (ms.loadTheme(), ms.ui.refresh()),
            "openURL",    (data) => (data.Has("url") ? Run(data["url"]) : 0),
            "editMacros", (data) => Run(A_ScriptDir "\ms_macros.ahk"),
            "userSettingChange", (data) {
                if !data.Has("key") {
                    return
                }
                ms.settings.set(data["key"], data.Has("value") ? data["value"] : "")
                ms.playSlot("update"), ms.ui.refresh()
            },
            "userSettingAction", (data) {
                if !data.Has("key") {
                    return
                }
                global _ms_user_index
                if _ms_user_index.Has(data["key"]) {
                    local def := _ms_user_index[data["key"]]
                    if def.type = "action" && def.HasProp("onAction") && def.onAction is Func
                        try def.onAction.Call()
                }

                ms.ui.refresh()
            },
            "resetUserSetting", (data) {
                if !data.Has("key") {
                    return
                }
                global _ms_user_index
                if _ms_user_index.Has(data["key"]) {
                    local def := _ms_user_index[data["key"]]
                    if def.HasProp("default") {
                        ms.settings.set(data["key"], def.default)
                    }

                }
                ms.playSlot("reset"), ms.ui.refresh()
            },
            "modalResult", (data) {
                if ms.ui._modal_cb is Func {
                    local cb := ms.ui._modal_cb
                    ms.ui._modal_cb := 0
                    try cb.Call({confirmed: data.Has("confirmed") && data["confirmed"] = true, value: data.Has("value") ? data["value"] : ""})
                }

            },
            "resetSetting", (data) {
                if !data.Has("key") {
                    return
                }
                local key := data["key"]
                local def := ms.macroDefaults
                if key = "sensitivity"  && def.HasProp("sensitivity") {
                    global CUR_CAM_SENS := Number(def.sensitivity)
                    ms.saveSettings(), ms.cam.updateMultiplier()
                } else if key = "trackpadMode" && def.HasProp("trackpadMode") {
                    global _ms_trackpad_mode := (def.trackpadMode = true)
                    ms.saveSettings(), ms.bind.rebind()
                } else if key = "socdEnabled" && def.HasProp("socdEnabled") {
                    ms.socdEnabled := (def.socdEnabled = true)
                    ms.saveSettings(), ms.socdApply()
                } else if key = "socdMode" && def.HasProp("socdMode") {
                    ms.socdMode := def.socdMode
                    ms.saveSettings()
                } else if key = "independentBinds" && def.HasProp("independentBinds") {
                    global _ms_independent_binds := (def.independentBinds = true)
                    ms.saveSettings(), ms.bind.rebind()
                }

                ms.playSlot("reset"), ms.ui.refresh()
            }

        )

        static modal(data, callback) {
            if !callback {
                return
            }
            if !ms.ui._panel_wv { try callback.Call({confirmed: false}) ; return }

            ms.ui._modal_cb := callback
            if !ms.ui._open {
                ms.ui.show()
            }
            local json := Jxon_Dump(Map("title", data.HasProp("title") ? data.title : "", "msg", data.HasProp("msg") ? data.msg : "", "confirm", data.HasProp("confirm") ? data.confirm : "OK", "cancel", data.HasProp("cancel") ? data.cancel : "Cancel"), 0)
            SetTimer () => (ms.ui._panel_wv ? ms.ui._panel_wv.ExecuteScript("openLuaModal(" json ")") : 0), -50
        }


        static prompt(data, callback) {
            if !callback {
                return
            }
            if !ms.ui._panel_wv { try callback.Call({confirmed: false, value: ""}) ; return }

            ms.ui._modal_cb := callback
            if !ms.ui._open {
                ms.ui.show()
            }
            local json := Jxon_Dump(Map("title", data.HasProp("title") ? data.title : "", "msg", data.HasProp("msg") ? data.msg : "", "confirm", data.HasProp("confirm") ? data.confirm : "OK", "cancel", data.HasProp("cancel") ? data.cancel : "Cancel", "hasInput", true, "inputDefault", data.HasProp("default") ? data.default : ""), 0)
            SetTimer () => (ms.ui._panel_wv ? ms.ui._panel_wv.ExecuteScript("openLuaModal(" json ")") : 0), -50
        }

    }

    ; ── _buildUIState ─────────────────────────────────────────────────────────

    static _buildUIState() {
        global _ms_binds, _ms_bindConfig, _ms_subBinds, _ms_modConfig
        global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign, _ms_sounds
        global _ms_trackpad_mode, _ms_independent_binds, _ms_hidden_feats
        global _ms_user_defs, _ms_user_index, _ms_user_vals, _ms_menu_defs
        global _ms_theme, _ms_theme_loaded, CUR_CAM_SENS, clickLevel, BindValidity

        ms._discoverSounds()

        local macros := []
        for _, id in ms.bind._defList {
            local def := ms.bind._defs[id]
            if !def || def.sub != "" || (def.group != "main" && def.group != "optional") {
                continue
            }
            local enabled := _ms_binds.Has(id) ? _ms_binds[id] : def.enabled
            local subs := []
            for _, subId in ms.bind._defList {
                local subDef := ms.bind._defs[subId]
                if !subDef || subDef.sub != id {
                    continue
                }
                local bindDisp := ""
                if _ms_subBinds.Has(subId)
                    bindDisp := ms._bindDisplay(_ms_subBinds[subId])
                subs.Push(Map("id", subId, "label", subDef.label, "mod", ms.getMod(subId), "bind", bindDisp))
            }

            local bindStr := ms._bindDisplay(ms._effectiveBind(id))
            macros.Push(Map("id", id, "label", def.label, "group", def.group, "bind", bindStr, "enabled", enabled ? true : false, "subs", subs))
        }


        local soundNames := []
        for name, _ in _ms_sounds {
            soundNames.Push(name)
        }
        soundNames.Sort()

        local status := ms.integrity.check()
        local meta := ms.macroMeta

        local userSoundSlots := []
        for _, def in _ms_user_defs
            if def.HasProp("type") && def.type = "soundSlot"
                userSoundSlots.Push(Map("key", def.key, "label", def.HasProp("label") ? def.label : def.key))
        for _, menuDef in _ms_menu_defs
            if menuDef.HasProp("items")
                for item in menuDef.items
                    if item.HasProp("type") && item.type = "soundSlot"
                        userSoundSlots.Push(Map("key", item.key, "label", item.HasProp("label") ? item.label : item.key))

        local userSettings := []
        for _, def in _ms_user_defs {
            local item := Map("type", def.HasProp("type") ? def.type : "", "key", def.HasProp("key") ? def.key : "", "label", def.HasProp("label") ? def.label : "")
            if def.HasProp("type") && def.type = "slider" {
                item["min"] := def.HasProp("min") ? def.min : 0, item["max"] := def.HasProp("max") ? def.max : 100, item["step"] := def.HasProp("step") ? def.step : 1, item["unit"] := def.HasProp("unit") ? def.unit : ""
            }
            if def.HasProp("type") && def.type = "action" {
                item["btnLabel"] := def.HasProp("btnLabel") ? def.btnLabel : "Run", item["danger"] := def.HasProp("danger") && def.danger = true
            }
            if def.HasProp("key") && def.key != "" {
                item["value"] := ms.settings.get(def.key)
            }
            userSettings.Push(item)
        }


        local userMenus := []
        for _, menuDef in _ms_menu_defs {
            local items := []
            for item in (menuDef.HasProp("items") ? menuDef.items : []) {
                local entry := Map("type", item.HasProp("type") ? item.type : "", "key", item.HasProp("key") ? item.key : "", "label", item.HasProp("label") ? item.label : "")
                if item.HasProp("key") && item.key != "" {
                    entry["value"] := ms.settings.get(item.key)
                }
                items.Push(entry)
            }

            userMenus.Push(Map("id", menuDef.HasProp("id") ? menuDef.id : "", "title", menuDef.HasProp("title") ? menuDef.title : "", "icon", menuDef.HasProp("icon") ? menuDef.icon : "", "items", items))
        }


        local themeOut := Map()
        for k, v in _ms_theme {
            themeOut[k] := v
        }

        local profileName := meta.HasProp("name") ? meta.name : ""

        return Map(
            "macrosEnabled",           BindValidity = 1,
            "macros",                  macros,
            "sensitivity",             CUR_CAM_SENS,
            "trackpadMode",            _ms_trackpad_mode,
            "socdEnabled",             ms.socdEnabled,
            "socdMode",                ms.socdMode,
            "independentBindsEnabled", _ms_independent_binds,
            "soundEnabled",            _ms_soundEnabled,
            "soundVolume",             _ms_soundVolume,
            "soundAssign",             _ms_soundAssign,
            "soundNames",              soundNames,
            "currentProfile",          profileName,
            "profiles",                _ms_getProfiles(),
            "integrityStatus",         status,
            "integrityHash",           ms.integrity.hashFile(_ms_core_path),
            "macroMeta",               Map("name", meta.HasProp("name") ? meta.name : "", "author", meta.HasProp("author") ? meta.author : "", "website", meta.HasProp("website") ? meta.website : ""),
            "docsURL",                 _ms_docs_url,
            "updateManifestURL",       _ms_manifest_url,
            "userSettings",            userSettings,
            "userSoundSlots",          userSoundSlots,
            "userMenus",               userMenus,
            "hiddenFeatures",          _ms_hidden_feats,
            "theme",                   themeOut
        )
    }


    static _bindDisplay(c) {
        if c = "" {
            return ""
        }
        if c.HasProp("type") && c.type = "mouse" {
            return "Mouse " c.button
        }
        if c.HasProp("type") && c.type = "key" {
            local parts := []
            if c.HasProp("mods")
                for m in c.mods {
                    parts.Push(SubStr(m, 1, 1) = Chr(Ord(SubStr(m,1,1)) - 32) ? m : StrUpper(SubStr(m,1,1)) SubStr(m,2))
                }
            parts.Push(StrUpper(c.HasProp("key") ? c.key : ""))
            local out := ""
            for p in parts {
                out .= (out ? "+" : "") p
            }
            return out
        }

        return ""
    }


    ; ── Developer tools ───────────────────────────────────────────────────────

    class dev {
        class console {
            static show() {
                global _ms_dev_console_gui, _ms_dev_console_wv, _ms_dev_console_open, _ms_dev_console_pos
                if _ms_dev_console_open && _ms_dev_console_gui {
                    WinActivate "ahk_id " _ms_dev_console_gui.Hwnd
                    return
                }

                local w := 360, h := 640
                MonitorGetWorkArea , &sL, &sT, &sR, &sB
                local x := sR - w - 48, y := sT + 20
                local gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                gui.Show("w" w " h" h " x" x " y" y " NoActivate")
                local wv := WebView2.create(gui.Hwnd)
                wv.Navigate("file:///" A_ScriptDir "\ui\ms_console.html")
                wv.OnEvent("WebMessageReceived", (wv2, evt) {
                    global _ms_dev_console_pos, _ms_dev_console_gui
                    local raw := evt.TryGetWebMessageAsString()
                    local data := Jxon_Load(&raw)
                    if !data {
                        return
                    }
                    local act := data.Has("action") ? data["action"] : ""
                    if act = "close" {
                        ms.dev.console.hide()
                    } else if act = "clear" {
                        try FileOpen(_ms_dev_log_path, "w").Write("")
                    } else if act = "openWatcher" {
                        ms.dev.watcher.show()
                    } else if act = "openKeys" {
                        ms.dev.keys.show()
                    } else if act = "move" {
                        _ms_dev_console_pos["x"] += data.Has("dx") ? data["dx"] : 0
                        _ms_dev_console_pos["y"] += data.Has("dy") ? data["dy"] : 0
                        _ms_dev_console_gui.Move(_ms_dev_console_pos["x"], _ms_dev_console_pos["y"])
                    } else if act = "execute" {
                        _ms_devWrite(Map("type", "result", "msg", "REPL not available in AHKv2 runtime."))
                    }

                })
                _ms_dev_console_gui := gui
                _ms_dev_console_wv  := wv
                _ms_dev_console_pos := Map("x", x, "y", y, "w", w, "h", h)
                _ms_dev_console_open := true
                _ms_loadDevHistory(wv, "")
            }

            static hide()   { global _ms_dev_console_open := false ; if _ms_dev_console_gui  _ms_dev_console_gui.Destroy(), (_ms_dev_console_gui := 0) }

            static toggle() { if _ms_dev_console_open  ms.dev.console.hide() ; else  ms.dev.console.show() }

        }

        class watcher {
            static show() {
                global _ms_dev_watcher_gui, _ms_dev_watcher_wv, _ms_dev_watcher_open, _ms_dev_watcher_pos
                if _ms_dev_watcher_open && _ms_dev_watcher_gui { WinActivate "ahk_id " _ms_dev_watcher_gui.Hwnd ; return }

                local w := 270, h := 480
                MonitorGetWorkArea , &sL, &sT, &sR, &sB
                local x := sR - 360 - 24, y := sT + 44
                local gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                gui.Show("w" w " h" h " x" x " y" y " NoActivate")
                local wv := WebView2.create(gui.Hwnd)
                wv.Navigate("file:///" A_ScriptDir "\ui\ms_watcher.html")
                wv.OnEvent("WebMessageReceived", (wv2, evt) {
                    global _ms_dev_watcher_pos, _ms_dev_watcher_gui
                    local raw := evt.TryGetWebMessageAsString()
                    local data := Jxon_Load(&raw)
                    if !data {
                        return
                    }
                    local act := data.Has("action") ? data["action"] : ""
                    if act = "close" {
                        ms.dev.watcher.hide()
                    } else if act = "clear" {
                        try FileOpen(_ms_dev_log_path, "w").Write("")
                    } else if act = "move" {
                        _ms_dev_watcher_pos["x"] += data.Has("dx") ? data["dx"] : 0
                        _ms_dev_watcher_pos["y"] += data.Has("dy") ? data["dy"] : 0
                        _ms_dev_watcher_gui.Move(_ms_dev_watcher_pos["x"], _ms_dev_watcher_pos["y"])
                    }

                })
                _ms_dev_watcher_gui := gui, _ms_dev_watcher_wv := wv
                _ms_dev_watcher_pos := Map("x", x, "y", y, "w", w, "h", h)
                _ms_dev_watcher_open := true
                _ms_loadDevHistory(wv, (e) => e.Has("type") && (e["type"] = "macro" || e["type"] = "print" || e["type"] = "error"))
            }

            static hide()   { global _ms_dev_watcher_open := false ; if _ms_dev_watcher_gui  _ms_dev_watcher_gui.Destroy(), (_ms_dev_watcher_gui := 0) }

            static toggle() { if _ms_dev_watcher_open  ms.dev.watcher.hide() ; else  ms.dev.watcher.show() }

        }

        class keys {
            static show() {
                global _ms_dev_keys_gui, _ms_dev_keys_wv, _ms_dev_keys_open, _ms_dev_keys_pos
                if _ms_dev_keys_open && _ms_dev_keys_gui { WinActivate "ahk_id " _ms_dev_keys_gui.Hwnd ; return }

                local w := 270, h := 480
                MonitorGetWorkArea , &sL, &sT, &sR, &sB
                local x := sR - 360 - 24 + 24, y := sT + 68
                local gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                gui.Show("w" w " h" h " x" x " y" y " NoActivate")
                local wv := WebView2.create(gui.Hwnd)
                wv.Navigate("file:///" A_ScriptDir "\ui\ms_keys.html")
                wv.OnEvent("WebMessageReceived", (wv2, evt) {
                    global _ms_dev_keys_pos, _ms_dev_keys_gui
                    local raw := evt.TryGetWebMessageAsString()
                    local data := Jxon_Load(&raw)
                    if !data {
                        return
                    }
                    local act := data.Has("action") ? data["action"] : ""
                    if act = "close" {
                        ms.dev.keys.hide()
                    } else if act = "clear" {
                        try FileOpen(_ms_dev_log_path, "w").Write("")
                    } else if act = "move" {
                        _ms_dev_keys_pos["x"] += data.Has("dx") ? data["dx"] : 0
                        _ms_dev_keys_pos["y"] += data.Has("dy") ? data["dy"] : 0
                        _ms_dev_keys_gui.Move(_ms_dev_keys_pos["x"], _ms_dev_keys_pos["y"])
                    }

                })
                _ms_dev_keys_gui := gui, _ms_dev_keys_wv := wv
                _ms_dev_keys_pos := Map("x", x, "y", y, "w", w, "h", h)
                _ms_dev_keys_open := true
                _ms_loadDevHistory(wv, (e) => e.Has("type") && (e["type"] = "key" || e["type"] = "mouse"))
            }

            static hide()   { global _ms_dev_keys_open := false ; if _ms_dev_keys_gui  _ms_dev_keys_gui.Destroy(), (_ms_dev_keys_gui := 0) }

            static toggle() { if _ms_dev_keys_open  ms.dev.keys.hide() ; else  ms.dev.keys.show() }

        }

        class window {
            static show() {
                global _ms_dev_window_gui, _ms_dev_window_wv, _ms_dev_window_open, _ms_dev_window_pos
                global _ms_dev_window_history, _ms_dev_window_last_id, _ms_dev_window_poller
                if _ms_dev_window_open && _ms_dev_window_gui { WinActivate "ahk_id " _ms_dev_window_gui.Hwnd ; return }

                local w := 360, h := 480
                MonitorGetWorkArea , &sL, &sT, &sR, &sB
                local x := sR - w - 110, y := sT + 20
                local gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                gui.Show("w" w " h" h " x" x " y" y " NoActivate")
                local wv := WebView2.create(gui.Hwnd)
                wv.Navigate("file:///" A_ScriptDir "\ui\ms_window.html")
                wv.OnEvent("WebMessageReceived", (wv2, evt) {
                    global _ms_dev_window_history, _ms_dev_window_pos, _ms_dev_window_gui
                    local raw := evt.TryGetWebMessageAsString()
                    local data := Jxon_Load(&raw)
                    if !data {
                        return
                    }
                    local act := data.Has("action") ? data["action"] : ""
                    if act = "close" {
                        ms.dev.window.hide()
                    } else if act = "clear" {
                        _ms_dev_window_history := []
                    } else if act = "playSlot" {
                        if data.Has("slot") {
                            ms.playSlot(data["slot"])
                        }

                    } else if act = "move" {
                        _ms_dev_window_pos["x"] += data.Has("dx") ? data["dx"] : 0
                        _ms_dev_window_pos["y"] += data.Has("dy") ? data["dy"] : 0
                        _ms_dev_window_gui.Move(_ms_dev_window_pos["x"], _ms_dev_window_pos["y"])
                    }

                })
                _ms_dev_window_gui := gui, _ms_dev_window_wv := wv
                _ms_dev_window_pos := Map("x", x, "y", y, "w", w, "h", h)
                _ms_dev_window_open := true
                ; Push current focused window
                ms.dev.window._pushCurrent()
                ; Start polling for window changes every 400 ms
                _ms_dev_window_poller := SetTimer ms.dev.window._poll.Bind(ms.dev.window), 400
            }

            static hide() {
                global _ms_dev_window_open, _ms_dev_window_gui, _ms_dev_window_wv, _ms_dev_window_poller
                _ms_dev_window_open := false
                if _ms_dev_window_poller {
                    SetTimer _ms_dev_window_poller, 0
                    _ms_dev_window_poller := 0
                }

                if _ms_dev_window_gui {
                    _ms_dev_window_gui.Destroy(), (_ms_dev_window_gui := 0)
                }
                _ms_dev_window_wv := 0
            }

            static toggle() { if _ms_dev_window_open  ms.dev.window.hide() ; else  ms.dev.window.show() }


            static _pushCurrent() {
                global _ms_dev_window_wv, _ms_dev_window_history
                local hwnd := WinExist("A")
                if !hwnd {
                    return
                }
                try {
                    local title := WinGetTitle("ahk_id " hwnd)
                    local proc := WinGetProcessName("ahk_id " hwnd)
                    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
                    local entry := Map(
                        "type", "focus",
                        "ts",  A_Now,
                        "app", proc,
                        "title", title,
                        "x", wx, "y", wy, "w", ww, "h", wh
                    )
                    _ms_dev_window_history.Push(entry)
                    if _ms_dev_window_history.Length > 80
                        _ms_dev_window_history.RemoveAt(1)
                    if _ms_dev_window_wv {
                        local json := Jxon_Dump(entry, 0)
                        try _ms_dev_window_wv.ExecuteScript("appendEntry(" json ")")
                        try _ms_dev_window_wv.ExecuteScript("updateCurrentWindow(" json ")")
                    }

                }
            }


            static _poll(self) {
                global _ms_dev_window_open, _ms_dev_window_last_id, _ms_dev_window_poller
                if !_ms_dev_window_open {
                    SetTimer _ms_dev_window_poller, 0
                    _ms_dev_window_poller := 0
                    return
                }

                local hwnd := WinExist("A")
                if !hwnd || hwnd = _ms_dev_window_last_id {
                    return
                }
                _ms_dev_window_last_id := hwnd
                ms.dev.window._pushCurrent()
            }

        }
    }


    ; ── Key / modifier name translation ──────────────────────────────────────

    static _key(k) {
        static map := Map(
            "space","Space", "return","Enter", "escape","Escape", "backspace","Backspace",
            "delete","Delete", "tab","Tab",
            "left","Left", "right","Right", "up","Up", "down","Down",
            "home","Home", "end","End", "pageup","PgUp", "pagedown","PgDn",
            "insert","Insert",
            "f1","F1",  "f2","F2",  "f3","F3",  "f4","F4",
            "f5","F5",  "f6","F6",  "f7","F7",  "f8","F8",
            "f9","F9",  "f10","F10","f11","F11","f12","F12",
            "[","[",    "]","]",    "\","\"
        )
        return map.Has(k) ? map[k] : k
    }


    static _mod(m) {
        static map := Map(
            "shift","+", "lshift","+", "rshift","+",
            "ctrl","^",  "lctrl","^",  "rctrl","^",
            "alt","!",   "lalt","!",   "ralt","!",
            "cmd","^",   "win","#"     ; macOS ⌘ → Windows Ctrl
        )
        return map.Has(m) ? map[m] : ""
    }


    static _mouseBtn(button) {
        static map := Map("Left","Left","Right","Right","Middle","Middle","X1","X1","X2","X2")
        return map.Has(button) ? map[button] : button
    }


}
; ── End ms class ───────────────────────────────────────────────────────────────

; ═══════════════════════════════════════════════════════════════════════════════
; Standalone helpers (outside class — needed for closures / Hotkey callbacks)
; ═══════════════════════════════════════════════════════════════════════════════

; ── Profile list helper ───────────────────────────────────────────────────────
_ms_getProfiles() {
    global _ms_profiles_path
    local list := []
    if !DirExist(_ms_profiles_path) {
        return list
    }
    Loop Files _ms_profiles_path "*", "D" {
        if FileExist(A_LoopFileFullPath "\ms_macros.ahk")
            list.Push(A_LoopFileName)
    }

    list.Sort()
    return list
}


; ── Dev log writer ────────────────────────────────────────────────────────────
_ms_devWrite(entry) {
    global _ms_dev_busy, _ms_dev_log_path, _ms_dev_console_wv, _ms_dev_watcher_wv, _ms_dev_keys_wv, _ms_dev_key_notice
    if _ms_dev_busy {
        return
    }
    _ms_dev_busy := true
    entry["ts"] := FormatTime(, "HH:mm:ss")
    local json := Jxon_Dump(entry, 0)
    try FileOpen(_ms_dev_log_path, "a").Write(json "`n")
    local t := entry.Has("type") ? entry["type"] : ""
    if (t = "key" || t = "mouse") {
        if _ms_dev_console_wv && !_ms_dev_key_notice {
            _ms_dev_key_notice := true
            local notice := Jxon_Dump(Map("ts", entry["ts"], "type", "print", "msg", "⌨  key activity — see Key Monitor"), 0)
            try _ms_dev_console_wv.ExecuteScript("appendEntry(" notice ")")
        }

        if _ms_dev_keys_wv
            try _ms_dev_keys_wv.ExecuteScript("appendEntry(" json ")")
    } else {
        if t = "macro" || t = "result" || t = "input" {
            _ms_dev_key_notice := false
        }
        if _ms_dev_console_wv
            try _ms_dev_console_wv.ExecuteScript("appendEntry(" json ")")
        if _ms_dev_watcher_wv && (t = "macro" || t = "print" || t = "error")
            try _ms_dev_watcher_wv.ExecuteScript("appendEntry(" json ")")
    }

    _ms_dev_busy := false
}


; Override OutputDebug to also write to the dev log
_ms_origPrint(msg) => OutputDebug msg
_ms_print(msg) {
    OutputDebug msg
    _ms_devWrite(Map("type", "print", "msg", msg))
}


; ── Dev history loader ────────────────────────────────────────────────────────
_ms_loadDevHistory(wv, filterFn) {
    global _ms_dev_log_path
    if !FileExist(_ms_dev_log_path) {
        return
    }
    local entries := []
    Loop Read _ms_dev_log_path {
        local raw := A_LoopReadLine
        try {
            local entry := Jxon_Load(&raw)
            if entry && (filterFn = "" || filterFn.Call(entry))
                entries.Push(entry)
        }

    }
    if entries.Length = 0 {
        return
    }
    try wv.ExecuteScript("loadHistory(" Jxon_Dump(entries, 0) ")")
}


; ── SOCD key handlers (outside class — used as Hotkey callbacks) ──────────────
_ms_socdKeyDown(key, *) {
    global _ms_socd_held, BindValidity
    if BindValidity != 1 {
        SendLevel 1
        Send "{" key " down}"
        SendLevel 0
        return
    }

    _ms_socd_held[key] := true
    local opp := Map("a","d","d","a","w","s","s","w").Get(key, "")
    if opp != "" && _ms_socd_held[opp] {
        local mode := ms.socdMode
        if mode = "lastWins" {
            SendLevel 1 ; Release the opposite key
            Send "{" opp " up}"
            SendLevel 0
        } else if mode = "firstWins" {
            _ms_socd_held[key] := false
            return   ; suppress this key
        } else if mode = "neutral" {
            _ms_socd_held[opp] := false, _ms_socd_held[key] := false
            SendLevel 1
            Send "{" opp " up}"
            SendLevel 0
            return   ; suppress this key too
        }

    }
    SendLevel 1
    Send "{" key " down}"
    SendLevel 0
}


_ms_socdKeyUp(key, *) {
    global _ms_socd_held
    _ms_socd_held[key] := false
    local opp := Map("a","d","d","a","w","s","s","w").Get(key, "")
    ; lastWins: when releasing current key, re-press opposite if still held
    if ms.socdMode = "lastWins" && opp != "" && _ms_socd_held[opp] {
        SendLevel 1
        Send "{" opp " down}"
        SendLevel 0
    }

    SendLevel 1
    Send "{" key " up}"
    SendLevel 0
}


; ── Trackpad hold listeners ───────────────────────────────────────────────────
global _ms_trackpad_l_active := false
global _ms_trackpad_r_active := false
global _ms_trackpad_l_held   := false
global _ms_trackpad_r_held   := false

_ms_trackpadStart() {
    global _ms_trackpad_mode
    if !_ms_trackpad_mode {
        return
    }
    HotIfWinActive _ms_target_exe
    local lk := _ms_trackpad_hold_keys.left
    local rk := _ms_trackpad_hold_keys.right
    Hotkey "$" lk,    _ms_tpLeftDown,   "On"
    Hotkey "$" lk " Up", _ms_tpLeftUp,  "On"
    Hotkey "$" rk,    _ms_tpRightDown,  "On"
    Hotkey "$" rk " Up", _ms_tpRightUp, "On"
    HotIfWinActive
}


_ms_trackpadStop() {
    HotIfWinActive _ms_target_exe
    local lk := _ms_trackpad_hold_keys.left
    local rk := _ms_trackpad_hold_keys.right
    try Hotkey "$" lk,       "Off"
    try Hotkey "$" lk " Up", "Off"
    try Hotkey "$" rk,       "Off"
    try Hotkey "$" rk " Up", "Off"
    HotIfWinActive
}


_ms_tpLeftDown(*) {
    global _ms_trackpad_l_held, _ms_trackpad_l_active, BindValidity
    if BindValidity != 1 {
        return
    }
    _ms_trackpad_l_held := true
    if _ms_trackpad_l_active {
        return
    }
    _ms_trackpad_l_active := true
    SetTimer _ms_tpLeftLoop, 10
}

_ms_tpLeftUp(*) {
    global _ms_trackpad_l_held
    _ms_trackpad_l_held := false
}

_ms_tpLeftLoop() {
    global _ms_trackpad_l_held, _ms_trackpad_l_active, BindValidity
    if !_ms_trackpad_l_held || BindValidity != 1 {
        ms.Mouse(Release, Left, Mouse, 0, 0)
        _ms_trackpad_l_active := false
        SetTimer _ms_tpLeftLoop, 0
        return
    }

    ms.Mouse(Press, Left, Mouse, 0, 0)
}


_ms_tpRightDown(*) {
    global _ms_trackpad_r_held, _ms_trackpad_r_active, BindValidity
    if BindValidity != 1 {
        return
    }
    _ms_trackpad_r_held := true
    if _ms_trackpad_r_active {
        return
    }
    _ms_trackpad_r_active := true
    SetTimer _ms_tpRightLoop, 10
}

_ms_tpRightUp(*) {
    global _ms_trackpad_r_held
    _ms_trackpad_r_held := false
}

_ms_tpRightLoop() {
    global _ms_trackpad_r_held, _ms_trackpad_r_active, BindValidity
    if !_ms_trackpad_r_held || BindValidity != 1 {
        ms.Mouse(Release, Right, Mouse, 0, 0)
        _ms_trackpad_r_active := false
        SetTimer _ms_tpRightLoop, 0
        return
    }

    ms.Mouse(Press, Right, Mouse, 0, 0)
}


; ── Rebind capture helpers ────────────────────────────────────────────────────
_ms_captureRebind(id) {
    ms.alert('Rebinding: "' (ms.bind._defs.Has(id) ? ms.bind._defs[id].label : id) '"' "`nPress your new key or mouse button.`nEscape to cancel.", 15)
    local ih := InputHook("L1 B", "{Escape}")
    ih.KeyOpt("{All}", "SN")
    ih.OnChar := (ih2, char) => 0
    ih.OnKeyDown := (ih2, vk, sc) {
        ih2.Stop()
        if vk = 27 { ms.alert("Rebind cancelled.", 2) ; ms.ui.show() ; return }

        local key := GetKeyName(Format("vk{:02X}", vk))
        global _ms_bindConfig
        _ms_bindConfig[id] := {type: "key", mods: [], key: StrLower(key)}

        ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update")
        ms.alert((ms.bind._defs.Has(id) ? ms.bind._defs[id].label : id) " bound to " key, 3, true)
        ms.ui.show(), ms.ui.refresh()
    }

    ih.Start()
}


_ms_captureModRebind(id) {
    local def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
    if def = "" || def.sub = "" {
        return
    }
    ms.alert('Modifier for "' def.label '"' "`nPress a key — Backspace to clear — Escape to cancel.", 15)
    local ih := InputHook("L1 B", "{Escape}{Backspace}")
    ih.KeyOpt("{All}", "SN")
    ih.OnKeyDown := (ih2, vk, sc) {
        ih2.Stop()
        if vk = 27 { ms.alert("Modifier rebind cancelled.", 2) ; ms.ui.show() ; return }

        global _ms_modConfig
        if vk = 8 { ; Backspace = clear
            _ms_modConfig.Delete(id)
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset")
            ms.alert("Modifier cleared.", 3, true)
        } else {
            local key := GetKeyName(Format("vk{:02X}", vk))
            _ms_modConfig[id] := StrLower(key)
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update")
            ms.alert("Modifier set to: " key, 3, true)
        }

        ms.ui.show(), ms.ui.refresh()
    }

    ih.Start()
}


; ── Target app helper ────────────────────────────────────────────────────────
; Returns true when the target app window is active (used by #HotIf and app poll).
_ms_targetActive() {
    global _ms_target_exe
    if _ms_target_exe = "" {
        return false
    }
    return WinActive(_ms_target_exe) != 0
}


; ── App watcher (poll every 100 ms) ──────────────────────────────────────────
_ms_AppPoll() {
    global _ms_roblox_active, _ms_ui_open_flag, _ms_loadDone, _ms_target_exe
    local active := _ms_targetActive()
    if active && !_ms_roblox_active {
        _ms_roblox_active := true
        ms.cam.updateMultiplier()
        if !_ms_loadDone {
            ; don't enable macros while loading toasts haven't fired yet
            return
        }
        if _ms_ui_open_flag {  ; returning from panel — re-enable silently
            BindValidity := 1
        } else {
            ms.setMacros(1)
        }

    } else if !active && _ms_roblox_active {
        ; Don't disable when focus moved to our own panel
        if _ms_ui_open_flag
            return
        _ms_roblox_active := false
        ms.setMacros(0, _ms_ui_open_flag)
    }

}
SetTimer _ms_AppPoll, 100

; ── Include macro file ────────────────────────────────────────────────────────
#Include ms_macros.ahk

; ── Loading indicator (mirrors Lua hs.canvas loading bar) ────────────────────
do {
    ; Build a small borderless GUI with a progress bar.
    local lw := 300, lh := 64
    MonitorGetWorkArea , &sL, &sT, &sR, &sB
    local lx := sL + (sR - sL - lw) // 2
    local ly := sB - 150 - lh
    local _lGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20")
    _lGui.BackColor := "060402"
    _lGui.MarginX := 0, _lGui.MarginY := 0
    ; Title
    _lGui.SetFont("s12 cF0DDB0", "Segoe UI")
    _lGui.Add("Text", "x16 y8 w" (lw - 32) " h22", "mudscript")
    ; Status text
    _lGui.SetFont("s9 cC47820", "Segoe UI")
    global _ms_loadStatus := _lGui.Add("Text", "x16 y30 w" (lw - 32) " h16", "Starting up...")
    ; Progress bar background
    _lGui.Add("Progress", "x16 y50 w" (lw - 32) " h3 c1C100C -Smooth", 0)
    ; Progress bar fill
    global _ms_loadProgress := _lGui.Add("Progress", "x16 y50 w" (lw - 32) " h3 Background060402 cC41A1A -Smooth Range0-100", 0)
    _lGui.Show("w" lw " h" lh " x" lx " y" ly " NoActivate")
    WinSetTransparent 220, _lGui

    ; Update function — called at startup milestones
    global _ms_loadUpdate := (pct, msg) => (
        _ms_loadProgress.Value := pct,
        _ms_loadStatus.Text := msg
    )

    ; Dismiss function — fades out and destroys
    global _ms_loadDismiss := () {
        local gui := _lGui
        if !gui {
            return
        }

        local step := 0
        SetTimer () {
            step++
            WinSetTransparent Max(0, 220 - step * 37), gui
            if step >= 6 {
                gui.Destroy()
                _lGui := 0
            }

        }, 30
    }


    _ms_loadUpdate(5, "Initializing...")
}


_ms_loadUpdate(8, "Installing fonts...")

; ── Font installation ─────────────────────────────────────────────────────────
; Copy bundled fonts from ui/fonts/ to the Windows user fonts directory.
; On Windows 10 1809+, user-installed fonts go in %LOCALAPPDATA%\Microsoft\Windows\Fonts
; and are available without admin privileges.
do {
    local fontSrc := A_ScriptDir "\ui\fonts"
    if DirExist(fontSrc) {
        local fontDst := EnvGet("LOCALAPPDATA") "\Microsoft\Windows\Fonts"
        DirCreate fontDst
        local installed := false
        Loop Files fontSrc "\*.*" {
            local ext := ""
            SplitPath A_LoopFileName,,, &ext
            if ext != "ttf" && ext != "otf" && ext != "woff" && ext != "woff2"
                continue
            local dstFile := fontDst "\" A_LoopFileName
            if !FileExist(dstFile) {
                FileCopy A_LoopFileFullPath, dstFile, 0
                installed := true
            }

        }
        if installed {
            ; Notify fonts were installed; a reload is needed for them to be recognized
            ; by WebView2. We schedule a reload after a brief delay so the user sees the alert.
            SetTimer () => Reload(), -500
        }

    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; Startup sequence (mirrors ms_core.lua "Startup Executions")
; ═══════════════════════════════════════════════════════════════════════════════

_ms_loadUpdate(10, "Processing macros...")

; Seed _ms_binds from registry defaults for any id not overridden by settings
for _, _ms_id in ms.bind._defList {
    local _ms_def := ms.bind._defs[_ms_id]
    if _ms_def && _ms_def.sub = "" && !_ms_binds.Has(_ms_id)
        _ms_binds[_ms_id] := _ms_def.enabled
}


_ms_loadUpdate(25, "Loading settings...")
ms._discoverSounds()
ms.loadSettings()

_ms_loadUpdate(50, "Applying theme...")
ms.loadTheme()

_ms_loadUpdate(65, "Configuring binds...")
ms.cam.updateMultiplier()
ms.bind.rebind()
ms.socdApply()

_ms_loadUpdate(90, "Finalizing...")

; Integrity auto-seed — 3 s after load (mirrors Lua timer)
SetTimer _ms_integrityAutoSeed, -3000
_ms_integrityAutoSeed() {
    if ms.integrity.check() != "uninitialized" {
        return
    }
    ; Try to auto-trust from MANIFEST.json (clean install)
    local mPath := A_ScriptDir "\MANIFEST.json"
    if FileExist(mPath) {
        local raw := ""
        FileRead &raw, mPath
        local manifest := Jxon_Load(&raw)
        if manifest && manifest.Has("windows_sha256") {
            local cur := ms.integrity.hashFile(_ms_core_path)
            if cur != "" && StrLower(cur) = StrLower(manifest["windows_sha256"]) {
                ms.integrity.writeTrustedHash(cur)
                return   ; silently trusted on clean install
            }

        }
    }

    ms.alert("⚠ No trusted hash on record.`nSettings → Developer → Trust Current Version.", 10)
}


; loadfinish timer — enables state toasts after 3 s
SetTimer _ms_setLoadfinish, -3000
_ms_setLoadfinish() {
    global loadfinish := 1
}


; Periodic integrity check — every 5 s (mirrors Lua _integrityPollTimer)
SetTimer _ms_integrityPoll, 5000
_ms_integrityPoll() {
    global loadfinish
    if loadfinish != 1 {
        return
    }
    if ms.integrity.check() = "mismatch"
        Reload   ; guardian will block ms_core.ahk on next load
}


; Load complete announcement
SetTimer _ms_loadAnnounce, -500
_ms_loadAnnounce() {
    global BindValidity, _ms_loadDone
    ms.playSlot("load")
    ms.alert("mudscript Windows Runtime`nBy: mudbourn — https://mudbourn.info", 6)
    if ms.macroMeta.HasProp("name") {
        local msg := '"' ms.macroMeta.name '"'
        if ms.macroMeta.HasProp("author") {
            msg .= "`nBy: " ms.macroMeta.author
        }
        if ms.macroMeta.HasProp("website") {
            msg .= " — " ms.macroMeta.website
        }
        ms.alert(msg, 6)
    }

    ms.alert("Macros loaded. Press Alt+P to open settings.", 6)
    ; Unlock macros now that loading toasts have fired.
    _ms_loadDone := true
    BindValidity := 1
    ; Dismiss loading indicator
    try _ms_loadDismiss()
}


; ── Tray icon & menu ─────────────────────────────────────────────────────────
; Custom tray icon: place ms_icon.png or ms_icon.ico in ui/icons/.
; Falls back to the default AutoHotkey icon if no file is found.
do {
    local iconPath := A_ScriptDir "\ui\icons\ms_icon.png"
    if !FileExist(iconPath)
        iconPath := A_ScriptDir "\ui\icons\ms_icon.ico"
    if FileExist(iconPath)
        TraySetIcon(iconPath)
    A_IconTip := "mudscript — " (ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "Macro Utilities")
    ; Build custom tray menu
    local tray := A_TrayMenu
    tray.Delete()  ; clear default items
    tray.Add("Toggle Settings", (*) => ms.ui.toggle())
    tray.Add()
    tray.Add("Reload Script", (*) => Reload())
    tray.Add("Reload Settings", (*) => ms.reloadSettings())
    tray.Add()
    tray.Add("Panic (Disable)", (*) => ms.setMacros(0))
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Toggle Settings"
    tray.ClickCount := 1  ; single-click runs default
}


; ── Global system hotkeys ─────────────────────────────────────────────────────
; Track last press time for / and Enter to filter auto-repeat (mirrors Lua !isRepeat)
global _ms_last_slash  := 0
global _ms_last_enter  := 0

#HotIf _ms_targetActive()
![ :: Reload                                               ; Alt+[  reload script
!] :: ms.reloadSettings()                                  ; Alt+]  reload settings
!p :: ms.ui.toggle()                                       ; Alt+P  toggle settings panel
!F10 :: ms.setMacros(0)                                    ; Alt+F10 panic/disable
/ :: {
    global _ms_last_slash
    if (A_TickCount - _ms_last_slash) < 100 {
        return
    }
    _ms_last_slash := A_TickCount
    if BindValidity {
        ms.setMacros(0)
    }

}                                                          ; /  disable macros (no repeat)
Enter :: {
    global _ms_last_enter
    if (A_TickCount - _ms_last_enter) < 100 {
        return
    }
    _ms_last_enter := A_TickCount
    if !BindValidity {
        ms.setMacros(1)
    }

}                                                          ; Enter  enable macros (no repeat)
#HotIf
