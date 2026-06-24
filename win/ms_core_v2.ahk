; ═══════════════════════════════════════════════════════════════════════════
; mudscript Windows Runtime — AutoHotkey v2
; ═══════════════════════════════════════════════════════════════════════════
; Native AHK v2 rewrite. Same ms.* macro API as macOS.
;
; Loading chain:  init.ahk → _ms_main.ahk → (hash check) → ms_core_v2.ahk
;
; Usage:
;   #Include ms_core_v2.ahk  (done by _ms_main.ahk after hash verification)
;   ; write macros using ms.bind.define(), ms.Mouse(), ms.wait(), etc.
; ═══════════════════════════════════════════════════════════════════════════

;@include lib/Jxon.ahk
;@include lib/WebView2.ahk

#Requires AutoHotkey v2.0

;; Section 1 — Globals ;;

;; Reference Defaults ;;
    global REF_W     := 1680
    global REF_H     := 1044
    global REF_SENS  := 1.5
;; END Reference Defaults ;;

;; Paths ;;
    global SoundLib        := A_ScriptDir "\sounds\"
    global _ms_json_path    := A_ScriptDir "\data\ms_settings.json"
    global _ms_default_path := A_ScriptDir "\data\ms_settings_default.json"
    global _ms_archive_path := A_ScriptDir "\backups\"
    global _ms_profiles_path:= A_ScriptDir "\profiles\"
    global _ms_core_path    := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\ms_core_v2.ahk"
    global _ms_hash_path    := A_ScriptDir "\data\.ms_trusted_hash"
    global _ms_theme_path   := A_ScriptDir "\data\ms_theme.json"
    global _ms_dev_log_path := A_ScriptDir "\data\ms_dev.log"
;; END Paths ;;

;; State Flags ;;
    global BindValidity   := 0
    global _ms_loadDone   := false
    global clickLevel     := 3
    global CUR_CAM_SENS   := 1.5
;; END State Flags ;;

;; Target Application ;;
    global _ms_target_exe := "ahk_exe RobloxPlayerBeta.exe"
;; END Target Application ;;

;; Cancellation ;;
    global _ms_cancel_gen := 0
;; END Cancellation ;;

;; Registry / Macro State ;;
    global _ms_registry   := Map()
    global _ms_active_sub := ""
    global _ms_running    := Map()
    global _ms_binds      := Map()
    global _ms_bindConfig := Map()
    global _ms_subBinds   := Map()
    global _ms_modConfig  := Map()
    global _ms_cooldowns  := Map()
;; END Registry / Macro State ;;

;; Sound State ;;
    global _ms_sounds         := Map()
    global _ms_soundAssign    := Map()
    global _ms_soundEnabled   := true
    global _ms_soundVolume    := 100
;; END Sound State ;;

;; UI State ;;
    global _ms_ui_panel_gui := 0
    global _ms_ui_panel_wv  := 0
    global _ms_ui_open      := false
    global _ms_ui_modal_cb  := 0
    global _ms_ui_pos       := {x:0, y:0, w:360, h:640}
;; END UI State ;;

;; Toast State ;;
    global _ms_toasts        := []
    global _ms_toast_timer   := 0
;; END Toast State ;;

;; Theme ;;
    global _ms_theme := Map(
        "bg",       "#060402",
        "surface",  "#100806",
        "surface2", "#1c100c",
        "hover",    "#301610",
        "accent",   "#c41a1a",
        "accentHi", "#e52424",
        "success",  "#4a7820",
        "danger",   "#d42020",
        "warning",  "#c47820",
        "text",     "#f0ddb0",
        "radius",   3,
        "font",     "Almendra",
    )
    global _ms_theme_loaded := false
;; END Theme ;;

;; User Settings ;;
    global _ms_user_defs  := []
    global _ms_user_index := Map()
    global _ms_user_vals  := Map()
;; END User Settings ;;

;; Security ;;
    global _ms_update_pubkey := "
(
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsm0KfyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
)"
;; END Security ;;

;; SOCD ;;
    global _ms_socd_held   := Map("a",false,"d",false,"w",false,"s",false)
    global _ms_socd_active := false
    global ms_socdEnabled  := false
    global ms_socdMode     := "lastWins"
;; END SOCD ;;

;; Trackpad ;;
    global _ms_trackpad_mode      := false
    global _ms_trackpad_hold_keys := {left:"n", right:"j"}
    global _ms_trackpad_bind_ovr  := Map()
    global _ms_independent_binds  := false
;; END Trackpad ;;

;; Menu / Features ;;
    global _ms_menu_defs    := []
    global _ms_hidden_feats := Map()
;; END Menu / Features ;;


