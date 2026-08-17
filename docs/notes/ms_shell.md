# MsShell

Shell infrastructure: webview window, dispatch, popouts.

## The shell window is a non-activating panel

The shell webview uses the `borderless | nonactivating` window mask, not a plain
borderless window. As a floating tool-palette-style panel it keeps its cursor
rectangles live while it is the frontmost panel, so the drag and resize regions
show their grab/resize cursors without flicker, even though Hammerspoon is a
background agent that never becomes the active app. A plain borderless window's
cursor rects are only live while it is the key window of the active app, which
Hammerspoon never is, so the system kept reverting the cursor to the arrow.
`hs.webview`'s window is an NSPanel subclass, so the nonactivating mask takes
effect. Borderless is preserved and `allowResizing()` re-adds the resizable bit.
This does not steal app focus. Popouts use the same mask for the same reason.

## Drag uses OS-mouse deltas, not window-relative coordinates

The JS only signals `dragStart`. Lua then tracks the real OS mouse position
(`hs.mouse.absolutePosition`) and moves the window by the delta of the mouse from
where the drag began, relative to where the window began. Using deltas (not
`mouse - windowOrigin`) means any constant offset between the mouse and webview
coordinate spaces cancels out, and the global mouse position can never feed back
from the window's own motion. The webview reports positions window-relative,
which is what made the panel accelerate off-screen away from the cursor.

While dragging, `ms._shellDragging` is set so the Window Spy engine and anything
else on the shared thread idles and does not contend with the drag eventtap. The
soft shadow is dropped for the duration of a drag or resize: recompositing a soft
shadow on a transparent, rounded window every reposition is the main thing that
made it lag behind the cursor.

## Top edge is floored, other edges are free

Every drag handle lives at the top of the window, so the window top is never
allowed above the usable top of the screen it started on, or there would be
nothing left to grab. Down/left/right are safe because the grabbed point stays
under the cursor. A north-edge resize applies the same floor so the title bar
can't be pushed into the menu bar.

## Move-end rubber-band (shell only)

After a shell drag ends, if the window is more than half off-screen it animates
back so at least half is visible, flooring the top at the screen edge. Popouts
deliberately have no rubber-band: the animated snap-back fought the user when
repositioning and misbehaved on multi-monitor (wrong-screen frame,
reverse-stick). The popout move handler already floors the top, so a popout can
never lose its title bar, and anything else stays where it is dropped.

## Inline module scripts are inlined at load

The shell loads via `html()` / `loadHTMLString`, and WKWebView refuses `file://`
subresources from string-loaded pages, so `<script src>` never executes. On
init, each `<script src="./modules/x.js">` is replaced with the file's contents
wrapped in an inline `<script>`. Popouts instead load via `url()` and keep their
`src` tags.

## Popouts are pre-baked with theme CSS

`bakePopOuts` writes a `_popout_<panel>.html` per panel with a `:root` theme CSS
block (`_buildThemeCSS`, derived from `ms._theme` tokens) injected into `<head>`,
so a popout renders with the correct palette immediately with no JS race. It also
injects the eight resize grab zones (same geometry and hover-highlight as the
shell) as `position:fixed` body children, and wraps the body in `#popout-root`.
Baking runs at init and again whenever the theme changes (via a wrapper around
`ms.loadTheme`).

Do NOT call `applyWindowRadius` on popouts: it sets the body background to
transparent, but popouts have no inner wrapper like `#shell-root` to fill the
gap, which produced an invisible-background bug. The bake CSS already handles
body background and border radius.

## Popout grow-in is deferred to page load

The grow-in animation is deferred until the page actually loads. Running it right
after `url()` played the animation over a still-blank, async-loading webview and
finished before any content rendered, so the open looked instant while the close
(content already up) animated. The `navigationCallback` is set before `url()` so
the finish event can't fire before we're listening, and a timeout backstops a
missed callback so a popout can never stay stuck invisible.

## `saveState` is the single frame funnel

`saveState` is the one place move-end, resize-end and hide all pass through, so
it is the only place that has to move the exit curtain to follow the shell. The
curtain stands in the shell's place at exit; moving it is a relayout, and one
paid mid-exit is what made shutdown's curtain arrive after its sound.
`_restoreFrame` (and `show`) also re-sync the curtain because opening is the
other way the frame changes without passing through `saveState`. See also project
memory: exit-curtain-is-host-owned, toast-level-must-clear-shell-webview.

## `toggle` reads `_shellState.visible`, not `:isVisible()`

`:isVisible()` returns true during fade-out animations, which made toggle close a
shell that was already being dismissed. The stored `_shellState.visible` flag is
the source of truth.

## `closePopOuts` at exit

The exit teardown retracts every popped-out panel back into the shell frame,
fading out, then hides and deletes its webview, so popouts leave *with* the shell
instead of being destroyed live on screen when `hs.reload()` / quit nukes their
webviews. Unlike `popIn` it does no shell round-trip (no `poppedIn` / history
reload) because the shell is on its way out too.

## Shell push uses `shellReceive`, not `shellDispatch`

Lua-to-JS panel notifications call `shellReceive`; `shellDispatch` loops back to
Lua. See project memory: shell-push-shellreceive-not-shelldispatch.

## Finder panels hide the shell (`finderInterlude`)

Every `hs.dialog.chooseFileOrFolder` call routes through `finderInterlude`,
installed once as a shim on `hs.dialog`. The always-on-top shell otherwise
occludes the native open/save panel, greying its sidebar, and a blocking alert
can softlock behind it. See project memory:
native-modal-occluded-by-shell-softlock, hs-openpanel-sidebar-greyed-needs-focus.

The panel blocks the runloop, so the hide and restore are synchronous. An async
fade would never render, which is why it uses `view:hide()` and `safeShow`
directly rather than `ms.shell.hide()`/`show()`. That also keeps it silent, with
no chime around a transient blink. It only hides windows that were visible, so it
cannot reveal a shell the person had closed, and it restores any popouts it hid.

The shim marks `hs.dialog` (not `ms`) once installed, so a quick reload that
rebuilds `ms` in place does not wrap an already-wrapped function and nest
interludes. The wrapper resolves `finderInterlude` on the live `ms` at call time,
so the fresh shell state is used after a reload.

This covers import and export file panels only. Reveal-in-Finder utilities that
run `open <folder>` are separate and not routed through it.
