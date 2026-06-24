@echo off
REM bin\install_deps.bat — downloads required AHKv2 libraries
REM
REM Downloads and installs the dependencies needed by mudscript:
REM   - WebView2.ahk  (with ComVar.ahk, Promise.ahk, WebView2/ DLLs)  from thqby/ahk2_lib
REM   - Jxon.ahk                                                        from TheArkive/JXON_ahk2
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

REM ── WebView2.ahk (fix #Include paths to use lib/ subdirectory) ───────────
set "WV2_FILE=%LIB_DIR%\WebView2.ahk"
set "WV2_URL=https://raw.githubusercontent.com/thqby/ahk2_lib/master/WebView2/WebView2.ahk"

if exist "%WV2_FILE%" (
    echo [SKIP] WebView2.ahk already exists.
) else (
    echo [DL]   Downloading WebView2.ahk...
    powershell -NoProfile -Command ^
        "$wv2 = Invoke-WebRequest -Uri '%WV2_URL%' -UseBasicParsing; " ^
        "$wv2 = $wv2.Content.Replace('..\ComVar.ahk', 'lib\ComVar.ahk'); " ^
        "$wv2 = $wv2.Content.Replace('..\Promise.ahk', 'lib\Promise.ahk'); " ^
        "[System.IO.File]::WriteAllText('%WV2_FILE%', $wv2, [System.Text.UTF8Encoding]::new($false))"
    if !errorlevel! equ 0 if exist "%WV2_FILE%" (
        echo [OK]   WebView2.ahk downloaded.
    ) else (
        echo [FAIL] Could not download WebView2.ahk.
        echo        Try manually from: %WV2_URL%
        pause
        exit /b 1
    )
)

REM ── WebView2/ folder (WebView2Loader DLLs) ───────────────────────────────
set "WV2_DIR=%LIB_DIR%\WebView2"
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
        pause
    )
)

REM ── ComVar.ahk (needed by WebView2) ──────────────────────────────────────
set "COMVAR_FILE=%LIB_DIR%\ComVar.ahk"
set "COMVAR_URL=https://raw.githubusercontent.com/thqby/ahk2_lib/master/ComVar.ahk"
if exist "%COMVAR_FILE%" (
    echo [SKIP] ComVar.ahk already exists.
) else (
    echo [DL]   Downloading ComVar.ahk...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%COMVAR_URL%' -OutFile '%COMVAR_FILE%' -UseBasicParsing"
    if !errorlevel! equ 0 if exist "%COMVAR_FILE%" (
        echo [OK]   ComVar.ahk downloaded.
    ) else (
        echo [FAIL] Could not download ComVar.ahk.
        pause
    )
)

REM ── Promise.ahk (needed by WebView2) ─────────────────────────────────────
set "PROMISE_FILE=%LIB_DIR%\Promise.ahk"
set "PROMISE_URL=https://raw.githubusercontent.com/thqby/ahk2_lib/master/Promise.ahk"
if exist "%PROMISE_FILE%" (
    echo [SKIP] Promise.ahk already exists.
) else (
    echo [DL]   Downloading Promise.ahk...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%PROMISE_URL%' -OutFile '%PROMISE_FILE%' -UseBasicParsing"
    if !errorlevel! equ 0 if exist "%PROMISE_FILE%" (
        echo [OK]   Promise.ahk downloaded.
    ) else (
        echo [FAIL] Could not download Promise.ahk.
        pause
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
        pause
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
set ALL_OK=true
if exist "%WV2_FILE%" ( echo WebView2.ahk:      OK ) else ( echo WebView2.ahk:      MISSING & set ALL_OK=false )
if exist "%COMVAR_FILE%" ( echo ComVar.ahk:      OK ) else ( echo ComVar.ahk:      MISSING & set ALL_OK=false )
if exist "%PROMISE_FILE%" ( echo Promise.ahk:    OK ) else ( echo Promise.ahk:    MISSING & set ALL_OK=false )
if exist "%WV2_DIR%"  ( echo WebView2/ folder:  OK ) else ( echo WebView2/ folder:  MISSING )
if exist "%JXON_FILE%" ( echo Jxon.ahk:          OK ) else ( echo Jxon.ahk:          MISSING & set ALL_OK=false )
if exist "%LIB_DIR%\..\ui\icons\ms_icon.png" ( echo ms_icon.png:       OK ) else ( echo ms_icon.png:       FALLBACK )
echo.

if "%ALL_OK%"=="false" (
    echo Some dependencies are missing — see lib\README.md for manual install instructions.
    echo.
)

pause
