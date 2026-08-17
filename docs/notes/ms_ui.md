# MsUI

The webview settings panel: the shell's data builders, the rebind capture flow,
sound-library management, reload phases, and the packages / browse / plugins
stages. `ms.ui` window methods are a thin adapter over the shell; the legacy
standalone panel (`ui/ms_settings_ui.html`) was deleted 2026-07-13, so callers
into it are no-ops kept only so boot warmup does not break. See project memory:
legacy-client-is-break-glass-only.

## Bind list and derived binds

The macro list is top-level macros in registration order, each carrying its
derived sub-binds, followed by the system binds. A bind is *derived* (a sub-bind
of another macro) when its `default.type` names another registered bind id, the
same test `ms.bind.define` uses; testing `default.type` alone is not enough,
because ordinary binds carry it too. A derived bind is *severed* from its parent
once the user gives it a concrete override via a full rebind (`bindConfig` then
holds a real trigger instead of `{ type = <parent> }`). Sub-binds attach to the
nearest top-level ancestor, walking the chain so a sub-of-a-sub lands correctly.
A macro with no effective bind has no trigger, so it can never be effectively on:
report it off and let the UI lock the toggle. Display shows accumulated modifiers
first, then the trigger; the rebind prompt also needs the tokens as an ordered
list (each modifier, then each trigger key) so it can spotlight one key cap.

## Rebind capture flow

One modal carries the whole flow: it informs the user, streams the held keys
live (rendered as spotlighted caps below instructional text), then turns into a
confirm for the detected bind, replacing the old floating alert toasts. Both
buttons are hidden during capture (a click would be swallowed by the eventtap and
registered as a mouse bind, and Escape is the intended cancel) and return in the
confirm/conflict phase. The eventtap only sees keyDown for real keys (bare
modifiers arrive as flagsChanged, which it does not watch), so by the time capture
settles there is always at least one key. Capture-phase Escape, a declined
confirm, or a declined conflict retry all land as a cancel. `shellReceive` routes
to the registered settings handler (`shellDispatch` would send back to Lua, the
wrong direction). The macros panel owns rebinding, so a completed capture repaints
its bind list too, and a Lua-side modal close resolves the callback as if the user
clicked, because during capture an eventtap swallows the keyboard so the modal's
own buttons cannot be clicked. See project memory:
shell-push-shellreceive-not-shelldispatch, setting-a-bind-must-auto-enable-macro.

## Assigning a bind enables the macro

Assigning a trigger implies intent to use the macro, so it is enabled in the same
step. `setMacroEnabled` refuses to enable an unbound macro (a bind is required
first), which previously left a freshly-bound builder macro off. Clearing an
override drops back to `def.default`; if the macro was never given a default bind
there is nothing to fall back to and it is now unbound. Reset to default re-nests
a sub under its parent and restores the default modifier `(MOD)+(BASE)`. See
project memory: setting-a-bind-must-auto-enable-macro.

## Sound library model

The Sounds tab lists on the *file* axis (slots are a separate axis, and several
slots can point at one file). `role` is what a file is, derived from the directory
it sits in; `imported` is where it came from. These used to be the same field, so
an import was labelled "imported" and nothing else. Imports keep their own group
so something you brought in stays findable whichever role you give it. Defaults
are the fallback floor and are never removable: removing one would leave slots
resolving to nothing. Presets are built from the `d_*`/`a_*` series named by
`ms.soundSlots` (preset 1 is the unsuffixed `a_*`, 2 and 3 the numbered variants
falling back through). See project memory: sound-slots-single-registry.

- An import never lands on a name the theme system owns and never overwrites a
  library file; the on-disk name follows the name it gets, so the two cannot
  drift. The picker is filtered but is still a file dialog, so a typed path or a
  dragged alias is re-checked (the library holds sounds only).
- Declaring an imported sound's type strips the prefix it carries (so re-typing
  twice cannot stack `m_a_Name`) and drops the `imported` flag rather than
  re-keying it: `imported` is the staging state for an untyped sound, and once it
  has a type it belongs in that type's group. A file already sitting where its
  kind belongs still stops being "imported". Slots point at names, so a rename
  follows or dangles; a slot pointing at a macro sound still resolves because
  `playSlot` falls through `ms.sounds` to `ms.macroSounds`.
- Removal deletes the file and drops every slot that pointed at it (a cleared slot
  falls back to its default). Defaults are never removable.

## Reload phases

