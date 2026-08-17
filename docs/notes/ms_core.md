# MsCore

The core system library. Guardian `dofile`s this after verifying hashes, so by
the time it runs `_guardianPassed` is set and there is nothing to invoke for
integrity here.

## Boot and module loading order

Modules load in a deliberate order, each seeing a more complete `ms`:

- MsGuardian has already run (from `mac/init.lua`); core does not re-invoke it.
- MsDevTools, MsAlert, MsSettings, MsUI load with graceful fallbacks so a failure
  in one prints and continues rather than aborting boot.
- The package format loads before the registry (the registry validates index
  entries against `ms.package.spec` and supplies the `trustLookup` that
  `ms.package.verify` takes). Registry fetch is deferred: boot only reads the
  on-disk cache.
- The compiler loads before macro packs, so installing a package that ships
  `ms_macros_visual.json` compiles it on the way in.
- Plugins load last on purpose: a plugin sees a finished `ms`, so it can bind,
  subscribe and define settings without ordering against the modules it depends
  on. Plugins are the one place third-party code enters the process.
- `MANIFEST.json` is the single source of truth for the installed version (the
  same file MsUI and the loading screen read), so it must exist before the
  fingerprint step.

## One-time migration and reload key-state cleanup

Core moves legacy `settings`/`hash` files into `data/` once. After `hs.reload()`,
OS-level key/button state from the previous session persists because the old Lua
state never sent release events, so core cleans up (using raw keycodes) before
initializing fresh state.

## Deleted handwritten macros are suppressed, not edited out

A handwritten macro (from `ms_macros.lua`) "deleted" in the shell UI is not
removed from source. Its id is parked: disabled, unbound from the live binds
(rebind skips suppressed ids), hidden from the panel, and persisted so it stays
gone across reloads. Visual-builder macros live in the JSON pack and can be truly
deleted; only handwritten ones are suppressed, because deleting them would mean
editing source. See project memory: handwritten-macro-delete-is-suppression.

## Target app is not hardcoded

The macro target is declared by a macro pack or plugin via `ms.setTargetApp()`.
An optional `TARGET_APP` global lets a pack seed it before core runs. See project
memory: engine-target-app-generalized.

## Sound slot registry

The one list of built-in sound slots is the single source: `playSlot`'s fallback,
the custom-theme reset, the preset builder and the Sounds tab all derive from it
and keep no copy, so adding a slot is a one-line change. Key points:

- A slot resolves in priority order: what the user assigned, then a library file
  named after the slot, then the sample the registry names as its default.
- Fallback chains: each slot is resolved in full before the next is tried, so a
  borrowed sound only stands in for a slot with nothing of its own. The walk is
  depth-capped so a fallback loop cannot hang the caller.
- A restart has its own samples (a restart is not a goodbye), with the shutdown
  fallback kept for when they are missing, because silence is worse than
  borrowing the send-off.
- The registry owns every name it lays claim to (numbered preset variants
  included); an import may not land on one, or a file like `a_Shutdown.wav` would
  overwrite a registry-owned sample. An imported filename is normalized to an
  `a_` user-audio name that cannot collide. See project memory:
  sound-slots-single-registry.
- `playSlot` stops a slot already playing and plays fresh so rapid hover/interact
  sounds don't gap. It records a start time so a caller that must outlive the
  sample (shutdown) can compute what is left of it.

## Sound file types and auto-sort

What counts as a sound file lives in one place, backed by what `hs.sound`
(NSSound) can actually open; the scanner and auto-sorter used to disagree.
Auto-sort moves misplaced samples by prefix (`d_` to `sounds/defaults/`, `a_` to
`sounds/active/`, `m_` to `sounds/macro/`) and never overwrites. The prefix is
what a file claims to be. See project memory: training-dummy-silenced-by-jar-edit
for the kind of drift this guards against.

## Reference resolution and scaling

Window-relative points scale by the reference resolution (`REF_W`/`REF_H`), which
macro packs retarget at runtime through `ms.settings` (`ms.setReference`). The
`ms._refW`/`ms._refH` fields stay in sync with the globals so older code reading
them keeps working. `Window*` points are scaled unless the caller passes
`Unscaled` or the user turns reference scaling off. Camera moves scale by the
sensitivity ratio so a macro calibrated at `refSens` produces the same rotation
regardless of in-game sensitivity.

