# ms_core.lua Comment Index

Extracted 199 comment blocks.

Decide: **document** (move to docs), **keep** (essential inline), or **discard**.

---

## Block 1 — L246

```lua
                    -- Stub so spoon.MsDevTools:* calls don't crash.
```

## Block 2 — L466

```lua
                        -- System bind overrides (enable/disable/toggle macros).
```

## Block 3 — L475

```lua
                        -- Runs last so user settings always take final effect.
```

## Block 4 — L502

```lua
                                -- Legacy key — migrate into user settings on next save.
```

## Block 5 — L581

```lua
                        -- Save system bind overrides (only non-default values).
```

## Block 6 — L641

```lua
                            -- JSON present but unreadable; fall through to flat-file check.
```

## Block 7 — L737

```lua
                    -- Reloads settings only (no macro re-execution).
```

## Block 8 — L793-794

```lua
                    -- Quick Reload: fires selected functions sequentially (no overlap),
                    -- closes the settings UI, unfocuses/refocuses the target app, then toasts.
```

## Block 9 — L797

```lua
                        -- 0. Mark quick reload in progress so it persists across the reload.
```

## Block 10 — L804

```lua
                        -- 1. Reload macros.
```

## Block 11 — L807

```lua
                        -- 2. Reload theme.
```

## Block 12 — L810

```lua
                        -- 3. Reload settings (rebind, camera, SOCD).
```

## Block 13 — L813

```lua
                        -- 4. Full UI rebuild.
```

## Block 14 — L816

```lua
                        -- Done with module reloads — clear the suppression flag.
```

## Block 15 — L819

```lua
                        -- 5. Clear the persistent flag on success.
```

## Block 16 — L825

```lua
                        -- 6. Always toast the result (warn if nothing selected).
```

## Block 17 — L874

```lua
                        -- Sound slot: no stored value — assignment lives in ms.soundAssign[key].
```

## Block 18 — L901-902

```lua
                        -- Seed with declared default; _applySettings will override with the
                        -- saved value once settings load from disk (after ms_macros.lua runs).
```

## Block 19 — L916

```lua
                        -- soundSlot values live in ms.soundAssign, not _userSettingVals.
```

## Block 20 — L939-940

```lua
                            -- soundSlot assignments are managed by the Sound panel, not _userSettingVals.
                            -- Calling set() on a soundSlot key is not supported; use the Sound section UI.
```

## Block 21 — L1039

```lua
                    -- Validate font.
```

## Block 22 — L1139

```lua
                -- Strip characters that are unsafe in macOS folder names.
```

## Block 23 — L1240-1241

```lua
                -- Forward declaration so switchProfile can call auditMacros,
                -- which is defined below in the same scope.
```

## Block 24 — L1299-1300

```lua
                -- A leading space is prepended so [^%w%.]-anchored patterns also
                -- fire at position 1 of the cleaned source.
```

## Block 25 — L1386

```lua
                        -- Direct Hammerspoon API
```

## Block 26 — L1389

```lua
                        -- Dynamic code loading
```

## Block 27 — L1396

```lua
                        -- OS / filesystem / shell
```

## Block 28 — L1401

```lua
                        -- Dangerous stdlib
```

## Block 29 — L1406

```lua
                        -- Sandbox / metatable / environment escape
```

## Block 30 — L1415

```lua
                        -- App control / URL / process
```

## Block 31 — L1420-1421

```lua
                        -- Filesystem paths to OS directories.
                        -- Exception: context within ~120 chars contains a media extension.
```

## Block 32 — L1475

```lua
                    -- Normalize: chooseFileOrFolder may use string keys ("1") not integer keys (1).
```

## Block 33 — L1521

```lua
                        -- Fallback: shell cp.
```

## Block 34 — L1568

```lua
                        -- Archive current profile (same as switchProfile archiving).
```

## Block 35 — L1590

```lua
                        -- Write blank template ms_macros.lua.
```

## Block 36 — L1607

```lua
                        -- Remove active settings/defaults/theme so the new profile starts clean.
```

