# MsDevTools

Logging and the dev panels (Console, Watcher, Inputs, Window Spy).

## Panel push and channel gating

`_push` routes through `shellReceive` when a panel is in the shell and falls back
to direct `evaluateJavaScript` for standalone/popout webviews (`shellDispatch`
would send back to Lua, the wrong direction). An octane logging gate maps each
channel (console, watcher, keys, window) to enabled; all default on, and octane's
`_apply` sets all off. A log entry that belongs to a disabled primary channel
skips all I/O and pushes, but is still checked against other enabled channels
(for example an error also belongs in watcher). Hot-path predicates gate the
expensive per-event work in `ms_core` when no dev consumer would use the data.
See project memory: shell-push-shellreceive-not-shelldispatch,
ms-bus-emits-topic-payload.

## Log file handling

One long-lived append handle per log file, opened lazily, flushed per line (so
immediacy is preserved), reopened after a trim, closed on teardown. Files are
trimmed to `_HIST_MAX` lines periodically to prevent unbounded growth, which was
the root cause of the Inputs panel hang. The history loader does a bounded read:
all raw lines (cheap string ops, no JSON decode), then decodes only the last
`_HIST_MAX` entries; the log is append-only so the tail is the newest.

## Console mirroring

`print()` already lands in the shell console via the `_G.print` wrap, because the
console evaluates typed input against `_G`. The eval helper is a global rather
than reached through `ms.dev`, because its name is baked into the string handed
back to the console, so it must resolve even if `ms.dev` is mid-reload. `res[1]`
is xpcall's success flag; the real values start at index 2, and a line with no
return value logs nothing rather than an empty result row. The preparser is
chained rather than clobbered: it is a single global slot something else may
already own.

## AX safety and the messaging timeout

A global Accessibility messaging timeout is the seatbelt that makes every AX call
(window reads, element-under-cursor) fail fast instead of freezing the single Lua
thread if a target app is unresponsive. The first-open danger-notice ack is
persisted into `ms_settings.json` so it survives reloads and reinstalls, and
pushed so the panel knows whether to raise the first-open warning.

## Window Spy engine

A hang-safe, event-driven replacement for the old 0.4s focus poller. Every AX read
is `pcall`-guarded and globally timed out. Key points:

- The engine idles the moment the Window monitor is not on screen, or its AX
  polling keeps hammering the shared Lua thread in the background. It self-stops
  when the shell hides and restarts when the shell is shown again with the Window
  panel active. A popped-out Window panel is live on its own, independent of the
  main shell's active panel or visibility.
- A light read (frame + flags only) backs the dirty tick (move/resize) so drags
  don't re-query bundleID/role/screen every 150ms; the light read is merged into
  the cached full state so the UI doesn't blank out app/title during dirty ticks.
  A merged tick coalesces window state and element/mouse into one push, replacing
  the old `_winTick` (0.15s) + `_winAxPoll` (0.2s) pair.
- Minimize/hide handling is the recurring trap: minimizing or hiding takes focus
  with it, so `focusedWindow()` at tick time names a different window or nil, and
  the flags would describe the wrong window. The window the readout is about is
  held separately from focus; a pending minimize/unminimize names its own window,
  and that window is the one the flags are about for that tick. Focus is checked
  first (focus moving to a new window is the normal case and must retarget), the
  tracked window second. App hide/unhide (Cmd+H) is logged too, since the
  per-window minimize watcher does not cover a whole-app visibility change. The
  trivial move callback fires hundreds of times per drag, so it does no AX/JSON/
  push, just tallies and flags; the tick does the work.
- Element-under-cursor AX inspection (the heaviest, riskiest call,
  `systemElementAtPosition`) is decoupled behind F6 (`_winElementInspect`), off by
  default and user-opt-in from the Window panel; octane forces it off. Leaving the
  Window monitor tears the AX engine down immediately, not on the next 0.15s tick,
  because a heavy element poll may be in flight and letting it keep firing hangs.
  A stationary refresh re-samples on an interval even when the cursor has not
  moved, because shiftlock (pointer-lock) pins the cursor while the screen under
  it keeps changing, so position-equality alone would freeze the readout.
- Priming reads window AX and creates the app watcher off the current runloop
  tick, because doing that synchronous work inline with the panel switch is what
  made the switch stutter. The rich live-state card is fed by the engine's
  `updateCurrentWindow` pushes, so a sparse log entry must not overwrite it, and
  the state is re-pushed on panel-ready because the engine's immediate prime may
  race the shell panel load.

## Coordinate tracking

In the shell there is no standalone keys panel and thus no `_mousePoller`, so a
move-driven mouse poller is the coord source for the Inputs readout (the
click-only eventtap was the only source before, so the readout froze between
clicks). The live reference resolution is pushed to the Inputs panel so the REF
coord-mode label shows real numbers instead of the hardcoded default.

## Forward declarations and bus handlers

Drag-handler upvalues are forward-declared so the Window bus handler registered in
`:start()` (far above their definitions) captures them instead of resolving to nil
globals. Bus handlers are invoked as `fn(topic, payload)`, so the panel name is on
the payload; taking only one arg bound the payload to the topic string. See
project memory: ms-bus-emits-topic-payload.
