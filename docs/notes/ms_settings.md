# MsSettings

Settings menu, profiles, theme, updates, SOCD, and the shutdown/restart exit
sequence.

## Authored settings (Tools > Setting Builder)

Settings authored from the Tools panel live in their own file, not the pack
(`ms_macros.lua`) and not the main settings JSON: definitions here are re-applied
via `ms.settings.define` after the pack loads. The UI is untrusted input, so a
posted definition is normalized (every field re-derived and clamped) before it is
trusted. Only `true` is stored for the disabled-plugins list, and only for a
well-formed bundle name: that file is the one place the list can be hand-edited,
and a stray key would otherwise decide whether code runs. `define()` stores the
table by reference, so authored defs are handed a copy or a later reset/reload
would accumulate runtime state on the persisted definition. Authored actions
carry no `onAction` (there is nowhere safe to run arbitrary UI-supplied code), so
the button is a deliberate no-op until wired up in the pack. Only authored
settings can be removed; a key the pack declared is not ours to unregister.
Adding or removing one nudges an open macro builder to re-pull its tool list. See
project memory: builder-tools-are-authored-settings, ui-modules-hardcode-theme-values.

## Bind override persistence

A saved override is restored only for a still-registered bind. The old guard
skipped every bind whose default had a `.type` (all of them), so confirmed
rebinds were dropped on the next reload and looked like they had not persisted.
Comparison is canonical across every trigger shape, including derived sub-bind
modifier changes (`type = <parentId>`) and chords (`type = "combo"` carrying
`keys`), which the old per-field chain treated as identical. Genuine overrides
are persisted: with a compiled default, save only a bind that differs from it;
with no default (a visual-builder macro authored without a bind), any configured
bind is by definition an override. The webview always starts hidden because it is
recreated fresh on reload and the persisted `visible` flag is stale after a
restart. See project memory: setting-a-bind-must-auto-enable-macro,
client-server-blockstate-desync.

## `ms.registry` is cleared in place

`ms.registry` also carries the package client API (list/refresh/download from
`ms_registry`), so it is cleared in place, never reassigned: a fresh table drops
that and empties the Browse stage. See project memory:
ms-registry-shared-table-clear-in-place.

## Theme system

The theme editor reads the raw on-disk theme (or `{}`) so it can tell an
explicitly-set key from an inherited default (`ms._theme` has already merged the
two). Writing a patch merges into `ms_theme.json` and reloads; an empty-string
value clears a key (how the editor reverts to default), and everything still
passes through `loadTheme`'s validation. Clearing back to defaults keeps a `.bak`
so a hand-authored file is recoverable. Override keys (text2, border, accentGlow,
etc.) accept any hex or rgba string for full control.

## Sound import

Packages ship sounds bare or prefixed; imports normalize to the destination's
prefix so the library keeps one naming scheme (`d_` defaults, `a_` active, `m_`
macro; unprefixed goes to active). Same-name imports become numbered variants
(Name, Name2, Name3); past slot 3 the importer stops guessing and asks which to
replace, chained one at a time because `ms.ui.prompt` has a single callback slot
(so conflicts cannot be resolved in a plain loop).

## Teardown (shared by shutdown and restart)

Shutdown and restart are the same act of putting mudscript down cleanly, differing
only in what happens after, so they share one teardown where every step is
`pcall`'d. Order matters:

1. Stop macros first (cancel running macros, release any held key/button) so
   nothing below can leave a modifier stuck.
2. Drop the input taps and pollers `ms` owns, named individually rather than
   swept, so a handle added later shows up as a deliberate omission instead of
   silently surviving. (`_gamepadTask` is an `hs.task` with no `:stop`/`:delete`;
   `ms.bind.teardown` already ran `ms.gamepadStop()`.)
3. Suppress the toasts and sounds each teardown step would otherwise fire; a
   caller wanting a send-off starts it before calling teardown.
4. Retract popped-out panels into the shell first, while the shell frame is still
   placed to animate home toward, or the standalone webviews sit on screen until
   `hs.reload()`/quit destroys them live.
5. Everything on screen leaves together: toasts hold for seconds and the exit does
   not wait for them, so without an explicit expire a toast is still there when
   the app goes.

## Exit curtain (host-owned)

One curtain serves both exits, owned by the host rather than the shell's page. It
cannot live in the shell: the restart hotkey fires whether or not the shell is
open, and the shell is the thing being torn down. See project memory:
exit-curtain-is-host-owned.