## Block 37 — L1618-1619

```lua
                    -- Collision guard: if a folder with this name already exists and it
                    -- is NOT the currently active profile, warn before overwriting.
```

## Block 38 — L1699

```lua
                    -- Includes manually-dropped files, not just UI-imported ones.
```

## Block 39 — L1964-1965

```lua
                    -- Find the top-level directory inside the bundle.
                    -- tar.gz extracts as mudscript-macos-X.Y.Z/...
```

## Block 40 — L1970

```lua
                        -- Fallback: maybe files are at the root of bundleDir
```

## Block 41 — L1973

```lua
                    -- Normalise: ensure trailing slash
```

## Block 42 — L1976

```lua
                    -- Always-replace list (files and directories).
```

## Block 43 — L1978

```lua
                    -- Create-if-missing list (files and directories).
```

## Block 44 — L1987

```lua
                            -- Back up existing (files and dirs).
```

## Block 45 — L1995

```lua
                            -- Replace: remove old, copy new.
```

## Block 46 — L2013

```lua
                -- ── Signature verification helper ───────────────────────────────
```

## Block 47 — L2083

```lua
                        -- Validate required fields.
```

## Block 48 — L2085

```lua
                            -- ok
```

## Block 49 — L2087

```lua
                            -- legacy single-file manifest
```

## Block 50 — L2093

```lua
                        -- Signature verification (works for both formats).
```

## Block 51 — L2099

```lua
                            -- ── Bundle update (tar.gz) ──────────────────────────────
```

## Block 52 — L2125

```lua
                                -- Extract to temp directory.
```

## Block 53 — L2153-2154

```lua
                                -- Re-seed trusted hash from the new ms_core.lua so the
                                -- Guardian and auto-seed don't fire on the post-update reload.
```

## Block 54 — L2160

```lua
                                -- Write local MANIFEST.
```

## Block 55 — L2173

```lua
                            -- ── Legacy single-file update (ms_core.lua only) ────────
```

## Block 56 — L2245-2246

```lua
                -- Returns true when `remote` is strictly newer than `local`.
                -- Compares component-by-component: 1.2.10 > 1.2.3, 2.0 > 1.99.
```

## Block 57 — L2264

```lua
                    -- Read local manifest for version comparison.
```

## Block 58 — L2284

```lua
                        -- Version mismatch → update available.
```

## Block 59 — L2299

```lua
                -- Path for persisting the last-installed testing run ID.
```

## Block 60 — L2353

```lua
                            -- No workflow run found — fall back to main branch.
```

## Block 61 — L2409

```lua
                                -- Fallback: try single-file download for older builds.
```

## Block 62 — L2457

```lua
                            -- Bundle download succeeded — extract and apply.
```

## Block 63 — L2490-2491

```lua
                            -- Re-seed trusted hash from the new ms_core.lua so the
                            -- Guardian and auto-seed don't fire on the post-update reload.
```

## Block 64 — L2611

```lua
                        -- Both held — resolve
```

## Block 65 — L2622

```lua
                            -- Already handled at keydown time — no extra action needed here
```

## Block 66 — L2705-2706

```lua
                                -- In lastWins: when you release the last-pressed key,
                                -- re-press the opposite if it's still physically held
```

## Block 67 — L3307

```lua
                        -- Rebindable system binds (enable/disable/toggle).
```

## Block 68 — L3402

```lua
                        -- Display-only system binds (hardcoded hs.hotkey.bind).
```

## Block 69 — L3417-3418

```lua
                        -- Always re-index the sounds folder so newly imported files
                        -- appear in the picker without requiring a full reload.
```

## Block 70 — L3520-3521

```lua
                                        -- Fallback: shell cp (catches cases where io.open
                                        -- lacks access but the shell subprocess does).
```

## Block 71 — L3778-3779

```lua
                        -- Disable "Save Current Profile" unless the active profile name
                        -- matches an existing saved profile.
```

## Block 72 — L3804

```lua
                            -- When turning ON from the native menu, also clear conflicting sub binds.
```

