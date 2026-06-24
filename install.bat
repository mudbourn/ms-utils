@echo off
REM install.bat — one-shot installer for mudscript (Windows)
REM
REM Run this from the repo root after cloning:
REM   install.bat
REM
REM It does everything the manual install docs describe:
REM   1. Copies repo contents to %USERPROFILE%\.hammerspoon\
REM   2. Downloads library dependencies (WebView2.ahk, Jxon.ahk)
REM   3. Generates tray icon from .tiff sources
REM   4. Installs OS-level Guardian (Scheduled Task) — requires Admin
REM   5. (Optional) Registers startup shortcut
REM   6. Locks init.ahk (attrib +r)
REM
REM To uninstall:
REM   schtasks /delete /tn "mudscript Guardian" /f
REM   rd /s /q "%USERPROFILE%\.hammerspoon"

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "HS=%USERPROFILE%\.hammerspoon"

echo.
echo ╔══════════════════════════════════════════════╗
echo ║       mudscript — Windows Installer         ║
echo ╚══════════════════════════════════════════════╝
echo.

REM ── Self-elevate (required for guardian scheduled task) ───────────────────
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [UP]   Requesting administrator privileges...
    echo.
    powershell -NoProfile -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

REM ── Preflight ─────────────────────────────────────────────────────────────

if not exist "%SCRIPT_DIR%ms_core.ahk" (
    echo ERROR: ms_core.ahk not found.
    echo        Run this script from the ms-utils repo root.
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%init.ahk" (
    echo ERROR: init.ahk not found.
    pause
    exit /b 1
)

REM ── Step 1: Copy files ────────────────────────────────────────────────────

echo ❶  Copying to %%USERPROFILE%%\.hammerspoon\ ...
if not exist "%HS%" mkdir "%HS%"
xcopy "%SCRIPT_DIR%*" "%HS%" /E /I /H /Y >nul 2>&1
echo    ✓ Files copied.

REM ── Step 2: Install dependencies ──────────────────────────────────────────

echo.
echo ❷  Installing library dependencies ...
if exist "%HS%\bin\install_deps.bat" (
    call "%HS%\bin\install_deps.bat"
    echo    ✓ Dependencies installed.
) else (
    echo    ⚠  install_deps.bat not found — skipping.
)

REM ── Step 3: Install Guardian Scheduled Task ───────────────────────────────

echo.
echo ❸  Installing OS-level Guardian (Scheduled Task) ...
if exist "%HS%\bin\install_guardian_agent.bat" (
    call "%HS%\bin\install_guardian_agent.bat"
    if !errorlevel! equ 0 (
        echo    ✓ Guardian installed.
    )
) else (
    echo    ⚠  install_guardian_agent.bat not found — skipping.
)

REM ── Step 4: Optional startup registration ─────────────────────────────────

echo.
echo ❹  Register auto-start on logon? ...
choice /C YN /N /M "    Add mudscript to startup folder? [Y/N] "
if !errorlevel! equ 1 (
    if exist "%HS%\bin\install_startup.bat" (
        call "%HS%\bin\install_startup.bat"
        echo    ✓ Startup registered.
    ) else (
        echo    ⚠  install_startup.bat not found — skipping.
    )
) else (
    echo    Skipped.
)

REM ── Step 5: Lock init.ahk ─────────────────────────────────────────────────

echo.
echo ❺  Locking bootstrap stub (attrib +r) ...
attrib +r "%HS%\init.ahk" 2>nul && echo    ✓ init.ahk locked. || echo    ⚠  Could not lock init.ahk.

REM ── Done ──────────────────────────────────────────────────────────────────

echo.
echo ╔══════════════════════════════════════════════╗
echo ║          Installation complete               ║
echo ╚══════════════════════════════════════════════╝
echo.
echo    Directory:  %HS%
echo    Guardian:   Scheduled Task "mudscript Guardian"
echo.
echo    The trusted hash is auto-seeded from MANIFEST.json on first load.
echo    Macros are enabled by default when Roblox is focused.
echo.
echo    Next steps:
echo      1. Double-click %%USERPROFILE%%\.hammerspoon\init.ahk to launch
echo         (or restart — startup shortcut handles it automatically)
echo      2. Make sure Roblox is running and focused
echo      3. Press Alt+P to open the settings panel
echo.
echo    Keybindings (Roblox focused):
echo      Alt+P      Toggle settings
echo      Alt+[      Reload script
echo      Alt+]      Reload settings
echo      Alt+F10    Panic (disable macros)
echo      /          Disable macros
echo      Enter      Enable macros
echo.
pause
