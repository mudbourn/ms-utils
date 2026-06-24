@echo off
REM install_guardian_agent.bat — installs the mudscript OS-level Guardian as a
REM Windows Scheduled Task.
REM
REM Run once from an Administrator Command Prompt after cloning / updating ms-utils:
REM   cd %USERPROFILE%\.hammerspoon
REM   bin\install_guardian_agent.bat
REM
REM To uninstall:
REM   schtasks /delete /tn "mudscript Guardian" /f
REM
REM NOTE: Must be run as Administrator for task creation.
REM If you are not running as Admin, the script will attempt to self-elevate.

@echo off
setlocal enabledelayedexpansion

set "HS=%~dp0.."
set "AGENT=%HS%\bin\ms_guardian_agent.bat"
set "CORE=%HS%\ms_core.ahk"
set "TASK_NAME=mudscript Guardian"

REM ── Self-elevate check ──────────────────────────────────────────────────────
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

REM ── Preflight checks ────────────────────────────────────────────────────────
if not exist "%AGENT%" (
    echo ERROR: Agent script not found at %AGENT%
    echo        Make sure ms-utils is installed properly.
    pause
    exit /b 1
)

if not exist "%CORE%" (
    echo ERROR: ms_core.ahk not found at %CORE%
    echo        Make sure ms-utils is installed properly.
    pause
    exit /b 1
)

REM ── Remove existing task if present ─────────────────────────────────────────
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

REM ── Create scheduled task ──────────────────────────────────────────────────
REM The guardian runs:
REM   1. At every logon (delayed 30 s for system stability)
REM   2. Every 5 minutes after logon (du/ri) — acts as file-change polling
REM
REM File-watch via WMI event triggers is unreliable across Windows versions,
REM so we use periodic polling instead. The guardian script itself is fast
REM (just a hash check) so running it every 5 minutes is negligible.

echo Installing "mudscript Guardian" scheduled task...

schtasks /create /tn "%TASK_NAME%" ^
    /tr "\"%AGENT%\"" ^
    /sc onlogon ^
    /delay 0000:30 ^
    /rl highest ^
    /f

if %errorlevel% neq 0 (
    echo ERROR: Failed to create scheduled task.
    pause
    exit /b 1
)

REM Set repetition interval: runs every 5 minutes for 24 hours
schtasks /change /tn "%TASK_NAME%" /ri 5 /du 24:00

if %errorlevel% neq 0 (
    echo WARNING: Could not set repetition interval — task will run at logon only.
)

echo.
echo mudscript Guardian agent installed.
echo It watches:  %CORE%
echo Triggers:    Logon + every 5 minutes
echo Log file:    %%LOCALAPPDATA%%\mudscript\guardian_agent.log
echo.
echo Optional: make the stub read-only for stronger protection:
echo   attrib +r %%USERPROFILE%%\.hammerspoon\init.ahk
echo.
pause