- **Prewarm.** The curtain page is built once at the tail of boot and kept loaded.
  Building it at exit time was the whole latency: WKWebView's `html()` is async,
  so the send-off started and the screen sat doing nothing while the page loaded.
  Prewarm failing costs nothing but that latency (the exit path still builds one
  on demand), so it never propagates.
- **Frame sync.** `ms.syncExitCurtainFrame` keeps the prewarmed curtain on the
  shell's frame as the shell moves, so the exit never has to move it. This is why
  shutdown and restart once behaved differently: shutdown is clicked in an open
  shell (frame already placed), restart often is not. The curtain takes the
  shell's frame, not the screen's: this is the shell going quiet, not the desktop
  being covered, so standing exactly in its place is what makes the handoff read
  as one window. Moving a webview forces a WKWebView relayout, and a reveal issued
  into that lands late, so a moved curtain waits a short settle before revealing.
- **Level.** The curtain sits above everything, re-asserted at show time, not one
  step above the shell: the shell's `show` calls `bringToFront(true)`, so a
  fixed one-level headroom lost the ordering. Two windows on the same level are
  ordered arbitrarily by AppKit, and a curtain that comes up behind the window it
  covers for is not a curtain. It stays transparent through the fade (the shell
  shows through until the curtain is opaque) which is the whole takeover.
- **Send-off timing.** `onShow` fires at the moment the curtain is told to fade
  in, and the send-off sound starts from there, so the sample and the fade begin
  together no matter how long the window and page took. The "fading" flag is armed
  before the JS is dispatched, because the page can report back before
  `evaluateJavaScript` even returns. If the page never handshakes (a dead page, or
  octane, which snaps), the send-off still happens: silence is not the fallback.

## Send-off hold math

`_waitForSlot` holds long enough that a send-off sample is not cut mid-note, with
a 0.25s floor so the window teardown is on screen, and a cap (it once had no upper
bound). `dur ~= dur` is the NaN test (NaN compares false to everything); inf/NaN
would schedule a timer that never fires and leave a torn-down app running.
`_secondsLeft` measures remaining sample time from now with no floor, because the
exit sequence adds its own fixed tail. The shared exit tail holds the screen,
fades the curtain, then does the thing; the exit must wait out the fade because
`hs.reload()` and `app:kill()` both take the process with them, so a fade started
but not waited for is never seen.

## Shutdown, restart, and external watchdogs

Shutdown is the power button's back end; its last step quits Hammerspoon, because
mudscript is not its own process (it is what Hammerspoon runs). A detached
`nohup ... &` script (NOT `hs.task`) guarantees the process dies even if the
runloop wedges mid-teardown: on restart, `hs.reload()` wipes the Lua state and
could collect an `hs.task` handle and take its child with it, exactly when the
backstop is needed. `kill()` is a request that can be refused or never answered,
which would hang with no timer left to rescue it, so the exit escalates. Restart
is full reload's back end: same teardown (a reload is just as much an exit,
`hs.reload()` discards the whole Lua state), with a runloop-independent backstop
that relaunches a wedged instance; a completed boot clears the sentinel in
`init.lua` to disarm it. A restart gets its own sound slot, shipped unassigned so
it falls through to the shutdown sound rather than to silence. See project memory:
exit-stall-needs-external-watchdog.

## Reload theme repaint

The shell repaints live via a JS push (`loadTheme` already rebaked popout HTML),
so there is no window rebuild and the legacy window must never surface on reload.
In shell mode theme repaint is a JS push (no hide/show cycle), so the reload path
always closes here, touching the legacy panel only if it is actually open
(`ms.ui.hide()` refocuses the target app as a side effect). See project memory:
legacy-client-is-break-glass-only.

## System integrity, updates, SOCD

`_readTrustedManifest` handles both the old single-hash format and the new JSON
manifest. Update/repair re-seeds the trusted manifest from all tracked files
after copying `MANIFEST.json` and `.ms_file_manifest.json` from the bundle.
Guardian is a security surface, so the custom theme is applied to its block screen
only when custom theming is enabled. A derived trigger (`default.type =
<parentBindID>`) resolves to the parent's key plus the child's mods.

## User-defined tools

`ms.tools.define` registers a callable action that appears in the macro builder's
picker under the User category with its own Tools-panel card. Tool settings are
ordinary user settings registered into the normal tables so get/set/persist/
validate work unchanged, with thin namespaced wrappers so a tool reads its own
config without hand-building the reserved key. See project memory:
macro-tool-setting-reference-model, engine-target-app-generalized.