## Block 73 — L3956-3957

```lua
                        -- Check system integrity once at menu-build time so the Trust item
                        -- can be greyed out immediately if the file is already trusted.
```

## Block 74 — L4129-4130

```lua
                    -- Wrap every fn so selecting an item reopens the menu,
                    -- unless ms._menuOpen was cleared (Escape / Alt+P to close).
```

## Block 75 — L4159-4160

```lua
                    -- If an import just completed, show the Sound submenu directly
                    -- as the top-level menu on this one reopen instead of the full menu.
```

## Block 76 — L4197-4198

```lua
                -- If the second argument is true, the first argument is treated as a raw keycode
                -- rather than a key name, bypassing getCode() lookup.
```

## Block 77 — L4212-4213

```lua
            -- Track previous modifier flag state so flagsChanged can emit
            -- discrete down/up events to the input monitor.
```

## Block 78 — L4467-4468

```lua
                            -- Track scroll-wheel click (button 2) hold state so
                            -- ms.keystate(998, true) works like ms.keystate(999, true) for right-click.
```

## Block 79 — L4633

```lua
                        -- Don't resume a coroutine whose macro has been cancelled or paused.
```

## Block 80 — L4646

```lua
                    -- Flush trace buffer before yielding so entries appear live.
```

## Block 81 — L4786

```lua
                -- Cancel any pending debounce; rapid toggles collapse to the settled state.
```

## Block 82 — L4790

```lua
                    -- Cut off any previous state sound before showing the new one.
```

## Block 83 — L4825-4826

```lua
                -- Repaint the panel immediately when it is open so the macro
                -- enabled/disabled indicator updates the moment the user tabs.
```

## Block 84 — L4838

```lua
                        -- Don't enable macros while the loading screen is still up.
```

## Block 85 — L4841

```lua
                            -- Returning from a Hammerspoon dialog/panel: re-enable silently.
```

## Block 86 — L4868-4869

```lua
                    -- Macro activation is deferred to _announceLoad, which fires
                    -- after the loading screen fully dismisses and toasts play.
```

## Block 87 — L4978-4979

```lua
            -- Cancels all active ms.fn macros and releases held keys/buttons.
            -- Called automatically on every setMacros(0).
```

## Block 88 — L4991

```lua
                -- Release every key currently held by a macro press.
```

## Block 89 — L5008

```lua
                -- Release every mouse button currently held by a macro press.
```

## Block 90 — L5038

```lua
                -- Merge in settings-tracked imports (fills gaps when folder is missing)
```

## Block 91 — L5108-5109

```lua
                -- Suppress all non-load sounds during startup so only launch.wav plays
                -- while the loading screen is visible.  Gate opens in _announceLoad.
```

## Block 92 — L5111

```lua
                -- Suppress if the same slot played within 50 ms.
```

## Block 93 — L5116-5117

```lua
                -- Cut off any still-playing instance of this same slot so sounds
                -- never overlap themselves (e.g. rapid-fire alerts in the console).
```

## Block 94 — L5193

```lua
                -- Find the display that owns this point (multi-monitor aware).
```

## Block 95 — L5219-5220

```lua
            -- Returns true if the pixel at (x, y) matches the given r, g, b target
            -- within the per-channel tolerance (default 10, scale 0-255).
```

## Block 96 — L5233-5234

```lua
            -- ms.bind.define(id, fn|opts, opts|fn)
            -- opts: label=id, group, enabled, cooldown, sub, mod, info, default, shared, system
```

## Block 97 — L5276-5277

```lua
            -- Register display-only system binds (handled by hs.hotkey.bind).
            -- Enable/Disable/Toggle are handled separately by ms.systemBinds.
```

## Block 98 — L5336

```lua
                -- Tear down previous handles.
```

## Block 99 — L5389-5390

```lua
            -- Tears down all active key and mouse binds without touching the
            -- trackpad listeners (they are started/stopped by rebind).
```

## Block 100 — L5402