Reload rebuilds in the same order boot does. Phase 2 tears down after the source
is validated (safe to destroy): plugins unload first, while the registry/bus they
registered against are still intact so their undo closures land cleanly (boot
loads plugins last, so teardown reverses that). The bind registry is cleared in
place, never reassigned, because `ms.registry` is shared with the package client
(`list`/`refresh`/`download`); a fresh table would silently drop it. A handwritten
pack that set credits owns them; a later in-session visual save yields its
`ms.macroMeta`. Builder-authored macros are re-registered exactly as boot does
after the handwritten pack, or every visual macro vanishes (the registry was
cleared in Phase 2). Plugins reload onto the freshly rebuilt registry. During a
quick reload the target-app refocus is deferred, because UI operations steal focus
and the refocus is handled after they complete. See project memory:
ms-registry-shared-table-clear-in-place, cem-relay-overwrites-not-additive.

## Theming toggle and presets

Turning theming off un-indexes the whole `a_*` series, so every slot is walked
back to its default in the same breath, or one left behind points at a sample
that no longer resolves. Re-enabling rebuilds presets from what is on disk now
that the series is indexed again, so restoring a saved preset is just replaying
it. The theme editor commits one key at a time and previews locally, so it is not
on the drag path of a colour picker. See project memory:
incompatible-packs-persist-in-options.

## Packages, Browse, and Plugins

Profile packaging rides the generic `exportPackage`/`importPackage` path (type
"profile"), so profiles are manifested `.mspkg` packages the registry accepts and
install audits. An inactive-profile export reads config from the saved profile dir
and assets from the live dirs, names the build from its folder (its own
`ms.macroMeta` travels inside the packaged `ms_macros.lua`), and names the build
OS on the way out so the sharer knows who it will work for. Split produces a
standalone `.mspkg` per component (theme/sound/macro).

- An unsigned package is the normal case until the validated library lands, so
  install confirms rather than refuses; plugins are the exception (they run as
  code, so install refuses them outright with no per-import prompt). The confirm
  is a themed shell modal, not a native `blockAlert`, because a native window
  draws behind the always-on-top shell and can softlock the instance; it is async,
  so the forced install runs in the callback. See project memory:
  native-modal-occluded-by-shell-softlock, mudscript-no-native-selects.
- Browse is the universal storefront: `browseList` answers with a full catalog
  push and the panel filters locally so typing stays a round-trip short; refresh
  (`force=true`) refetches the signed index. Install from the registry verifies
  the bytes against the index hash before handing back a path, and re-checks trust
  before writing; `trustLookup` lets a signed-index package clear without the
  unsigned prompt. A freshly installed profile needs both `_profilesDirty` and
  `markDirty`, or `getProfiles` serves a stale cache. See project memory:
  mudscript-universal-browse-stage, partial-install-single-asset-slices,
  saved-profiles-config-only-snapshot.
- Plugins: the enabled flag decides and `ms.plugins.apply()` enforces, loading
  what is newly enabled and tearing down what is newly off, so a toggle takes
  effect on the next keystroke rather than the next reboot. `enabled` is what the
  user asked for; `loadError` is what happened (a plugin can be on and not
  running). Delete tears down first and deletes second: the undo list is only good
  while the plugin is loaded. See project memory: jobsplus-join-rules,
  plugin-disable-must-not-move-files, plugin-teardown-via-env-proxy.

## Editor picker and shell adapter

`editMacros` opens the HANDWRITTEN suite (the visual macros live in
`data/ms_macros_visual.json`), so the themed confirm says which file is opening
and, on first run, sends the user to pick an editor. `open -a` launches the chosen
app; `open -t` is the fallback for a backed-out picker (a bare `open` on a `.lua`
does nothing when no app claims the extension). `_pickEditor` fronts Hammerspoon
first (`hs.focus`). The shell webview is built during boot rather than on first
open, so its page is loaded and on the default panel by the time the hotkey is
pressed. Bringing the shell forward mid-session skips the alpha-0-to-1 fade and
open sound when it is already up (`ms.ui.show` always replays the intro). See
project memory: hs-openpanel-sidebar-greyed-needs-focus.

## Bus routing

Shell messages route to the same action handlers, topic shape
`ui:<panel>:<action>`. The macros panel needs the rebind action set; the plugins
and browse stages send on their own channels so their actions read as plugin/
browse actions in the log, but they resolve in the same set. See project memory:
ms-bus-emits-topic-payload.

## Browse refresh and Update state

`browseList` merges the plugin ledger and the content ledger
(`ms.package.listContent`) into an installed-by-id map, so an entry already on
disk carries `installed` and `installedVersion`. The card reads that as "Update"
instead of "Install". Virtual profile slices inherit the parent profile's flag,
so they read "Update" once the profile is installed. See MsPackage,
Install-vs-Update ledger.

Browse refetches on every open, not just the first. The rail button forces a
catalog refresh so newly published packages and version bumps appear without the
manual Refresh. It stays lazy (nothing loads until Browse is opened) and skips a
refetch while one is already in flight.
