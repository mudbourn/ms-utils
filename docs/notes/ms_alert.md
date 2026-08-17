# MsAlert

## Toast window level (`screenSaver + 1`)

`makeCanvas` sets the canvas level to `windowLevels.screenSaver + 1`.

The shell and popouts force themselves above the screenSaver level via
`bringToFront(true)` on show and on interaction, so any move/resize re-asserts
the shell over a plain screenSaver-level toast. The only level proven to sit
above that force-front is the exit curtain at `screenSaver + 1`, so toasts live
there too. Tying with the curtain is safe: exit both clears existing toasts
(`expireAll`) and seals against new ones (`_sealed`), so no toast is ever alive
when the curtain shows. See also project memory: toast-level-must-clear-shell-webview,
exit-curtain-is-host-owned.

## `expireAll` — animate, don't delete, on exit

The exit paths call `expireAll`. A toast still sitting there when the curtain
comes down outlives the app that put it there, and `dismissAll` deletes canvases
outright, so the toasts would vanish mid-air. `expireAll` runs each one through
the same fade the hold expiring would have, so they leave the way toasts
normally leave — just now instead of later. It iterates the queue backwards
because `dismissEntry` removes as it goes.

## `_sealed` — the one-way seal

After `expireAll`'s sweep, `_sealed` is set: everything already queued gets its
fade, and nothing new is accepted after it. From here the screen only empties.

The `__call` entry point checks `_sealed` and returns early. Without it, anything
that toasts during teardown lands *after* `expireAll` and sits there through the
whole send-off — the one thing `expireAll` exists to prevent. There is no
un-gating: the only paths that set it end in a quit or a reload, and both take
this state with them.

## Append order = newest nearest the bottom

Alerts appear sequentially in send order. `_redraw` iterates `#queue → 1`,
positioning from bottom to top, so appending a new entry keeps the newest alert
nearest the bottom of the stack.