## Key dispatch, resilient taps, and specificity

- Actual dispatch lives in `_bindHotkeys()`: one resilient tap per key. System
  binds registered elsewhere are display-only; wiring dispatch there once spun up
  a second orphaned watcher. Everything rides the central resilient eventtap via
  `ms.key`; a private tap not added to `_resilientTaps` was never revived by the
  watchdog after macOS disabled it.
- Tap-disable watchdog: macOS silently disables an eventtap whose callback
  overruns (`kCGEventTapDisabledByTimeout`), so dead taps are re-enabled every 2s.
- `ms.held(id)` is true iff every identifier modifier of bind `id` is held, used
  to route a shared trigger among claimants; binds with no identifier mods (the
  fallback) return false.
- Dispatch is exact-match on modifiers (required held AND no extras) so a
  bare-key bind doesn't swallow a modified combo like alt+esc. Chord binds require
  their companion keys physically held.
- A reverse code→name lookup for the dev key feed is cached because
  `hs.keycodes.map` logs a console warning for any code absent from the active
  keymap and is hit on every key event (the globe/Fn key 179 is the usual
  offender).
- `mods == "any"` matches the key under any modifier state, the way the old
  system binds did (return/escape fire even while a movement modifier is held).
- Chords count each key toward specificity, so `V+K` registers ahead of a plain
  `V` in the shared first-match-wins bucket, letting the chord claim `V+K` while
  the bare key still fires on its own. Registration sorts most-mods-first.
- A single conflict-detection pass runs all binds through the same key-conflict
  path (derived binds resolve via `effectiveBind`).

## `ms.hold`, `ms.flick`, and the coroutine main-thread gotcha

`ms.hold(key, mods, durationMs)` presses and holds (the compiler emits it for a
builder Hold step); it was previously undefined, so a Hold step compiled to a nil
call. Repeats begin only after the initial delay, like a physical hold.
`ms.flick(dx, dy, opts)` is a deterministic tightly-bunched delta stream that runs
synchronously (no yield).

Lua 5.4 (Hammerspoon) returns `(mainthread, true)` from `coroutine.running()` on
the main thread, where 5.1 returned nil, so a bare `if co` was always true and a
yield fired even on the main thread (which cannot yield). Gate on the `isMain`
flag. See project memory: ms-wait-mainthread-yield-gotcha.

## Native hotkeys vs eventtaps

Quick Reload, Full Reload and Open/Close Shell are native `hs.hotkey`s, not
`_makeKeyWatcher` taps: the eventtap only swallows when `ms._swallowHotkeys` is
on, so by default the combos leaked to the target app. They fire regardless of
target focus (they are Hammerspoon UI actions), so a global hotkey matches. The
Quick Reload timer is retained in a field so an anonymous `doAfter` isn't GC'd
mid-reload (heavy allocation churn), which would latch `_qrCooldown` true forever.
`ms.restart` tears down the way shutdown does and then reloads (bare `hs.reload()`
dropped state), and self-guards against re-entry.

## Octane Mode

A low-overhead performance toggle that strips logging, animations, pollers and
sounds while macros run unchanged.

## Keystate watchers