```lua
                -- Helper: canonical string for bind-conflict comparison.
```

## Block 101 — L5414

```lua
                -- Root bind conflicts: two enabled root binds with the same effective bind.
```

## Block 102 — L5439

```lua
                -- Sub-item modifier conflicts: two siblings sharing the same modifier key.
```

## Block 103 — L5475-5476

```lua
                        -- Sub-item: register when independent binds is on and a bind is configured.
                        -- Cooldown check + auto-dispatch (_activeSub) are both inside the wrapper.
```

## Block 104 — L5504

```lua
                        -- Root bind: honour enabled state, then look up effective bind.
```

## Block 105 — L5537

```lua
                -- Trackpad hold listeners: start or stop based on current mode.
```

## Block 106 — L5545

```lua
                -- Register system binds (always active regardless of BindValidity).
```

## Block 107 — L5548

```lua
            -- Must be called after ms.bind.rebind() and whenever _robloxActive changes.
```

## Block 108 — L5550

```lua
                -- Tear down previous system bind handles.
```

## Block 109 — L5586

```lua
                -- Also refresh the standalone system binds (enable/disable/toggle).
```

## Block 110 — L5617-5618

```lua
            -- Returns the id of a sub-item sibling that already uses the given modifier key,
            -- or nil. Sibling scope is direct siblings (same immediate parent).
```

## Block 111 — L5701

```lua
            -- Returns the default modifier key for a sub-item id, using the registry.
```

## Block 112 — L5723-5724

```lua
            -- Returns true if the given sub-item id should fire for this invocation.
            -- Self-clearing on match so only one variant fires per call sequence.
```

## Block 113 — L5769

```lua
            -- "Mouse 3" / "Alt+V" style display string for the macro-row pill.
```

## Block 114 — L5781

```lua
            -- Snapshots runtime state for the webview panel.
```

## Block 115 — L5785-5786

```lua
                -- Pre-build a children map: parentId → list of child ids.
                -- This turns the O(n³) nested scan into a single O(n) pass.
```

## Block 116 — L5836

```lua
                -- Inject system binds (enable/disable/toggle) as virtual entries.
```

## Block 117 — L5858

```lua
                -- Collect user-defined sound slots for the Sound section.
```

## Block 118 — L5873-5874

```lua
                -- Serialize user setting defs, routed by target section.
                -- Helper: serialize a single def to a JSON-safe item table.
```

## Block 119 — L5933

```lua
                -- Serialize custom section defs.
```

## Block 120 — L5966

```lua
                -- Build theme state (resolve file paths to file:// URLs for the panel).
```

## Block 121 — L5971

```lua
                -- Resolve font file to a file:// URL if it looks like a path.
```

## Block 122 — L6036-6037

```lua
                -- Pre-encodes the full state JSON so ms.ui.refresh() is instant.
                -- Built once at startup, then rebuilt only when state actually changes.
```

## Block 123 — L6041

```lua
                -- Rebuilds the cache synchronously. Safe to call before the panel exists.
```

## Block 124 — L6050

```lua
                -- Mark the cache stale. Refresh will rebuild on next call.
```

## Block 125 — L6053-6054

```lua
                -- Pushes a fresh state snapshot into the open panel. Safe to call even
                -- when the panel hasn't been built yet (no-op) or isn't visible.
```

## Block 126 — L6095

```lua
                                -- Fallback: seed from the webview if somehow unset.
```

## Block 127 — L6106

```lua
                        -- Re-run just the macro sandbox (no settings/theme reload).
```

## Block 128 — L6167-6168

```lua
                            -- Unfocus → refocus the target app so it picks up
                            -- the new macro/key state.
```

## Block 129 — L6297-6298

```lua
                        -- When turning ON: pre-clear any sub bind that conflicts with a root
                        -- bind or with another sub bind, so rebind() starts clean.
```

## Block 130 — L6369-6370

```lua
                    -- switchProfile() reloads Hammerspoon ~3s after success (see Profile
                    -- Management above), so no explicit refresh is needed on success.
```

