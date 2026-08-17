# MsPackage

Typed package format (`.mspkg`). A `.mspkg` is a zip archive carrying a single
kind of shareable content plus a manifest (`mspkg.json`) describing what it is
and what it contains.

## The five types

Each type declares exactly which paths it may carry, so a theme package can never
smuggle macro code and a sound package can never overwrite settings.

- `macro`: `ms_macros.lua` and/or `ms_macros_visual.json`, plus `sounds/macro/`.
- `theme`: `ms_theme.json`, plus `ui/fonts/`, and optionally audio + the slot map.
- `sound`: `sounds/active/` and `sounds/macro/`, plus `sound_assign.json`.
- `plugin`: a Spoon under `Spoons/<Name>.spoon/`, the third-party surface.
- `profile`: the whole set (macros, settings, theme, sounds) together.

`profile` is the legacy monolithic shape: an archive with no manifest reads as a
formatVersion-0 profile so packages made before typing still import.

Macro packages carry Lua, JSON, or both; neither is legacy. Hand-written
`ms_macros.lua` and builder-authored `ms_macros_visual.json` are permanent peers,
and `macroFormat` records which a package ships.

## What each type may carry, and why

- Sounds are a theme aspect, not a profile one: a theme is the whole sensory
  surface, so it may carry audio and the slot map. `bundleSoundsWithTheme`
  decides whether an export actually includes them; the type spec only says what
  a theme is *allowed* to carry.
- No type may carry `sounds/defaults/`: those ship with the app, are identical
  everywhere, and must never be overwritten by a package. The `sound` type once
  named `sounds/Default/` (which never existed), so its required check could
  never pass; it was removed rather than corrected, because letting a package
  write into `sounds/defaults/` would overwrite the fallback floor every slot
  lands on.
- Plugins nest under `Spoons/<Name>.spoon/`, never at the install root: `lib/` is
  first-party only, and a flat `plugin.json` would let the second plugin
  installed overwrite the first one's manifest.
- A profile is a wholesale swap, not a layer, so the theme/sound overlap is not a
  conflict: on install it simply is the source of truth for every file it names.

## Spoon-tree digest must match Guardian

`spoonTreeHash` must stay byte-identical to `_hashSpoonTree` in
`ms_guardian.lua`; Guardian reads the ledger before `ms` exists, so the two sides
share only a file format and a hash recipe. Same two invariants apply: `LC_ALL=C`
pins sort collation (locale differs C on GUI launch vs en_US on terminal launch),
and the `._*` / `__MACOSX` excludes drop AppleDouble metadata macOS reaps later.
Either drift trips Guardian's Unrecognized Plugin block on a legitimate install.

## The ledger records display fields at install time

`recordPlugins` writes the ledger row (hash plus id/name/version/author/etc.)
because install is the only moment those fields exist: install copies the
`Spoons/` tree verbatim, so nothing on disk afterwards remembers what the package
called itself, and reading a name out of the Spoon's own `init.lua` would mean
parsing third-party code to draw a list.

## Version compare is component-wise

`versionLess` compares numerically per component, not lexicographically:
`"1.10.0" < "1.9.0"` is true as a string compare, which read every double-digit
version as older than its single-digit predecessor. Unparseable input compares as
equal, so a malformed `requires` warns about nothing rather than everything.

## Verify: integrity self-contained, trust external

Every file the manifest lists must be present and hash as recorded (integrity).
Trust is external: `trustLookup` (supplied by `ms_registry`) maps a package hash
to `trusted` / `community` / `unsigned`; a failed integrity check yields
`tampered`. Verify enforces the type's path allowlist and its required-file
minimum even though pack enforces them on the way out, because a package built by
anything other than this packer has never been through that gate, which is
exactly the case the registry exists to handle.

## Profile decomposition

`profileComponents` is the single source of truth for how a profile decomposes,
used both to record the `components` block at pack time and to cut a profile
apart in `split`. Sounds have a canonical exclusive home in the `sound` package;
the `theme` may also carry a copy when `includeSoundsInTheme` is set (the same
opt-in the standalone theme export offers), so "just the theme" and "just the
sounds" stay separately downloadable by default. Macro-triggered audio travels
with the macros so a macro pack is self-contained. Settings are profile-only,
never emitted as a component package. Split always re-derives file lists from the
archive's real contents (not a possibly hand-edited manifest), so a legacy
profile with no components block still splits.

## Install: destinations from the type spec, never the archive

Every destination is derived from the type spec, so a package can only ever write
where its own type is allowed to. Key points:

