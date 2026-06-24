# ms-utils
Mudscript Macro Utilities — macOS & Windows

---

## Platform overview

| Platform | Runtime | Entry Point | Macro File | Core Library |
|---|---|---|---|---|
| **macOS** | [Hammerspoon](https://www.hammerspoon.org/) (Lua) | `init.lua` | `ms_macros.lua` | `ms_core.lua` |
| **Windows** | [AutoHotkey v2](https://www.autohotkey.com/) | `init.ahk` | `ms_macros.ahk` | `ms_core.ahk` |

Both platforms share the same directory layout and identical `ms.*` API, so macro logic ports with minimal changes.

---

## One-shot install

**macOS:**
```bash
bash install.sh
```

**Windows (Run as Administrator):**
```batch
install.bat
```

Each installer copies files, installs dependencies, sets up the OS-level Guardian, locks the bootstrap stub, and prints next steps.

---

## Directory layout

```
./
│
│   install.sh            macOS one-shot installer
│   install.bat           Windows one-shot installer (Run as Admin)
│   init.lua              macOS bootstrap stub (read-only: chmod 444)
│   init.ahk              Windows bootstrap stub (read-only: attrib +r)
│   ms_core.lua           macOS main library. Protected by the Guardian.
│   ms_core.ahk           Windows main library. Protected by the Guardian.
│   ms_macros.lua         macOS macro pack — the file you edit.
│   ms_macros.ahk         Windows macro pack — the file you edit.
│   MANIFEST.json         Update manifest — version, sha256, url, signature.
│                         Auto-stamped and signed by GitHub Actions on every push.
│
├── Spoons/               [macOS only]
│   └── MsGuardian.spoon/
│       └── init.lua      Pre-load tamper check. Hashes ms_core.lua before loading.
│
├── bin/
│   ├── hidinject                [macOS] Compiled HID injection binary.
│   ├── ms_hidinject.swift       [macOS] Source for hidinject.
│   ├── ms_guardian_agent.sh     [macOS] OS-level Guardian — kills Hammerspoon on mismatch.
│   ├── ms_guardian_agent.bat    [Windows] OS-level Guardian — kills AutoHotkey on mismatch.
│   ├── com.mudscript.guardian.plist  [macOS] Launch Agent plist template.
│   ├── install_guardian_agent.sh     [macOS] One-time install: registers the Launch Agent.
│   ├── install_guardian_agent.bat    [Windows] One-time install: registers Scheduled Task.
│   ├── install_startup.bat      [Windows] Add init.ahk to startup folder (logon auto-start).
│   ├── install_deps.bat         [Windows] Auto-download WebView2.ahk and Jxon.ahk to lib/.
│   └── make_release.sh / .bat        Developer utility — stamp MANIFEST hash / bump version.
│
├── lib/                   [Windows only — dependencies]
│   ├── WebView2.ahk       Download from thqby/ahk2_lib
│   ├── WebView2/          Companion folder for WebView2.ahk
│   └── Jxon.ahk           Download from TheArkive/JXON_ahk2
│
├── data/                  Per-user runtime files — all gitignored.
│   ├── ms_settings.json        Live settings (binds, sensitivity, sound, etc.)
│   ├── ms_settings_default.json  Saved default — restored by Reset to Default.
│   ├── ms_theme.json          UI theme overrides (colours, font, radius).
│   ├── ms_dev.log             Developer log.
│   ├── ms_dev_logs/           Archived developer logs (auto-pruned to last 20).
│   ├── .ms_trusted_hash       SHA-256 baseline for tamper detection.
│   └── guardian_agent.log     Guardian agent output log.
│
├── ui/
│   ├── ms_settings_ui.html   Settings panel (WebView2).
│   ├── ms_guardian.html      Tamper-detection dialog (WebView2).
│   ├── ms_console.html       Developer Console panel (WebView2).
│   ├── ms_watcher.html       Macro Monitor panel (WebView2).
│   ├── ms_keys.html          Input Monitor panel (WebView2).
│   ├── ms_window.html        Window Monitor panel (WebView2).
│   ├── fonts/                Bundled fonts — auto-installed on startup.
│   └── icons/                Menu bar / tray icons.
│
├── sounds/                User sound files — gitignored.
├── backups/               Auto-created backups (update, settings archive) — gitignored.
└── profiles/              Saved macro profiles — gitignored.
    └── <name>/
        ├── ms_macros.lua/.ahk
        ├── ms_settings.json
        └── ms_settings_default.json
```

---

## Security layers

| Layer | macOS | Windows |
|---|---|---|
| **Load-time check** | `MsGuardian.spoon` hashes `ms_core.lua` at load. Mismatch → blocking dialog, nothing loads. | `init.ahk` hashes `ms_core.ahk` at load. Mismatch → blocking WebView2 dialog, script exits. |
| **OS-level watcher** | Launch Agent watches `ms_core.lua`. Kills Hammerspoon independently. | Scheduled Task watches `ms_core.ahk`. Kills AutoHotkey independently. |
| **Stub lock** | `init.lua` — `chmod 444` makes silent edits observable. | `init.ahk` — `attrib +r` makes silent edits observable. |
| **Signed MANIFEST** | GitHub Actions signs every release with RSA-2048. Invalid signature → hard abort. | Same key, separate `windows_*` fields in `MANIFEST.json`. |
| **Macro sandbox** | `ms_macros.lua` runs in restricted env — no `hs`, `os`, `io`, shell, or `_G`. | `ms_macros.ahk` runs with no special restrictions (AHKv2 no sandbox). Audit scanner blocks dangerous patterns. |

---

## macOS install

```bash
# 1. Copy repo contents to ~/.hammerspoon/
cp -r . ~/.hammerspoon/

# 2. Install the OS-level Guardian Launch Agent
bash ~/.hammerspoon/bin/install_guardian_agent.sh

# 3. Lock the bootstrap stub
chmod 444 ~/.hammerspoon/init.lua

# 4. Reload Hammerspoon
# Trusted hash is seeded automatically from MANIFEST.json on first load.
```

---

## Windows install

### Prerequisites

1. **AutoHotkey v2** — Download and install from [autohotkey.com](https://www.autohotkey.com/)
2. **WebView2 Runtime** — Pre-installed on Windows 10 21H2+ and all Windows 11.
   If missing, download from [Microsoft](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
3. **Dependencies** — Auto-download (fast, recommended):
   ```batch
   bin\install_deps.bat
   ```
   Or manually place in `lib\`:
   - `WebView2.ahk` (and `WebView2/` folder) from [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib/tree/master/WebView2)
   - `Jxon.ahk` from [TheArkive/JXON_ahk2](https://github.com/TheArkive/JXON_ahk2)

### Setup

```batch
REM 1. Copy repo contents to %USERPROFILE%\.hammerspoon\
xcopy /E /I . %USERPROFILE%\.hammerspoon\

REM 2. Install the OS-level Guardian Scheduled Task
REM    (Run as Administrator)
%USERPROFILE%\.hammerspoon\bin\install_guardian_agent.bat

REM 3. Lock the bootstrap stub (optional but recommended)
attrib +r %USERPROFILE%\.hammerspoon\init.ahk

REM 4. (Optional) Auto-start on logon
bin\install_startup.bat

REM 5. Launch AutoHotkey on init.ahk
REM    Double-click init.ahk (or restart — startup shortcut handles it)
```

### First launch

On first load, the trusted hash is auto-seeded from `MANIFEST.json` (the `windows_sha256` field).
Macros are enabled by default when Roblox is focused.

**Keybindings (Roblox-focused):**

| Key | Action |
|---|---|
| `Alt+P` | Toggle settings panel |
| `Alt+[` | Reload script |
| `Alt+]` | Reload settings |
| `Alt+F10` | Panic — disable all macros |
| `/` | Disable macros (single press only, no auto-repeat) |
| `Enter` | Enable macros (single press only, no auto-repeat) |

### Changing the target application

By default macros target Roblox (`RobloxPlayerBeta.exe`). Change at runtime:

```ahk
ms.setTargetApp("notepad.exe")        ; by exe name
ms.setTargetApp("ahk_exe chrome.exe") ; explicit criteria
ms.getTargetWin()                       ; returns current criteria string
ms.setTargetApp("")                     ; clear target
```

---

## Release workflow (maintainer)

Pushing `ms_core.lua` or `ms_core.ahk` to `main` automatically:
1. Computes the SHA-256
2. Signs it with the RSA private key in GitHub Secrets (`MS_SIGNING_KEY`)
3. Commits an updated `MANIFEST.json` back to the repo

To bump the version number, edit `MANIFEST.json` version field before pushing, or run:

**macOS:**
```bash
bash bin/make_release.sh 1.2.0
```

**Windows:**
```batch
bin\make_release.bat 1.2.0
```

---

## Key differences: macOS → Windows

| Concept | macOS (Lua) | Windows (AHKv2) |
|---|---|---|
| Coroutines / async | `ms.fn()` wraps in coroutine; `ms.wait()` yields | Synchronous; `ms.wait()` calls `Sleep` with cancellation check |
| `cmd` key | Maps to ⌘ | Maps to Ctrl |
| Mouse input | `hs.eventtap` key events | `SendInput` with `MOUSEEVENTF_MOVE` for camera |
| Alert/Toast | `hs.alert` overlay | `ToolTip` in top-left corner |
| Settings panel | `hs.webview` with usercontent callback | `WebView2.ahk` control with `WebMessageReceived` |
| Menu bar | `hs.menubar` icon with NSMenu | System tray icon via WebView2 panel |
| Font installation | Copy to `~/Library/Fonts/` | Copy to `%LOCALAPPDATA%\Microsoft\Windows\Fonts` |
| Dev tools | `hs.canvas` panels | WebView2 tool panels |
| Macro sandbox | Frozen `ms` proxy + blocked globals | Audit scanner at import/switch time |