## Block 131 — L6373

```lua
                    -- Deletes a single non-active saved profile.
```

## Block 132 — L6378

```lua
                        -- Hard guard: never delete the active profile.
```

## Block 133 — L6393

```lua
                    -- Deletes all saved profiles except the active one.
```

## Block 134 — L6396-6397

```lua
                        -- Guard: if the active profile name is blank we can't safely identify
                        -- which folder to protect, so refuse to delete anything.
```

## Block 135 — L6424

```lua
                    -- importProfile() drives its own native file picker / alerts.
```

## Block 136 — L6506

```lua
                    -- Import a sound file and assign it directly to a specific slot.
```

## Block 137 — L6603

```lua
                            -- Reload so the startup guardian seizes full control.
```

## Block 138 — L6626-6627

```lua
                    -- Triggered by right-click › Rebind… on a macro row in the webview.
                    -- Runs the same eventtap capture used by the native menu rebind flow.
```

## Block 139 — L6631

```lua
                        -- System bind rebind (enable/disable/toggle macros).
```

## Block 140 — L6757

```lua
                        -- Regular macro rebind (registry-based).
```

## Block 141 — L6854

```lua
                                        -- Sub-items store in subBinds; root binds in bindConfig.
```

## Block 142 — L6894

```lua
                    -- Resets a single system setting to its macro-pack default.
```

## Block 143 — L6924-6925

```lua
                    -- Changes a user-defined setting value from the panel.
                    -- Routes through ms.settings.set for validation, persistence, and onChange.
```

## Block 144 — L6944

```lua
                    -- Resets a user-defined setting to its declared default value.
```

## Block 145 — L6954-6955

```lua
                    -- Receives the result of a Lua-initiated HTML modal (openLuaModal in JS).
                    -- Fires the pending _modalCallback and clears it.
```

## Block 146 — L6967

```lua
                    -- Resets a macro's bind back to its defined default.
```

## Block 147 — L6971

```lua
                        -- System bind reset.
```

## Block 148 — L6985

```lua
                        -- Regular macro bind reset.
```

## Block 149 — L6988

```lua
                        -- Sub-items use subBinds; root binds use bindConfig.
```

## Block 150 — L6991-6992

```lua
                            -- In independent bind mode, clearing a sub's bind means it can no
                            -- longer fire at all — disable it so the UI reflects that.
```

## Block 151 — L7008

```lua
                    -- Sets the modifier key for a sub-item.
```

## Block 152 — L7076

```lua
                                -- Detect which modifier key was just pressed (not released).
```

## Block 153 — L7089

```lua
                            -- keyDown event.
```

## Block 154 — L7123

```lua
                -- always posts a JSON string of the form { action = "...", ... }.
```

## Block 155 — L7142-7143

```lua
                -- Positions the panel in the left half of the screen — centred between
                -- the left edge and the screen midpoint, near the top of the usable area.
```

## Block 156 — L7147

```lua
                    -- X: centred between the left screen edge and the screen midpoint.
```

## Block 157 — L7149

```lua
                    -- Y: vertically centred on the usable screen area.
```

## Block 158 — L7164

```lua
                    -- Keep _open in sync when the user closes via the X button or Escape.
```

## Block 159 — L7245-7246

```lua
                    -- Push the pre-built state once WebKit has had time to register
                    -- receiveState().  Skipped if the panel is already open.
```

## Block 160 — L7316-7317

```lua
                        -- Wrap ms.key and ms.mouse to strip the internal isSystem
                        -- flag so macro code cannot bypass BindValidity.
```

## Block 161 — L7340

```lua
                        -- Wrap ms.alert to auto-tag macro-sourced toasts.
```

## Block 162 — L7347-7348

```lua
                                    -- Expose read-only alert methods (updateById, dismissById)
                                    -- but not dismissAll — macros should not nuke all toasts.
```

## Block 163 — L7368

```lua
                -- Globals that are explicitly blocked and will error on access.
```

## Block 164 — L7384

```lua
                    -- Safe Lua builtins
```

