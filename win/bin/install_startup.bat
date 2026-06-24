@echo off
REM install_startup.bat — registers init.ahk to run at Windows logon
REM
REM Creates a shortcut in the current user's Startup folder so AutoHotkey
REM launches mudscript automatically on every login.
REM
REM To undo:
REM   del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\mudscript.lnk"

setlocal

set "HS=%~dp0.."
set "INIT=%HS%\init.ahk"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "LNK=%STARTUP%\mudscript.lnk"

REM ── Preflight ────────────────────────────────────────────────────────────────

if not exist "%INIT%" (
    echo ERROR: init.ahk not found at %INIT%
    echo        Make sure ms-utils is installed to %%USERPROFILE%%\.hammerspoon\
    pause
    exit /b 1
)

if not exist "%STARTUP%" (
    mkdir "%STARTUP%"
)

REM ── Create shortcut via PowerShell ──────────────────────────────────────────
REM This avoids needing the deprecated shortcut.vbs approach.
echo Installing mudscript to startup folder...

powershell -NoProfile -Command ^
    "$ws = New-Object -ComObject WScript.Shell;" ^
    "$s = $ws.CreateShortcut('%LNK%');" ^
    "$s.TargetPath = '%INIT%';" ^
    "$s.WorkingDirectory = '%HS%';" ^
    "$s.Description = 'mudscript Macro Utilities';" ^
    "$s.WindowStyle = 7;" ^
    "$s.Save();" ^
    "Write-Output 'Created: %LNK%'"

if %errorlevel% equ 0 (
    echo.
    echo mudscript will now start automatically at logon via:
    echo   %LNK%
    echo.
    echo To remove: del "%LNK%"
) else (
    echo ERROR: Failed to create startup shortcut.
)

pause
