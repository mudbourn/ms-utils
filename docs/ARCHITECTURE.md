# Architecture

Technical details about mudscript's internal structure, security model, and development workflow.

---

## Platform overview

| Platform | Runtime | Entry Point | Macro File | Core Library |
|---|---|---|---|---|
| **macOS** | [Hammerspoon](https://www.hammerspoon.org/) (Lua) | `init.lua` | `ms_macros.lua` | `ms_core.lua` |
| **Windows** | [AutoHotkey v2](https://www.autohotkey.com/) | `init.ahk` | `ms_macros.ahk` | `ms_core_v2.ahk` |

Both platforms share the same directory layout and identical `ms.*` API, so macro logic ports with minimal changes.

---

## Directory layout

```
./
│
├── mac/                        macOS platform files
│   ├── install.sh              One-shot installer
│   ├── init.lua                Bootstrap stub (read-only: chmod 444)
│   ├── ms_core.lua             Main library. Protected by the Guardian.
│   ├── ms_macros.lua           Macro pack — the file you edit.
│   ├── templates/
│   │   └── ms_macros.lua       Barebones macro template for new packs.
│   ├── Spoons/
│   │   └── MsGuardian.spoon/
│   │       └── init.lua        Pre-load tamper check. Hashes ms_core.lua before loading.
│   └── bin/
│       ├── ms_guardian_agent.sh   OS-level Guardian — kills Hammerspoon on mismatch.
│       ├── com.mudscript.guardian.plist  Launch Agent plist template.
│       ├── install_guardian_agent.sh     One-time install: registers the Launch Agent.
│       └── make_release.sh     Developer utility — stamp MANIFEST hash / bump version.
│
├── win/                        Windows platform files
│   ├── install.bat             One-time installer (Run as Admin)
│   ├── init.ahk                Bootstrap stub (read-only: attrib +r)
│   ├── _ms_main.ahk            Entry point / WebView2 bootstrap
│   ├── ms_core_v2.ahk          Main library. Protected by the Guardian.
│   ├── ms_macros.ahk           Macro pack — the file you edit.
│   ├── lib/
│   │   ├── WebView2.ahk        WebView2 wrapper
│   │   ├── WebView2/           Companion files for WebView2.ahk
│   │   ├── Jxon.ahk            JSON parser
│   │   ├── ComVar.ahk          COM helper
│   │   ├── Promise.ahk         Promise/async helper
│   │   ├── 32bit/              32-bit WebView2Loader.dll
│   │   └── 64bit/              64-bit WebView2Loader.dll
│   ├── bin/
│   │   ├── ms_guardian_agent.bat   OS-level Guardian — kills AutoHotkey on mismatch.
│   │   ├── install_guardian_agent.bat  One-time install: registers Scheduled Task.
│   │   ├── install_startup.bat     Add init.ahk to startup folder (logon auto-start).
│   │   ├── install_deps.bat        Auto-download WebView2 and Jxon to lib/.
│   │   ├── make_release.bat        Developer utility — stamp MANIFEST hash / bump version.
│   │   └── generate_icon.ps1       Build tray icon from source image.
│   └── data/
│       └── ms_settings_default.json  Windows default settings baseline.
│
├── ui/                         Shared UI assets (both platforms)
│   ├── ms_shell.html           Macro Development Lab shell
│   ├── ms_settings_ui.html     Settings panel
│   ├── ms_guardian.html        Tamper-detection dialog
│   ├── ms_console.html         Developer Console
│   ├── ms_watcher.html         Macro Monitor
│   ├── ms_keys.html            Input Monitor
│   ├── ms_window.html          Window Monitor
│   ├── ms_loading.html         Loading screen
│   ├── modules/
│   │   ├── log-panel.js        Shared LogPanel factory (Console, Watcher, Keys, Window)
│   │   ├── step-block.js       StepCanvas — drag-and-drop macro builder
│   │   └── step-editor.js      Inline parameter editors
│   ├── svg/                    Theme-compliant SVG icons (currentColor)
│   ├── fonts/                  Bundled fonts — auto-installed on startup.
│   └── icons/                  Menu bar / tray icons.
│
├── data/                       Per-user runtime files — all gitignored.
│   ├── ms_settings.json        Live settings (binds, sensitivity, sound, etc.)
│   ├── ms_settings_default.json  Saved default — restored by Reset to Default.
│   ├── ms_theme.json           UI theme overrides (colours, font, radius).
│   ├── ms_macros_visual.json   Visual macro definitions (JSON)
│   ├── ms_macros_visual.lua    Compiled visual macros (Lua)
│   ├── ms_dev.log              Developer log.
│   ├── ms_dev_logs/            Archived developer logs (auto-pruned to last 20).
│   ├── .ms_trusted_hash        SHA-256 baseline for tamper detection.
│   ├── .ms_file_manifest.json  Per-file manifest (Guardian hardening).
│   └── guardian_agent.log      Guardian agent output log.
│
├── profiles/                   Saved macro profiles — gitignored.
│   └── <name>/
│       ├── ms_macros.lua/.ahk
│       ├── ms_settings.json
│       └── ms_settings_default.json
│
├── sounds/                     User sound files — gitignored.
├── backups/                    Auto-created backups (update, settings archive) — gitignored.
├── docs/
│   ├── DOCS_MAC.md             macOS API reference (~1,600 lines)
│   ├── DOCS_WINDOWS.md         Windows API reference
│   ├── function-index.md       Quick reference for all ms.* functions
│   ├── icon-requirements.md    SVG icon specifications
│   └── ARCHITECTURE.md         This file
│
├── MANIFEST.json               Update manifest — version, sha256, url, bundle, signature.
│                               Auto-stamped and signed by GitHub Actions on every release.
└── LICENSE
```

---

## Security layers

| Layer | macOS | Windows |
|---|---|---|
| **Load-time check** | `MsGuardian.spoon` hashes `ms_core.lua` at load. Mismatch → blocking dialog, nothing loads. | `init.ahk` hashes `ms_core_v2.ahk` at load. Mismatch → blocking WebView2 dialog, script exits. |
| **OS-level watcher** | Launch Agent watches `ms_core.lua`. Kills Hammerspoon independently. | Scheduled Task watches `ms_core_v2.ahk`. Kills AutoHotkey independently. |
| **Stub lock** | `init.lua` — `chmod 444` makes silent edits observable. | `init.ahk` — `attrib +r` makes silent edits observable. |
| **Signed MANIFEST** | GitHub Actions signs every release with RSA-2048. Invalid signature → hard abort. | Same key, separate `windows_*` fields in `MANIFEST.json`. |
| **Macro sandbox** | `ms_macros.lua` runs in restricted env — no `hs`, `os`, `io`, shell, or `_G`. | `ms_macros.ahk` runs with no special restrictions (AHKv2 no sandbox). Audit scanner blocks dangerous patterns. |
| **Per-file manifest** | Guardian verifies all shipped files (Lua, HTML, scripts) against signed manifest. | Same approach. |

---

## Update channels

| Channel | Trigger | Assets |
|---|---|---|
| **Stable** | Manual — maintainer runs the Release workflow | `mudscript-macos-{version}.tar.gz` bundle + single `ms_core.lua` fallback |
| **Testing** | Auto — every push to `main` that touches `ms_core.lua` or `ms_core_v2.ahk` | Pre-release tagged `pre-{build_number}` with both platform bundles |

**Bundle updates** (`tar.gz` / `.zip`) replace the full install — UI files, templates, profiles, and core library. The updater checks `MANIFEST.json` for a `bundle` field first; if absent, falls back to single-file `ms_core.lua` / `ms_core_v2.ahk` download.

Switch channels from the Settings panel under **Update Channel**.

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

---

## Release workflow (maintainer)

### Stable release

From the GitHub Actions tab, run the **Release** workflow with a version string (e.g. `1.3.0`). It will:
1. Package the macOS bundle (`tar.gz`) with all platform files, UI, and templates
2. Compute SHA-256 for both the bundle and legacy single-file `ms_core.lua`
3. Sign the bundle hash with the RSA private key (`MS_SIGNING_KEY` secret)
4. Stamp and commit `MANIFEST.json`
5. Create a GitHub Release with the bundle attached

### Testing pre-release

Every push to `main` that modifies `mac/ms_core.lua` or `win/ms_core_v2.ahk` automatically:
1. Builds platform bundles for both macOS and Windows
2. Creates a tagged pre-release (`pre-{build_number}`) with both archives attached

### Manual version bump

```bash
# macOS
bash mac/bin/make_release.sh 1.3.0

# Windows
win\bin\make_release.bat 1.3.0
```

---

## Profiles

Save and switch between macro packs:

- **Profiles → Save Current** — snapshots `ms_macros.lua`, `ms_settings.json`, and `ms_settings_default.json` into `profiles/<name>/`.
- **Profiles → Load** — restores a saved profile and reloads.
- **Profiles → Export** — exports a profile folder for sharing.

Profiles are per-user and gitignored.

---

## Quick Reload

The reload dropdown (next to the Reload button) offers granular control over what gets reloaded:

| Option | Default | What it reloads |
|---|---|---|
| Macros | ✓ | Re-evaluates `ms_macros.lua` |
| Theme | ✓ | Reloads `ms_theme.json` and redraws UI |
| Settings | ✓ | Reloads `ms_settings.json` and re-binds keys |
| UI | ✓ | Recreates all WebView2 panels |

Click the text to reload that item; click the checkbox to toggle whether it's included in full reloads. Preferences persist across sessions.
