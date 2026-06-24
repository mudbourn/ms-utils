; Minimal test — loads ms_core.ahk with stub dependencies
#Requires AutoHotkey v2.0

; Stub WebView2 so ms_core.ahk can parse
class WebView2 {
    class Base {
        static Prototype.Ptr := 0
    }
    static create(hwnd, *) {
        return { Navigate: (*) => "", add_NavigationCompleted: (*) => "", add_WebMessageReceived: (*) => "", ExecuteScript: (*) => "" }
    }
}

; Stub Jxon
Jxon_Load(&raw) {
    try return JSON.Parse(&raw)
    return Map()
}
Jxon_Dump(data, indent) {
    return JSON.Stringify(data, indent)
}

; Load ms_core.ahk directly
#Include ms_core.ahk

MsgBox "ms_core.ahk loaded successfully!"