## Block 165 — L7402-7403

```lua
                    -- ms.Mouse operation constants (seeded explicitly so the sandbox
                    -- __newindex cannot overwrite them in _G via the fallthrough).
```

## Block 166 — L7407

```lua
                    -- ms.Mouse button constants
```

## Block 167 — L7410

```lua
                    -- ms.Mouse reference constants
```

## Block 168 — L7439

```lua
                -- Store sandbox reference so ms.quickReload() can reuse it.
```

## Block 169 — L7465

```lua
                    -- Lua 5.1 fallback (LuaJIT should never reach here).
```

## Block 170 — L7477

```lua
                -- Validation pass
```

## Block 171 — L7509

```lua
        -- Seed ms.binds from registry defaults for any id not set by the settings file.
```

## Block 172 — L7523

```lua
        -- Clean up any stale update sentinel from a previous session.
```

## Block 173 — L7541-7542

```lua
                -- Derive palette from the loaded theme so the canvas respects the active profile.
                -- Falls back to the original dark crimson defaults when a key is absent.
```

## Block 174 — L7562

```lua
                -- Derive font: accept any plain name (no path separators), fall back to Almendra.
```

## Block 175 — L7571

```lua
                    -- 1: background
```

## Block 176 — L7575

```lua
                    -- 2: top accent strip
```

## Block 177 — L7579

```lua
                    -- 3: title (static)
```

## Block 178 — L7584

```lua
                    -- 4: status line (updated by _lUpdate)
```

## Block 179 — L7589

```lua
                    -- 5: progress track
```

## Block 180 — L7593

```lua
                    -- 6: progress fill (frame.w updated by _lUpdate)
```

## Block 181 — L7597

```lua
                    -- 7: separator above checkbox row
```

## Block 182 — L7600

```lua
                    -- 8: hit area — transparent full-width row, trackMouseDown for click detection
```

## Block 183 — L7605

```lua
                    -- 9: checkbox glyph (☐ / ☑) — updated on toggle
```

## Block 184 — L7611

```lua
                    -- 10: label
```

## Block 185 — L7617

```lua
                    -- 11: active profile name (right-aligned in the title row)
```

## Block 186 — L7660

```lua
                -- Load-end sound fires the instant the canvas disappears.
```

## Block 187 — L7662-7663

```lua
                -- Brief pause before opening the gate so the load-end sound
                -- has a moment before any subsequent sounds can play.
```

## Block 188 — L7665

```lua
                    -- Open the sound gate for all future sounds.
```

## Block 189 — L7667

```lua
                    -- Launch sound plays with the first toast.
```

## Block 190 — L7669

```lua
                    -- 1. Settings notice (immediate)
```

## Block 191 — L7671

```lua
                    -- 2. Library creator \xe2\x80\x94 after first toast fades
```

## Block 192 — L7675

```lua
                    -- 3. Macro pack creator \xe2\x80\x94 after second toast fades
```

## Block 193 — L7684

```lua
                    -- Loading complete: allow macros to run and activate them if Roblox is already focused.
```

## Block 194 — L7688-7689

```lua
                    -- 4. Integrity warning / update check — after all three announce toasts
                    -- have faded (3 x 3 s = 9 s total) plus a 1 s gap.
```

## Block 195 — L7723-7724

```lua
            -- Stagger each WebView creation into its own timer tick so startup
            -- never freezes for more than one build at a time.
```

## Block 196 — L7767-7768

```lua
            -- Failsafe: if any prewarm step stalls and the normal fade never fires,
            -- force-dismiss the loading screen after 8 s so startup always completes.
```

## Block 197 — L7771

```lua
                -- Also open the sound gate so sounds are never permanently suppressed.
```

## Block 198 — L7790-7791

```lua
                -- Bootstrap failed: flag the warning so _announceLoad shows it after
                -- the startup toasts have had time to display and fade.
```

## Block 199 — L7795-7796

```lua
        -- Activate Roblox so the app watcher can seed _robloxActive correctly
        -- on first launch.
```

