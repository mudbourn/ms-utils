# MsPlugins — plugin loading & teardown

Staged rationale from `mac/lib/ms_plugins.lua`. Source material for the phase-4
navigable docs. The code keeps mechanics; the "why" lives here.

## The problem: Hammerspoon has no unload

`Spoons/` is the only place third-party code enters the process. This module
decides which of them run, and — the harder half — how to make one stop.

Hammerspoon has no unload. `require` caches the module, and anything the code
registered on its way in (hotkeys, timers, eventtaps, bus handlers) is held by
whoever it registered with, not by the module table. So a plugin switched off at
the settings level keeps firing until the next reload — and an off switch that
does nothing for a minute is worse than no off switch.

## The fix: a recording proxy per plugin

Every plugin is loaded with an `ms` of its own: a proxy that forwards everything
to the real one, but records an undo closure for each registration it sees pass
through. Turning the plugin off replays that list backwards.

The proxy reaches the plugin through `_ENV`, not through a swapped global.
`hs.loadSpoon` loads Spoons with `require`, so `package.preload` is the seam: a
preload entry compiles the Spoon's `init.lua` against an environment whose `ms`
is the proxy. Closures defined in that chunk capture the environment as an
upvalue, so a callback that fires an hour later still registers against the
plugin that owns it. Hammerspoon still does everything else — meta.json,
`:init()`, docs, the `spoon.<Name>` global — because `loadSpoon` still runs.

What this cannot see is a plugin calling `hs.hotkey.bind` or `hs.timer.new`
directly, behind mudscript's back. Nothing in-process can: those register with
Hammerspoon itself. That is why "register through `ms`, implement `:stop()`" is a
library requirement rather than a hope — every plugin in the validated library
is reviewed, so it is enforceable at the door.

## `ms.plugins` state shape

- `loaded`: dir → true, for plugins whose code is in the process now.
- `failed`: dir → error string.
- `_undo`: dir → array of teardown closures, newest last.

## subProxy — forward, override a few keys

Forwards to `real`, except for the keys in `overrides`. Writes go straight
through: a plugin setting `ms.something` is configuring the real install, and
pretending otherwise would give it a private copy of state that nothing else
reads.

## The wrapped surfaces (makeProxy)

Each wrapped surface calls straight through and then records how to take it back
out again. Only surfaces that keep *executing* after teardown matter for
correctness — binds, bus handlers, key and mouse callbacks. Settings and tools
definitions are cleaned up too, but only so a disabled plugin's rows leave the
settings panel; a stale row is cosmetic, a stale keybind is not.

- **bind**: the dispatcher reads `_wires` and `_defs` at fire time, so clearing
  them stops the bind on the very next keystroke — no OS unregistration involved.
- **key**: already hands back a handle with `:delete()`, which is exactly the
  undo closure needed.
- **mouse**: keeps one callback per button and returns nothing, so the undo has
  to find its own registration again. The identity check matters: if something
  else has since claimed the button, clearing it would disable a binding this
  plugin does not own.
- **scrollBind**: same handle shape as `key`, but the callback is per-direction
  rather than per-registration, so deleting blindly would clear whatever
  registered last — the undo checks it is still ours.

## load()

Nothing is verified here. Guardian refuses to reach `ms_core` at all if `Spoons/`
holds anything the ledger does not vouch for, so by the time this runs every
bundle on disk arrived through install.

The plugin's environment: reads fall through to `_G`, so `hs` and the standard
library are all present; only `ms` is swapped. Writes go to `_G`, because a
plugin declaring a global is doing something visible and should not get a
private one. `require` checks `package.preload` before searching the path, so
the preload entry hands `loadSpoon` our chunk without reimplementing it.

On a mid-load throw, a plugin may already have registered. `load` replays what it
managed (`unload` with `quiet`) before giving up, or the failure leaves live
binds nothing will ever clean up. `loadAll` uses pcall per plugin: a third-party
error costs that plugin, not the rest of the boot.

## unload()

Stops a plugin as far as it can be stopped in a live process. Three steps, in
order:
1. The Spoon's own `:stop()` first — the only one that knows about state this
   module never saw.
2. The recorded undo list, newest first, so a plugin that registered and
   re-registered the same id unwinds in the order it wound up.
3. The module caches, so re-enabling actually re-runs the file instead of
   handing back the warm copy `require` kept.

Marks the UI dirty afterward: the settings panel may have just lost rows, and
the bind list may have just lost entries.

## apply()

Brings the running set in line with what is enabled on disk. This is what the
panel's toggle calls: it does not need to know which way the switch went, only
that the answer may have changed. A plugin removed from disk is gone from
`listPlugins` entirely, so the reconcile loop never sees it — a final sweep
unloads anything still marked running whose bundle no longer exists.
