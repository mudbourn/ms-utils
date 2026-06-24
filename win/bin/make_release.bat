@echo off
REM bin\make_release.bat
REM ─────────────────────────────────────────────────────────────────────────────
REM Stamps the SHA-256 of ms_core.ahk into MANIFEST.json locally.
REM Signing is handled automatically by GitHub Actions (.github/workflows/release.yml)
REM whenever ms_core.ahk is pushed to main — you do not need to sign manually.
REM
REM Use this script when you want to verify the hash locally before pushing,
REM or to bump the version number:
REM   bin\make_release.bat [version]
REM ─────────────────────────────────────────────────────────────────────────────

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "ROOT=%SCRIPT_DIR%.."
set "CORE=%ROOT%\ms_core.ahk"
set "MANIFEST=%ROOT%\MANIFEST.json"
set "URL=https://raw.githubusercontent.com/mudbourn/ms-utils/main/ms_core.ahk"

REM ── Preflight ─────────────────────────────────────────────────────────────────

if not exist "%CORE%" (
    echo ERROR: ms_core.ahk not found at %CORE%
    pause
    exit /b 1
)

if not exist "%MANIFEST%" (
    echo ERROR: MANIFEST.json not found at %MANIFEST%
    pause
    exit /b 1
)

REM ── Hash ──────────────────────────────────────────────────────────────────────

for /f "usebackq delims=" %%a in (`
    powershell -NoProfile -Command "(Get-FileHash \"%CORE%\" -Algorithm SHA256).Hash.ToLower()"
`) do set "HASH=%%a"

if "%HASH%"=="" (
    echo ERROR: Failed to compute SHA-256 hash.
    pause
    exit /b 1
)

echo ms_core.ahk  SHA-256: %HASH%

REM ── Version ───────────────────────────────────────────────────────────────────

for /f "usebackq delims=" %%v in (`
    powershell -NoProfile -Command ^
        "try { $d = Get-Content '%MANIFEST%' -Raw | ConvertFrom-Json; $d.windows_version } catch { '1.0.0' }"
`) do set "CURRENT_VERSION=%%v"
if "%CURRENT_VERSION%"=="" set "CURRENT_VERSION=1.0.0"

set "NEW_VERSION=%~1"
if "%NEW_VERSION%"=="" set "NEW_VERSION=%CURRENT_VERSION%"

REM ── Write MANIFEST.json (preserves all existing macOS fields) ─────────────────

powershell -NoProfile -Command ^
    "$path = '%MANIFEST%'; " ^
    "$raw = Get-Content $path -Raw; " ^
    "$m = $raw | ConvertFrom-Json; " ^
    "$m | Add-Member -MemberType NoteProperty -Name 'windows_url' -Value '%URL%' -Force; " ^
    "$m | Add-Member -MemberType NoteProperty -Name 'windows_sha256' -Value '%HASH%' -Force; " ^
    "$m | Add-Member -MemberType NoteProperty -Name 'windows_version' -Value '%NEW_VERSION%' -Force; " ^
    "$m | ConvertTo-Json | Set-Content $path -NoNewline; " ^
    "Write-Output ('Updated: windows_sha256={0} windows_version={1}' -f '%HASH%', '%NEW_VERSION%')"

echo.
echo Stage and commit:
echo   git add ms_core.ahk MANIFEST.json
echo   git commit -m "release: v%NEW_VERSION%"
echo.
pause