Fire on key down, wait for key up plus cooldown, and do not swallow input. The
fire gate is exact-match on modifiers (bare-key watchers don't swallow alt+esc);
the `flagsChanged` reset stays subset-match on purpose.

## Macro control-flow logging

`ms.log` renders hand-written macro control flow: `ms.log("if", cond, true)` ->
`[label] if (cond) -> true`, `ms.log("for", "i=1,14", 14)` ->
`[label] for i=1,14 (14 iterations)`. The current innermost label comes from the
call stack, nil outside a macro context.

## Window actions and the recorder

`ms.Window` moves/resizes a window (Move -> top-left to (a,b); Resize -> size;
Frame -> both) and backs the recorder's window-action capture. Window move/resize
rides a separate `hs.window.filter`, not the eventtap: the OS reports the settled
frame, and diffing it against the last-seen frame tells move from resize.
Hammerspoon-owned windows (shell, console, panels) are never captured, only the
user's apps. `windowMoved` covers most builds; `windowsChanged` is also subscribed
where it exists so an edge-only resize is not missed.

## `ms.dragPath` and the recorder's path handling

`ms.dragPath` accepts `points` as a table of `{x,y}` pairs or an `"x,y;x,y;..."`
string; the visual builder and the drag recorder both author the string form, so
parsing it here means one runtime serves authored steps and recordings. "Center"
(what the recorder and `ms.Mouse` emit for the middle button) is accepted
alongside "Middle" so a middle-button drag doesn't play back as a left drag.

The recorder emits a wait module only for idle gaps over a threshold (sub-threshold
gaps are noise), skips input landing on the shell window itself, and builds the
tapped-event set from the options so the tap does the least work it can. A plain
click and the start of a drag look identical until the mouse moves or releases in
place, so the decision is deferred. Recorded drags are decimated with
Ramer-Douglas-Peucker (a dense ~60-120 pts/sec stream keeps only shape-changing
points), with an absolute cap thinning a frantic path to evenly-spaced points so
the emitted string stays bounded. A genuine curve becomes one `dragPath` step;
a straight two-point drag becomes the compact Mouse Drag op. OS auto-repeat
keyDowns are kept, because reproducing them is the whole point of a hold-to-spam
recording. The recorder never consumes the event: the user's input must still
reach the foreground app.

## Anti-Timeout

Generic idle-prevention (for example a game's inactivity kick); the action and
interval come from whichever pack or plugin configures it.

## Live macro session updates

`write()`/`delete()` only regenerate the on-disk `.lua`; `load()` re-defines the
macro in the live session so a saved or deleted macro is immediately listable,
bindable and runnable without a reboot. `ms.bus` calls handlers as
`(topic, payload)`, so a handler must be `function(_, body)`; declaring
`function(body)` bound `body` to the topic string. See project memory:
ms-bus-emits-topic-payload.

## Pack meta ownership (handwritten wins)

Handwritten `ms_macros.lua` loads first and owns the pack credits (`ms.macroMeta`).
The compiled visual pack (section 14a, loaded after) also emits `ms.macroMeta`;
when handwritten already set it, the visual write yields (a sandbox `__newindex`
lock). A coexistence guard skips a visual macro whose id already belongs to a
handwritten or system bind. See project memory: ms-compiler notes,
visual-macros-coexist-boot-load.

## Test Run and Record Mode

Test Run compiles and runs the in-progress macro def once and reports ok/err so
the panel toast resolves instead of timing out; the run is async (a coroutine,
like a bound macro). Record Mode captures keystrokes, clicks and idle gaps,
pushing each as a module into the canvas.

## Builder Tools list

The builder's Tools section lists every live value-bearing setting so a module
parameter can be wired to one (compiled to `ms.settings.get`). A setting's
`section` becomes its heading, so a plugin's `section="roblox"` settings get their
own named group. Authored tools can be deleted from the builder; pack-declared
ones live in source and are reference-only. See project memory:
builder-tools-are-authored-settings, macro-tool-setting-reference-model.

## Startup announce sequence

`_loadComplete` gates the hotkeys and is deliberately not the same flag as the
startup-sound gate: `_loadComplete` lands at the end of the boot body, while the
"macros loaded" toast lands about 1.5s later. The announce lead-in delays only the
announcement toasts/sound, never the unblocking that gates macros, sound and
alerts (raise the lead-in freely; do NOT raise the 0.4s body delay). Each
announcement toast must be fully gone before the next is sent, or their timers
land on the same deadline and fire in undefined order. Custom-theming-off resets
every built-in slot to its default (not just the three the loading screen needs)
on every boot, because settings written while theming was on survive on disk. The
exit curtain's page is loaded at boot while nothing waits on it, so it is not dead
air during the send-off. A hard guarantee at the end sets the startup flags even
if `_announceLoad` faulted or returned early, so sounds and macros are never left
blocked. See project memory: exit-stall-needs-external-watchdog,
toast-level-must-clear-shell-webview.