;; Section 2 — ms class (public API) ;;
    class ms {
        ; metadata set by ms_macros.ahk
        static macroMeta      := {}
        static macroDefaults  := {}
        static _currentFlags  := {}

        ;; Keyboard ;;
            static press(key, mods := [], hidinject := false) {
                m := ""
                for mod in mods
                    m .= _ms_keyMod(mod)
                SendInput m "{" _ms_keyName(key) " down}"
            }

            static release(key, mods := [], hidinject := false) {
                SendInput "{" _ms_keyName(key) " up}"
            }

            static type(key, mods := [], hidinject := false) {
                m := ""
                for mod in mods
                    m .= _ms_keyMod(mod)
                SendInput m "{" _ms_keyName(key) "}"
            }
        ;; END Keyboard ;;

        ;; Timing ;;
            static wait(ms_time) {
                global _ms_cancel_gen
                gen := _ms_cancel_gen
                Sleep ms_time
                if _ms_cancel_gen != gen
                    throw Error("ms.cancelled")
            }

            static fn(func, async := true) {
                return func
            }
        ;; END Timing ;;

        ;; Clipboard ;;
            static copy(text) {
                A_Clipboard := text
            }
        ;; END Clipboard ;;

        ;; Scroll ;;
            static scroll(direction, amount := 1) {
                if direction = "up"
                    Send "{WheelUp " amount "}"
                else
                    Send "{WheelDown " amount "}"
            }
        ;; END Scroll ;;

        ;; Audio ;;
            static sound(path, async := true) {
                global _ms_soundEnabled
                if !_ms_soundEnabled || !path
                    return
                if async
                    SoundPlay path, 1
                else
                    SoundPlay path
            }

            static playSlot(slotId) {
                global _ms_soundEnabled, _ms_sounds, _ms_soundAssign
                static lastTimes := Map()
                if !_ms_soundEnabled
                    return false
                now := A_TickCount
                if lastTimes.Has(slotId) && (now - lastTimes[slotId]) < 50
                    return false
                lastTimes[slotId] := now
                assigned := _ms_soundAssign.Has(slotId) ? _ms_soundAssign[slotId] : ""
                path := ""
                if assigned != "" && _ms_sounds.Has(assigned)
                    path := _ms_sounds[assigned]
                else if _ms_sounds.Has(slotId)
                    path := _ms_sounds[slotId]
                if path = ""
                    return false
                ms.sound(path, true)
                return true
            }
        ;; END Audio ;;

        ;; Alert / Toast ;;
            ; Shows a styled toast notification (Gui-based, matches macOS look).
            ; Automatically fades out after duration seconds.
            static alert(msg, duration := 3, noSound := false) {
                _ms_showToast(msg, duration)
            }
        ;; END Alert / Toast ;;

        ;; Target App ;;
            static setTargetApp(name) {
                global _ms_target_exe
                if name = "" {
                    _ms_target_exe := ""
                    return
                }
                if InStr(name, "ahk_") = 1
                    _ms_target_exe := name
                else
                    _ms_target_exe := "ahk_exe " name
            }

            static getTargetWin() {
                global _ms_target_exe
                return _ms_target_exe
            }
        ;; END Target App ;;

        ;; State Queries ;;
            static keystate(key, rawCode := false) {
                return GetKeyState(_ms_keyName(key), "P")
            }

            static app() {
                try return WinGetTitle("A")
                return ""
            }

            static mousePos() {
                MouseGetPos &mx, &my
                wX := 0, wY := 0, wW := REF_W, wH := REF_H
                global _ms_target_exe
                try WinGetPos &wX, &wY, &wW, &wH, _ms_target_exe
                relX := (mx - wX) * (REF_W / wW)
                relY := (my - wY) * (REF_H / wH)
                return [relX, relY]
            }
        ;; END State Queries ;;

        ;; Sub-item Dispatch ;;
            static getMod(id) {
                global _ms_modConfig, _ms_registry
                if _ms_modConfig.Has(id)
                    return _ms_modConfig[id]
                if _ms_registry.Has(id) && _ms_registry[id].opts.Has("mod")
                    return _ms_registry[id].opts.mod
                return ""
            }

            static modHeld(id) {
                mod := ms.getMod(id)
                if mod = ""
                    return false
                return GetKeyState(_ms_keyName(mod), "P")
            }

            static isSub(id) {
                global _ms_active_sub
                if (_ms_active_sub = id) || (_ms_active_sub = "" && ms.modHeld(id)) {
                    _ms_active_sub := ""
                    return true
                }
                return false
            }
        ;; END Sub-item Dispatch ;;

        ;; Mouse ;;
            static Mouse(operation, button, reference, params*) {
                unscaled := false
                x1 := 0, y1 := 0, x2 := 0, y2 := 0, offset := 1

                if params.Length >= 1 && params[1] == true
                    unscaled := true, offset := 2
                if params.Length >= offset
                    x1 := params[offset]
                if params.Length >= offset + 1
                    y1 := params[offset + 1]
                if params.Length >= offset + 2
                    x2 := params[offset + 2]
                if params.Length >= offset + 3
                    y2 := params[offset + 3]

                btn  := _ms_mouseButton(button)
                pos1 := _ms_resolvePoint(x1, y1, reference, unscaled)
                pos2 := _ms_resolvePoint(x2, y2, reference, unscaled)

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

            static resolvePoint(x, y, reference, unscaled := false) {
                p := _ms_resolvePoint(x, y, reference, unscaled)
                return [p.x, p.y]
            }
        ;; END Mouse ;;

        ;; Pixel Color ;;
            static pixelColor(x, y, reference := "Absolute") {
                pos := _ms_resolvePoint(x, y, reference)
                color := PixelGetColor(pos.x, pos.y, "RGB")
                return Map(
                    "r", (color >> 16) & 0xFF,
                    "g", (color >> 8)  & 0xFF,
                    "b",  color        & 0xFF,
                )
            }

            static pixelMatch(x, y, reference, r, g, b, tolerance := 10) {
                c := ms.pixelColor(x, y, reference)
                return Abs(c["r"] - r) <= tolerance
                    && Abs(c["g"] - g) <= tolerance
                    && Abs(c["b"] - b) <= tolerance
            }
        ;; END Pixel Color ;;

        ;; Camera ;;
            class cam {
                static _mult := 1.0

                static updateMultiplier() {
                    global CUR_CAM_SENS
                    ms.cam._mult := REF_SENS / (CUR_CAM_SENS > 0 ? CUR_CAM_SENS : 1.5)
                }

                static move(dy, dx) {
                    sdx := Round(dx * ms.cam._mult)
                    sdy := Round(dy * ms.cam._mult)
                    if sdx = 0 && sdy = 0
                        return
                    ; MOUSE INPUT via SendInput (x64 struct)
                    static INPUT_SIZE := 40
                    input := Buffer(INPUT_SIZE, 0)
                    NumPut "UInt", 0,      input,  0
                    NumPut "Int",  sdx,    input,  8
                    NumPut "Int",  sdy,    input, 12
                    NumPut "UInt", 0x0001, input, 20
                    DllCall "SendInput", "UInt", 1, "Ptr", input, "Int", INPUT_SIZE
                }

                static enable()  => 0
                static disable() => 0
                static updateAnchor() => 0
                static scheduleUpdate() => 0
            }
        ;; END Camera ;;

        ;; Bind / Registry ;;
            class bind {
                static _defs    := Map()
                static _defList := []
                static _hotkeys := Map()
                static _autoCount := 0

                static define(id, fnOrOpts, optsOrFn := "") {
                    global _ms_registry

                    func := "", opts := {}

                    if IsObject(fnOrOpts) && fnOrOpts.HasProp("sub")
                        opts := fnOrOpts, func := (optsOrFn != "" ? optsOrFn : "")
                    else
                        func := fnOrOpts, opts := (optsOrFn != "" ? optsOrFn : {})

                    label := "", group := ""
                    if !opts.HasProp("sub") || opts.sub = "" {
                        if opts.HasProp("label") && opts.label != ""
                            label := opts.label
                        else
                            ms.bind._autoCount++, label := "Macro" ms.bind._autoCount
                        group := opts.HasProp("group") ? opts.group : "main"
                    } else {
                        label := opts.HasProp("label") ? opts.label : id
                        group := opts.HasProp("group") ? opts.group : ""
                    }

                    def := Map(
                        "label",    label,
                        "group",    group,
                        "enabled",  (!opts.HasProp("enabled") || opts.enabled != false),
                        "cooldown", opts.HasProp("cooldown") ? opts.cooldown : 1000,
                        "shared",   opts.HasProp("shared")   ? opts.shared   : "",
                        "sub",      opts.HasProp("sub")       ? opts.sub      : "",
                        "mod",      opts.HasProp("mod")       ? opts.mod      : "",
                        "info",     opts.HasProp("info")      ? opts.info     : "",
                        "default",  opts.HasProp("default")   ? opts.default  : "",
                    )

                    _ms_registry[id] := {func:func, opts:def}
                    ms.bind._defs[id] := def
                    ms.bind._defList.Push(id)
                }

                static group(id) {
                    global _ms_registry
                    if !_ms_registry.Has(id)
                        return "G_" id
                    def := _ms_registry[id].opts
                    if def["shared"] != ""
                        return def["shared"]
                    current := id, seen := Map()
                    loop {
                        d := _ms_registry.Has(current) ? _ms_registry[current].opts : ""
                        if d = "" || d["sub"] = "" || seen.Has(current)
                            break
                        seen[current] := true
                        current := d["sub"]
                    }
                    rootDef := _ms_registry.Has(current) ? _ms_registry[current].opts : ""
                    if rootDef != "" && rootDef["shared"] != ""
                        return rootDef["shared"]
                    return "G_" current
                }

                static teardown() {
                    for hk, _ in ms.bind._hotkeys
                        try Hotkey hk, "Off"
                    ms.bind._hotkeys := Map()
                }

                static rebind() {
                    global _ms_registry, _ms_binds, _ms_bindConfig, _ms_subBinds
                    global _ms_modConfig, _ms_cooldowns, _ms_independent_binds
                    global _ms_trackpad_mode, _ms_active_sub, _ms_running
                    global BindValidity, _ms_target_exe

                    ms.bind.teardown()

                    conflicted := Map()
                    rootUsed := Map()

                    ; Detect root-level bind conflicts
                    for _, id in ms.bind._defList {
                        def := ms.bind._defs[id]
                        if !def || def["sub"] != ""
                            continue
                        enabled := _ms_binds.Has(id) ? _ms_binds[id] : def["enabled"]
                        if !enabled
                            continue
                        c := _ms_effectiveBind(id)
                        k := _ms_bindKey(c)
                        if k = ""
                            continue
                        if rootUsed.Has(k)
                            conflicted[id] := true, conflicted[rootUsed[k]] := true
                        else
                            rootUsed[k] := id
                    }

                    ; Register root binds
                    for _, id in ms.bind._defList {
                        if conflicted.Has(id)
                            continue
                        def := ms.bind._defs[id]
                        if !def || def["sub"] != ""
                            continue
                        enabled := _ms_binds.Has(id) ? _ms_binds[id] : def["enabled"]
                        if !enabled
                            continue
                        c := _ms_effectiveBind(id)
                        if c = ""
                            continue
                        entry := _ms_registry.Has(id) ? _ms_registry[id] : ""
                        if entry = "" || !entry.func
                            continue
                        groupId := ms.bind.group(id)
                        cd := _ms_cooldowns.Has(id) ? _ms_cooldowns[id] : def["cooldown"]
                        hk := _ms_buildHotkey(c)
                        if hk = ""
                            continue
                        fn := entry.func
                        HotIfWinActive _ms_target_exe
                        try Hotkey "$" hk, _ms_fireRoot.Bind(fn, id, groupId, cd)
                        HotIfWinActive
                        ms.bind._hotkeys["$" hk] := id
                    }

                    ; Register sub-item independent binds
                    for _, id in ms.bind._defList {
                        if conflicted.Has(id)
                            continue
                        def := ms.bind._defs[id]
                        if !def || def["sub"] = ""
                            continue
                        if !_ms_independent_binds || !_ms_subBinds.Has(id)
                            continue
                        c := _ms_subBinds[id]
                        hk := _ms_buildHotkey(c)
                        if hk = ""
                            continue
                        entry := _ms_registry.Has(id) ? _ms_registry[id] : ""
                        if entry = "" || !entry.func
                            continue
                        groupId := ms.bind.group(id)
                        cd := _ms_cooldowns.Has(id) ? _ms_cooldowns[id] : def["cooldown"]
                        fn := entry.func
                        HotIfWinActive _ms_target_exe
                        try Hotkey "$" hk, _ms_fireSub.Bind(fn, id, groupId, cd)
                        HotIfWinActive
                        ms.bind._hotkeys["$" hk] := id
                    }
                }
            }
        ;; END Bind / Registry ;;

        ;; Macro Lifecycle ;;
            static setMacros(state, silent := false) {
                global BindValidity, _ms_cancel_gen, _ms_running
                if state = 1 && BindValidity != 1 {
                    BindValidity := 1
                    if !silent
                        _ms_notify(1)
                } else if state = 0 && BindValidity != 0 {
                    BindValidity := 0
                    ms.cancelMacros()
                    _ms_running := Map()
                    if !silent
                        _ms_notify(0)
                }
            }

            static cancelMacros() {
                global _ms_cancel_gen
                _ms_cancel_gen++
            }

            static done(id) {
                global _ms_running
                group := ms.bind.group(id)
                if _ms_running.Has(group)
                    _ms_running.Delete(group)
            }

            static setClickLevel(n) {
                global clickLevel
                n := Integer(n)
                if n >= 1 && n <= 4
                    clickLevel := n
            }
        ;; END Macro Lifecycle ;;

        ;; Settings ;;
            static reloadSettings() {
                ms.loadSettings()
                ms.bind.rebind()
                ms.cam.updateMultiplier()
                ms.playSlot("update")
                ms.alert("Settings reloaded.", 5, true)
            }

            static saveSettings() {
                global _ms_json_path, _ms_binds, _ms_bindConfig, _ms_subBinds
                global _ms_modConfig, _ms_cooldowns, _ms_user_vals
                global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign
                global _ms_trackpad_mode, _ms_trackpad_hold_keys, _ms_independent_binds
                global CUR_CAM_SENS, clickLevel

                macros := Map()
                for id, enabled in _ms_binds {
                    if !macros.Has(id)
                        macros[id] := Map()
                    macros[id]["enabled"] := enabled
                }
                for id, cfg in _ms_bindConfig {
                    if !macros.Has(id)
                        macros[id] := Map()
                    macros[id]["bind"] := cfg
                }
                for id, key in _ms_modConfig {
                    if !macros.Has(id)
                        macros[id] := Map()
                    macros[id]["mod"] := key
                }
                for id, cfg in _ms_subBinds {
                    if !macros.Has(id)
                        macros[id] := Map()
                    macros[id]["bind"] := cfg
                }
                for id, cd in _ms_cooldowns {
                    if !macros.Has(id)
                        macros[id] := Map()
                    macros[id]["cooldown"] := cd
                }

                data := Map(
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
                    "user",             _ms_user_vals,
                    "macros",           macros,
                )
                DirCreate A_ScriptDir "\data"
                try FileOpen(_ms_json_path, "w").Write(Jxon_Dump(data, 4))
            }

            static loadSettings() {
                global _ms_json_path, _ms_default_path
                if FileExist(_ms_json_path) {
                    raw := ""
                    try raw := FileRead(_ms_json_path)
                    data := Jxon_Load(&raw)
                    if data {
                        _ms_applySettings(data)
                        return
                    }
                }
                if FileExist(_ms_default_path) {
                    raw2 := ""
                    try raw2 := FileRead(_ms_default_path)
                    data2 := Jxon_Load(&raw2)
                    if data2 {
                        _ms_applySettings(data2)
                        return
                    }
                }
                _ms_buildDefaultSettings()
                if FileExist(_ms_default_path) {
                    raw3 := ""
                    try raw3 := FileRead(_ms_default_path)
                    data3 := Jxon_Load(&raw3)
                    if data3
                        _ms_applySettings(data3)
                }
            }

            static saveDefault() {
                global _ms_json_path, _ms_default_path, _ms_archive_path
                ms.saveSettings()
                if !FileExist(_ms_json_path)
                    return
                DirCreate _ms_archive_path
                ts := FormatTime(, "yyyy-MM-dd_HHmm")
                try FileCopy _ms_json_path, _ms_archive_path "ms_settings_default_" ts ".json"
                FileCopy _ms_json_path, _ms_default_path, 1
                ms.alert("Default settings saved.", 3)
            }

            static resetToDefault() {
                global _ms_bindConfig, _ms_subBinds, _ms_modConfig, _ms_cooldowns
                global _ms_default_path, _ms_user_index, _ms_user_vals
                if !FileExist(_ms_default_path) {
                    ms.alert("No default settings file found.", 3)
                    return false
                }
                raw := ""
                try raw := FileRead(_ms_default_path)
                data := Jxon_Load(&raw)
                if !data {
                    ms.alert("Default settings file could not be decoded.", 3)
                    return false
                }
                _ms_bindConfig := Map(), _ms_subBinds := Map()
                _ms_modConfig  := Map(), _ms_cooldowns := Map()
                _ms_applySettings(data)
                ms.saveSettings()
                ms.bind.rebind()
                ms.cam.updateMultiplier()
                ms.playSlot("reset")
                return true
            }
        ;; END Settings ;;

        ;; Feature Detection ;;
            static has(feature) {
                global _ms_sounds, _ms_soundEnabled, _ms_theme_loaded
                global _ms_trackpad_mode
                if feature = "theme"
                    return _ms_theme_loaded = true
                if feature = "sound"
                    return _ms_soundEnabled = true && _ms_sounds.Count > 0
                if feature = "socd"
                    return ms.socdEnabled = true
                if feature = "trackpad"
                    return _ms_trackpad_mode = true
                if feature = "userSettings" || feature = "userMenu"
                    return true
                if feature = "integrity"
                    return ms.integrity.check() = "trusted"
                if feature = "profiles"
                    return _ms_getProfiles().Length > 0
                return false
            }
        ;; END Feature Detection ;;

        ;; Theme ;;
            static loadTheme() {
                global _ms_theme, _ms_theme_path, _ms_theme_loaded
                ; Reset to defaults
                defaults := Map(
                    "bg","#060402","surface","#100806","surface2","#1c100c",
                    "hover","#301610","accent","#c41a1a","accentHi","#e52424",
                    "success","#4a7820","danger","#d42020","warning","#c47820",
                    "text","#f0ddb0","radius",3,"font","Almendra",
                )
                for k, v in defaults
                    _ms_theme[k] := v
                if !FileExist(_ms_theme_path)
                    return
                raw := ""
                try raw := FileRead(_ms_theme_path)
                data := Jxon_Load(&raw)
                if !data
                    return
                _ms_theme_loaded := true
                colorKeys := ["bg","surface","surface2","hover","accent",
                    "accentHi","success","danger","warning","text"]
                for _, k in colorKeys {
                    if data.Has(k) && RegExMatch(data[k], "^#[0-9a-fA-F]+$")
                        _ms_theme[k] := data[k]
                }
                if data.Has("radius") && data["radius"] is Number
                    _ms_theme["radius"] := Max(0, Min(40, Integer(data["radius"])))
                if data.Has("font") && data["font"] != "" {
                    clean := RegExReplace(data["font"], "[;{}()<>`"]", "")
                    if clean != ""
                        _ms_theme["font"] := clean
                }
            }
        ;; END Theme ;;

        ;; Integrity ;;
            class integrity {
                static hashFile(path) {
                    out := ""
                    RunWait 'powershell -NoProfile -Command "(Get-FileHash \"' path '\" -Algorithm SHA256).Hash.ToLower()" > "' A_Temp '\ms_hash.txt"',, "Hide"
                    try out := FileRead(A_Temp "\ms_hash.txt")
                    try FileDelete A_Temp "\ms_hash.txt"
                    h := Trim(out)
                    return (StrLen(h) = 64) ? h : ""
                }

                static readTrustedHash() {
                    global _ms_hash_path
                    if !FileExist(_ms_hash_path)
                        return ""
                    h := ""
                    try h := FileRead(_ms_hash_path)
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
                    cur := ms.integrity.hashFile(_ms_core_path)
                    trusted := ms.integrity.readTrustedHash()
                    if trusted = ""
                        return "uninitialized"
                    return (cur = trusted) ? "trusted" : "mismatch"
                }

                static trustCurrent() {
                    global _ms_core_path
                    hash := ms.integrity.hashFile(_ms_core_path)
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
            }
        ;; END Integrity ;;

        ;; User Settings API ;;
            class settings {
                static define(def) {
                    global _ms_user_defs, _ms_user_index, _ms_user_vals
                    validTypes := Map("toggle",true,"slider",true,"seg",true,
                        "action",true,"divider",true,"groupLabel",true)
                    t := def.HasProp("type") ? def.type : ""
                    if !validTypes.Has(t)
                        throw Error("ms.settings.define: unknown type '" t "'")
                    if t = "divider" || t = "groupLabel" {
                        _ms_user_defs.Push(def)
                        return
                    }
                    key := def.HasProp("key") ? def.key : ""
                    if key = ""
                        throw Error("ms.settings.define: 'key' required for '" t "'")
                    if _ms_user_index.Has(key)
                        throw Error("ms.settings.define: duplicate key '" key "'")
                    _ms_user_index[key] := def
                    _ms_user_defs.Push(def)
                    if t = "action"
                        return
                    default := def.HasProp("default") ? def.default : ""
                    _ms_user_vals[key] := default
                }

                static get(key) {
                    global _ms_user_index, _ms_user_vals
                    if !_ms_user_index.Has(key)
                        return ""
                    def := _ms_user_index[key]
                    if _ms_user_vals.Has(key)
                        return _ms_user_vals[key]
                    return def.HasProp("default") ? def.default : ""
                }

                static set(key, value) {
                    global _ms_user_index, _ms_user_vals
                    if !_ms_user_index.Has(key)
                        return
                    def := _ms_user_index[key]
                    if def.type = "action"
                        return
                    validated := _ms_validateUserValue(def, value)
                    if validated = ""
                        return
                    _ms_user_vals[key] := validated
                    if def.HasProp("save") && def.save = false
                        return
                    ms.saveSettings()
                }
            }
        ;; END User Settings API ;;

        ;; SOCD ;;
            static socdStart() {
                global _ms_socd_active, _ms_socd_held, _ms_target_exe
                if _ms_socd_active
                    return
                _ms_socd_active := true
                _ms_socd_held := Map("a",false,"d",false,"w",false,"s",false)
                HotIfWinActive _ms_target_exe
                Hotkey "$a",    _ms_socd_keyDown.Bind("a"), "On"
                Hotkey "$a Up", _ms_socd_keyUp.Bind("a"),   "On"
                Hotkey "$d",    _ms_socd_keyDown.Bind("d"), "On"
                Hotkey "$d Up", _ms_socd_keyUp.Bind("d"),   "On"
                Hotkey "$w",    _ms_socd_keyDown.Bind("w"), "On"
                Hotkey "$w Up", _ms_socd_keyUp.Bind("w"),   "On"
                Hotkey "$s",    _ms_socd_keyDown.Bind("s"), "On"
                Hotkey "$s Up", _ms_socd_keyUp.Bind("s"),   "On"
                HotIfWinActive
            }

            static socdStop() {
                global _ms_socd_active, _ms_socd_held, _ms_target_exe
                if !_ms_socd_active
                    return
                _ms_socd_active := false
                HotIfWinActive _ms_target_exe
                for _, k in ["a","a Up","d","d Up","w","w Up","s","s Up"]
                    try Hotkey "$" k, "Off"
                HotIfWinActive
                _ms_socd_held := Map("a",false,"d",false,"w",false,"s",false)
            }

            static socdApply() {
                if ms.socdEnabled
                    ms.socdStart()
                else
                    ms.socdStop()
            }
        ;; END SOCD ;;

        ;; Audio Discovery ;;
            static _discoverSounds() {
                global _ms_sounds, SoundLib
                _ms_sounds := Map()
                if DirExist(SoundLib) {
                    Loop Files SoundLib "*.*" {
                        name := RegExReplace(A_LoopFileName, "\.[^.]+$")
                        if name != ""
                            _ms_sounds[name] := A_LoopFileFullPath
                    }
                }
            }
        ;; END Audio Discovery ;;

        ;; UI Panel ;;
            class ui {
                static show() {
                    global _ms_ui_panel_gui, _ms_ui_panel_wv, _ms_ui_open, _ms_ui_pos
                    if _ms_ui_open && _ms_ui_panel_gui {
                        WinActivate "ahk_id " _ms_ui_panel_gui.Hwnd
                        return
                    }
                    _ms_ui_open := true
                    panelW := 360, panelH := 640
                    hGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
                    hGui.OnEvent("Close", (*) => ms.ui.hide())
                    hGui.Show("w" panelW " h" panelH " NoActivate")
                    MonitorGetWorkArea 1, &sL, &sT, &sR, &sB
                    x := sL + Floor((sR - sL) / 4 - panelW / 2)
                    y := sT + Floor(((sB - sT) - panelH) / 2)
                    hGui.Move(x, y)
                    _ms_ui_pos := {x:x, y:y, w:panelW, h:panelH}
                    hWv := WebView2.create(hGui.Hwnd)
                    hWvCore := hWv.CoreWebView2
                    hWvCore.Navigate("file:///" StrReplace(A_ScriptDir "\..\ui\ms_settings_ui.html", "\", "/"))
                    hWvCore.add_WebMessageReceived(_ms_ui_onMessage)
                    _ms_ui_panel_gui := hGui
                    _ms_ui_panel_wv  := hWv
                    _ms_ui_open      := true
                    ms.playSlot("settingsOpen")
                }

                static hide() {
                    global _ms_ui_panel_gui, _ms_ui_panel_wv, _ms_ui_open, _ms_target_exe
                    if _ms_ui_panel_gui {
                        ms.playSlot("settingsClose")
                        _ms_ui_panel_gui.Destroy()
                        _ms_ui_panel_gui := 0
                        _ms_ui_panel_wv  := 0
                    }
                    _ms_ui_open := false
                    if _ms_target_exe != ""
                        try WinActivate _ms_target_exe
                }

                static toggle() {
                    global _ms_ui_open
                    if _ms_ui_open
                        ms.ui.hide()
                    else
                        ms.ui.show()
                }

                static refresh() {
                    global _ms_ui_panel_wv
                    if !_ms_ui_panel_wv
                        return
                    json := Jxon_Dump(_ms_sanitizeForJSON(_ms_buildUIState()), 0)
                    try _ms_ui_panel_wv.ExecuteScript("receiveState(" json ")")
                }

                static modal(data, callback) {
                    global _ms_ui_panel_wv, _ms_ui_modal_cb, _ms_ui_open
                    if !callback
                        return
                    if !_ms_ui_panel_wv {
                        try callback.Call(Map("confirmed", false))
                        return
                    }
                    _ms_ui_modal_cb := callback
                    if !_ms_ui_open
                        ms.ui.show()
                    m := Map()
                    m["title"]   := data.HasProp("title")   ? data.title   : ""
                    m["msg"]     := data.HasProp("msg")     ? data.msg     : ""
                    m["confirm"] := data.HasProp("confirm") ? data.confirm : "OK"
                    m["cancel"]  := data.HasProp("cancel")  ? data.cancel  : "Cancel"
                    json := Jxon_Dump(m, 0)
                    if _ms_ui_panel_wv
                        try _ms_ui_panel_wv.ExecuteScript("openLuaModal(" json ")")
                }

                static prompt(data, callback) {
                    global _ms_ui_panel_wv, _ms_ui_modal_cb, _ms_ui_open
                    if !callback
                        return
                    if !_ms_ui_panel_wv {
                        try callback.Call(Map("confirmed", false, "value", ""))
                        return
                    }
                    _ms_ui_modal_cb := callback
                    if !_ms_ui_open
                        ms.ui.show()
                    m := Map()
                    m["title"]        := data.HasProp("title")   ? data.title   : ""
                    m["msg"]          := data.HasProp("msg")     ? data.msg     : ""
                    m["confirm"]      := data.HasProp("confirm") ? data.confirm : "OK"
                    m["cancel"]       := data.HasProp("cancel")  ? data.cancel  : "Cancel"
                    m["hasInput"]     := true
                    m["inputDefault"] := data.HasProp("default") ? data.default : ""
                    json := Jxon_Dump(m, 0)
                    if _ms_ui_panel_wv
                        try _ms_ui_panel_wv.ExecuteScript("openLuaModal(" json ")")
                }
            }
        ;; END UI Panel ;;

        ;; Sound Import ;;
            static importSounds() {
                global SoundLib, _ms_sounds
                files := FileSelect("M3", SoundLib, "Select sound files to import")
                if !files
                    return
                added := 0
                for file in files {
                    if !FileExist(file)
                        continue
                    fname := RegExReplace(file, ".*[/\\]")
                    dst := SoundLib fname
                    if !FileExist(dst) {
                        FileCopy file, dst
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
        ;; END Sound Import ;;

        ;; Profile System ;;
            static switchProfile(targetName) {
                global _ms_profiles_path, _ms_json_path
                targetFile := _ms_profiles_path targetName "\ms_macros.ahk"
                if !FileExist(targetFile) {
                    ms.alert("Profile switch failed: cannot read target profile.", 5)
                    return
                }
                curName := ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "default"
                safeN := RegExReplace(curName, "[/\:*?`"<>|]", "_")
                DirCreate _ms_profiles_path safeN
                FileCopy A_ScriptDir "\ms_macros.ahk", _ms_profiles_path safeN "\ms_macros.ahk", 1
                FileCopy _ms_json_path, _ms_profiles_path safeN "\ms_settings.json", 1
                FileCopy targetFile, A_ScriptDir "\ms_macros.ahk", 1
                tSettings := _ms_profiles_path targetName "\ms_settings_default.json"
                if FileExist(tSettings)
                    FileCopy tSettings, _ms_json_path, 1
                ms.playSlot("update")
                ms.alert("Switched to '" targetName "'.`nReloading in 3 s…", 5, true)
                SetTimer () => Reload(), -3000
            }

            static exportProfilePkg() {
                name := ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "profile"
                safe := RegExReplace(name, "[/\:*?`"<>|]", "_")
                outFile := A_MyDocuments "\Downloads\" safe ".mspkg"
                tmpDir := A_Temp "\ms_export_" A_TickCount
                DirCreate tmpDir
                FileCopy A_ScriptDir "\ms_macros.ahk", tmpDir "\ms_macros.ahk", 1
                FileCopy A_ScriptDir "\data\ms_settings_default.json", tmpDir "\ms_settings_default.json", 0
                if DirExist(SoundLib) {
                    DirCreate tmpDir "\sounds"
                    Loop Files SoundLib "*.*"
                        FileCopy A_LoopFileFullPath, tmpDir "\sounds\" A_LoopFileName, 0
                }
                RunWait "powershell -NoProfile -Command Compress-Archive -Path '" tmpDir "\*' -DestinationPath '" outFile "' -Force",, "Hide"
                DirDelete tmpDir, true
                ms.playSlot("update")
                ms.alert("Profile exported to:`n" outFile, 6)
            }

            static importProfilePkg() {
                file := FileSelect(3, A_ScriptDir, "Select a .mspkg file", "Macro Pack (*.mspkg)")
                if file = ""
                    return
                tmpDir := A_Temp "\ms_import_" A_TickCount
                DirCreate tmpDir
                RunWait "powershell -NoProfile -Command Expand-Archive -Path '" file "' -DestinationPath '" tmpDir "' -Force",, "Hide"
                macrosFile := tmpDir "\ms_macros.ahk"
                if !FileExist(macrosFile) {
                    DirDelete tmpDir, true
                    ms.alert("Import failed: ms_macros.ahk not found in package.", 5)
                    return
                }
                profileName := "imported"
                DirCreate _ms_profiles_path profileName
                FileCopy macrosFile, _ms_profiles_path profileName "\ms_macros.ahk", 1
                if FileExist(tmpDir "\ms_settings_default.json")
                    FileCopy tmpDir "\ms_settings_default.json", _ms_profiles_path profileName "\ms_settings_default.json", 1
                if DirExist(tmpDir "\sounds") {
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
        ;; END Profile System ;;

        ;; Update Checker ;;
            static update() {
                manifestURL := "https://raw.githubusercontent.com/mudbourn/ms-utils/main/MANIFEST.json"
                if !RegExMatch(manifestURL, "^https://") {
                    ms.alert("Update URL must use HTTPS.", 6)
                    return
                }
                ms.alert("Fetching update manifest…", 4, true)
                tmpManifest := A_Temp "\ms_manifest.json"
                try FileDelete tmpManifest
                RunWait "powershell -NoProfile -Command Invoke-WebRequest -Uri '" manifestURL "' -OutFile '" tmpManifest "' -UseBasicParsing",, "Hide"
                if !FileExist(tmpManifest) {
                    ms.alert("Update failed: could not download manifest.", 5)
                    return
                }
                raw := ""
                try raw := FileRead(tmpManifest)
                try FileDelete tmpManifest
                manifest := Jxon_Load(&raw)
                if !manifest || !manifest.Has("windows_sha256") || !manifest.Has("windows_url") {
                    ms.alert("Update failed: manifest missing Windows fields.", 5)
                    return
                }
                newVer       := manifest.Has("version") ? manifest["version"] : "?"
                expectedHash := manifest["windows_sha256"]
                dlURL        := manifest["windows_url"]
                ms.alert("Downloading v" newVer "…", 4, true)
                tmpFile := A_Temp "\ms_core_update.ahk"
                try FileDelete tmpFile
                RunWait "powershell -NoProfile -Command Invoke-WebRequest -Uri '" dlURL "' -OutFile '" tmpFile "' -UseBasicParsing",, "Hide"
                if !FileExist(tmpFile) {
                    ms.alert("Update failed: could not download file.", 5)
                    return
                }
                actualHash := ms.integrity.hashFile(tmpFile)
                global _ms_archive_path, _ms_core_path
                DirCreate _ms_archive_path
                ts := FormatTime(, "yyyy-MM-dd_HHmm")
                backup := _ms_archive_path "ms_core_" ts ".ahk.bak"
                FileCopy _ms_core_path, backup, 1
                try {
                    FileDelete _ms_core_path
                    FileCopy tmpFile, _ms_core_path
                    FileDelete tmpFile
                }
                ms.integrity.writeTrustedHash(actualHash)
                ms.alert("Updated to v" newVer ".`nReloading in 3 seconds…", 5, true)
                SetTimer () => Reload(), -3000
            }
        ;; END Update Checker ;;

        ;; Dev Tools ;;
            class dev {
                class console {
                    static toggle() => 0
                }
                class watcher {
                    static toggle() => 0
                }
                class keys {
                    static toggle() => 0
                }
                class window {
                    static toggle() => 0
                }
            }
        ;; END Dev Tools ;;

        ;; Menu / Features API ;;
            class menu {
                static define(def) {
                    global _ms_menu_defs
                    _ms_menu_defs.Push(def)
                }
            }

            class features {
                static hide(name) {
                    global _ms_hidden_feats
                    _ms_hidden_feats[name] := true
                }
            }
        ;; END Menu / Features API ;;

        ;; parseBind ;;
            static parseBind(str) {
                if RegExMatch(str, "^mouse:(\d+)$", &m)
                    return Map("type", "mouse", "button", Integer(m[1]))
                mods := [], parts := StrSplit(StrLower(str), "+")
                keys := Map("cmd",true,"alt",true,"ctrl",true,"shift",true)
                mainKey := ""
                for p in parts {
                    if keys.Has(p)
                        mods.Push(p)
                    else
                        mainKey := p
                }
                if mainKey != ""
                    return Map("type", "key", "mods", mods, "key", mainKey)
                return ""
            }
        ;; END parseBind ;;
    }
;; END Section 2 — ms class (public API) ;;

;; Section 3 — Helpers ;;

;; Coordinate Resolution ;;

    _ms_resolvePoint(x, y, reference, unscaled := false) {
        global REF_W, REF_H, _ms_target_exe

        if reference = "Absolute"
            return {x:x, y:y}

        if reference = "Mouse" {
            MouseGetPos &mx, &my
            return {x:mx + x, y:my + y}
        }

        wX := 0, wY := 0, wW := REF_W, wH := REF_H
        try WinGetPos &wX, &wY, &wW, &wH, _ms_target_exe

        sX := unscaled ? 1 : wW / REF_W
        sY := unscaled ? 1 : wH / REF_H

        if reference = "WindowTL"
            return {x:wX + x * sX, y:wY + y * sY}
        if reference = "WindowTR"
            return {x:wX + wW + x * sX, y:wY + y * sY}
        if reference = "WindowBL"
            return {x:wX + x * sX, y:wY + wH + y * sY}
        if reference = "WindowBR"
            return {x:wX + wW + x * sX, y:wY + wH + y * sY}
        if reference = "WindowCenter"
            return {x:wX + wW // 2 + x * sX, y:wY + wH // 2 + y * sY}

        MonitorGetWorkArea 1, &sL, &sT, &sR, &sB
        if reference = "ScreenTL"
            return {x:sL + x, y:sT + y}
        if reference = "ScreenTR"
            return {x:sR + x, y:sT + y}
        if reference = "ScreenBL"
            return {x:sL + x, y:sB + y}
        if reference = "ScreenBR"
            return {x:sR + x, y:sB + y}
        if reference = "ScreenCenter"
            return {x:(sL + sR) // 2 + x, y:(sT + sB) // 2 + y}

        return {x:x, y:y}
    }
;; END Coordinate Resolution ;;

;; Mouse Button Translation ;;
    _ms_mouseButton(btn) {

        buttons := Map(
            "Left","Left","Right","Right","Middle","Middle",
            "X1","X1","X2","X2",
            "Center","Middle","Button4","X1","Button5","X2",
        )
        return buttons.Has(btn) ? buttons[btn] : btn
    }
;; END Mouse Button Translation ;;

;; Key Name / Modifier Translation ;;

    _ms_keyName(k) {
        static kmap := ""
        if kmap = "" {
            kmap := Map(
                "space","Space", "enter","Enter", "return","Enter",
                "escape","Escape", "tab","Tab", "backspace","Backspace",
                "delete","Delete", "insert","Insert",
                "up","Up", "down","Down", "left","Left", "right","Right",
                "home","Home", "end","End", "pageup","PgUp", "pagedown","PgDn",
                "f1","F1","f2","F2","f3","F3","f4","F4",
                "f5","F5","f6","F6","f7","F7","f8","F8",
                "f9","F9","f10","F10","f11","F11","f12","F12",
                "[","[","]","]","\\","\\",
            )
        }
        return kmap.Has(k) ? kmap[k] : k
    }

    _ms_keyMod(m) {
        static mmap := ""
        if mmap = "" {
            mmap := Map(
                "shift","+","lshift","+","rshift","+",
                "ctrl","^","lctrl","^","rctrl","^",
                "alt","!","lalt","!","ralt","!",
                "cmd","^","win","#",
            )
        }
        return mmap.Has(m) ? mmap[m] : ""
    }
;; END Key Name / Modifier Translation ;;

;; Effective Bind Resolver ;;

    _ms_effectiveBind(id) {
        global _ms_bindConfig, _ms_trackpad_mode, _ms_trackpad_bind_ovr

        if _ms_trackpad_mode && _ms_trackpad_bind_ovr.Has(id)
            return _ms_trackpad_bind_ovr[id]
        if _ms_bindConfig.Has(id)
            return _ms_bindConfig[id]
        def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
        if def != "" && def.Has("default") && def["default"] != ""
            return def["default"]
        return ""
    }
;; END Effective Bind Resolver ;;

;; Bind Key / Hotkey Building ;;

    _ms_bindKey(c) {

        if c = ""
            return ""
        hasType := (c is Map) ? c.Has("type") : c.HasProp("type")
        if hasType && c.type = "mouse"
            return "mouse:" c.button
        if hasType && c.type = "key" {
            hasMods := (c is Map) ? c.Has("mods") : c.HasProp("mods")
            mods := hasMods ? c.mods.Clone() : []
            s := ""
            for m in mods
                s .= m ","
            hasKey := (c is Map) ? c.Has("key") : c.HasProp("key")
            return "key:" s ":" (hasKey ? c.key : "")
        }
        return ""
    }

    _ms_buildHotkey(c) {

        if c = ""
            return ""
        hasType := (c is Map) ? c.Has("type") : c.HasProp("type")
        if hasType && c.type = "mouse" {
            buttons := Map(0,"LButton",1,"RButton",2,"MButton",3,"XButton1",4,"XButton2")
            return buttons.Has(c.button) ? buttons[c.button] : ""
        }
        if hasType && c.type = "key" {
            prefix := ""
            hasMods := (c is Map) ? c.Has("mods") : c.HasProp("mods")
            if hasMods {
                for mod in c.mods
                    prefix .= _ms_keyMod(mod)
            }
            hasKey := (c is Map) ? c.Has("key") : c.HasProp("key")
            return prefix _ms_keyName(hasKey ? c.key : "")
        }
        return ""
    }
;; END Bind Key / Hotkey Building ;;

;; Hotkey Fire Callbacks ;;
    _ms_fireRoot(fn, id, group, cd, *) {
        global BindValidity, _ms_running, _ms_active_sub
        if BindValidity != 1
            return
        if _ms_running.Has(group)
            return
        _ms_running[group] := true
        SetTimer () => _ms_running.Has(group) && _ms_running.Delete(group), -cd
        _ms_active_sub := ""
        ms._currentFlags := {alt: GetKeyState("Alt", "P"), ctrl: GetKeyState("Ctrl", "P"), shift: GetKeyState("Shift", "P"), win: GetKeyState("LWin", "P")}
        try fn()
        catch as e {
            if e.Message != "ms.cancelled"
                ms.alert("Macro error — check OutputDebug.", 4)
        }
    }

    _ms_fireSub(fn, id, group, cd, *) {
        global _ms_running, _ms_active_sub
        if _ms_running.Has(group)
            return
        _ms_running[group] := true
        SetTimer () => _ms_running.Has(group) && _ms_running.Delete(group), -cd
        _ms_active_sub := id
        ms._currentFlags := {alt: GetKeyState("Alt", "P"), ctrl: GetKeyState("Ctrl", "P"), shift: GetKeyState("Shift", "P"), win: GetKeyState("LWin", "P")}
        fn()
    }
;; END Hotkey Fire Callbacks ;;

;; SOCD Key Handlers ;;
    _ms_socd_keyDown(key, *) {
        global _ms_socd_held, ms_socdMode, BindValidity

        if BindValidity != 1 {
            SendLevel 1
            Send "{" key " down}"
            SendLevel 0
            return
        }
        _ms_socd_held[key] := true
        opp := Map("a","d","d","a","w","s","s","w")[key]
        if _ms_socd_held[opp] {
            if ms_socdMode = "lastWins" {
                Send "{" opp " up}"
                SendLevel 0
            } else if ms_socdMode = "firstWins" {
                _ms_socd_held[key] := false
                return
            } else if ms_socdMode = "neutral" {
                _ms_socd_held[opp] := false
                _ms_socd_held[key] := false
                Send "{" opp " up}"
                SendLevel 0
                return
            }
        }
        SendLevel 1
        Send "{" key " down}"
        SendLevel 0
    }

    _ms_socd_keyUp(key, *) {
        global _ms_socd_held
        _ms_socd_held[key] := false
        SendLevel 1
        Send "{" key " up}"
        SendLevel 0
    }
;; END SOCD Key Handlers ;;

;; Settings ;;

    _ms_applySettings(data) {
        global _ms_binds, _ms_bindConfig, _ms_subBinds, _ms_modConfig, _ms_cooldowns
        global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign
        global _ms_trackpad_mode, _ms_trackpad_hold_keys, _ms_independent_binds
        global _ms_user_index, _ms_user_vals, CUR_CAM_SENS, clickLevel

        if !data
            return

        if data.Has("sensitivity") {
            n := Number(data["sensitivity"])
            if n >= 0.1 && n <= 4
                CUR_CAM_SENS := n
        }
        if data.Has("frameLevel") {
            n := Number(data["frameLevel"])
            if n >= 1 && n <= 4
                clickLevel := Integer(n)
        }
        if data.Has("trackpadMode")
            _ms_trackpad_mode := (data["trackpadMode"] = true)
        if data.Has("socdEnabled")
            ms.socdEnabled := (data["socdEnabled"] = true)
        if data.Has("independentBinds")
            _ms_independent_binds := (data["independentBinds"] = true)

        m := data.Has("socdMode") ? data["socdMode"] : ""
        if m = "lastWins" || m = "neutral" || m = "firstWins"
            ms.socdMode := m

        if data.Has("trackpadHoldKeys") {
            thk := data["trackpadHoldKeys"]
            if thk.Has("left")
                _ms_trackpad_hold_keys.left := thk["left"]
            if thk.Has("right")
                _ms_trackpad_hold_keys.right := thk["right"]
        }
        if data.Has("soundEnabled")
            _ms_soundEnabled := (data["soundEnabled"] = true)
        if data.Has("soundVolume") {
            v := Number(data["soundVolume"])
            if v >= 0 && v <= 100
                _ms_soundVolume := Integer(v)
        }
        if data.Has("soundAssign")
            _ms_soundAssign := data["soundAssign"]

        if data.Has("macros") {
            for id, entry in data["macros"] {
                if entry.Has("enabled")
                    _ms_binds[id] := (entry["enabled"] = true)
                if entry.Has("bind") {
                    def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
                    if def != "" && def.Has("sub") && def["sub"] != ""
                        _ms_subBinds[id] := entry["bind"]
                    else
                        _ms_bindConfig[id] := entry["bind"]
                }
                if entry.Has("mod")
                    _ms_modConfig[id] := entry["mod"]
                if entry.Has("cooldown") {
                    n := Number(entry["cooldown"])
                    if n >= 0
                        _ms_cooldowns[id] := Integer(n)
                }
            }
        }

        if data.Has("user") {
            for key, val in data["user"] {
                if _ms_user_index.Has(key) {
                    validated := _ms_validateUserValue(_ms_user_index[key], val)
                    if validated != ""
                        _ms_user_vals[key] := validated
                }
            }
        }
    }

    _ms_buildDefaultSettings() {
        global _ms_default_path, _ms_archive_path

        DirCreate A_ScriptDir "\data"

        data := Map(
            "sensitivity",      1.5,
            "frameLevel",       3,
            "trackpadMode",     false,
            "socdEnabled",      false,
            "socdMode",         "lastWins",
            "independentBinds", false,
            "trackpadHoldKeys", Map("left","n","right","j"),
            "soundEnabled",     true,
            "soundVolume",      100,
            "soundAssign",      Map(),
            "macros",           Map(),
        )

        if ms.macroDefaults.HasProp("sensitivity")
            data["sensitivity"]      := ms.macroDefaults.sensitivity
        if ms.macroDefaults.HasProp("frameLevel")
            data["frameLevel"]       := ms.macroDefaults.frameLevel
        if ms.macroDefaults.HasProp("trackpadMode")
            data["trackpadMode"]     := ms.macroDefaults.trackpadMode
        if ms.macroDefaults.HasProp("socdEnabled")
            data["socdEnabled"]      := ms.macroDefaults.socdEnabled
        if ms.macroDefaults.HasProp("socdMode")
            data["socdMode"]         := ms.macroDefaults.socdMode

        for _, id in ms.bind._defList {
            def := ms.bind._defs[id]
            if !def || def.Has("sub") && def["sub"] != ""
                continue
            if !data["macros"].Has(id)
                data["macros"][id] := Map()
            if !data["macros"][id].Has("enabled")
                data["macros"][id]["enabled"] := def["enabled"]
        }

        if ms.macroDefaults.HasProp("macros") {
            for id, entry in ms.macroDefaults.macros {
                if !data["macros"].Has(id)
                    data["macros"][id] := Map()
                for k, v in entry
                    data["macros"][id][k] := v
            }
        }

        try FileOpen(_ms_default_path, "w").Write(Jxon_Dump(data, 4))
    }

    _ms_validateUserValue(def, value) {

        if def.type = "toggle" {
            if value = true || value = false
                return value
        } else if def.type = "slider" {
            n := Number(value)
            if n != ""
                return Max(def.HasProp("min") ? def.min : 0, Min(def.HasProp("max") ? def.max : 100, n))
        } else if def.type = "seg" {
            if def.HasProp("options") {
                for opt in def.options {
                    if opt.HasProp("value") && opt.value = value
                        return value
                }
            }
        }
        return ""
    }
;; END Settings ;;

;; Profile List ;;

    _ms_getProfiles() {
        global _ms_profiles_path

        list := []
        if !DirExist(_ms_profiles_path)
            return list
        Loop Files _ms_profiles_path "*.*", "D" {
            if FileExist(A_LoopFileFullPath "\ms_macros.ahk")
                list.Push(A_LoopFileName)
        }
        return list
    }
;; END Profile List ;;

;; Notify ;;
    _ms_notify(state) {
        global _ms_loadDone
        if state != 1 && state != 0
            _ms_showToast(state, 3)
        else if _ms_loadDone {
            if state = 1 {
                ms.playSlot("enabled")
                _ms_showToast("Macros enabled!", 3)
            } else {
                ms.playSlot("disabled")
                _ms_showToast("Macros disabled.", 3)
            }
        }
    }
;; END Notify ;;

;; Toast System ;;
    _ms_toastQueue := []
    _ms_toastMax  := 4
    _ms_toastBase := 80        ; px above bottom
    _ms_toastGap  := 6
    _ms_toastFade := 225

    _ms_showToast(msg, duration := 5) {
        ; Evict oldest if queue full
        if _ms_toastQueue.Length >= _ms_toastMax {
            oldest := _ms_toastQueue.RemoveAt(1)
            try oldest.gui.Destroy()
        }

        bg  := Trim(_ms_theme["surface2"], "#")
        fg  := Trim(_ms_theme["text"], "#")
        font := _ms_theme.Has("font") && _ms_theme["font"] != "" ? _ms_theme["font"] : ""

        hGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
        hGui.BackColor := bg
        hGui.MarginX := 14, hGui.MarginY := 8
        if font != ""
            hGui.SetFont("s11 c" fg, font)
        else
            hGui.SetFont("s11 c" fg)

        ; Centered text control at full width
        hGui.Add("Text", "Center", msg)

        ; Measure by autosizing, then reposition
        hGui.Show("AutoSize")
        hGui.GetPos(,, &tw, &th)
        guiW := Max(220, Min(560, tw + 12))
        guiH := th + 4

        ; Stack from bottom
        MonitorGetWorkArea 1, &sL, &sT, &sR, &sB
        x := sL + (sR - sL - guiW) // 2

        totalH := 0
        for entry in _ms_toastQueue
            totalH += entry._h + _ms_toastGap
        y := sB - _ms_toastBase - totalH - guiH

        hGui.Move(x, y, guiW, guiH)
        hGui.Show("NoActivate")
        WinSetTransparent _ms_toastFade, hGui

        entry := {gui: hGui, msg: msg, _h: guiH}
        _ms_toastQueue.Push(entry)

        SetTimer () => _ms_toastDismiss(hGui), -(duration * 1000)
        hGui.OnEvent("Close", (*) => _ms_toastDismiss(hGui))
    }

    _ms_toastDismiss(hGui) {
        for i, entry in _ms_toastQueue {
            if entry.HasProp("gui") && entry.gui = hGui {
                _ms_toastQueue.RemoveAt(i)
                try hGui.Destroy()
                _ms_toastRedraw()
                break
            }
        }
    }

    _ms_toastRedraw() {
        MonitorGetWorkArea 1, &sL, &sT, &sR, &sB
        totalH := 0
        for entry in _ms_toastQueue {
            entry.gui.GetPos(&gx, &gy, &gw, &gh)
            x := sL + (sR - sL - gw) // 2
            y := sB - _ms_toastBase - totalH - gh
            entry.gui.Move(x, y)
            totalH += gh + _ms_toastGap
        }
    }
;; END Toast System ;;

;; Loading Screen ;;
    _ms_loadGui  := 0
    _ms_loadWv   := 0

        _ms_loadingShow() {
            global _ms_loadGui, _ms_loadWv, _ms_theme

            lw := 300, lh := 104
            MonitorGetWorkArea 1, &sL, &sT, &sR, &sB
            x := sL + (sR - sL - lw) // 2
            y := sB - 150 - lh

            hGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
            hGui.Show("w" lw " h" lh " x" x " y" y " NoActivate")
            _ms_loadGui := hGui
            WebView2.create(hGui.Hwnd, _ms_loadingWvReady)
        }

        _ms_loadingWvReady(hWv) {
            global _ms_loadGui, _ms_loadWv, _ms_theme
            hWv.CoreWebView2.Navigate("file:///" StrReplace(A_ScriptDir "\..\ui\ms_loading.html", "\", "/"))
            ; Push theme once page loads so HTML can style itself from ms_theme.json values
            hWv.CoreWebView2.add_NavigationCompleted((w, *) => (
                w.ExecuteScript("applyTheme(" Jxon_Dump(_ms_theme, 0) ")")
            ))
            _ms_loadWv  := hWv
        }

        _ms_loadingUpdate(pct, msg) {
            global _ms_loadWv
            if !_ms_loadWv
                return
            try _ms_loadWv.ExecuteScript('setProgress(' Round(Max(0, Min(100, pct))) ', "' msg '")')
        }

        _ms_loadingDismiss() {
            global _ms_loadGui, _ms_loadWv, _ms_loadFadeGui, _ms_loadFadeStep
            if !_ms_loadGui
                return
            _ms_loadFadeGui  := _ms_loadGui
            _ms_loadFadeStep := 0
            _ms_loadGui := 0
            _ms_loadWv  := 0
            SetTimer _ms_loadFadeTick, 30
        }

    _ms_loadFadeGui  := 0
    _ms_loadFadeStep := 0

        _ms_loadFadeTick() {
            global _ms_loadFadeGui, _ms_loadFadeStep
            _ms_loadFadeStep++
            WinSetTransparent Max(0, 255 - _ms_loadFadeStep * 43), _ms_loadFadeGui
            if _ms_loadFadeStep >= 6 {
                _ms_loadFadeGui.Destroy()
                _ms_loadFadeGui  := 0
                _ms_loadFadeStep := 0
                SetTimer , 0
            }
        }
;; END Loading Screen ;;

;; App Watcher ;;
    _ms_robloxActive := false
    _ms_pollTimer    := 0

        _ms_appPoll() {
            global _ms_robloxActive, _ms_ui_open, _ms_loadDone, _ms_target_exe

            if !_ms_loadDone
                return
            active := _ms_target_exe != "" && WinActive(_ms_target_exe) != 0
            if active && !_ms_robloxActive {
                _ms_robloxActive := true
                ms.cam.updateMultiplier()
                global BindValidity
                if !_ms_loadDone
                    return
                if !_ms_ui_open
                    ms.setMacros(1, true)
            } else if !active && _ms_robloxActive {
                if !_ms_ui_open {
                    _ms_robloxActive := false
                    ms.setMacros(0, true)
                }
            }
        }
;; END App Watcher ;;

;; System Hotkey Registration ;;
    _ms_lastSlash := 0
    _ms_lastEnter := 0

        _ms_registerHotkeys() {
            global _ms_target_exe, _ms_lastSlash, _ms_lastEnter

            HotIfWinActive _ms_target_exe
            Hotkey "![",   (*) => Reload()
            Hotkey "!]",   (*) => ms.reloadSettings()
            Hotkey "!p",   (*) => ms.ui.toggle()
            Hotkey "!F10", (*) => ms.setMacros(0)
            Hotkey "/",    _ms_hotkeySlash
            Hotkey "Enter", _ms_hotkeyEnter
            HotIfWinActive
        }

        _ms_hotkeySlash(*) {
            global _ms_lastSlash, BindValidity
            if (A_TickCount - _ms_lastSlash) < 100
                return
            _ms_lastSlash := A_TickCount
            if BindValidity
                ms.setMacros(0)
        }

        _ms_hotkeyEnter(*) {
            global _ms_lastEnter, BindValidity
            if (A_TickCount - _ms_lastEnter) < 100
                return
            _ms_lastEnter := A_TickCount
            if !BindValidity
                ms.setMacros(1)
        }
;; END System Hotkey Registration ;;

;; Integrity Auto-Seed ;;
    _ms_integritySeed() {

        if ms.integrity.check() != "uninitialized"
            return
        mPath := A_ScriptDir "\MANIFEST.json"
        if FileExist(mPath) {
            raw := ""
            try raw := FileRead(mPath)
            manifest := Jxon_Load(&raw)
            if manifest && manifest.Has("windows_sha256") {
                cur := ms.integrity.hashFile(_ms_core_path)
                if cur != "" && StrLower(cur) = StrLower(manifest["windows_sha256"])
                    ms.integrity.writeTrustedHash(cur)
            }
        }
    }
;; END Integrity Auto-Seed ;;

;; Font Installation ;;
    _ms_installFonts() {

        fontSrc := A_ScriptDir "\ui\fonts"
        if !DirExist(fontSrc)
            return
        fontDst := EnvGet("LOCALAPPDATA") "\Microsoft\Windows\Fonts"
        DirCreate fontDst
        installed := false
        Loop Files fontSrc "\*.*" {
            ext := ""
            SplitPath A_LoopFileName,,, &ext
            if ext != "ttf" && ext != "otf"
                continue
            dstFile := fontDst "\" A_LoopFileName
            if !FileExist(dstFile) {
                FileCopy A_LoopFileFullPath, dstFile, 0
                installed := true
            }
        }
        if installed
            SetTimer () => Reload(), -500
    }
;; END Font Installation ;;


;; Dev Log Archive ;;
    _ms_pruneLogs() {
        global _ms_dev_log_path

        if !FileExist(_ms_dev_log_path)
            return
        archDir := A_ScriptDir "\data\ms_dev_logs"
        DirCreate archDir
        ts := FormatTime(, "yyyy-MM-dd_HHmmss")
        try FileMove _ms_dev_log_path, archDir "\ms_dev_" ts ".log", 0
        ; Keep only 20 most recent
        archives := []
        Loop Files archDir "\ms_dev_*.log"
            archives.Push(A_LoopFileName)
        while archives.Length > 20 {
            try FileDelete archDir "\" archives[1]
            archives.RemoveAt(1)
        }
    }
;; END Dev Log Archive ;;

;; JSON Sanitizer Helper ;;
    ; Recursively converts Objects to Maps so Jxon_Dump can serialize them.
    _ms_sanitizeForJSON(val) {
        if !IsObject(val)
            return val
        if val is Map {
            result := Map()
            for k, v in val {
                if !(v is Func) && !(v is Closure) && !(v is BoundFunc)
                    result[k] := _ms_sanitizeForJSON(v)
            }
            return result
        }
        if val is Array {
            result := []
            for v in val {
                if !(v is Func) && !(v is Closure) && !(v is BoundFunc)
                    result.Push(_ms_sanitizeForJSON(v))
            }
            return result
        }
        ; Plain Object — convert own properties to Map
        result := Map()
        for k in val.OwnProps() {
            v := val.%k%
            if !(v is Func) && !(v is Closure) && !(v is BoundFunc)
                result[k] := _ms_sanitizeForJSON(v)
        }
        return result
    }
;; END JSON Sanitizer Helper ;;

;; UI State Builder ;;
    _ms_buildUIState() {
        global _ms_binds, _ms_bindConfig, _ms_subBinds, _ms_modConfig
        global _ms_soundEnabled, _ms_soundVolume, _ms_soundAssign, _ms_sounds
        global _ms_trackpad_mode, _ms_independent_binds, _ms_hidden_feats
        global _ms_user_defs, _ms_user_index, _ms_user_vals, _ms_menu_defs
        global _ms_theme, _ms_theme_loaded, CUR_CAM_SENS, clickLevel, BindValidity

        ms._discoverSounds()

        macros := []
        for _, id in ms.bind._defList {
            def := ms.bind._defs[id]
            if !def || (def.Has("sub") && def["sub"] != "") || (def["group"] != "main" && def["group"] != "optional")
                continue
            enabled := _ms_binds.Has(id) ? _ms_binds[id] : def["enabled"]
            subs := []
            for _, sid in ms.bind._defList {
                sdef := ms.bind._defs[sid]
                if sdef && sdef.Has("sub") && sdef["sub"] = id {
                    bindStr := ""
                    if _ms_subBinds.Has(sid) {
                        c := _ms_subBinds[sid]
                        hasSType := (c is Map) ? c.Has("type") : c.HasProp("type")
                        hasSKey := (c is Map) ? c.Has("key") : c.HasProp("key")
                        bindStr := (hasSType && c.type = "mouse") ? "mouse:" c.button : (hasSKey ? c.key : "")
                    }
                    subs.Push(Map("id", sid, "label", sdef["label"], "bind", bindStr))
                }
            }
            c := _ms_effectiveBind(id)
            bindStr := ""
            if c != "" {
                hasCType := (c is Map) ? c.Has("type") : c.HasProp("type")
                hasCMods := (c is Map) ? c.Has("mods") : c.HasProp("mods")
                hasCKey := (c is Map) ? c.Has("key") : c.HasProp("key")
                if hasCType && c.type = "mouse"
                    bindStr := "mouse:" c.button
                else if hasCMods && c.mods.Length > 0 {
                    for m in c.mods
                        bindStr .= m "+"
                    bindStr .= hasCKey ? c.key : ""
                } else
                    bindStr := hasCKey ? c.key : ""
            }
            macros.Push(Map("id",id,"label",def["label"],"group",def["group"],"bind",bindStr,"enabled",enabled,"subs",subs))
        }

        soundNames := []
        for name, _ in _ms_sounds
            soundNames.Push(name)

        status := ms.integrity.check()
        meta := ms.macroMeta

        return Map(
            "theme",            _ms_theme,
            "sensitivity",      CUR_CAM_SENS,
            "frameLevel",       clickLevel,
            "trackpadMode",     _ms_trackpad_mode,
            "socdEnabled",      ms.socdEnabled,
            "socdMode",         ms.socdMode,
            "independentBinds", _ms_independent_binds,
            "soundEnabled",     _ms_soundEnabled,
            "soundVolume",      _ms_soundVolume,
            "soundAssign",      _ms_soundAssign,
            "sounds",           soundNames,
            "macros",           macros,
            "macroName",        meta.HasProp("name")    ? meta.name    : "",
            "macroAuthor",      meta.HasProp("author")  ? meta.author  : "",
            "macroWebsite",     meta.HasProp("website") ? meta.website : "",
            "macroVersion",     meta.HasProp("version") ? meta.version : "",
            "version",          "1.2.0",
            "integrity",        status,
            "userDefs",         _ms_user_defs,
            "userVals",         _ms_user_vals,
            "menuDefs",         _ms_menu_defs,
            "hiddenFeats",      _ms_hidden_feats,
            "profiles",         _ms_getProfiles(),
            "bindValidity",     BindValidity,
            "hasConsole",       false,
            "hasKeys",          false,
        )
    }
;; END UI State Builder ;;


;; UI Panel WebView2 Message Handler ;;
    _ms_ui_onMessage(wv, event) {

        raw := event.TryGetWebMessageAsString()
        data := Jxon_Load(&raw)
        if !data || !data.Has("action")
            return

        action := data["action"]

        if action = "ready" {
            ms.ui.refresh()
        } else if action = "setMacros" {
            ms.setMacros(data.Has("value") && data["value"] = 1 ? 1 : 0)
            ms.ui.refresh()
        } else if action = "playSlot" {
            if data.Has("slot")
                ms.playSlot(data["slot"])
        } else if action = "alert" {
            if data.Has("msg")
                ms.alert(data["msg"], data.Has("duration") ? data["duration"] : 3)
        } else if action = "close" {
            ms.ui.hide()
        } else if action = "moveWindow" {
            dx := data.Has("dx") ? data["dx"] : 0
            dy := data.Has("dy") ? data["dy"] : 0
            global _ms_ui_pos, _ms_ui_panel_gui
            _ms_ui_pos.x += dx, _ms_ui_pos.y += dy
            if _ms_ui_panel_gui
                _ms_ui_panel_gui.Move(_ms_ui_pos.x, _ms_ui_pos.y)
        } else if action = "reloadMacros" {
            Reload()
        } else if action = "reloadSettings" {
            ms.reloadSettings()
            ms.ui.refresh()
        } else if action = "setMacroEnabled" && data.Has("id") {
            global _ms_binds
            _ms_binds[data["id"]] := (data.Has("value") && data["value"] = true)
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
        } else if action = "setSensitivity" && data.Has("value") {
            n := Number(data["value"])
            if n >= 0.1 && n <= 4 {
                global CUR_CAM_SENS := n
                ms.saveSettings(), ms.cam.updateMultiplier(), ms.playSlot("update")
            }
            ms.ui.refresh()
        } else if action = "setSocdEnabled" {
            ms.socdEnabled := (data.Has("value") && data["value"] = true)
            ms.saveSettings(), ms.socdApply(), ms.playSlot("update"), ms.ui.refresh()
        } else if action = "setSoundEnabled" {
            global _ms_soundEnabled := (data.Has("value") && data["value"] = true)
            ms.saveSettings(), ms.playSlot("update"), ms.ui.refresh()
        } else if action = "setSoundVolume" {
            n := data.Has("value") ? Number(data["value"]) : -1
            if n >= 0 && n <= 100 {
                global _ms_soundVolume := Integer(n)
                ms.saveSettings(), ms.playSlot("update")
            }
            ms.ui.refresh()
        } else if action = "setSoundAssign" && data.Has("slot") {
            global _ms_soundAssign
            name := data.Has("name") ? data["name"] : ""
            if name = ""
                _ms_soundAssign.Delete(data["slot"])
            else
                _ms_soundAssign[data["slot"]] := name
            ms.saveSettings(), ms.playSlot("update"), ms.ui.refresh()
        } else if action = "importSounds" {
            ms.importSounds()
        } else if action = "switchProfile" && data.Has("name") {
            ms.switchProfile(data["name"])
        } else if action = "importProfilePkg" {
            ms.importProfilePkg()
        } else if action = "exportProfilePkg" {
            ms.exportProfilePkg()
        } else if action = "saveDefault" {
            ms.saveDefault(), ms.ui.refresh()
        } else if action = "resetToDefault" {
            if ms.resetToDefault()
                ms.playSlot("reset")
            ms.ui.refresh()
        } else if action = "trustCurrentVersion" {
            ms.integrity.trustCurrent(), ms.ui.refresh()
        } else if action = "deleteTrustedHash" {
            ms.integrity.deleteTrustedHash(), ms.ui.refresh()
        } else if action = "checkIntegrity" {
            ms.ui.refresh()
        } else if action = "checkForUpdate" {
            ms.update()
        } else if action = "openConsole" {
            if ms.HasProp("dev")
                ms.dev.console.toggle()
        } else if action = "openWatcher" {
            if ms.HasProp("dev")
                ms.dev.watcher.toggle()
        } else if action = "openKeys" {
            if ms.HasProp("dev")
                ms.dev.keys.toggle()
        } else if action = "openWindow" {
            if ms.HasProp("dev")
                ms.dev.window.toggle()
        } else if action = "startRebind" && data.Has("id") {
            ms.ui.hide()
            _ms_captureRebind(data["id"])
        } else if action = "setModifier" && data.Has("id") {
            global _ms_modConfig
            key := data.Has("key") ? Trim(data["key"]) : ""
            if key = ""
                _ms_modConfig.Delete(data["id"])
            else
                _ms_modConfig[data["id"]] := key
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update"), ms.ui.refresh()
        } else if action = "startModRebind" && data.Has("id") {
            ms.ui.hide()
            _ms_captureModRebind(data["id"])
        } else if action = "resetBind" && data.Has("id") {
            global _ms_bindConfig, _ms_subBinds
            def := ms.bind._defs.Has(data["id"]) ? ms.bind._defs[data["id"]] : ""
            if def != "" {
                if def.Has("sub") && def["sub"] != ""
                    _ms_subBinds.Delete(data["id"])
                else
                    _ms_bindConfig.Delete(data["id"])
            }
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset"), ms.ui.refresh()
        } else if action = "clearModifier" && data.Has("id") {
            global _ms_modConfig
            _ms_modConfig.Delete(data["id"])
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset"), ms.ui.refresh()
        } else if action = "reloadTheme" {
            ms.loadTheme(), ms.ui.refresh()
        } else if action = "openURL" && data.Has("url") {
            Run data["url"]
        } else if action = "editMacros" {
            Run A_ScriptDir "\ms_macros.ahk"
        } else if action = "userSettingChange" && data.Has("key") {
            ms.settings.set(data["key"], data.Has("value") ? data["value"] : "")
            ms.playSlot("update"), ms.ui.refresh()
        } else if action = "userSettingAction" && data.Has("key") {
            global _ms_user_index
            if _ms_user_index.Has(data["key"]) {
                def := _ms_user_index[data["key"]]
                if def.type = "action" && def.HasProp("onAction") && IsObject(def.onAction)
                    try def.onAction.Call()
            }
            ms.ui.refresh()
        } else if action = "resetUserSetting" && data.Has("key") {
            global _ms_user_index
            if _ms_user_index.Has(data["key"]) {
                def := _ms_user_index[data["key"]]
                if def.HasProp("default")
                    ms.settings.set(data["key"], def.default)
            }
            ms.playSlot("reset"), ms.ui.refresh()
        } else if action = "modalResult" {
            global _ms_ui_modal_cb
            if IsObject(_ms_ui_modal_cb) {
                cb := _ms_ui_modal_cb
                _ms_ui_modal_cb := 0
                try cb.Call(Map("confirmed", data.Has("confirmed") && data["confirmed"] = true, "value", data.Has("value") ? data["value"] : ""))
            }
        } else if action = "resetSetting" && data.Has("key") {
            key := data["key"]
            def := ms.macroDefaults
            if key = "sensitivity" && def.HasProp("sensitivity") {
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
    }
;; END UI Panel WebView2 Message Handler ;;

;; Rebind Capture Helpers ;;
    _ms_captureRebind(id) {
        ms.alert('Rebinding: "' (ms.bind._defs.Has(id) ? ms.bind._defs[id]["label"] : id) '"`nPress new key — Escape to cancel.', 15)

        ih := InputHook("L1 B", "{Escape}")
        ih.KeyOpt("{All}", "SN")
        ih.OnChar := (ih2, char) => 0
        ih.OnKeyDown := _ms_onRebindKey.Bind(id)
        ih.Start()
    }

    _ms_onRebindKey(id, ih2, vk, sc) {
        ih2.Stop()
        if vk = 27 {
            ms.alert("Rebind cancelled.", 2)
            ms.ui.show()
            return
        }
        global _ms_bindConfig

        key := GetKeyName(Format("vk{:02X}", vk))
        _ms_bindConfig[id] := Map("type", "key", "mods", [], "key", key)
        ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update")
        ms.alert((ms.bind._defs.Has(id) ? ms.bind._defs[id]["label"] : id) " bound to " key, 3, true)
        ms.ui.show(), ms.ui.refresh()
    }

    _ms_captureModRebind(id) {

        def := ms.bind._defs.Has(id) ? ms.bind._defs[id] : ""
        if def = "" || !def.Has("sub") || def["sub"] = ""
            return
        ms.alert('Modifier for "' def["label"] '"`nPress key — Backspace to clear — Escape to cancel.', 15)
        ih := InputHook("L1 B", "{Escape}{Backspace}")
        ih.KeyOpt("{All}", "SN")
        ih.OnKeyDown := _ms_onModRebindKey.Bind(id)
        ih.Start()
    }

    _ms_onModRebindKey(id, ih2, vk, sc) {
        ih2.Stop()
        if vk = 27 {
            ms.alert("Modifier rebind cancelled.", 2)
            ms.ui.show()
            return
        }
        global _ms_modConfig

        if vk = 8 {
            _ms_modConfig.Delete(id)
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("reset")
            ms.alert("Modifier cleared.", 3, true)
        } else {
            key := GetKeyName(Format("vk{:02X}", vk))
            _ms_modConfig[id] := StrLower(key)
            ms.saveSettings(), ms.bind.rebind(), ms.playSlot("update")
            ms.alert("Modifier set to: " key, 3, true)
        }
        ms.ui.show(), ms.ui.refresh()
    }
;; END Rebind Capture Helpers ;;

;; Section 4 — Startup Sequence ;;

    ;; Dev Log Archive ;;
        _ms_pruneLogs()

    ;; Loading Screen ;;
        _ms_loadingShow()
        _ms_loadingUpdate(5, "Initializing...")

    ;; Font Installation ;;
        _ms_loadingUpdate(8, "Installing fonts...")
        _ms_installFonts()

    ;; Process Macros ;;
        _ms_loadingUpdate(10, "Processing macros...")
        #Include ms_macros.ahk

    ;; Seed Bind Defaults ;;
        for _, id in ms.bind._defList {
            def := ms.bind._defs[id]
            if def && (!def.Has("sub") || def["sub"] = "") && !_ms_binds.Has(id)
                _ms_binds[id] := def["enabled"]
        }

    ;; Load Settings / Theme / Binds ;;
        _ms_loadingUpdate(25, "Loading settings...")
        ms._discoverSounds()
        ms.loadSettings()
        _ms_loadingUpdate(50, "Applying theme...")
        ms.loadTheme()
        _ms_loadingUpdate(65, "Configuring binds...")
        ms.cam.updateMultiplier()
        ms.bind.rebind()
        ms.socdApply()

    ;; Final Startup Tasks ;;
        _ms_loadingUpdate(90, "Finalizing...")
        _ms_registerHotkeys()
        SetTimer _ms_integritySeed, -3000
        SetTimer _ms_setLoadDone, -3000

        _ms_setLoadDone() {
            global _ms_loadDone := true
        }

    ;; App Watcher Poll ;;
        SetTimer _ms_appPoll, 100

    ;; Load Complete Announcement ;;
        SetTimer _ms_announceLoad, -500
        _ms_announceLoad() {
            global BindValidity, _ms_loadDone
            ms.playSlot("load")
            ms.playSlot("launch")
            ; 1. Settings notice — immediate, 3s duration
            ms.alert("Macros loaded. Press Alt+P to open settings.", 3, true)
            ; 2. Library creator — after first toast fades (3s delay), 3s duration
            SetTimer () => ms.alert("mudscript Windows Runtime`nBy: mudbourn — https://mudbourn.info", 3, true), -3000
            ; 3. Macro pack creator — after second toast (6s delay), 3s duration
            SetTimer _ms_showMacroToast, -6000
            _ms_loadDone := true
            BindValidity := 1
            _ms_loadingDismiss()
        }

        _ms_showMacroToast() {
            if !ms.macroMeta.HasProp("name")
                return
            msg := Chr(34) ms.macroMeta.name Chr(34)
            ms.macroMeta.HasProp("author")  ? msg .= "`nBy: " ms.macroMeta.author : ""
            ms.macroMeta.HasProp("website") ? msg .= " — " ms.macroMeta.website : ""
            ms.alert(msg, 3, true)
        }

    ;; Tray Icon ;;
        iconPath := A_ScriptDir "\ui\icons\ms_icon.png"
        if !FileExist(iconPath)
            iconPath := A_ScriptDir "\ui\icons\ms_icon.ico"
        if FileExist(iconPath)
            TraySetIcon iconPath
        A_IconTip := "mudscript — " (ms.macroMeta.HasProp("name") ? ms.macroMeta.name : "Macro Utilities")

        tray := A_TrayMenu
        tray.Delete()
        tray.Add("Toggle Settings", (*) => ms.ui.toggle())  ; single click on tray icon opens panel
        tray.Default := "Toggle Settings"
        tray.ClickCount := 1

    ;; Periodic Integrity Check ;;
        SetTimer _ms_integrityPoll, 5000
        _ms_integrityPoll() {
            global _ms_loadDone
            if _ms_loadDone != 1
                return
            if ms.integrity.check() = "mismatch"
                Reload()
        }
;; END Section 4 — Startup Sequence ;;
