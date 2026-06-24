; init.ahk — mudscript Windows bootstrap
;
; This file has NO #Include directives so it can load even from a ZIP preview
; (where Windows only extracts the single clicked file). On success it launches
; _ms_main.ahk which has all the real dependencies.
;
; Users: always double-click init.ahk after extracting the ZIP.
; Startup shortcuts and guardian scheduled tasks ALSO point to this file.

#Requires AutoHotkey v2.0

;; Check Extraction ;;
    if !FileExist(A_ScriptDir "\ms_core_v2.ahk") {
        MsgBox "mudscript requires the full extracted folder.`n`n"
            . "1. Right-click the ZIP file → Extract All...`n"
            . "2. Open the extracted folder`n"
            . "3. Double-click init.ahk",
            "mudscript — Missing Files", "Icon!"
        ExitApp
    }

    if !FileExist(A_ScriptDir "\lib\WebView2.ahk") {
        MsgBox "Missing lib\WebView2.ahk — dependencies not installed.`n`n"
            . "Run install.bat as Administrator to install dependencies, or re-download"
            . " the full release ZIP.",
            "mudscript — Missing Dependencies", "Icon!"
        ExitApp
    }
;; END Check Extraction ;;

; Launch the real entry point.
Run A_ScriptDir "\_ms_main.ahk", A_ScriptDir