- Plugins are inside the trust boundary and `force` does not reach them. Every
  other type is data the app interprets; a plugin is code that runs with the
  app's privileges, so a one-off "import anyway" is far too cheap a bypass. The
  only way to run an unvalidated plugin is to turn protection off wholesale
  (`protectionDisabled`), a deliberate, visible, sticky act. That seam defaults
  closed, so with nothing wired up no unvalidated plugin can install.
- `ms_macros.lua` is executable code, so install scans it with `ms.auditMacros`
  before writing anything and rejects the whole install on failure, exactly as
  the hand-rolled importer does. The generic path previously skipped this, so a
  profile or macro package (including one pulled from the registry via Browse)
  could land unscanned code on disk.
- Optional component slice: install only one slice of a profile (theme / sound /
  macro) from the manifest's `components` map. The package is still verified
  whole, so slicing only narrows which files land. This is how one uploaded
  profile serves four install choices without duplicated bytes. See project
  memory: saved-profiles-config-only-snapshot, partial-install-single-asset-slices.
- A `sound_assign.json` that lands is state, not a file the install root keeps:
  it is read back into `ms.soundAssign` and the stray copy dropped, or the audio
  lands but every slot still points where it did before, which looks like a
  silent failure.
- A plugin install records the ledger row (the only writer), which is what earns
  a Spoon the right to load; a `.spoon` hand-dropped into the dir never reaches
  this code and so is blocked by Guardian.

## Plugin inventory

`listPlugins` joins every `.spoon` on disk against the ledger. `status` is `ok`
(recorded, tree still hashes to its record), `modified` (recorded, tree changed
underneath), or `unrecorded` (no ledger row). The last two normally block boot in
Guardian, so seeing one here means Guardian is off or the tree changed after it
ran; the panel shows them anyway, because a list that quietly omitted the plugin
about to stop the next boot would be the worst kind of correct.

Disabling a plugin sets a flag only and leaves the bundle where it is: moving or
renaming it would change what Guardian sees in `Spoons/` and turn an off switch
into a blocked boot. A fresh install defaults to enabled (the trust gate on the
way in is the decision point), and an unknown name can never read as "off".
`removePlugin` deletes the bundle and its ledger row together (both or neither: a
dir with no row blocks boot, a row with no dir vouches for whatever lands under
that name later) and clears the disabled flag so reinstalling gives an on plugin.
Hammerspoon has no unload, so the files are gone but the code stays loaded for the
session.

## Export and self-test

`collect` gathers the live install's files for a type. For a profile,
`opts.configDir` reads config from a saved profile dir so an inactive profile
exports without switching to it; sounds and fonts are not snapshotted per-profile
and always come from the live dirs. Theme export carries sounds opt-out, not
opt-in. `selfTest` round-trips the live theme through pack, verify and install
(theme is the smallest type, and its install leg rewrites `ms_theme.json` with
the bytes it packed from, so a pass leaves the install as it found it);
`backup = false` there because `.bak` copies of identical bytes would be litter.

## Install-vs-Update ledger

Browse shows "Update" rather than "Install" for content already on disk. The
signal is a per-content ledger, `.ms_content_ledger.json`, written by
`recordContent` on every non-plugin install and read by `listContent`. Plugins
keep their own hash-verified ledger, this one only needs the version.

The ledger is keyed by the registry entry id, not by anything inside the package.
A `.mspkg` manifest carries no id, because the registry id is assigned at publish
time and lives only in the index row. So the caller passes the id it downloaded
by: `browseInstall` threads `data.id` into `install`, which forwards `opts.id` to
`recordContent` and `recordPlugins`. Keying by manifest id silently recorded
nothing, because that field is absent.

A component slice (`opts.component`, a theme/sound/macro carved out of a profile)
is a partial install, so it is not recorded and stays "Install". Installing the
whole profile records the profile id, and Browse treats the profile's slices as
installed by inheriting that flag.

Content installed before the ledger existed is not detected retroactively, since
its version was never recorded. It reads "Install" until reinstalled once.

## Publishing a `.spoon`

`registry_publish.sh` accepts a `.spoon` bundle directly and packs it into a
temporary plugin `.mspkg` before publishing, so plugins do not need a
pre-built package. The staged manifest matches `ms.package.pack`'s plugin output
(type `plugin`, files under `Spoons/`, each hashed into `contents`) so the client
validates it identically on install. Metadata is read from the Spoon's `init.lua`
(`name`, `version`, `author`, `homepage`) and overridable by flag. The registry
id defaults to a slug of the name, and the asset repo defaults to the canonical
registry repo rather than the ambient git origin, which points at ms-utils.
