@echo off
REM bin\install_deps.bat — downloads required AHKv2 libraries
REM
REM Downloads and installs the dependencies needed by mudscript:
REM   - WebView2.ahk  (and WebView2/ folder)  from thqby/ahk2_lib
REM   - Jxon.ahk                              from TheArkive/JXON_ahk2
REM
REM Run once after cloning ms-utils:
REM   bin\install_deps.bat

setlocal enabledelayedexpansion

set "LIB_DIR=%~dp0..\lib"

echo === mudscript — Installing AHKv2 Library Dependencies ===
echo.
echo Target: %LIB_DIR%
echo.

REM ── Ensure lib\ exists ─────────────────────────────────────────────────────
if not exist "%LIB_DIR%" mkdir "%LIB_DIR%"

REM ── WebView2.ahk ──────────────────────────────────────────────────────────
set "WV2_FILE=%LIB_DIR%\WebView2.ahk"
set "WV2_DIR=%LIB_DIR%\WebView2"
set "WV2_URL=https://raw.githubusercontent.com/thqby/ahk2_lib/master/WebView2/WebView2.ahk"

if exist "%WV2_FILE%" (
    echo [SKIP] WebView2.ahk already exists.
) else (
    echo [DL]   Downloading WebView2.ahk...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%WV2_URL%' -OutFile '%WV2_FILE%' -UseBasicParsing"
    if !errorlevel! equ 0 if exist "%WV2_FILE%" (
        echo [OK]   WebView2.ahk downloaded.
    ) else (
        echo [FAIL] Could not download WebView2.ahk.
        echo        Try manually from: %WV2_URL%
    )
)

REM ── WebView2/ folder ──────────────────────────────────────────────────────
if exist "%WV2_DIR%" (
    echo [SKIP] WebView2/ folder already exists.
) else (
    echo [DL]   Downloading WebView2/ folder contents...
    mkdir "%WV2_DIR%" 2>nul
    powershell -NoProfile -Command ^
        "$github = 'https://api.github.com/repos/thqby/ahk2_lib/contents/WebView2'; " ^
        "$items = Invoke-RestMethod $github; " ^
        "foreach ($item in $items) { " ^
        "  if ($item.type -eq 'file') { " ^
        "    $out = '%LIB_DIR%\WebView2\' + $item.name; " ^
        "    Invoke-WebRequest -Uri $item.download_url -OutFile $out -UseBasicParsing; " ^
        "    Write-Output ('    ' + $item.name); " ^
        "  } " ^
        "}"
    if !errorlevel! equ 0 (
        echo [OK]   WebView2/ folder populated.
    ) else (
        echo [FAIL] Could not download WebView2/ contents.
        echo        Try manually from: https://github.com/thqby/ahk2_lib/tree/master/WebView2
    )
)

REM ── Jxon.ahk ──────────────────────────────────────────────────────────────
set "JXON_FILE=%LIB_DIR%\Jxon.ahk"
set "JXON_URL=https://raw.githubusercontent.com/TheArkive/JXON_ahk2/main/Jxon.ahk"

if exist "%JXON_FILE%" (
    echo [SKIP] Jxon.ahk already exists.
) else (
    echo [DL]   Downloading Jxon.ahk...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%JXON_URL%' -OutFile '%JXON_FILE%' -UseBasicParsing"
    if !errorlevel! equ 0 if exist "%JXON_FILE%" (
        echo [OK]   Jxon.ahk downloaded.
    ) else (
        echo [FAIL] Could not download Jxon.ahk.
        echo        Try manually from: %JXON_URL%
    )
)

REM ── Generate tray icon ──────────────────────────────────────────────────────
echo.
echo === Generating tray icon ===
echo [GEN] Generating ms_icon.ico from .tiff sources (or creating fallback)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\generate_icon.ps1"

REM ── Summary ───────────────────────────────────────────────────────────────
echo.
echo === Summary ===
if exist "%WV2_FILE%" ( echo WebView2.ahk:      OK ) else ( echo WebView2.ahk:      MISSING )
if exist "%WV2_DIR%"  ( echo WebView2/ folder:  OK ) else ( echo WebView2/ folder:  MISSING )
if exist "%JXON_FILE%" ( echo Jxon.ahk:          OK ) else ( echo Jxon.ahk:          MISSING )
if exist "%LIB_DIR%\..\ui\icons\ms_icon.ico" ( echo ms_icon.ico:       OK ) else ( echo ms_icon.ico:       FALLBACK )
echo.

if not exist "%WV2_FILE%" or not exist "%WV2_DIR%" or not exist "%JXON_FILE%" (
    echo Some dependencies are missing — see lib\README.md for manual install instructions.
    echo.
)

pause
