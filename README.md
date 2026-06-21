# ms-utils
Mudscript Macro Utilities — macOS

---

## ~/.hammerspoon layout

```
~/.hammerspoon/
│
│   init.lua                  Bootstrap stub — loads MsGuardian.spoon.
│                             Keep this file read-only: chmod 444 init.lua
│   ms_core.lua               Main library. Protected by the Guardian.
│   ms_macros.lua             Your macro pack. The only file you normally edit.
│   MANIFEST.json             Update manifest — version, sha256, url, signature.
│                             Auto-stamped and signed by GitHub Actions on every push.
│
├── Spoons/
│   └── MsGuardian.spoon/
│       └── init.lua          Pre-load tamper check. Hashes ms_core.lua before
│                             dofile()-ing it. Runs before any macro code.
│
├── bin/
│   ├── hidinject             Compiled HID injection binary.
│   ├── ms_hidinject.swift    Source for hidinject.
│   ├── ms_guardian_agent.sh  OS-level Guardian — kill Hammerspoon on hash mismatch.
│   ├── com.mudscript.guardian.plist  Launch Agent plist template.
│   ├── install_guardian_agent.sh     One-time install: registers the Launch Agent.
│   └── make_release.sh       Developer utility — stamp local MANIFEST hash / bump version.
│                             Signing is handled automatically by GitHub Actions.
│
├── data/                     Per-user runtime files — all gitignored.
│   ├── ms_settings.json      Live settings (binds, sensitivity, sound, etc.)
│   ├── ms_settings_default.json  Saved default — restored by Reset to Default.
│   ├── ms_theme.json         UI theme overrides (colours, font, radius, uifc paths).
│   ├── .ms_trusted_hash      SHA-256 baseline for tamper detection.
│   └── guardian_agent.log    Launch Agent output log.
│
├── ui/
│   ├── ms_settings_ui.html   Settings panel (webview).
│   ├── ms_guardian.html      Tamper-detection dialog (webview).
│   ├── ms_console.html       Developer Console panel (webview).
│   ├── ms_watcher.html       Macro Monitor panel (webview).
│   ├── ms_keys.html          Input Monitor panel (webview).
│   ├── ms_window.html        Window Monitor panel (webview).
│   ├── fonts/                Bundled fonts — copied to ~/Library/Fonts/ at startup.
│   └── icons/                Menu bar icons.
│
├── sounds/                   User sound files — gitignored.
├── backups/                  Auto-created backups (update, settings archive) — gitignored.
└── profiles/                 Saved macro profiles — gitignored.
    └── <name>/
        ├── ms_macros.lua
        ├── ms_settings.json
        └── ms_settings_default.json
```

---

## Security layers

| Layer | What it does |
|---|---|
| `MsGuardian.spoon` | Hashes `ms_core.lua` at load time. Mismatch → blocking dialog, nothing loads. |
| Launch Agent | OS-level watcher on `ms_core.lua`. Kills Hammerspoon independently of the Spoon. |
| `init.lua` stub | 14-line file. `chmod 444` makes silent edits observable. |
| Signed MANIFEST | GitHub Actions signs every release with RSA-2048. Invalid signature → hard abort. |
| Macro sandbox | `ms_macros.lua` runs in a restricted environment — no `hs`, `os`, `io`, shell, or `_G`. |

---

## First-time install

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

## Release workflow (maintainer)

Pushing `ms_core.lua` to `main` automatically:
1. Computes the SHA-256
2. Signs it with the RSA private key in GitHub Secrets (`MS_SIGNING_KEY`)
3. Commits an updated `MANIFEST.json` back to the repo

To bump the version number, edit `MANIFEST.json` version field before pushing, or run:

```bash
bash bin/make_release.sh 1.2.0
```
