; _ms_main.ahk — mudscript Windows main entry (launched by init.ahk)
; Analog of macOS init.lua: the entry point. Users shortcut or startup-register init.ahk.
; Keep this file read-only after install: attrib +r _ms_main.ahk

#Requires AutoHotkey v2.0
#Include lib\WebView2.ahk   ; thqby/WebView2.ahk  — install to lib\
#Include lib\Jxon.ahk       ; thqby/Jxon.ahk      — install to lib\

; ── Persistent handles (super-globals so _ms_runGuardian can assign them) ─────
global _ms_guardGui := 0, _ms_guardWv := 0

; ── Startup hash check ────────────────────────────────────────────────────────
_ms_corePath := A_ScriptDir "\ms_core.ahk"
_ms_hashPath := A_ScriptDir "\data\.ms_trusted_hash"
_ms_current  := _ms_sha256(_ms_corePath)
_ms_trusted  := _ms_readHash(_ms_hashPath)

if (_ms_trusted != "" && _ms_current != _ms_trusted) {
    _ms_runGuardian(_ms_trusted, _ms_current, _ms_hashPath)
    return              ; end auto-execute; GUI event loop keeps the script alive
}

; ── Hash OK (or no trusted hash yet) — fall through to core ──────────────────
#Include ms_core.ahk

; ═════════════════════════════════════════════════════════════════════════════
; Guardian helpers  (AHKv2 hoists all function defs — safe to define after #Include)
; ═════════════════════════════════════════════════════════════════════════════

_ms_runGuardian(trusted, current, hashPath) {
    _ms_guardGui := Gui("+AlwaysOnTop -Caption", "mudscript")
    _ms_guardGui.Show("w360 h300")
    _ms_guardGui.OnEvent("Close", (*) => ExitApp())

    _ms_guardWv := WebView2.create(_ms_guardGui.hwnd)
    local url := "file:///" StrReplace(A_ScriptDir "\ui\ms_guardian.html", "\", "/")
    _ms_guardWv.Navigate(url)

    ; Store callbacks in statics so they are not garbage-collected.
    static _navH := 0, _msgH := 0
    _navH := (_wv, _) => _wv.ExecuteScript('setHashes("' trusted '","' current '")')
    _ms_guardWv.add_NavigationCompleted(_navH)
    _msgH := _ms_onGuardianMsg.Bind(_ms_guardGui, hashPath)
    _ms_guardWv.add_WebMessageReceived(_msgH)
}

_ms_onGuardianMsg(g, hashPath, wv, args) {
    local raw := ""
    args.TryGetWebMessageAsString(&raw)
    local action := raw, dx := 0, dy := 0
    try {
        local obj := Jxon_Load(&raw)
        if IsObject(obj) && obj.HasOwnProp("action") {
            action := obj.action
            dx     := obj.HasOwnProp("dx") ? obj.dx : 0
            dy     := obj.HasOwnProp("dy") ? obj.dy : 0
        }
    }
    switch action {
        case "confirmDelete":
            try FileDelete hashPath
            g.Destroy()
            Reload
        case "keepBlocked":
            g.Destroy()
            ExitApp
        case "move":
            WinGetPos &wx, &wy,,, "ahk_id " g.hwnd
            WinMove wx + dx, wy + dy,,, "ahk_id " g.hwnd
    }
}

_ms_sha256(path) {
    local out := ""
    RunWait 'powershell -NoProfile -Command "(Get-FileHash \"' path '\" -Algorithm SHA256).Hash.ToLower()" > "' A_Temp '\ms_hash.txt"',, "Hide"
    FileRead &out, A_Temp "\ms_hash.txt"
    try FileDelete A_Temp "\ms_hash.txt"
    return Trim(out)
}

_ms_readHash(path) {
    if !FileExist(path)
        return ""
    local h := ""
    FileRead &h, path
    return Trim(h)
}
