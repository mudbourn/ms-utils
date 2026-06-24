@echo off
REM install.bat — mudscript one-shot installer (Windows)
REM
REM Usage:
REM   curl -LO https://raw.githubusercontent.com/mudbourn/ms-utils/main/install.bat
REM   install.bat
REM
REM Works whether you have the full repo or just this file.
REM Downloads the latest release from GitHub if the repo isn't local.
REM Run as Administrator for full setup (guardian scheduled task).
REM
REM To uninstall:
REM   schtasks /delete /tn "mudscript Guardian" /f
REM   rd /s /q "%USERPROFILE%\.hammerspoon"

setlocal enabledelayedexpansion

set "REPO=mudbourn/ms-utils"
set "HS=%USERPROFILE%\.hammerspoon"
set "SCRIPT_DIR=%~dp0"

echo.
echo ╔══════════════════════════════════════════════╗
echo ║      mudscript — Windows Installer          ║
echo ╚══════════════════════════════════════════════╝
echo.

REM ── Self-elevate check ─────────────────────────────────────────────────────
REM (deferred until after download — elevation resets CWD)

REM ── Step 1: Source the files ────────────────────────────────────────────────

if exist "%SCRIPT_DIR%ms_core.ahk" if exist "%SCRIPT_DIR%init.ahk" (
    echo ❶  Copying local repo to %%USERPROFILE%%\.hammerspoon\ ...
    if not exist "%HS%" mkdir "%HS%"
    xcopy "%SCRIPT_DIR%*" "%HS%" /E /I /H /Y >nul 2>&1
    echo    ✓ Files copied from %SCRIPT_DIR%
    goto :step2
)

REM ── Standalone script — download from GitHub ───────────────────────────────

echo ❶  Downloading latest release from GitHub ...
if not exist "%HS%" mkdir "%HS%"

REM Try latest release first, fall back to main branch zip
echo    Checking for latest release...
set "RELEASE_URL=https://api.github.com/repos/%REPO%/releases/latest"

REM Use PowerShell to find the Windows asset URL
for /f "usebackq delims=" %%u in (`
    powershell -NoProfile -Command ^
        "try { $r = Invoke-RestMethod '%RELEASE_URL%' -UseBasicParsing; $a = $r.assets | Where-Object { $_.name -like '*windows*' } | Select-Object -First 1; if ($a) { $a.browser_download_url } else { '' } } catch { '' }"
`) do set "DL_URL=%%u"

if defined DL_URL if not "!DL_URL!"=="" (
    echo    Downloading: !DL_URL!
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '!DL_URL!' -OutFile '%TEMP%\mudscript.zip' -UseBasicParsing"
    if exist "%TEMP%\mudscript.zip" (
        powershell -NoProfile -Command ^
            "Expand-Archive '%TEMP%\mudscript.zip' '%TEMP%\mudscript-extracted' -Force"
        xcopy "%TEMP%\mudscript-extracted\*" "%HS%" /E /I /H /Y >nul 2>&1
        rd /s /q "%TEMP%\mudscript-extracted" 2>nul
        del "%TEMP%\mudscript.zip" 2>nul
        echo    ✓ Release downloaded and extracted.
        goto :step2
    )
)

REM No release yet — download main branch zip
echo    No release found — downloading main branch...
powershell -NoProfile -Command ^
    "Invoke-WebRequest -Uri 'https://github.com/%REPO%/archive/refs/heads/main.zip' -OutFile '%TEMP%\mudscript-main.zip' -UseBasicParsing"
if exist "%TEMP%\mudscript-main.zip" (
    powershell -NoProfile -Command ^
        "Expand-Archive '%TEMP%\mudscript-main.zip' '%TEMP%\mudscript-extracted' -Force"
    REM The zip contains a folder ms-utils-main/
    if exist "%TEMP%\mudscript-extracted\ms-utils-main" (
        xcopy "%TEMP%\mudscript-extracted\ms-utils-main\*" "%HS%" /E /I /H /Y >nul 2>&1
    ) else (
        xcopy "%TEMP%\mudscript-extracted\*" "%HS%" /E /I /H /Y >nul 2>&1
    )
    rd /s /q "%TEMP%\mudscript-extracted" 2>nul
    del "%TEMP%\mudscript-main.zip" 2>nul
    REM Remove macOS files
    del "%HS%\install.sh" 2>nul
    del "%HS%\*.lua" 2>nul
    if exist "%HS%\bin" (
        del "%HS%\bin\*.sh" 2>nul
        del "%HS%\bin\*.plist" 2>nul
        del "%HS%\bin\*.swift" 2>nul
        if exist "%HS%\bin\hidinject" del "%HS%\bin\hidinject" 2>nul
    )
    if exist "%HS%\Spoons" rd /s /q "%HS%\Spoons" 2>nul
    echo    ✓ Repository downloaded and Windows files extracted.
) else (
    echo    ERROR: Could not download repository.
    pause
    exit /b 1
)

:step2

REM ── Now self-elevate for guardian installation ─────────────────────────────
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [UP]   Requesting administrator privileges for guardian setup...
    echo.
    cd /d "%HS%"
    powershell -NoProfile -Command ^
        "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b 0
)

REM If we got here, we're elevated or elevation was skipped.
REM Check for --elevated flag to skip re-elevation loop
if "%~1"=="--elevated" shift

REM ── Step 3: Install dependencies ───────────────────────────────────────────

echo.
echo ❷  Installing library dependencies ...
if exist "%HS%\bin\install_deps.bat" (
    cd /d "%HS%"
    call "%HS%\bin\install_deps.bat"
    echo    ✓ Dependencies installed.
) else (
    echo    ⚠  install_deps.bat not found — skipping.
)

REM ── Step 4: Install Guardian Scheduled Task ───────────────────────────────

echo.
echo ❸  Installing OS-level Guardian (Scheduled Task) ...
if exist "%HS%\bin\install_guardian_agent.bat" (
    cd /d "%HS%"
    call "%HS%\bin\install_guardian_agent.bat"
    if !errorlevel! equ 0 (
        echo    ✓ Guardian installed.
    )
) else (
    echo    ⚠  install_guardian_agent.bat not found — skipping.
)

REM ── Step 5: Optional startup registration ─────────────────────────────────

echo.
echo ❹  Register auto-start on logon? ...
choice /C YN /N /M "    Add mudscript to startup folder? [Y/N] "
if !errorlevel! equ 1 (
    if exist "%HS%\bin\install_startup.bat" (
        cd /d "%HS%"
        call "%HS%\bin\install_startup.bat"
        echo    ✓ Startup registered.
    ) else (
        echo    ⚠  install_startup.bat not found — skipping.
    )
) else (
    echo    Skipped.
)

REM ── Step 6: Lock init.ahk ─────────────────────────────────────────────────

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
echo.
echo    Next steps:
echo      1. Make sure Roblox is running
echo      2. Double-click %%HS%%\init.ahk
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
